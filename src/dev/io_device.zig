const std = @import("std");

const Self = @This();

pub const Error = error{};

pub const VTable = struct {
    write_fn: *const fn (*anyopaque, buffer: []const u8) Error!usize,
    read_fn: *const fn (*anyopaque, buffer: []u8) Error![]u8,
};

ctx: *anyopaque,
vtable: *const VTable,

pub fn write_some(self: Self, buffer: []const u8) Error!usize {
    return self.vtable.write_fn(self.ctx, buffer);
}
pub fn read_some(self: Self, buffer: []u8) Error![]u8 {
    return self.vtable.read_fn(self.ctx, buffer);
}
