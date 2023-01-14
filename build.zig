const std = @import("std");

const pkgs = struct {
    const gale = std.build.Pkg{
        .name = "gale",
        .source = .{ .path = "lib/gale/gale.zig" },
        .dependencies = &[_]std.build.Pkg{},
    };
};

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("gale", "lib/gale/gale.zig");
    lib.setBuildMode(mode);
    lib.install();

    const exe = b.addExecutable("gale", "src/gale/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackage(pkgs.gale);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // gale library and core tests
    const lib_tests = b.addTest("lib/gale/test_gale.zig");
    lib_tests.setTarget(target);
    lib_tests.setBuildMode(mode);

    // gale CLI tests
    const exe_tests = b.addTest("src/gale/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    // End-to-end tests of the protolang
    const protolang_tests = b.addTest("tests/test_protolang.zig");
    protolang_tests.setTarget(target);
    protolang_tests.setBuildMode(mode);
    protolang_tests.addPackage(pkgs.gale);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&lib_tests.step);
    test_step.dependOn(&exe_tests.step);
    test_step.dependOn(&protolang_tests.step);
}
