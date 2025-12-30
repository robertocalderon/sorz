/// For now this simple file system stores data in a similar way to TAR
/// The main diference is the fact that this has a variable block size
/// that depends on the block size of the underlaying block device, so
/// for now the way it is goind to work is to have the "super block" at
/// the beggining of the disk, storing a simple magic value and the offset
/// at which the data start (just 1 for now), at this address will start
/// a series of header (including the path and name, and file size)
/// followed by a enough blocks to contiguosly store the file
const std = @import("std");
const INode = @import("inode.zig");
const dev = @import("../dev/root.zig");
const BlockDevice = dev.BlockDevice;
const VFS = @import("root.zig");
const FS = VFS.FS;

const Self = @This();
const Error = FS.Error;

alloc: std.mem.Allocator,
backing_device: BlockDevice,
block_size: usize,
device_size: usize,
device_cache: []u8,
starting_block: usize,
fs_id: usize,

pub fn new(alloc: std.mem.Allocator, backing_device: BlockDevice, fs_id: usize) !Self {
    const block_size = try backing_device.get_block_size();
    const device_cache = try alloc.alloc(u8, block_size);
    return .{
        .alloc = alloc,
        .backing_device = backing_device,
        .block_size = block_size,
        .device_size = try backing_device.get_number_of_blocks(),
        .starting_block = 1,
        .device_cache = device_cache,
        .fs_id = fs_id,
    };
}
pub fn deinit(self: *Self) void {
    self.alloc.free(self.device_cache);
}

pub fn format(self: *Self) !void {
    // For now clear all, later do this on a better way
    @memset(self.device_cache, 0);
    for (0..self.device_size) |i| {
        _ = try self.backing_device.write_block(i, self.device_cache);
    }
    _ = try self.backing_device.read_block(0, self.device_cache);
    const sblock: *Superblock = @ptrCast(@alignCast(self.device_cache.ptr));
    @memcpy(sblock.magic[0..6], "RAMFS.");
    sblock.starting_block = 1;
    self.starting_block = sblock.starting_block;
    _ = try self.backing_device.write_block(0, self.device_cache);
}

pub const Superblock = extern struct {
    /// Magic RAMFS.
    magic: [6]u8,
    starting_block: usize,
};
pub const BlockHeader = struct {
    file_size: usize,
    file_alloc: usize,
};
pub const BlockHeaderInDisk = extern struct {
    /// Real file size in bytes
    file_size: u32,
    /// Reserved space for file, in blocks
    file_alloc: u32,
    name: u8,
};

/// Depends on block size, so have to calculate it at runtime
pub fn max_name_size(self: *Self) usize {
    const offset: usize = @offsetOf(BlockHeaderInDisk, "name");
    const rem_space = self.block_size - offset;
    std.debug.assert(rem_space > 64);
    return rem_space;
}
pub fn get_name(self: *Self, header: *const BlockHeaderInDisk) []const u8 {
    const name_buffer_unsized: [*]const u8 = @ptrCast(&header.name);
    const name_buffer = name_buffer_unsized[0..self.max_name_size()];
    const name_end = std.mem.indexOf(u8, name_buffer, &.{0}) orelse name_buffer.len;
    return name_buffer[0..name_end];
}

pub fn read_block_at_id(self: *Self, id: usize) ![]u8 {
    if (id >= self.device_size) {
        return BlockDevice.Error.InvalidAddress;
    }
    return try self.backing_device.read_block(id, self.device_cache);
}
pub fn write_block_at_it(self: *Self, id: usize, buffer: []const u8) !void {
    if (id >= self.device_size) {
        return BlockDevice.Error.InvalidAddress;
    }
    try self.backing_device.write_block(id, buffer);
}

const FileSearchResult = struct {
    block_id: usize,
    header: BlockHeader,
};
pub fn search_file_block_id(self: *Self, path: []const u8) FS.Error!?FileSearchResult {
    var i = self.starting_block;
    while (i < self.device_size) {
        const tmp = try self.read_block_at_id(i);
        const header: *const BlockHeaderInDisk = @ptrCast(@alignCast(tmp.ptr));
        const file_name = self.get_name(header);
        if (std.mem.eql(u8, file_name, path)) {
            return .{
                .block_id = i,
                .header = .{
                    .file_size = header.file_size,
                    .file_alloc = header.file_alloc,
                },
            };
        }
        const file_size = header.file_alloc;
        const file_block_count = 1 + file_size;
        i += file_block_count;
    }
    return null;
}
pub fn alloc_file(self: *Self, path: []const u8, current_size: usize, max_size: usize) !?usize {
    if (path.len > self.max_name_size()) {
        // TODO: make an FS Error and report that
        @panic("Filename too big");
    }
    const size = @min(current_size, max_size);
    const real_max_size: usize = std.mem.alignForward(usize, max_size, self.block_size);
    // find first empty space
    const start_block: usize = blk: {
        var i = self.starting_block;
        while (i < self.device_size) {
            const tmp = try self.read_block_at_id(i);
            const header: *const BlockHeaderInDisk = @ptrCast(@alignCast(tmp.ptr));
            if (header.file_alloc == 0 and header.file_size == 0 and header.name == 0) {
                break :blk i;
            }
            const file_size = header.file_alloc;
            const file_block_count = 1 + file_size;
            i += file_block_count;
        }
        return null;
    };
    if (self.device_size < (start_block + 1 + (real_max_size / self.block_size))) {
        return null;
    }
    const tmp = try self.read_block_at_id(start_block);
    const header: *BlockHeaderInDisk = @ptrCast(@alignCast(tmp.ptr));
    header.file_size = size;
    header.file_alloc = real_max_size / self.block_size;
    const name_buffer_unsized: [*]u8 = @ptrCast(&header.name);
    const name_buffer = name_buffer_unsized[0..self.max_name_size()];
    @memset(name_buffer, 0);
    @memcpy(name_buffer[0..path.len], path);
    try self.backing_device.write_block(start_block, tmp);

    @memset(self.device_cache, 0);
    for (0..(std.mem.alignForward(usize, size, self.block_size) / self.block_size)) |i| {
        try self.backing_device.write_block(i + 1 + start_block, self.device_cache);
    }
    return start_block;
}

fn open_file(_self: *anyopaque, path: []const u8) Error!INode {
    const self: *Self = @ptrCast(@alignCast(_self));
    const search_results = (try self.search_file_block_id(path)) orelse return Error.FileDoesntExists;
    const file_blocks = std.mem.alignForward(usize, search_results.header.file_size, self.block_size) / self.block_size;
    if (file_blocks > 12) {
        // TODO: when inodes support more than 12 blocks change this
        return Error.FileDoesntExists;
    }

    var ret = INode{
        .fs_id = self.fs_id,
        .file_len = search_results,
        .inode_number = 0,
        .ref_count = 1,
        .simple_block_ptrs = undefined,
    };
    @memset(ret.simple_block_ptrs, 12);
    for (0..file_blocks) |i| {
        ret.simple_block_ptrs[i] = search_results.block_id + 1 + i;
    }
    return ret;
}

pub fn get_fs(self: *Self) FS {
    return FS{
        .fs_id = self.fs_id,
        .ctx = @ptrCast(self),
        .vtable = &.{
            .open_file = &open_file,
        },
    };
}
