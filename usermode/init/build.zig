const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    var features_add = std.Target.riscv.featureSet(&.{});
    features_add.addFeature(@intFromEnum(std.Target.riscv.Feature.@"32bit"));
    features_add.addFeature(@intFromEnum(std.Target.riscv.Feature.i));
    features_add.addFeature(@intFromEnum(std.Target.riscv.Feature.m));
    features_add.addFeature(@intFromEnum(std.Target.riscv.Feature.a));
    features_add.addFeature(@intFromEnum(std.Target.riscv.Feature.c));
    features_add.addFeature(@intFromEnum(std.Target.riscv.Feature.zihintpause));

    var features_sub = std.Target.riscv.featureSet(&.{});
    features_sub.removeFeature(@intFromEnum(std.Target.riscv.Feature.f));
    features_sub.removeFeature(@intFromEnum(std.Target.riscv.Feature.d));

    const target_query: std.Target.Query = .{
        .cpu_arch = .riscv32,
        .cpu_features_add = features_add,
        .cpu_features_sub = features_sub,
        .cpu_model = .baseline,
        .os_tag = .freestanding,
        .abi = .none,
        .ofmt = .elf,
    };
    const target = b.resolveTargetQuery(target_query);

    const kernel_lib = b.dependency("sorz", .{ .optimize = optimize, .target = target });
    const kernel_mod = kernel_lib.module("sorz");
    _ = kernel_mod;

    const mod = b.addModule("init", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "init",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "init", .module = mod },
                // .{ .name = "sorz", .module = kernel_mod },
            },
        }),
    });
    exe.setLinkerScript(.{ .cwd_relative = "usermode/linker.ld" });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
