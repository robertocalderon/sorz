const std = @import("std");
const Spinlock = @import("../../sync/spinlock.zig").Spinlock;
const DTB = @import("dtb");

const log = std.log.scoped(.DriverRegistry);
const dev = @import("../root.zig");

const SimpleBus = @import("simple_bus.zig").SimpleBus;

pub const Error = error{};

pub const DeviceReference = struct {
    handle: dev.Device,
    path: []const u8,
};
pub const DeviceDefinition = struct {
    name: []const u8,
    check_fn: *const fn (current_device: *const DTB.FDTDevice, device_registry: *DriverRegistry, alloc: std.mem.Allocator) std.mem.Allocator.Error!?dev.Device,
};

pub const DriverRegistry = struct {
    alloc: std.mem.Allocator,
    lock: Spinlock(void),

    all_devices: std.array_list.Managed(DeviceReference),
    power_devices: std.array_list.Managed(DeviceReference),

    pub fn init(alloc: std.mem.Allocator) DriverRegistry {
        return .{
            .alloc = alloc,
            .lock = .init({}),
            .all_devices = .init(alloc),
            .power_devices = .init(alloc),
        };
    }
    pub fn device_init(self: *DriverRegistry, device: *const DTB.FDTDevice, alloc: std.mem.Allocator) Error!void {
        if (try self.init_root_device(device, alloc)) {
            return;
        }
        log.debug("Trying to init dev: {s}", .{device.name() orelse "???"});
        blk: {
            for (AVAILABLE_DEVICES) |cdev| {
                const ndev = cdev.check_fn(device, self, alloc) catch continue orelse continue;
                // alloc.destroy(ndev)
                std.log.info("Inited deivce: {s}", .{cdev.name});
                _ = ndev;
                break :blk;
            }
            var compatible: []const u8 = "???";
            if (device.find_prop("compatible")) |prop| {
                compatible = prop.data;
            }
            log.err("Device {s} (compatible with: {s}) couldn't be inited or it is unknown", .{ device.name() orelse "???", compatible });
        }
    }
    pub fn init_root_device(self: *DriverRegistry, device: *const DTB.FDTDevice, alloc: std.mem.Allocator) Error!bool {
        const dname = device.name() orelse return false;
        if (!std.mem.eql(u8, dname, "/")) {
            return false;
        }
        log.debug("Found root device, initing children", .{});
        var iter = device.get_children();
        while (iter.next()) |cdev| {
            try self.device_init(&cdev, alloc);
        }
        return true;
    }
};

pub const AVAILABLE_DEVICES: []const DeviceDefinition = &.{
    .{ .name = SimpleBus.dev_name, .check_fn = &SimpleBus.try_create_from_dtb },
};
