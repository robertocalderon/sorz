const std = @import("std");

const Self = @This();

pub const VTable = struct {};

vtable: *const VTable,
ctx: *anyopaque,

var platform_controller: Self = undefined;

pub fn set_platform_controller(ictrl: Self) void {
    platform_controller = ictrl;
}
pub fn get_platform_controller() *Self {
    return &platform_controller;
}
