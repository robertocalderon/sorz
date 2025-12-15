pub const serial = @import("serial.zig");
pub const clock = @import("clock/root.zig");
pub const plic = @import("plic.zig");
pub const InterruptController = @import("interrupt_controller.zig");
const std = @import("std");
const root = @import("../root.zig");

pub const Device = struct {
    pub const Error = error{} || std.mem.Allocator.Error || InterruptController.Error;

    pub const VTable = struct {
        init: *const fn (self: *anyopaque, state: *root.KernelThreatState) Error!void,
    };
    vtable: *const VTable,
    ctx: *anyopaque,

    pub fn init(self: *Device, state: *root.KernelThreatState) Error!void {
        return self.vtable.init(self.ctx, state);
    }
};
