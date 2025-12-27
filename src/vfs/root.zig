const std = @import("std");

pub const RamFS = @import("ramfs.zig");

const Self = @This();

alloc: std.mem.Allocator,
next_fs_id: usize,

/// Maps from fs_id to FS structure
available_fs: std.hash_map.AutoHashMap(usize, *FS),

pub fn new(alloc: std.mem.Allocator) !Self {
    return .{
        .alloc = alloc,
        .next_fs_id = 0,
        .available_fs = .init(alloc),
    };
}
pub fn deinit(self: *Self) void {
    _ = self;
}

pub const FS = struct {
    const Error = error{} || std.mem.Allocator.Error;
    pub const VTable = struct {};
    ctx: *anyopaque,
    vtable: *const VTable,
    fs_id: usize,
};
