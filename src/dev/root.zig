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
    PowerDevice,
    DeviceGroup,
};

pub const Device = struct {
    pub const Error = error{
        BufferTooSmall,
        CapabilityUnavailable,
    } || std.mem.Allocator.Error || InterruptController.Error;

    pub const VTable = struct {
        init: *const fn (self: *anyopaque, state: *root.KernelThreadState) Error!void,
        get_device_type: *const fn (self: *anyopaque) Error!DeviceType,
        get_device_name: *const fn (self: *anyopaque, buffer: []u8) Error![]u8,
        /// dependency_build
        ///
        /// Used to determine the order of initialization of devices, this function will run before device initialization
        /// and should modify the self_node parameter in order to specify which devices should be initialized before this one is
        /// for example, if a device needs interrupts, it should add a dependency to all interrupt controllers
        dependency_build: *const fn (self: *anyopaque, self_node: *DependencyNode, all_nodes: []const DependencyNode) Device.Error!void = &default_dependency_build,
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
    pub fn dependency_build(self: Device, self_node: *DependencyNode, all_nodes: []const DependencyNode) Error!void {
        return self.vtable.dependency_build(self.ctx, self_node, all_nodes);
    }
};

pub const PowerDevice = struct {
    pub const Error = error{} || Device.Error;

    pub const Capabilities = enum(u32) {
        PowerOff = 1 << 0,
        RebootNow = 1 << 1,
        _,
    };

    pub const VTable = struct {
        request_poweroff: *const fn (*anyopaque) Error!void,
    };
};

pub const DependencyNode = struct {
    driver: *drivers.DeviceReference,
    inited: bool,
    dependencies: std.array_list.Managed(*DependencyNode),
};

fn default_dependency_build(_: *anyopaque, _: *DependencyNode, _: []const DependencyNode) Device.Error!void {}
