const std = @import("std");
pub const Vec2u = @import("linalg.zig").Vec2u;
pub const ArenaAllocator = @import("mem/ArenaAllocator.zig").ArenaAllocator;

std.heap.MemoryPool(comptime Item: type)

/// A simple pool allocator, which holds capacity elements of type T.
/// Allocates within the struct, so no dynamic allocations happen
pub fn PoolAllocator(comptime T: type, comptime Index: type, comptime capacity: Index) type {
    return struct {
        const Self = @This();

        mem: [capacity]T,
        free: [capacity]Index,
        free_len: Index,

        pub fn init() Self {
            var self: Self = .{
                .mem = .{0} ** capacity,
                .free = .{0} ** capacity,
                .free_len = capacity,
            };
            for (0..capacity) |i| self.free[i] = capacity - 1 - i;
            return self;
        }

        const Error = std.mem.Allocator.Error;

        pub fn create(self: *Self) Error!*T {
            if (self.free_len == 0) return Error.OutOfMemory;

            self.free_len -= 1;
            const idx = self.free[self.free_len];
            return &self.mem[idx];
        }

        pub fn destroy(self: *Self, elm: *T) void {
            const base = @intFromPtr(&self.mem);
            const addr = @intFromPtr(elm);

            const idx = (addr - base) / @sizeOf(T);
            self.free[self.free_len] = idx;
            self.free_len += 1;
        }
    };
}

test {
    std.testing.refAllDecls(@This());
}
