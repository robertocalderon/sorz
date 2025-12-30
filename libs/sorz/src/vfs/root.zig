const std = @import("std");

pub const RamFS = @import("ramfs.zig");
const BlockDevice = @import("../dev/block_device.zig");
const INode = @import("inode.zig");

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
    pub const Error = error{
        FileDoesntExists,
    } || BlockDevice.Error || std.mem.Allocator.Error;
    pub const VTable = struct {
        open_file: *const fn (self: *anyopaque, path: []const u8) Error!INode,
    };
    ctx: *anyopaque,
    vtable: *const VTable,
    fs_id: usize,

    pub fn open_file(self: FS, path: []const u8) Error!INode {
        return self.vtable.open_file(self.ctx, path);
    }
};
