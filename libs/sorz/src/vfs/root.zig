const std = @import("std");

pub const RamFS = @import("ramfs.zig");
const BlockDevice = @import("../dev/block_device.zig");
const INode = @import("inode.zig");

const Self = @This();

alloc: std.mem.Allocator,
next_fs_id: usize,

/// Maps from fs_id to FS structure
available_fs: std.hash_map.AutoHashMap(usize, FS),
root_fs: FS,

pub fn new(alloc: std.mem.Allocator) !Self {
    return .{
        .alloc = alloc,
        .next_fs_id = 1,
        .available_fs = .init(alloc),
        .root_fs = .empty(),
    };
}
pub fn deinit(self: *Self) void {
    _ = self;
}
pub fn register_fs(self: *Self, fs: FS) !void {
    const look = self.available_fs.get(fs.fs_id);
    if (look) |_| {
        return error{FSIdAlreadyRegistered}.FSIdAlreadyRegistered;
    }
    try self.available_fs.put(fs.fs_id, fs);
}
pub fn set_root_fs(self: *Self, fs: FS) void {
    self.root_fs = fs;
}
pub fn generate_fs_id(self: *Self) usize {
    const ret = self.next_fs_id;
    self.next_fs_id += 1;
    return ret;
}

pub fn open_file(self: Self, path: []const u8) FS.Error!INode {
    blk: {
        const inode = self.root_fs.open_file(path) catch |e| {
            switch (e) {
                FS.Error.FileDoesntExists => break :blk,
                else => return e,
            }
        };
        return inode;
    }
    // TODO: when failed to get the file from root_fs try with smaller paths
    // to try to find the containing folder/file and see if it is another fs
    return FS.Error.FileDoesntExists;
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

    pub fn empty() FS {
        return FS{
            .ctx = @ptrFromInt(1),
            .vtable = &.{
                .open_file = &empty_open_file,
            },
            .fs_id = 0,
        };
    }
    fn empty_open_file(_: *anyopaque, _: []const u8) Error!INode {
        return Error.FileDoesntExists;
    }
};
