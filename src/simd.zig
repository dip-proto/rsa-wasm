const std = @import("std");
const key = @import("key.zig");

pub const N32: usize = 64; // 2048-bit modulus as 64 limbs of 32 bits
pub const NP: usize = N32 / 2; // packed elements (2 columns each)

pub const L = @Vector(2, u32); // one column for each prime: {p, q}
pub const W = @Vector(2, u64);
pub const Q4 = @Vector(4, u32); // two columns: {p0, q0, p1, q1}
pub const Q4w = @Vector(4, u64);
pub const Batched = [NP]Q4; // packed number: element k = columns 2k, 2k+1

const MASK: W = @splat(0xffff_ffff);
const SH: W = @splat(32);
const WZERO: W = @splat(0);

// Packed modulus {p,q,p,q} per element.
const modP: Batched = blk: {
    var m: Batched = undefined;
    for (0..NP) |k| m[k] = .{
        @intCast(key.p32[2 * k]),     @intCast(key.q32[2 * k]),
        @intCast(key.p32[2 * k + 1]), @intCast(key.q32[2 * k + 1]),
    };
    break :blk m;
};
const n0invV: L = .{ @intCast(key.p_n0inv32), @intCast(key.q_n0inv32) };

inline fn loHalf(x: Q4w) W {
    return @shuffle(u64, x, undefined, [2]i32{ 0, 1 });
}
inline fn hiHalf(x: Q4w) W {
    return @shuffle(u64, x, undefined, [2]i32{ 2, 3 });
}
// Column i (a single {p,q} limb pair) from a packed number.
inline fn col(a: *const Batched, i: usize) L {
    const e = a[i >> 1];
    return if (i & 1 == 0) L{ e[0], e[1] } else L{ e[2], e[3] };
}
// Broadcast a column pair to a 4-lane multiplier {p,q,p,q}.
inline fn bcast(c: L) Q4 {
    return .{ c[0], c[1], c[0], c[1] };
}

// CIOS Montgomery multiply for both primes at once, processing 2 columns per
// widening multiply (i64x2.extmul_low/high).
pub fn montMulV(a: *const Batched, b: *const Batched) Batched {
    @setEvalBranchQuota(50000);
    var t: [N32]W = @splat(WZERO); // per-column accumulator, < 2^32 between i steps
    var tn: W = WZERO;
    var i: usize = 0;
    while (i < N32) : (i += 1) {
        const a4 = bcast(col(a, i));
        // t += a[i] * b
        var c: W = WZERO;
        inline for (0..NP) |k| {
            const prod = @as(Q4w, a4) * @as(Q4w, b[k]);
            var s = loHalf(prod) + t[2 * k] + c;
            t[2 * k] = s & MASK;
            c = s >> SH;
            s = hiHalf(prod) + t[2 * k + 1] + c;
            t[2 * k + 1] = s & MASK;
            c = s >> SH;
        }
        const s0 = tn + c;
        const tcarry = s0 >> SH;

        // m_hat = t[0]*n0inv mod 2^32; t = (t + m_hat*modulus) / 2^32
        const t0: L = @truncate(t[0]);
        const mh: L = @truncate(@as(W, t0) * @as(W, n0invV) & MASK);
        const m4 = bcast(mh);
        var c2: W = WZERO;
        {
            const prod = @as(Q4w, m4) * @as(Q4w, modP[0]);
            c2 = (loHalf(prod) + t[0]) >> SH; // column 0: low part is zero
            const s = hiHalf(prod) + t[1] + c2; // column 1
            t[0] = s & MASK;
            c2 = s >> SH;
        }
        inline for (1..NP) |k| {
            const prod = @as(Q4w, m4) * @as(Q4w, modP[k]);
            var s = loHalf(prod) + t[2 * k] + c2;
            t[2 * k - 1] = s & MASK;
            c2 = s >> SH;
            s = hiHalf(prod) + t[2 * k + 1] + c2;
            t[2 * k] = s & MASK;
            c2 = s >> SH;
        }
        const s1 = (s0 & MASK) + c2;
        t[N32 - 1] = s1 & MASK;
        tn = tcarry + (s1 >> SH);
    }

    // Per-lane conditional subtraction of the modulus.
    var diff: [N32]W = undefined;
    var borrow: W = WZERO;
    var k: usize = 0;
    while (k < N32) : (k += 1) {
        const mk: L = col(&modP, k);
        const d = (t[k] -% @as(W, mk)) -% borrow;
        diff[k] = d & MASK;
        borrow = (d >> SH) & @as(W, @splat(1));
    }
    const sub = (tn != WZERO) | (borrow == WZERO);
    var r: Batched = undefined;
    k = 0;
    while (k < NP) : (k += 1) {
        const lo: L = @truncate(@select(u64, sub, diff[2 * k], t[2 * k]));
        const hi: L = @truncate(@select(u64, sub, diff[2 * k + 1], t[2 * k + 1]));
        r[k] = .{ lo[0], lo[1], hi[0], hi[1] };
    }
    return r;
}

inline fn montSqrV(a: *const Batched) Batched {
    return montMulV(a, a);
}

// ---- conversions ----
pub fn split32(src: *const [32]u64) [N32]u32 {
    var out: [N32]u32 = undefined;
    for (0..32) |i| {
        out[2 * i] = @truncate(src[i]);
        out[2 * i + 1] = @truncate(src[i] >> 32);
    }
    return out;
}
// Build a packed batched number from two per-prime 32-bit limb arrays.
pub fn pack(p: *const [N32]u32, q: *const [N32]u32) Batched {
    var out: Batched = undefined;
    for (0..NP) |k| out[k] = .{ p[2 * k], q[2 * k], p[2 * k + 1], q[2 * k + 1] };
    return out;
}
// Extract one prime's 64-bit limbs (lane 0 = p, lane 1 = q).
pub fn unpack64(b: *const Batched, comptime lane: usize) [32]u64 {
    var c32: [N32]u32 = undefined;
    for (0..NP) |k| {
        c32[2 * k] = b[k][lane];
        c32[2 * k + 1] = b[k][lane + 2];
    }
    var out: [32]u64 = undefined;
    for (0..32) |i| out[i] = @as(u64, c32[2 * i]) | (@as(u64, c32[2 * i + 1]) << 32);
    return out;
}

inline fn bit(exp: *const [32]u64, idx: usize) u64 {
    if (idx >= 32 * 64) return 0;
    return (exp[idx >> 6] >> @intCast(idx & 63)) & 1;
}
inline fn window(exp: *const [32]u64, pos: usize) usize {
    var v: usize = 0;
    inline for (0..WINDOW) |b| v |= @as(usize, @intCast(bit(exp, pos + b))) << b;
    return v;
}

pub const WINDOW = 5;
pub const NW = 1 << WINDOW;
const EXP_BITS = ((2048 + WINDOW - 1) / WINDOW) * WINDOW;

pub fn batchedExp(
    tableP: *const [NW][N32]u32,
    tableQ: *const [NW][N32]u32,
    one: *const Batched,
) Batched {
    var result = one.*;
    var pos: isize = EXP_BITS - WINDOW;
    var first = true;
    while (pos >= 0) : (pos -= WINDOW) {
        if (!first) {
            inline for (0..WINDOW) |_| result = montSqrV(&result);
        }
        first = false;
        const cp = window(&key.p_exp, @intCast(pos));
        const cq = window(&key.q_exp, @intCast(pos));
        const op = pack(&tableP[cp], &tableQ[cq]);
        result = montMulV(&result, &op);
    }
    return result;
}
