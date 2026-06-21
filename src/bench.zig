const build_options = @import("build_options");

// Number of signatures per benchmark run, fixed at build time via -Diters=N.
// The harness builds two binaries with different counts and subtracts the wall
// times, which cancels every fixed cost: process startup, wasm instantiation,
// and the one-time runtime key setup.
pub const iters: usize = build_options.iters;
