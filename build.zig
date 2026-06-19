const std = @import("std");

pub fn build(b: *std.Build) void {
    // Default to the goal's target: wasm32-wasi, cpu lime1+simd128+wide_arithmetic, ReleaseFast.
    // Override with -Dtarget=... / -Dcpu=... / -Doptimize=... for e.g. native tests.
    const default_query = std.Target.Query.parse(.{
        .arch_os_abi = "wasm32-wasi",
        .cpu_features = "lime1+simd128+wide_arithmetic",
    }) catch unreachable;
    const target = b.standardTargetOptions(.{ .default_target = default_query });
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Optimization mode (default ReleaseFast)") orelse .ReleaseFast;

    const exe = b.addExecutable(.{
        .name = "rsa",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = true,
        }),
    });
    b.installArtifact(exe);

    const opt_step = b.step("opt", "Build then run wasm-opt -O4 on the wasm");
    const wasm_opt = b.addSystemCommand(&.{
        "wasm-opt",
        "-O4",
        "--enable-simd",
        "--enable-bulk-memory",
        "--enable-bulk-memory-opt",
        "--enable-nontrapping-float-to-int",
        "--enable-sign-ext",
        "--enable-multivalue",
        "--enable-extended-const",
        "--enable-wide-arithmetic",
    });
    wasm_opt.addArtifactArg(exe);
    wasm_opt.addArg("-o");
    const opt_out = wasm_opt.addOutputFileArg("rsa.opt.wasm");
    const install_opt = b.addInstallBinFile(opt_out, "rsa.opt.wasm");
    opt_step.dependOn(&install_opt.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/rsa.zig"),
            .target = b.resolveTargetQuery(.{}), // native
            .optimize = optimize,
        }),
    });
    const test_step = b.step("test", "Run correctness tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const run_step = b.step("run", "Run the app (under the host or a wasm runtime)");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
}
