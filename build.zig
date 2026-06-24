const std = @import("std");

pub fn build(b: *std.Build) void {
    // Default to the goal's target: wasm32-wasi, cpu lime1+simd128+wide_arithmetic, ReleaseFast.
    // Override with -Dtarget=... / -Dcpu=... / -Doptimize=... for e.g. native tests.
    //
    // wide_arithmetic lets the Montgomery inner loop lower to i64.mul_wide_u instead
    // of a __multi3 helper and is worth ~2.4x. Runtimes that do not implement the
    // proposal cannot validate such a module; build with -Dwide-arithmetic=false to
    // drop the feature (bigint.zig then synthesizes the product from plain i64.mul)
    // and the artifact is named rsa_nowide so both can sit in zig-out/bin together.
    const wide = b.option(bool, "wide-arithmetic", "Use the wasm wide-arithmetic feature (default true; set false for old runtimes)") orelse true;
    const default_query = std.Target.Query.parse(.{
        .arch_os_abi = "wasm32-wasi",
        .cpu_features = if (wide) "lime1+simd128+wide_arithmetic" else "lime1+simd128",
    }) catch unreachable;
    const target = b.standardTargetOptions(.{ .default_target = default_query });
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Optimization mode (default ReleaseFast)") orelse .ReleaseFast;

    const iters = b.option(usize, "iters", "Signatures per benchmark run (default 500)") orelse 500;
    const bits = b.option(usize, "bits", "RSA modulus size: 2048, 3072 or 4096 (default 4096)") orelse 4096;
    std.debug.assert(bits == 2048 or bits == 3072 or bits == 4096);
    const bench_opts = b.addOptions();
    bench_opts.addOption(usize, "iters", iters);
    bench_opts.addOption(usize, "bits", bits);

    const root_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = true,
    });
    root_mod.addOptions("build_options", bench_opts);

    const exe = b.addExecutable(.{
        .name = if (wide) "rsa" else "rsa_nowide",
        .root_module = root_mod,
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
    });
    if (wide) wasm_opt.addArg("--enable-wide-arithmetic");
    wasm_opt.addArtifactArg(exe);
    wasm_opt.addArg("-o");
    const opt_name = if (wide) "rsa.opt.wasm" else "rsa_nowide.opt.wasm";
    const opt_out = wasm_opt.addOutputFileArg(opt_name);
    const install_opt = b.addInstallBinFile(opt_out, opt_name);
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
