const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    // Main entrypoint for the lib
    const lib = b.addModule("zul", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // Testing step
    const test_step = b.step("test", "Run tests");

    // Testing the lib
    const lib_tests = b.addTest(.{
        .root_module = lib,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    test_step.dependOn(&run_lib_tests.step);

    // Test all modules
    const mods: []const []const u8 = &.{ "monitoring", "testing" };
    inline for (mods) |mod_name| {
        const mod = b.addModule(mod_name, .{
            .root_source_file = b.path("src/" ++ mod_name ++ ".zig"),
            .target = target,
        });

        lib.addImport(mod_name, mod);

        const mod_tests = b.addTest(.{
            .root_module = mod,
        });
        const run_mod_tests = b.addRunArtifact(mod_tests);

        test_step.dependOn(&run_mod_tests.step);
    }
}
