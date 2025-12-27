const std = @import("std");
const inode = @import("inode.zig");

const Self = @This();

alloc: std.mem.Allocator,

pub fn new(alloc: std.mem.Allocator) !Self {
    return .{
        .alloc = alloc,
    };
}
pub fn deinit(self: *Self) void {
    _ = self;
}
