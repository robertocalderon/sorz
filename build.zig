const std = @import("std");

pub fn build(b: *std.Build) void {
    var features = std.Target.riscv.featureSet(&.{});
    features.addFeature(@intFromEnum(std.Target.riscv.Feature.@"32bit"));
    features.addFeature(@intFromEnum(std.Target.riscv.Feature.i));
    features.addFeature(@intFromEnum(std.Target.riscv.Feature.m));
    features.addFeature(@intFromEnum(std.Target.riscv.Feature.a));
    features.addFeature(@intFromEnum(std.Target.riscv.Feature.c));
    features.addFeature(@intFromEnum(std.Target.riscv.Feature.zihintpause));

    features.removeFeature(@intFromEnum(std.Target.riscv.Feature.f));
    features.removeFeature(@intFromEnum(std.Target.riscv.Feature.d));

    const default_target: std.Target = .{
        .cpu = .{
            .arch = .riscv32,
            .features = features,
            .model = &std.Target.riscv.cpu.generic,
        },
        .abi = .none,
        .os = .{
            .tag = .freestanding,
            .version_range = .{
                .none = {},
            },
        },
        .ofmt = .elf,
    };
    const rv_baremetal = std.Target.Query.fromTarget(&default_target);
    const target = b.standardTargetOptions(.{
        .default_target = rv_baremetal,
        .whitelist = &.{
            rv_baremetal,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    const kernel = b.addExecutable(.{
        .name = "kernel.sorz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
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
        "-bios",
        "none",
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

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

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
