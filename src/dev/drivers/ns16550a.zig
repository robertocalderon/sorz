const std = @import("std");
const DTB = @import("dtb");
const dev = @import("../root.zig");
const root = @import("../../root.zig");

const log = std.log.scoped(.NS16550a);

pub const NS16550a = struct {
    pub const dev_name: []const u8 = "ns16550a";

    self_device: DTB.FDTDevice,

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
        log.debug("Serial port found, initing", .{});

        const self_instance: *NS16550a = try alloc.create(NS16550a);
        self_instance.* = .{
            .self_device = current_device.*,
        };
        const dev_interface = dev.Device{
            .ctx = @ptrCast(self_instance),
            .vtable = &dev.Device.VTable{
                .get_device_name = &get_device_name,
                .get_device_type = &get_device_type,
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
};
