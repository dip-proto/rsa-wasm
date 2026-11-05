const std = @import("std");

pub fn build(b: *std.Build) void {
    // Wide arithmetic makes signing about 2.5x faster, but not every runtime supports it yet.
    // -Dwide-arithmetic=false builds without it, as rsa_nowide.wasm.
    //
    // The output name and wasm-opt flags follow the CPU features actually used, so they stay right with -Dtarget or -Dcpu.
    const wide_option = b.option(bool, "wide-arithmetic", "Use the wasm wide-arithmetic feature (default true; set false for old runtimes)");
    const default_query = std.Target.Query.parse(.{
        .arch_os_abi = "wasm32-wasi",
        .cpu_features = if (wide_option orelse true) "lime1+simd128+wide_arithmetic" else "lime1+simd128",
    }) catch unreachable;
    const target = b.standardTargetOptions(.{ .default_target = default_query });
    const is_wasm = target.result.cpu.arch.isWasm();
    const wide = is_wasm and std.Target.wasm.featureSetHas(target.result.cpu.features, .wide_arithmetic);
    const name = if (is_wasm and !wide) "rsa_nowide" else "rsa";
    const optimize = b.option(std.lang.Optimize, "optimize", "Optimization mode (default fast)") orelse .fast;

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
        .name = name,
        .root_module = root_mod,
    });
    if (wide_option) |requested| {
        if (is_wasm and requested != wide) {
            exe.step.dependOn(&b.addFail("-Dwide-arithmetic doesn't match the CPU features from -Dtarget/-Dcpu").step);
        }
    }
    b.installArtifact(exe);

    const opt_step = b.step("opt", "Build then run wasm-opt -O4 on the wasm");
    if (is_wasm) {
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
        const opt_name = b.fmt("{s}.opt.wasm", .{name});
        const opt_out = wasm_opt.addOutputFileArg(opt_name);
        const install_opt = b.addInstallBinFile(opt_out, opt_name);
        opt_step.dependOn(&install_opt.step);
    } else {
        opt_step.dependOn(&b.addFail("the opt step only works for wasm targets").step);
    }

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
