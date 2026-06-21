const std = @import("std");
const rsa = @import("rsa.zig");
const bench = @import("bench.zig");

pub fn main() !void {
    const msg = "hello rsa wasm benchmark message";

    // Correctness: print signature hex
    const sig = rsa.sign(msg);
    const hex = std.fmt.bytesToHex(sig, .lower);
    std.debug.print("sig={s}\n", .{hex});

    // Benchmark: the loop count is fixed at build time (-Diters). Timing two
    // counts and subtracting cancels all fixed overhead.
    var acc: u8 = 0;
    for (0..bench.iters) |_| {
        const s = rsa.sign(msg);
        acc ^= s[0] ^ s[511];
    }
    std.debug.print("iters={d} acc={d}\n", .{ bench.iters, acc });
}
