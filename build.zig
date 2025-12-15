const std = @import("std");

pub fn build(b: *std.Build) void {
    const host_target = b.standardTargetOptions(.{});
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

    const freestanding_lib = b.dependency("freestanding", .{
        .target = target,
        .optimize = optimize,
    });

    const kernel = b.addExecutable(.{
        .name = "kernel.sorz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "freestanding", .module = freestanding_lib.module("freestanding") },
            },
        }),
    });
    kernel.setLinkerScript(.{ .cwd_relative = "./src/linker.ld" });

    b.installArtifact(kernel);

    const run_step = b.step("run", "Run the app");

    // const run_cmd = b.addRunArtifact(exe);
    const run_cmd = b.addSystemCommand(&.{
        "qemu-system-riscv32",
        "-M",
        "virt",
        "-m",
        "128M",
        "-nographic",
        "-smp",
        "16",
        "-serial",
        "mon:stdio",
        "-kernel",
    });
    run_cmd.addFileInput(kernel.getEmittedBin());
    run_cmd.addFileArg(kernel.getEmittedBin());
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    const debug_step = b.step("debug", "start debug server");

    // const run_cmd = b.addRunArtifact(exe);
    const debug_cmd = b.addSystemCommand(&.{
        "qemu-system-riscv32",
        "-M",
        "virt",
        "-m",
        "128M",
        "-nographic",
        "-smp",
        "16",
        "-serial",
        "mon:stdio",
        "-s",
        "-S",
        "-kernel",
    });
    debug_cmd.addFileInput(kernel.getEmittedBin());
    debug_cmd.addFileArg(kernel.getEmittedBin());
    debug_step.dependOn(&debug_cmd.step);

    debug_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const functions_str_cmd = b.addSystemCommand(&.{
        "llvm-objdump",
        "-t",
    });
    functions_str_cmd.addFileArg(kernel.getEmittedBin());
    functions_str_cmd.step.dependOn(&kernel.step);
    const functions_str_cmd_out = functions_str_cmd.captureStdOut();
    //b.getInstallStep().dependOn(&b.addInstallFile(functions_str_cmd_out, "functions_str_cmd_out").step);

    const line_info = b.addExecutable(.{
        .name = "line_info",
        .root_module = b.createModule(.{
            .root_source_file = b.path("utils/line_info.zig"),
            .target = host_target,
            .optimize = optimize,
        }),
    });

    const line_info_gen_step = b.addRunArtifact(line_info);
    line_info_gen_step.addFileArg(functions_str_cmd_out);
    line_info_gen_step.addFileArg(kernel.getEmittedBin());
    line_info_gen_step.step.dependOn(&functions_str_cmd.step);
    line_info_gen_step.step.dependOn(&kernel.step);

    const lgs = b.step("line_gen", "run linegen step");
    lgs.dependOn(&line_info_gen_step.step);
    b.installArtifact(line_info);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = kernel.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Install docs into zig-out/docs");
    docs_step.dependOn(&install_docs.step);

    // const run_step = b.step("run", "Run the app");
    //
    // const run_cmd = b.addRunArtifact(exe);
    // run_step.dependOn(&run_cmd.step);
    //
    // run_cmd.step.dependOn(b.getInstallStep());
    //
    // if (b.args) |args| {
    //     run_cmd.addArgs(args);
    // }
    //
    // const mod_tests = b.addTest(.{
    //     .root_module = mod,
    // });
    //
    // const run_mod_tests = b.addRunArtifact(mod_tests);
    //
    // const exe_tests = b.addTest(.{
    //     .root_module = exe.root_module,
    // });
    //
    // const run_exe_tests = b.addRunArtifact(exe_tests);
    //
    // const test_step = b.step("test", "Run tests");
    // test_step.dependOn(&run_mod_tests.step);
    // test_step.dependOn(&run_exe_tests.step);
}
