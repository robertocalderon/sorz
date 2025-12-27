const std = @import("std");
const DTB = @import("dtb");
const dev = @import("../root.zig");
const root = @import("../../root.zig");

const log = std.log.scoped(.NS16550a);

pub const NS16550a = struct {
    pub const dev_name: []const u8 = "ns16550a";

    self_device: DTB.FDTDevice,
    interrupt_controller: u32,
    interrupt_number: u32,
    mmio: []u8,

    pub fn try_create_from_dtb(current_device: *const DTB.FDTDevice, device_registry: *dev.drivers.DriverRegistry, alloc: std.mem.Allocator, current_path: [][]const u8) std.mem.Allocator.Error!?dev.Device {
        _ = device_registry;
        _ = current_path;

        const comp_with = current_device.find_prop("compatible") orelse return null;
        var comp_with_iter = std.mem.splitAny(u8, comp_with.data, ",");

        blk: {
            while (comp_with_iter.next()) |_comp| {
                var comp = _comp;
                if (std.mem.endsWith(u8, comp, "\x00")) {
                    comp.len -= 1;
                }
                if (std.mem.eql(u8, comp, dev_name)) {
                    break :blk;
                }
            }
            return null;
        }
        log.debug("Serial port found, checking compatibility...", .{});
        if (current_device.find_prop("interrupt-parent") == null) {
            log.err("Serial port doens't have required properties, aborting", .{});
            return null;
        }
        if (current_device.find_prop("interrupts") == null) {
            log.err("Serial port doens't have required properties, aborting", .{});
            return null;
        }
        if (current_device.find_prop("reg") == null) {
            log.err("Serial port doens't have required properties, aborting", .{});
            return null;
        }

        const mmio_start = current_device.find_prop("reg").?.get_u64(0).?;
        const mmio_size = current_device.find_prop("reg").?.get_u64(8).?;
        var mmio: []u8 = undefined;
        log.debug("Serial MMIO: 0x{x:0>8} -> 0x{x:0>8}", .{ mmio_start, mmio_start + mmio_size });
        mmio.ptr = @ptrFromInt(@as(usize, @intCast(mmio_start)));
        mmio.len = @intCast(mmio_size);

        const self_instance: *NS16550a = try alloc.create(NS16550a);
        self_instance.* = .{
            .self_device = current_device.*,
            .interrupt_controller = current_device.find_prop("interrupt-parent").?.get_small_integer().?,
            .interrupt_number = current_device.find_prop("interrupts").?.get_small_integer().?,
            .mmio = mmio,
        };
        const dev_interface = dev.Device{
            .ctx = @ptrCast(self_instance),
            .vtable = &dev.Device.VTable{
                .get_device_name = &get_device_name,
                .get_device_type = &get_device_type,
                .dependency_build = &dependency_build,
                .init = &init,
            },
        };
        return dev_interface;
    }

    fn get_device_type(_: *anyopaque) dev.Device.Error!dev.DeviceType {
        return dev.DeviceType.IODevice;
    }
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
    fn init(_self: *anyopaque, state: *root.KernelThreadState) dev.Device.Error!void {
        _ = _self;
        _ = state;
        log.debug("ns16550a init", .{});
    }
    fn dependency_build(_self: *anyopaque, self_node: *dev.DependencyNode, all_devices: []const dev.DependencyNode) dev.Device.Error!void {
        const self: *NS16550a = @ptrCast(@alignCast(_self));

        for (all_devices, 0..) |cdev, i| {
            const phandle_prop = cdev.driver.dtb_entry.find_prop("phandle") orelse continue;
            const phandle = phandle_prop.get_u32(0) orelse continue;
            if (phandle != self.interrupt_controller) {
                continue;
            }
            try self_node.dependencies.append(&all_devices[i]);
        }
    }
};
