pub const serial = @import("serial.zig");
pub const clock = @import("clock/root.zig");
pub const plic = @import("plic.zig");
pub const InterruptController = @import("interrupt_controller.zig");
const std = @import("std");
const root = @import("../root.zig");

pub const DeviceType = enum {
    IODevice,
    InterruptController,
};

pub const Device = struct {
    pub const Error = error{} || std.mem.Allocator.Error || InterruptController.Error;

    pub const VTable = struct {
        init: *const fn (self: *anyopaque, state: *root.KernelThreadState) Error!void,
        get_device_type: *const fn (self: *anyopaque) Error!DeviceType,
    };
    vtable: *const VTable,
    ctx: *anyopaque,

    pub fn init(self: *Device, state: *root.KernelThreadState) Error!void {
        return self.vtable.init(self.ctx, state);
    }
    pub fn get_device_type(self: *Device) Error!DeviceType {
        return self.vtable.get_device_type(self.ctx);
    }
};
