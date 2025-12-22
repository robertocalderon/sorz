pub const serial = @import("serial.zig");
pub const clock = @import("clock/root.zig");
pub const plic = @import("plic.zig");
pub const InterruptController = @import("interrupt_controller.zig");
pub const drivers = @import("drivers/root.zig");
const std = @import("std");
const root = @import("../root.zig");

pub const DeviceType = enum {
    IODevice,
    InterruptController,
};

pub const Device = struct {
    pub const Error = error{
        BufferTooSmall,
    } || std.mem.Allocator.Error || InterruptController.Error;

    pub const VTable = struct {
        init: *const fn (self: *anyopaque, state: *root.KernelThreadState) Error!void,
        get_device_type: *const fn (self: *anyopaque) Error!DeviceType,
        get_device_name: *const fn (self: *anyopaque, buffer: []u8) Error![]u8,
    };
    vtable: *const VTable,
    ctx: *anyopaque,

    pub fn init(self: *Device, state: *root.KernelThreadState) Error!void {
        return self.vtable.init(self.ctx, state);
    }
    pub fn get_device_type(self: *Device) Error!DeviceType {
        return self.vtable.get_device_type(self.ctx);
    }
    pub fn get_device_name(self: *Device, buffer: []u8) Error![]u8 {
        return self.vtable.get_device_name(self.ctx, buffer);
    }
};
