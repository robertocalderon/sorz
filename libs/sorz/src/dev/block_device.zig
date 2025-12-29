const std = @import("std");

const Self = @This();

pub const Error = error{
    BufferTooSmall,
    InvalidAddress,
};

pub const VTable = struct {
    block_size: *const fn (self: *anyopaque) Error!usize,
    n_blocks: *const fn (self: *anyopaque) Error!usize,
    /// Reads a block at a specific location, if the buffer is bigger than a block, only reads the first block and returns
    /// a buffer containing only the portion of data that was writen to
    read_block: *const fn (self: *anyopaque, block_id: usize, buffer: []u8) Error![]u8,
    /// Write a block at a specified location, if the buffer is bigger than a block, ignores the extra data
    write_block: *const fn (self: *anyopaque, block_id: usize, buffer: []const u8) Error!void,
};

ctx: *anyopaque,
vtable: *const VTable,

pub fn get_block_size(self: Self) Error!usize {
    return self.vtable.block_size(self.ctx);
}
pub fn get_number_of_blocks(self: Self) Error!usize {
    return self.vtable.n_blocks(self.ctx);
}
/// Reads a block at a specific location, if the buffer is bigger than a block, only reads the first block and returns
/// a buffer containing only the portion of data that was writen to
pub fn read_block(self: Self, block_id: usize, buffer: []u8) Error![]u8 {
    return self.vtable.read_block(self.ctx, block_id, buffer);
}
/// Write a block at a specified location, if the buffer is bigger than a block, ignores the extra data
pub fn write_block(self: Self, block_id: usize, buffer: []const u8) Error!void {
    return self.vtable.write_block(self.ctx, block_id, buffer);
}
