//! Tools for monitoring your code

const std = @import("std");
const testing = std.testing;
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

    pub fn plain(self: *Logger, comptime format: []const u8, args: anytype) Error!void {
        try self.writer.print(format ++ "\n", args);
    }
    pub fn debug(self: *Logger, comptime format: []const u8, args: anytype) Error!void {
        try self.writer.print("[Debug] " ++ format ++ "\n", args);
    }
    pub fn info(self: *Logger, comptime format: []const u8, args: anytype) Error!void {
        try self.writer.print("[Info] " ++ format ++ "\n", args);
    }
    pub fn warn(self: *Logger, comptime format: []const u8, args: anytype) Error!void {
        try self.writer.print("[Warn] " ++ format ++ "\n", args);
    }
    pub fn err(self: *Logger, comptime format: []const u8, args: anytype) Error!void {
        try self.writer.print("[Err] " ++ format ++ "\n", args);
    }
    pub fn flush(self: *Logger) !void {
        try self.writer.flush();
    }

    const Error = std.Io.Writer.Error;
};

test "Types" {
    const msg = "Testing Logger";
    const cases = .{
        .{ .func = Logger.plain, .expected = msg ++ "\n" },
        .{ .func = Logger.info, .expected = "[Info] " ++ msg ++ "\n" },
        .{ .func = Logger.debug, .expected = "[Debug] " ++ msg ++ "\n" },
        .{ .func = Logger.warn, .expected = "[Warn] " ++ msg ++ "\n" },
        .{ .func = Logger.err, .expected = "[Err] " ++ msg ++ "\n" },
    };

    var buf: [1024]u8 = undefined;
    var mw: Writer = .fixed(&buf);
    var log: Logger = .init(&mw);

    inline for (cases) |case| {
        try case.func(&log, msg, .{});
        try testing.expectEqualStrings(case.expected, mw.buffer[0..mw.end]);
        mw.end = 0;
    }
}
