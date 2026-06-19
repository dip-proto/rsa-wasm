const std = @import("std");
const rsa = @import("rsa.zig");

pub fn main() !void {
    const msg = "hello rsa wasm benchmark message";

    // Correctness: print signature hex
    const sig = rsa.sign(msg);
    const hex = std.fmt.bytesToHex(sig, .lower);
    std.debug.print("sig={s}\n", .{hex});

    // Benchmark: timed externally with `time`. ITERS via comptime default.
    const iters = 500;
    var acc: u8 = 0;
    for (0..iters) |_| {
        const s = rsa.sign(msg);
        acc ^= s[0] ^ s[511];
    }
    std.debug.print("iters={d} acc={d}\n", .{ iters, acc });
}
