const std = @import("std");
const root = @import("../root.zig");

const Self = @This();

pub const Error = error{
    non_existant_interrupt,
};

pub const VTable = struct {
    init: *const fn (*anyopaque) void,
    enable_interrupt_with_id: *const fn (*anyopaque, id: usize, state: *root.KernelThreadState) Error!void,
    enable_threshold: *const fn (*anyopaque, tsh: u3, state: *root.KernelThreadState) Error!void,
    enable_priority_with_id: *const fn (*anyopaque, id: usize, pri: u3, state: *root.KernelThreadState) Error!void,
    register_interrupt_callback: *const fn (*anyopaque, id: usize, callback: *const fn (*anyopaque, *root.KernelThreadState) void, ctx: *anyopaque, state: *root.KernelThreadState) Error!void,
};

vtable: *const VTable,
ctx: *anyopaque,

pub fn init(self: *Self) void {
    return self.vtable.init(self.ctx);
}

pub fn enable_interrupt_with_id(self: *Self, id: usize, state: *root.KernelThreadState) Error!void {
    return self.vtable.enable_interrupt_with_id(self.ctx, id, state);
}
pub fn enable_threshold(self: *Self, tsh: u3, state: *root.KernelThreadState) Error!void {
    return self.vtable.enable_threshold(self.ctx, tsh, state);
}
pub fn enable_priority_with_id(self: *Self, id: usize, pri: u3, state: *root.KernelThreadState) Error!void {
    return self.vtable.enable_priority_with_id(self.ctx, id, pri, state);
}
pub fn register_interrupt_callback(self: *Self, id: usize, callback: *const fn (*anyopaque, *root.KernelThreadState) void, ctx: *anyopaque, state: *root.KernelThreadState) Error!void {
    return self.vtable.register_interrupt_callback(self.ctx, id, callback, ctx, state);
}
