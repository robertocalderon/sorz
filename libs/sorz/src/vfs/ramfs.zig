/// For now this simple file system stores data in a similar way to TAR
/// The main diference is the fact that this has a variable block size
/// that depends on the block size of the underlaying block device, so
/// for now the way it is goind to work is to have the "super block" at
/// the beggining of the disk, storing a simple magic value and the offset
/// at which the data start (just 1 for now), at this address will start
/// a series of header (including the path and name, and file size)
/// followed by a enough blocks to contiguosly store the file
const std = @import("std");
const inode = @import("inode.zig");
const dev = @import("../dev/root.zig");
const BlockDevice = dev.BlockDevice;

const Self = @This();

alloc: std.mem.Allocator,
backing_device: BlockDevice,
block_size: usize,
device_size: usize,
device_cache: []u8,
starting_block: usize,

pub fn new(alloc: std.mem.Allocator, backing_device: BlockDevice) !Self {
    return .{
        .alloc = alloc,
        .backing_device = backing_device,
        .block_size = 0,
        .device_size = 0,
        .starting_block = 1,
        .device_cache = undefined,
    };
}
pub fn deinit(self: *Self) void {
    self.alloc.free(self.device_cache);
}
pub fn init(self: *Self) !void {
    self.block_size = self.backing_device.get_block_size();
    self.device_size = self.backing_device.get_number_of_blocks();
    self.device_cache = try self.alloc.alloc(u8, self.block_size);
}

pub fn format(self: *Self) void {
    // For now clear all, later do this on a better way
    @memset(self.device_cache, 0);
    for (0..self.device_size) |i| {
        _ = try self.backing_device.write_block(i, self.device_cache);
    }
    _ = try self.backing_device.read_block(0, self.device_cache);
    const sblock: *Superblock = @ptrCast(@alignCast(&self.device_cache.ptr));
    @memcpy(sblock.magic, "RAMFS.");
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
    n_blocks: usize,
    name: []const u8,
};
pub const BlockHeaderInDisk = extern struct {
    file_size: u32,
    n_blocks: u32,
    name: u8,
};
