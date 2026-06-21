const std = @import("std");
const bi = @import("bigint.zig");
const key_rt = @import("key_rt.zig");

const Fe = bi.Fe;
const N = bi.N;
pub const Key = key_rt.Key;

const K = 512; // modulus bytes (4096 bits)

const sha256_prefix = [_]u8{
    0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01,
    0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
};

fn encodeMessage(msg: []const u8) [2 * N]u64 {
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

    var out: [2 * N]u64 = @splat(0);
    for (0..2 * N) |i| {
        out[i] = std.mem.readInt(u64, em[K - 8 * (i + 1) ..][0..8], .big);
    }
    return out;
}

fn reduceToMont(full: *const [2 * N]u64, m: *const Fe, n0inv: u64, rr: *const Fe) Fe {
    var mlo: Fe = full[0..N].*;
    var mhi: Fe = full[N .. 2 * N].*;
    bi.condSubRt(&mlo, m);
    bi.condSubRt(&mhi, m);
    const tlo = bi.montMulRt(&mlo, rr, m, n0inv);
    const thi = bi.montMulRt(&mhi, rr, m, n0inv);
    const thiR = bi.montMulRt(&thi, rr, m, n0inv);
    return bi.addModNoMontRt(&thiR, &tlo, m);
}

inline fn bitAt(exp: *const Fe, idx: usize) u1 {
    return @truncate(exp[idx >> 6] >> @intCast(idx & 63));
}

const WINDOW = 7;
const TABLE_SIZE = 1 << (WINDOW - 1);

fn montExp(base_mont: *const Fe, exp: *const Fe, m: *const Fe, n0inv: u64, mont_one: *const Fe) Fe {
    var table: [TABLE_SIZE]Fe = undefined;
    table[0] = base_mont.*;
    const x2 = bi.montSqrRt(base_mont, m, n0inv);
    for (1..TABLE_SIZE) |k| {
        table[k] = bi.montMulRt(&table[k - 1], &x2, m, n0inv);
    }

    var top: isize = -1;
    {
        var li: usize = N;
        while (li > 0) {
            li -= 1;
            if (exp[li] != 0) {
                top = @intCast(li * 64 + 63 - @clz(exp[li]));
                break;
            }
        }
    }
    if (top < 0) return mont_one.*;

    var result = mont_one.*;
    var i: isize = top;
    while (i >= 0) {
        if (bitAt(exp, @intCast(i)) == 0) {
            result = bi.montSqrRt(&result, m, n0inv);
            i -= 1;
            continue;
        }
        var l: isize = i - WINDOW + 1;
        if (l < 0) l = 0;
        while (bitAt(exp, @intCast(l)) == 0) l += 1;
        const wbits: usize = @intCast(i - l + 1);
        for (0..wbits) |_| result = bi.montSqrRt(&result, m, n0inv);
        var val: usize = 0;
        var b: isize = i;
        while (b >= l) : (b -= 1) {
            val = (val << 1) | bitAt(exp, @intCast(b));
        }
        result = bi.montMulRt(&result, &table[(val - 1) >> 1], m, n0inv);
        i = l - 1;
    }
    return result;
}

inline fn montOne(m: *const Fe, n0inv: u64, rr: *const Fe) Fe {
    var one = bi.zero();
    one[0] = 1;
    return bi.montMulRt(&one, rr, m, n0inv);
}

// Sign with a runtime key: returns the 512-byte big-endian signature.
pub fn sign(k: *const Key, msg: []const u8) [K]u8 {
    const m_full = encodeMessage(msg);

    const base_p = reduceToMont(&m_full, &k.p, k.p_n0inv, &k.p_rr);
    const base_q = reduceToMont(&m_full, &k.q, k.q_n0inv, &k.q_rr);

    const mont_one_p = montOne(&k.p, k.p_n0inv, &k.p_rr);
    const mont_one_q = montOne(&k.q, k.q_n0inv, &k.q_rr);

    const sp_mont = montExp(&base_p, &k.p_exp, &k.p, k.p_n0inv, &mont_one_p);
    const sq_mont = montExp(&base_q, &k.q_exp, &k.q, k.q_n0inv, &mont_one_q);

    var one = bi.zero();
    one[0] = 1;
    const sp = bi.montMulRt(&sp_mont, &one, &k.p, k.p_n0inv);
    const sq = bi.montMulRt(&sq_mont, &one, &k.q, k.q_n0inv);

    // Garner: h = (sp - sq) * qinv mod p ; s = sq + q*h
    var sq_modp = sq;
    bi.condSubRt(&sq_modp, &k.p);
    const diff = bi.subModRt(&sp, &sq_modp, &k.p);
    const h = bi.montMulRt(&diff, &k.qinv_mont, &k.p, k.p_n0inv);

    const qh = bi.mulFull(&k.q, &h);
    var s: [2 * N]u64 = qh;
    var carry: u128 = 0;
    for (0..N) |i| {
        const t = @as(u128, s[i]) + @as(u128, sq[i]) + carry;
        s[i] = @truncate(t);
        carry = t >> 64;
    }
    var i: usize = N;
    while (i < 2 * N and carry != 0) : (i += 1) {
        const t = @as(u128, s[i]) + carry;
        s[i] = @truncate(t);
        carry = t >> 64;
    }

    var sig: [K]u8 = undefined;
    for (0..2 * N) |j| {
        std.mem.writeInt(u64, sig[K - 8 * (j + 1) ..][0..8], s[j], .big);
    }
    return sig;
}

test "runtime-key sign matches the OpenSSL reference signature" {
    const d = key_rt.default;
    const k = try Key.fromHex(d.p_hex, d.q_hex, d.dp_hex, d.dq_hex, d.qinv_hex);
    const expected_hex = "b6aa8323eea329987e604742c8d81aa146bb925bd9e3361f1c8361a0737cb75b4c9d8e370f6a2375de35fd3282c5f099d9ed42394858060a5377ebd9d0aee2cbc88a7183e82fb00f3864bf8de00137964907e28049e6cca652974f8fa15b68cf651a4ddbd6afefa7a8d2db3f6ad4f4d045bd54cf1cf668248594c1bf2c1cb34619e0e6812380abf2f456b90b74660c8bf4409b0a9aaedde63042d0cbefebefebb2c9f92b83bc82d27a39223420e18b9b44a2bf8774ae730e66cb35258b8c35f3ffcba2ed76842d7f93e9d86a0312c58a5e29d89d9a851543501b5b5c14d7b2ccbffc55c092d91229f0e3ac673b439a7e6ec8d8445d8634a4ec40e39a1f52a95d6e57e5a854d36dcc2be87ac8bd69bece3f9c65e8dd6b0210dcff35faa595c79f436cda2c36dc3d3606dcfc7917d356a92bd715acfecdaff0ec2e71585472d6e2314c6877cbf2734c0075c194864f2f0f2b33a9eb511296c669cdf8d96d2da3ba00403dff544a6c868fb3e38a95931701e9bd4eef5e869859865b2c1b5156e21af3ce0a140441bc712b429e582af78e9b79c8cabc6b38df1e54933689851011650bebdcf5d27a40d724c34c12f566d9f353c457dc23a8ec86d0e9f724068145a4eb29bb8abb93ed5de1cb26840539984c5dca2d7e85507fb7fd9a5bb72d3daa47e9d17001ae61834a54bccf9bde7ef568db13c0556817aab9d904ad95bc1107fa";
    var expected: [K]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected, expected_hex);
    const sig = sign(&k, "hello rsa wasm benchmark message");
    try std.testing.expectEqualSlices(u8, &expected, &sig);
}
