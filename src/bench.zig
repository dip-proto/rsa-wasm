const std = @import("std");
const build_options = @import("build_options");

// Time two builds with different -Diters and subtract, so startup and key setup cancel out.
pub const iters: usize = build_options.iters;

pub const bits: usize = build_options.bits;

pub const side_channels_mitigations = @field(std.crypto.SideChannelsMitigations, @tagName(build_options.side_channels_mitigations));
