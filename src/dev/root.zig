pub const serial = @import("serial.zig");
pub const clock = @import("clock/root.zig");
pub const plic = @import("plic.zig");
pub const InterruptController = @import("interrupt_controller.zig");
const std = @import("std");

pub const Device = struct {
    pub const Error = error{} || std.mem.Allocator.Error;

    pub const VTable = struct {
        init: *const fn (self: *anyopaque, alloc: std.mem.Allocator) Error!void,
    };
    vtable: *const VTable,
    ctx: *anyopaque,

    pub fn init(self: *Device, alloc: std.mem.Allocator) Error!void {
        return self.vtable.init(self.ctx, alloc);
    }
};
