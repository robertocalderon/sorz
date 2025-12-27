const std = @import("std");

pub const RamFS = @import("ramfs.zig");

const Self = @This();

alloc: std.mem.Allocator,
next_dev_id: usize,

pub fn new(alloc: std.mem.Allocator) !Self {
    return .{
        .alloc = alloc,
        .next_dev_id = 0,
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
};
