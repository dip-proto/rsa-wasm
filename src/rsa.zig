const std = @import("std");
const bi = @import("bigint.zig");
const key = @import("key.zig");
const simd = @import("simd.zig");

const Fe = bi.Fe;
const N = bi.N;

pub const Params = struct {
    m: Fe,
    n0inv: u64,
    rr: Fe,
};

const P_params = Params{ .m = key.p, .n0inv = key.p_n0inv, .rr = key.p_rr };
const Q_params = Params{ .m = key.q, .n0inv = key.q_n0inv, .rr = key.q_rr };

inline fn montSqr(a: *const Fe, comptime P: Params) Fe {
    return bi.montSqr(a, P.m, P.n0inv);
}
inline fn montMul(a: *const Fe, b: *const Fe, comptime P: Params) Fe {
    return bi.montMul(a, b, P.m, P.n0inv);
}

// Reduce a full 2N-limb value into Montgomery form mod P.m: returns (M mod m)*R mod m.
pub fn reduceToMont(full: *const [2 * N]u64, comptime P: Params) Fe {
    var mlo: Fe = full[0..N].*;
    var mhi: Fe = full[N .. 2 * N].*;
    bi.condSub(&mlo, P.m); // each half < R < 2m, one subtraction reduces mod m
    bi.condSub(&mhi, P.m);
    const tlo = montMul(&mlo, &P.rr, P); // mlo * R mod m
    const thi = montMul(&mhi, &P.rr, P); // mhi * R mod m
    const thiR = montMul(&thi, &P.rr, P); // mhi * R^2 mod m
    return bi.addModNoMont(&thiR, &tlo, P.m);
}

inline fn bitAt(exp: *const Fe, idx: usize) u1 {
    return @truncate(exp[idx >> 6] >> @intCast(idx & 63));
}

const WINDOW = 7;
const TABLE_SIZE = 1 << (WINDOW - 1); // odd powers x^1, x^3, ... x^(2^w-1)

// Montgomery exponentiation with sliding window. base_mont is in Montgomery domain.
pub fn montExp(base_mont: *const Fe, exp: *const Fe, comptime P: Params, mont_one: *const Fe) Fe {
    var table: [TABLE_SIZE]Fe = undefined;
    table[0] = base_mont.*;
    const x2 = montSqr(base_mont, P);
    var k: usize = 1;
    while (k < TABLE_SIZE) : (k += 1) {
        table[k] = montMul(&table[k - 1], &x2, P);
    }

    // find highest set bit
    var top: isize = -1;
    {
        var i: isize = @as(isize, @intCast(N * 64)) - 1;
        while (i >= 0) : (i -= 1) {
            if (bitAt(exp, @intCast(i)) == 1) {
                top = i;
                break;
            }
        }
    }
    if (top < 0) return mont_one.*;

    var result = mont_one.*;
    var i: isize = top;
    while (i >= 0) {
        if (bitAt(exp, @intCast(i)) == 0) {
            result = montSqr(&result, P);
            i -= 1;
            continue;
        }
        // sliding window: find lowest index l >= i-WINDOW+1 with a set bit
        var l: isize = i - WINDOW + 1;
        if (l < 0) l = 0;
        while (bitAt(exp, @intCast(l)) == 0) l += 1;
        const wbits: usize = @intCast(i - l + 1);
        var s: usize = 0;
        while (s < wbits) : (s += 1) result = montSqr(&result, P);
        // extract window value (bits l..i)
        var val: usize = 0;
        var b: isize = i;
        while (b >= l) : (b -= 1) {
            val = (val << 1) | bitAt(exp, @intCast(b));
        }
        result = montMul(&result, &table[(val - 1) >> 1], P);
        i = l - 1;
    }
    return result;
}

fn montOne(comptime P: Params) Fe {
    // R mod m = (1 in Montgomery domain) = montMul(1, rr)
    var one = bi.zero();
    one[0] = 1;
    return montMul(&one, &P.rr, P);
}

const mont_one_p = montOne(P_params);
const mont_one_q = montOne(Q_params);

// PKCS#1 v1.5 DigestInfo prefix for SHA-256.
const sha256_prefix = [_]u8{
    0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01,
    0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
};

const K = 512; // modulus bytes (4096 bits)

// Build the PKCS#1 v1.5 padded message as a 2N-limb little-endian integer.
pub fn encodeMessage(msg: []const u8) [2 * N]u64 {
    var em: [K]u8 = undefined;
    em[0] = 0x00;
    em[1] = 0x01;
    const tlen = sha256_prefix.len + 32;
    const ps_len = K - 3 - tlen;
    @memset(em[2 .. 2 + ps_len], 0xff);
    em[2 + ps_len] = 0x00;
    @memcpy(em[3 + ps_len ..][0..sha256_prefix.len], &sha256_prefix);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(msg, &digest, .{});
    @memcpy(em[3 + ps_len + sha256_prefix.len ..][0..32], &digest);

    // Convert big-endian EM into little-endian limbs.
    var out: [2 * N]u64 = @splat(0);
    var i: usize = 0;
    while (i < 2 * N) : (i += 1) {
        var limb: u64 = 0;
        var b: usize = 0;
        while (b < 8) : (b += 1) {
            const byte_idx = K - 1 - (i * 8 + b);
            limb |= @as(u64, em[byte_idx]) << @intCast(b * 8);
        }
        out[i] = limb;
    }
    return out;
}

// Build the fixed-window table x^0..x^31 (Montgomery domain) in 32-bit limbs.
fn buildTable(base: *const Fe, comptime P: Params, mont_one: *const Fe) [simd.NW][simd.N32]u32 {
    var t64: [simd.NW]Fe = undefined;
    t64[0] = mont_one.*;
    t64[1] = base.*;
    var k: usize = 2;
    while (k < simd.NW) : (k += 1) t64[k] = montMul(&t64[k - 1], base, P);
    var t32: [simd.NW][simd.N32]u32 = undefined;
    for (0..simd.NW) |i| t32[i] = simd.split32(&t64[i]);
    return t32;
}

pub const USE_SIMD = false;

// Sign: returns 512-byte signature (big-endian).
pub fn sign(msg: []const u8) [K]u8 {
    const m_full = encodeMessage(msg);

    // CRT bases in Montgomery domain.
    const base_p = reduceToMont(&m_full, P_params);
    const base_q = reduceToMont(&m_full, Q_params);

    var one = bi.zero();
    one[0] = 1;
    var sp_mont: Fe = undefined;
    var sq_mont: Fe = undefined;
    if (USE_SIMD) {
        // Both modular exponentiations run in lockstep across SIMD lanes (p||q).
        const tP = buildTable(&base_p, P_params, &mont_one_p);
        const tQ = buildTable(&base_q, Q_params, &mont_one_q);
        const oneB = simd.pack(&simd.split32(&mont_one_p), &simd.split32(&mont_one_q));
        const res = simd.batchedExp(&tP, &tQ, &oneB);
        sp_mont = simd.unpack64(&res, 0);
        sq_mont = simd.unpack64(&res, 1);
    } else {
        sp_mont = montExp(&base_p, &key.p_exp, P_params, &mont_one_p);
        sq_mont = montExp(&base_q, &key.q_exp, Q_params, &mont_one_q);
    }

    // convert out of Montgomery domain
    const sp = montMul(&sp_mont, &one, P_params);
    const sq = montMul(&sq_mont, &one, Q_params);

    // Garner: h = (sp - sq) * qinv mod p ; s = sq + q*h
    var sq_modp = sq;
    bi.condSub(&sq_modp, key.p); // sq mod p
    const diff = bi.subMod(&sp, &sq_modp, key.p);
    const h = bi.montMul(&diff, &key.qinv_mont, key.p, key.p_n0inv); // diff*qinv mod p

    // s = sq + q*h  (full 2N-limb result)
    const qh = bi.mulFull(&key.q, &h);
    var s: [2 * N]u64 = qh;
    var carry: u128 = 0;
    var i: usize = 0;
    while (i < N) : (i += 1) {
        const t = @as(u128, s[i]) + @as(u128, sq[i]) + carry;
        s[i] = @truncate(t);
        carry = t >> 64;
    }
    while (i < 2 * N and carry != 0) : (i += 1) {
        const t = @as(u128, s[i]) + carry;
        s[i] = @truncate(t);
        carry = t >> 64;
    }

    // I2OSP: little-endian limbs -> big-endian bytes
    var sig: [K]u8 = undefined;
    i = 0;
    while (i < 2 * N) : (i += 1) {
        var b: usize = 0;
        while (b < 8) : (b += 1) {
            sig[K - 1 - (i * 8 + b)] = @truncate(s[i] >> @intCast(b * 8));
        }
    }
    return sig;
}

test "sign matches the OpenSSL reference signature" {
    const expected_hex = "b6aa8323eea329987e604742c8d81aa146bb925bd9e3361f1c8361a0737cb75b4c9d8e370f6a2375de35fd3282c5f099d9ed42394858060a5377ebd9d0aee2cbc88a7183e82fb00f3864bf8de00137964907e28049e6cca652974f8fa15b68cf651a4ddbd6afefa7a8d2db3f6ad4f4d045bd54cf1cf668248594c1bf2c1cb34619e0e6812380abf2f456b90b74660c8bf4409b0a9aaedde63042d0cbefebefebb2c9f92b83bc82d27a39223420e18b9b44a2bf8774ae730e66cb35258b8c35f3ffcba2ed76842d7f93e9d86a0312c58a5e29d89d9a851543501b5b5c14d7b2ccbffc55c092d91229f0e3ac673b439a7e6ec8d8445d8634a4ec40e39a1f52a95d6e57e5a854d36dcc2be87ac8bd69bece3f9c65e8dd6b0210dcff35faa595c79f436cda2c36dc3d3606dcfc7917d356a92bd715acfecdaff0ec2e71585472d6e2314c6877cbf2734c0075c194864f2f0f2b33a9eb511296c669cdf8d96d2da3ba00403dff544a6c868fb3e38a95931701e9bd4eef5e869859865b2c1b5156e21af3ce0a140441bc712b429e582af78e9b79c8cabc6b38df1e54933689851011650bebdcf5d27a40d724c34c12f566d9f353c457dc23a8ec86d0e9f724068145a4eb29bb8abb93ed5de1cb26840539984c5dca2d7e85507fb7fd9a5bb72d3daa47e9d17001ae61834a54bccf9bde7ef568db13c0556817aab9d904ad95bc1107fa";
    var expected: [K]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected, expected_hex);
    const sig = sign("hello rsa wasm benchmark message");
    try std.testing.expectEqualSlices(u8, &expected, &sig);
}
