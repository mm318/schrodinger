const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mfem_dep = b.dependency("mfem", .{
        .target = target,
        .optimize = optimize,
    });
    const arkode_dep = mfem_dep.builder.dependency("arkode_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    exe_mod.addImport("cmfem", mfem_dep.module("cmfem"));
    exe_mod.addImport("arkode-zig", arkode_dep.module("arkode-zig"));

    const exe = b.addExecutable(.{
        .name = "schrodinger",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
