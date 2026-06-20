const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const mod = b.addModule("zul", .{
        .root_source_file = b.path("src/std.zig"),
        .target = target,
    });

    // Testing step
    const test_step = b.step("test", "Run tests");

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    test_step.dependOn(&run_mod_tests.step);
}
