const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    _ = target;
    const optimize = b.standardOptimizeOption(.{});

    var sorz_options = b.addOptions();
    const trace_support = b.option(bool, "sorz_trace", "Build kernel with support for printing stack traces with debug info, this will disable the ability to use a debugger with the kernel though") orelse true;
    sorz_options.addOption(bool, "trace", trace_support);

    const dtb = b.dependency("dtb", .{
        // .target = target,
        .optimize = optimize,
    });

    const mod = b.addModule("sorz", .{
        .root_source_file = b.path("src/root.zig"),
        // .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "dtb", .module = dtb.module("dtb") },
        },
    });
    mod.addOptions("sorz_options", sorz_options);
}
