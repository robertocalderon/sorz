const std = @import("std");
const DTB = @import("dtb");
const dev = @import("../root.zig");
const root = @import("../../root.zig");

const log = std.log.scoped(.SimpleBus);

pub const SimpleBus = struct {
    pub const dev_name: []const u8 = "simple-bus";

    self_device: DTB.FDTDevice,
    inner_devices: std.array_list.Managed(dev.drivers.DeviceReference),

    pub fn try_create_from_dtb(current_device: *const DTB.FDTDevice, device_registry: *dev.drivers.DriverRegistry, alloc: std.mem.Allocator, current_path: [][]const u8) std.mem.Allocator.Error!?dev.Device {
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
        log.debug("Simple bus found, initing", .{});

        var childs: usize = 0;
        var iter = current_device.get_children();
        while (iter.next()) |_| {
            childs += 1;
        }

        log.debug("Found {d} childs devices", .{childs});
        // var arr = try alloc.alloc(DTB.FDTDevice, childs);
        var arr = try std.array_list.Managed(dev.drivers.DeviceReference).initCapacity(alloc, childs);
        errdefer arr.deinit();

        const self_instance: *SimpleBus = try alloc.create(SimpleBus);
        self_instance.* = .{
            .self_device = current_device.*,
            .inner_devices = arr,
        };
        const dev_interface = dev.Device{
            .ctx = @ptrCast(self_instance),
            .vtable = &dev.Device.VTable{
                .get_device_name = &get_device_name,
                .get_device_type = &get_device_type,
                .init = &init,
            },
        };
        iter = current_device.get_children();
        log.debug("Try yo identify childern", .{});
        const new_path = try alloc.alloc([]const u8, current_path.len + 1);
        defer alloc.free(new_path);
        @memcpy(new_path[0..current_path.len], current_path);
        new_path[current_path.len] = dev_name;
        while (iter.next()) |elem| {
            const ndev = try device_registry.device_init(&elem, alloc, new_path);
            arr.appendAssumeCapacity(ndev);
        }
        return dev_interface;
    }

    fn get_device_type(_: *anyopaque) dev.Device.Error!dev.DeviceType {
        return dev.DeviceType.DeviceGroup;
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
        log.debug("Simple-bus init", .{});
    }
};
