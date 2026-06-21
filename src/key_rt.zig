const std = @import("std");
const bi = @import("bigint.zig");

const Fe = bi.Fe;
const N = bi.N;

// A signing key whose limbs and Montgomery constants are produced at runtime.
// Everything here is computed once, before the benchmark's timing loop, so the
// per-signature cost reflects only the modular exponentiation with a modulus the
// compiler never saw.
pub const Key = struct {
    p: Fe,
    q: Fe,
    p_exp: Fe, // dp = d mod (p-1)
    q_exp: Fe, // dq = d mod (q-1)
    p_n0inv: u64,
    q_n0inv: u64,
    p_rr: Fe, // R^2 mod p
    q_rr: Fe, // R^2 mod q
    qinv_mont: Fe, // (q^-1 mod p) * R mod p

    pub fn fromHex(
        p_hex: []const u8,
        q_hex: []const u8,
        dp_hex: []const u8,
        dq_hex: []const u8,
        qinv_hex: []const u8,
    ) !Key {
        const p = try hexToFe(p_hex);
        const q = try hexToFe(q_hex);
        const p_rr = computeRR(&p);
        const q_rr = computeRR(&q);
        const qinv = try hexToFe(qinv_hex);
        return .{
            .p = p,
            .q = q,
            .p_exp = try hexToFe(dp_hex),
            .q_exp = try hexToFe(dq_hex),
            .p_n0inv = negInv64(p[0]),
            .q_n0inv = negInv64(q[0]),
            .p_rr = p_rr,
            .q_rr = q_rr,
            // qinv * R mod p = montMul(qinv, R^2) since montMul folds in one R^-1.
            .qinv_mont = bi.montMulRt(&qinv, &p_rr, &p, negInv64(p[0])),
        };
    }
};

// Big-endian hex (up to 2048 bits) into little-endian 64-bit limbs.
fn hexToFe(hex: []const u8) !Fe {
    if (hex.len > 2 * 8 * N) return error.KeyTooLong;
    var bytes: [8 * N]u8 = @splat(0);
    // Right-align the value so short (leading-zero-trimmed) hex still lands in
    // the low end of the big-endian buffer.
    const nbytes = hex.len / 2;
    _ = try std.fmt.hexToBytes(bytes[8 * N - nbytes ..], hex);
    var fe: Fe = @splat(0);
    for (0..N) |i| {
        fe[i] = std.mem.readInt(u64, bytes[8 * N - 8 * (i + 1) ..][0..8], .big);
    }
    return fe;
}

// -m^-1 mod 2^64 via Newton's iteration (doubles correct bits each step).
fn negInv64(m0: u64) u64 {
    var x: u64 = 1;
    inline for (0..6) |_| x = x *% (2 -% m0 *% x);
    return 0 -% x;
}

// R^2 mod m with R = 2^(64*N): start at 1 and double mod m 2*64*N times.
fn computeRR(m: *const Fe) Fe {
    var acc: Fe = @splat(0);
    acc[0] = 1;
    for (0..2 * 64 * N) |_| {
        var carry: u64 = 0;
        for (0..N) |i| {
            const nc = acc[i] >> 63;
            acc[i] = (acc[i] << 1) | carry;
            carry = nc;
        }
        if (carry != 0 or bi.geq(&acc, m)) {
            var borrow: u128 = 0;
            for (0..N) |i| {
                const d = @as(u128, acc[i]) -% @as(u128, m[i]) -% borrow;
                acc[i] = @truncate(d);
                borrow = (d >> 64) & 1;
            }
        }
    }
    return acc;
}

// The default key (same one carried in src/key.zig), used when no key is passed
// on the command line. Parsing still happens at runtime.
pub const default = struct {
    pub const p_hex = "fb2a1320a90ee6c86e32e58dbdb2ee83ef3b0d469777c03dfa00100dfdba1bcc7fc81436609a1eb48bcc9d3fed834c92eeda92b98f94fad6de1154a64df92d71246e8e3c47117c891f9b11735c4e26da82240d8682c260eaf7ea809ca4e650f6b94792ff6e6fc21639faba5e42d28a0ea10f964faf8fe6617ca9cd6e3eb8a11b9dda9711d94e445d65442a319756873ee9c1f07c1e4fc0b70004361144e7a1dbee22f6506de29568e85cc88b2c55fd65092800f0e3ef7e03086739119c40e1ac3d7a02236956c400bc0e1f774782a26905ce5ac71388231273be097b571dc53f20f83154a173ea9b003708ade10e9df8aa1e74556ed92f21ba4a3c90c8c3ef17";
    pub const q_hex = "d79723f52ffb8aa5b3d538a8b4cc70986437e330f35c258f62e1c798e81e120d87d52e1e1d871ac274be4a34bdc1c9e2ca8344822ace5e4a2fbe43775725056d6e8592bbbab015f659f483725a5bcf796d14527f1f224420955fc1985ad18a12a08e1005aa417669407867f3dbad2a686112804f284b0052444e4fdcee5f5a9de1ae1fc6ba0b8126ca555bfde9a4ae0ee646b5f5c8536a066bab025e05db8d37ba1de45f150627cafe42313fe9c6ea842d96f2de84e60021d4fe863fcf5717ecf6fe6e6f39698f35ae71bf561b9d1c30eebd600fe4505fccf691b9f7acffdc284d505383efc9e6590ad224e03c4583ee4e1e02aff9ef77eeff5b9ec29b0359eb";
    pub const dp_hex = "cd95e70a38d765b871db5f62e1fff09435e1d4401003896c31929391a03a123f15e924024e9858c1d81ca82a87b38d9e47bcc994f21e342464a932ecddae34b003ee2aa6d4554fe6bde424289549b32bf092aa2f8c20a74c2d99d9a45ea5d767dcc8e55e077b9b16ae66b8de273c469d2ae0a35c9e8bdf3bb4db18b840c6c7b8df40e99f468c76112caedb0ab4a1b31aa0248b404d5f6293688409eda0c5290be8a4dd91802093c3c74f0b28402632bfdcfacdaa6028ccb096d447364efc1cbceba54ed2c58aabed1e01416855346cd42258829da93329e214b35cf7849b6db4fabbad4564d2891a4ed6bd57f67c0c7a5a658b3bd2fc1b44344447c70b4eb609";
    pub const dq_hex = "52bff5924ff789f12e448239e723ad7820c77ed1b42743577509da75eb6a575d902c984600e971b0ffe466513620a2e005013b9386e0ad3a6676ee28696f9154be9e5082f4165067bd8167cec5b605bdc2cb911ab01593f6b9bf066cf737047b3fdb277535336942def71857769351fabc7fc07621ae2012739b6776129cd10856ae620e022d16469055113935abfb0f46fe0f2ba6d7b5937f52255777821d032dd1f96d3181aa56751f6d0dee2a66ab9360241a9b02393cc3276ada253875bb83d68706f40f7b638c70a6936387fb6120d1d984600b25aa635dedf68e15ab2860fc9b01c25149b415be315f4c63164faaf643ebcdd047c599884e38be0d1c3f";
    pub const qinv_hex = "39e5d481418f5c754ff1fb3c9aaee8905d76e95091134bb48bb0206172b8eb0aff5d1cac2fc2bc06bb465f8f0b4c30d9156789f57890807f3e61b91a6d510b3ad36e9ea01a1e9c40d98e6a21f6f5e188751b13712b1e0e3469bb14b9715b3a43483813156c6b0b20ea96fc33c3154a2b3d79d8b294d5b82dbb8c3ae7aa433a9ee8cc0ae0aff4605bc7921c41b01b96b1ffca5771f201176d2529e9cf2f4993cf69a055889f45f38462089392670a7421780c8ed031dd11160ef071c612c898c14841de917e0052ed3800e56cf8f81f28ee54c93f58bf07ebf53e3e0f5e26fd784b7ef539c87aa8c34b122a0224f05ea1f63b58233ef801ad8a0e18b8b136dba5";
};
