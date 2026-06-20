const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const page_size = std.heap.pageSize();
const _ = std.heap.ArenaAllocator;

comptime {
    if (builtin.os.tag != .linux) @compileError("This implementation requires mprotect");
}

/// A simple page backed, memory minimal arena allocator.
/// No free, resize or remap are supported
pub const ArenaAllocator = struct {
    mem: []align(4096) u8,
    commited: usize,
    offset: usize,

    const Error = Allocator.Error || error{CommitFailed};
    pub const vtable: Allocator.VTable = .{ .alloc = vt_alloc, .free = Allocator.noFree, .remap = Allocator.noRemap, .resize = Allocator.noResize };
    pub fn allocator(self: *ArenaAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    pub const Config = struct {
        /// The maximum allowed size for the arena
        max_capacity: usize = 1024 * 1024 * 1024,

        /// The initial size accessible without a syscall
        initial_commited: usize = page_size,
    };
    pub fn init(config: Config) Error!ArenaAllocator {
        const mem = std.posix.mmap(null, config.max_capacity, .{}, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0) catch return Error.OutOfMemory;
        const res = std.os.linux.mprotect(mem.ptr, config.initial_commited, .{ .READ = true, .WRITE = true });
        if (res != 0) return Error.CommitFailed;
        return .{
            .mem = mem,
            .commited = page_size,
            .offset = 0,
        };
    }

    pub fn alloc(self: *ArenaAllocator, comptime T: type, count: usize) Error![]T {
        // state requirements
        std.debug.assert(self.commited % page_size == 0);

        const alignment = @alignOf(T);
        const len = @sizeOf(T) * count;

        self.offset = std.mem.alignForward(usize, self.offset, alignment);

        try self.reserveCommit(len);

        const mem = self.mem[self.offset..].ptr;
        self.offset += len;

        const ptr: [*]T = @ptrCast(@alignCast(mem));
        return ptr[0..count];
    }
    /// Ensure 'size' bytes are available without a syscall
    pub fn reserveCommit(self: *ArenaAllocator, size: usize) Error!void {
        if (self.offset + size <= self.commited) return; // nothing to do
        if (self.offset + size > self.mem.len) return Error.OutOfMemory;
        const new_commited = std.math.ceilPowerOfTwo(usize, self.offset + size) catch unreachable;

        // TODO: new_commit may be bigger than mem.len. Is this ok?
        // If it just fails, then we get defined behaviour anyway
        const res = std.os.linux.mprotect(self.mem[self.commited..].ptr, new_commited - self.commited, .{ .READ = true, .WRITE = true });
        if (res != 0) return Error.OutOfMemory;

        self.commited = new_commited;
    }

    pub fn deinit(self: *ArenaAllocator) void {
        std.posix.munmap(self.mem);
    }

    /// What happens to the pages on reset
    pub const ResetMode = union(enum) {
        /// Empty the arena without affecting the state of the memory
        /// Cannot fail
        retain,

        /// Empty the arena, decommiting all but one of the pages used
        /// Since pages are decommited, trying to access them will result in a segfault.
        decommit,

        /// Empty the arena, decommiting all but the specified memory
        /// Rounds up to the pow(next page, n)
        /// Since pages are decommited, trying to access them will result in a segfault.
        decommit_to: usize,
    };
    /// Reset the allocator. Frees all memory and optionally decommits pages
    pub fn reset(self: *ArenaAllocator, mode: ResetMode) Error!void {
        switch (mode) {
            .retain => {
                self.offset = 0;
            },
            .decommit => {
                const res = std.os.linux.mprotect(self.mem[page_size..].ptr, self.commited - page_size, .{});
                if (res != 0) return Error.CommitFailed;

                self.commited = page_size;
                self.offset = 0;
            },
            .decommit_to => |len| {
                const new_commit = @max(std.math.ceilPowerOfTwo(usize, len), page_size);

                const res = std.os.linux.mprotect(self.mem[new_commit..].ptr, self.commited - new_commit, .{});
                if (res != 0) return Error.CommitFailed;

                self.commited = new_commit;
                self.offset = 0;
            },
        }
    }

    fn vt_alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
        const self: *ArenaAllocator = @ptrCast(@alignCast(ctx));

        // state requirements
        std.debug.assert(self.commited % page_size == 0);

        self.offset = std.mem.alignForward(usize, self.offset, alignment.toByteUnits());

        self.reserveCommit(len) catch return null;

        const mem = self.mem[self.offset..].ptr;
        self.offset += len;
        return mem;
    }

    // Extra functions

    pub const ResetPoint = struct {
        offset: usize,
        commited: usize,
        arena: if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) *ArenaAllocator else void,
    };
    /// Get a point to reset the allocator to
    pub fn getResetPoint(self: *ArenaAllocator) ResetPoint {
        return .{
            .offset = self.offset,
            .commited = self.commited,
            .arena = if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) self,
        };
    }
    /// Revert the arena to a prevoiusly grabbed state.
    /// In Debug and ReleaseSafe, checks that the ResetPoint refers to this allocator. May cause weird behaviour.
    /// Does not support 'decommit_to'.
    pub fn revertResetPoint(self: *ArenaAllocator, point: ResetPoint, comptime mode: ResetMode) Error!void {
        std.debug.assert(self.offset >= point.offset);
        if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) std.debug.assert(point.arena == self);

        switch (mode) {
            .retain => {
                self.offset = point.offset;
            },
            .decommit => {
                const res = std.os.linux.mprotect(self.mem[point.commited..].ptr, self.commited - point.commited, .{});
                if (res != 0) return Error.CommitFailed;

                self.commited = point.commited;
                self.offset = point.offset;
            },
            .decommit_to => {
                @compileError("cannot 'decommit_to' with ResetPoint");
            },
        }
    }

    /// Frees the top n bytes from the arena stack. If you want to get the bytes first, use peekN.
    /// Invalidates slices of any of these bytes. use with caution.
    pub fn popN(self: *ArenaAllocator, n: usize) void {
        std.debug.assert(self.offset >= n);
        self.offset -= n;
    }
    /// Returns a slice of the top n bytes from the arena stack.
    pub fn peekN(self: *ArenaAllocator, n: usize) []u8 {
        std.debug.assert(self.offset >= n);
        return self.mem[self.offset - n .. self.offset];
    }
};

test {
    std.testing.refAllDecls(@This());
}
