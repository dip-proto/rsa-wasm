const std = @import("std");
const rsa = @import("rsa.zig");
const key = @import("key.zig");
const bench = @import("bench.zig");

// The modulus size is chosen at build time (-Dbits=N). Rsa(bits) and the matching
// default key are both selected at comptime, so the signing loop below is fully
// specialized for the one size this binary was built for.
const R = rsa.Rsa(bench.bits);
const d = switch (bench.bits) {
    2048 => key.default2048,
    3072 => key.default3072,
    4096 => key.default4096,
    else => @compileError("unsupported modulus size"),
};

pub fn main() !void {
    const msg = "hello rsa wasm benchmark message";

    // Build the key from its hex form at runtime and hand it to sign() as an
    // ordinary argument, exactly the way the message is. The modulus is never a
    // compile-time constant, so the optimizer cannot specialize the Montgomery
    // loops on it. This setup runs once, before the timed loop below.
    const k = try R.Key.fromHex(d.p_hex, d.q_hex, d.dp_hex, d.dq_hex, d.qinv_hex);

    // Correctness: print signature hex.
    const sig = R.sign(&k, msg);
    const hex = std.fmt.bytesToHex(sig, .lower);
    std.debug.print("bits={d} sig={s}\n", .{ bench.bits, hex });

    // Benchmark: the key setup above is one-time and outside this loop. The loop
    // count is fixed at build time (-Diters); timing two counts and subtracting
    // also cancels process/instantiation overhead.
    var acc: u8 = 0;
    for (0..bench.iters) |_| {
        const s = R.sign(&k, msg);
        acc ^= s[0] ^ s[R.signature_len - 1];
    }
    std.debug.print("iters={d} acc={d}\n", .{ bench.iters, acc });
}
