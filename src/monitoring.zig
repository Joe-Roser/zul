//! Tools for monitoring your code

const std = @import("std");
const Writer = std.Io.Writer;

/// A logger that will write to any writer interface
///
pub const Logger = struct {
    writer: *Writer,

    pub fn init(writer: *Writer) Logger {
        return .{
            .writer = writer,
        };
    }

    pub fn plain(self: *Logger, comptime format: []const u8, args: anytype) !void {
        try self.writer.print(format ++ "\n", args);
    }
    pub fn debug(self: *Logger, comptime format: []const u8, args: anytype) !void {
        try self.writer.print("[Debug] " ++ format ++ "\n", args);
    }
    pub fn info(self: *Logger, comptime format: []const u8, args: anytype) !void {
        try self.writer.print("[Info] " ++ format ++ "\n", args);
    }
    pub fn warn(self: *Logger, comptime format: []const u8, args: anytype) !void {
        try self.writer.print("[Warn] " ++ format ++ "\n", args);
    }
    pub fn err(self: *Logger, comptime format: []const u8, args: anytype) !void {
        try self.writer.print("[Err] " ++ format ++ "\n", args);
    }
    pub fn flush(self: *Logger) !void {
        try self.writer.flush();
    }
};

test "infoLog" {
    var buf: [1024]u8 = undefined;
    var mw: Writer = .fixed(&buf);
    var log = Logger.init(&mw);

    try log.info("A logging test", .{});

    try std.testing.expectEqualStrings("[Info] A logging test\n", mw.buffer[0..mw.end]);
}
