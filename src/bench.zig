const build_options = @import("build_options");

// Number of signatures per benchmark run, fixed at build time via -Diters=N.
// The harness builds two binaries with different counts and subtracts the wall
// times, which cancels every fixed cost: process startup, wasm instantiation,
// and the one-time runtime key setup.
pub const iters: usize = build_options.iters;

// RSA modulus size selected at build time via -Dbits=N (2048, 3072 or 4096).
pub const bits: usize = build_options.bits;
