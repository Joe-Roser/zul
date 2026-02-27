const std = @import("std");
const monitoring = @import("monitoring");
const testing = @import("testing.zig");

test "recurse" {
    std.testing.refAllDecls(@This());
}
