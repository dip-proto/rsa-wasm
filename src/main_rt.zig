const std = @import("std");
const rsa = @import("rsa_rt.zig");
const key_rt = @import("key_rt.zig");
const bench = @import("bench.zig");

pub fn main() !void {
    const msg = "hello rsa wasm benchmark message";

    // Build the key from its hex form at runtime and hand it to sign() as an
    // ordinary argument, exactly the way the message is. The modulus is never a
    // compile-time constant, so the optimizer cannot specialize the Montgomery
    // loops on it. This setup runs once, before the timed loop below.
    const d = key_rt.default;
    const k = try rsa.Key.fromHex(d.p_hex, d.q_hex, d.dp_hex, d.dq_hex, d.qinv_hex);

    // Correctness: print signature hex.
    const sig = rsa.sign(&k, msg);
    const hex = std.fmt.bytesToHex(sig, .lower);
    std.debug.print("sig={s}\n", .{hex});

    // Benchmark: the key setup above is one-time and outside this loop. The loop
    // count is fixed at build time (-Diters); timing two counts and subtracting
    // also cancels process/instantiation overhead.
    var acc: u8 = 0;
    for (0..bench.iters) |_| {
        const s = rsa.sign(&k, msg);
        acc ^= s[0] ^ s[511];
    }
    std.debug.print("iters={d} acc={d}\n", .{ bench.iters, acc });
}
