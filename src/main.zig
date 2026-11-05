const std = @import("std");
const rsa = @import("rsa.zig");
const key = @import("key.zig");
const bench = @import("bench.zig");

pub const std_options: std.Options = .{ .side_channels_mitigations = bench.side_channels_mitigations };

const R = rsa.Rsa(bench.bits);
const d = switch (bench.bits) {
    2048 => key.default2048,
    3072 => key.default3072,
    4096 => key.default4096,
    else => @compileError("unsupported modulus size"),
};

pub fn main() !void {
    const msg = "hello rsa wasm benchmark message";

    // Parse the key at runtime, like a real app would, so the modulus isn't a compile-time constant.
    const k = try R.Key.fromHex(d.p_hex, d.q_hex, d.dp_hex, d.dq_hex, d.qinv_hex);

    // Print the signature so it can be checked against the reference.
    const sig = R.sign(&k, msg);
    const hex = std.fmt.bytesToHex(sig, .lower);
    std.debug.print("bits={d} sig={s}\n", .{ bench.bits, hex });

    var acc: u8 = 0;
    for (0..bench.iters) |_| {
        const s = R.sign(&k, msg);
        acc ^= s[0] ^ s[R.signature_len - 1];
    }
    std.debug.print("iters={d} acc={d}\n", .{ bench.iters, acc });
}
