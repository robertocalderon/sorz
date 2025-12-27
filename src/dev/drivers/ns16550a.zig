const std = @import("std");
const DTB = @import("dtb");
const dev = @import("../root.zig");
const root = @import("../../root.zig");

const log = std.log.scoped(.NS16550a);

pub const NS16550a = struct {
    pub const dev_name: []const u8 = "ns16550a";

    self_device: DTB.FDTDevice,
    interrupt_controller_phandle: u32,
    interrupt_number: u32,
    mmio: []volatile u8,
    interface: std.Io.Writer,
    interrupt_controller: dev.Device,

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
        var mmio: []volatile u8 = undefined;
        log.debug("Serial MMIO: 0x{x:0>8} -> 0x{x:0>8}", .{ mmio_start, mmio_start + mmio_size });
        mmio.ptr = @ptrFromInt(@as(usize, @intCast(mmio_start)));
        mmio.len = @intCast(mmio_size);

        const self_instance: *NS16550a = try alloc.create(NS16550a);
        self_instance.* = .{
            .self_device = current_device.*,
            .interrupt_controller_phandle = current_device.find_prop("interrupt-parent").?.get_small_integer().?,
            .interrupt_number = current_device.find_prop("interrupts").?.get_small_integer().?,
            .mmio = mmio,
            .interface = std.Io.Writer{ .buffer = &.{}, .end = 0, .vtable = &std.Io.Writer.VTable{
                .drain = &NS16550a.drain,
                .flush = &NS16550a.flush,
            } },
            .interrupt_controller = undefined,
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
        log.debug("ns16550a init", .{});
        const self: *NS16550a = @ptrCast(@alignCast(_self));
        const ptr: [*]volatile u8 = @ptrCast(self.mmio.ptr);
        const lcr = (1 << 0) | (1 << 1);
        ptr[3] = lcr;
        ptr[2] = 1 << 0;
        ptr[1] = 1 << 0;
        const divisor: u16 = 592;
        const divisor_least: u8 = @intCast(divisor & 0xff);
        const divisor_most: u8 = @intCast(divisor >> 8);
        ptr[3] = lcr | 1 << 7;
        ptr[0] = divisor_least;
        ptr[1] = divisor_most;
        ptr[3] = lcr;

        //var ictrl = state.platform_interrupt_controller;

        var ictrl = (try self.interrupt_controller.get_interrupt_controller()).?;
        try ictrl.enable_threshold(0, state);
        try ictrl.enable_interrupt_with_id(10, state);
        try ictrl.enable_priority_with_id(10, 1, state);

        try ictrl.register_interrupt_callback(10, &handle_exception, @ptrCast(self), state);
    }
    pub fn handle_exception(ctx: *anyopaque, state: *root.KernelThreadState) void {
        const self: *NS16550a = @ptrCast(@alignCast(ctx));
        _ = state;
        self.put(self.get() orelse return);
    }
    fn dependency_build(_self: *anyopaque, self_node: *dev.DependencyNode, all_devices: []const dev.DependencyNode) dev.Device.Error!void {
        const self: *NS16550a = @ptrCast(@alignCast(_self));

        for (all_devices, 0..) |cdev, i| {
            const phandle_prop = cdev.driver.dtb_entry.find_prop("phandle") orelse continue;
            const phandle = phandle_prop.get_u32(0) orelse continue;
            if (phandle != self.interrupt_controller_phandle) {
                continue;
            }
            try self_node.dependencies.append(&all_devices[i]);
            self.interrupt_controller = cdev.driver.handle;
        }
    }

    pub fn put(self: *NS16550a, data: u8) void {
        self.mmio[0] = data;
    }
    pub fn get(self: *NS16550a) ?u8 {
        const ptr: [*]volatile u8 = @ptrCast(self.mmio.ptr);
        if (ptr[5] & 1 == 0) {
            return null;
        }
        return ptr[0];
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        var written: usize = 0;
        const self: *NS16550a = @fieldParentPtr("interface", w);
        for (w.buffered()) |c| {
            self.mmio[0] = c;
        }
        _ = w.consumeAll();
        if (data.len > 1) {
            for (data[0 .. data.len - 1]) |buffer| {
                for (buffer) |c| {
                    written += 1;
                    self.mmio[0] = c;
                }
            }
        }
        for (0..splat) |_| {
            for (data[data.len - 1]) |c| {
                written += 1;
                self.mmio[0] = c;
            }
        }
        return written;
    }
    pub fn flush(w: *std.Io.Writer) std.Io.Writer.Error!void {
        const self: *NS16550a = @fieldParentPtr("interface", w);
        for (w.buffered()) |c| {
            self.mmio[0] = c;
        }
        _ = w.consumeAll();
    }
};
