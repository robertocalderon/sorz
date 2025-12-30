const std = @import("std");
const dev = @import("../root.zig");
const root = @import("../../root.zig");

const Self = @This();

raw_data: []u8,
block_size: usize,
n_blocks: usize,

pub const Error = error{} || std.mem.Allocator.Error;

pub fn new(alloc: std.mem.Allocator, block_size: usize, max_blocks: usize) Error!Self {
    const raw_bytes = block_size * max_blocks;
    const buffer = try alloc.alloc(u8, raw_bytes);
    return .{
        .raw_data = buffer,
        .block_size = block_size,
        .n_blocks = max_blocks,
    };
}
pub fn newWithBuffer(block_size: usize, buffer: []u8) Self {
    const n_blocks = buffer.len / block_size;
    const real_buffer = buffer[0..(n_blocks * block_size)];
    return .{
        .block_size = block_size,
        .n_blocks = n_blocks,
        .raw_data = real_buffer,
    };
}
pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
    alloc.free(self.raw_data);
}

pub fn get_device(self: *Self) dev.Device {
    return .{
        .ctx = @ptrCast(self),
        .vtable = &dev.Device.VTable{
            .get_device_name = &get_device_name,
            .get_block_device = &get_block_device,
            .init = &init,
        },
    };
}

fn get_block_device(_self: *anyopaque) dev.Device.Error!?dev.BlockDevice {
    return dev.BlockDevice{
        .ctx = _self,
        .vtable = &dev.BlockDevice.VTable{
            .block_size = &get_block_size,
            .n_blocks = &get_n_blocks,
            .read_block = &read_block,
            .write_block = &write_block,
        },
    };
}
fn get_block_size(self: *anyopaque) dev.BlockDevice.Error!usize {
    const ptr: *Self = @ptrCast(@alignCast(self));
    return ptr.block_size;
}
fn get_n_blocks(self: *anyopaque) dev.BlockDevice.Error!usize {
    const ptr: *Self = @ptrCast(@alignCast(self));
    return ptr.n_blocks;
}
pub fn read_block(_self: *anyopaque, block_id: usize, buffer: []u8) dev.BlockDevice.Error![]u8 {
    const self: *Self = @ptrCast(@alignCast(_self));
    if (self.block_size > buffer.len) {
        return dev.BlockDevice.Error.BufferTooSmall;
    }
    const slice = buffer[0..self.block_size];
    const start = block_id * self.block_size;
    const end = start + self.block_size;
    if (end > self.raw_data.len) {
        return dev.BlockDevice.Error.InvalidAddress;
    }
    @memcpy(slice, self.raw_data[start..end]);
    return slice;
}
pub fn write_block(_self: *anyopaque, block_id: usize, buffer: []const u8) dev.BlockDevice.Error!void {
    const self: *Self = @ptrCast(@alignCast(_self));
    if (self.block_size > buffer.len) {
        return dev.BlockDevice.Error.BufferTooSmall;
    }
    const slice = buffer[0..self.block_size];
    const start = block_id * self.block_size;
    const end = start + self.block_size;
    if (end > self.raw_data.len) {
        return dev.BlockDevice.Error.InvalidAddress;
    }
    @memcpy(self.raw_data[start..end], slice);
}

fn init(_self: *anyopaque, state: *root.KernelThreadState) dev.Device.Error!void {
    _ = _self;
    _ = state;
}
const dev_name: []const u8 = "ramdisk";
pub fn get_device_name(_: *anyopaque, buffer: []u8) dev.Device.Error![]u8 {
    const device_name = dev_name;
    if (buffer.len < device_name.len) {
        @memcpy(buffer, device_name[0..buffer.len]);
        return dev.Device.Error.BufferTooSmall;
    } else {
        @memcpy(buffer, device_name);
        return buffer[0..device_name.len];
    }
}
