const std = @import("std");
const dev = @import("root.zig");
const root = @import("../root.zig");

pub const Serial = struct {
    base: *volatile u8,
    interface: std.Io.Writer,

    fn get_device_type(_: *anyopaque) dev.Device.Error!dev.DeviceType {
        return dev.DeviceType.IODevice;
    }
    pub fn get_device_name(_: *anyopaque, buffer: []u8) dev.Device.Error![]u8 {
        const device_name = "generic-serial";
        if (buffer.len < device_name.len) {
            @memcpy(buffer, device_name[0..buffer.len]);
            return dev.Device.Error.BufferTooSmall;
        } else {
            @memcpy(buffer, device_name);
            return buffer[0..device_name.len];
        }
    }
    pub fn get_device(self: *Serial) dev.Device {
        return .{
            .ctx = @ptrCast(self),
            .vtable = &dev.Device.VTable{
                .init = &Serial.init,
                .get_device_type = &get_device_type,
                .get_device_name = &get_device_name,
            },
        };
    }

    fn init(_self: *anyopaque, state: *root.KernelThreadState) dev.Device.Error!void {
        const self: *Serial = @ptrCast(@alignCast(_self));
        const ptr: [*]volatile u8 = @ptrCast(self.base);
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

        var ictrl = state.platform_interrupt_controller;
        try ictrl.enable_threshold(0, state);
        try ictrl.enable_interrupt_with_id(10, state);
        try ictrl.enable_priority_with_id(10, 1, state);

        try ictrl.register_interrupt_callback(10, &handle_exception, @ptrCast(self), state);
    }
    pub fn handle_exception(ctx: *anyopaque, state: *root.KernelThreadState) void {
        const self: *Serial = @ptrCast(@alignCast(ctx));
        _ = state;
        self.put(self.get() orelse return);
    }

    pub fn default(buffer: []u8) Serial {
        return Serial.new(@ptrFromInt(0x10000000), buffer);
    }
    pub fn new(base: *volatile u8, buffer: []u8) Serial {
        return .{
            .base = base,
            .interface = std.Io.Writer{ .buffer = buffer, .end = 0, .vtable = &std.Io.Writer.VTable{
                .drain = &Serial.drain,
                .flush = &Serial.flush,
            } },
        };
    }
    pub fn put(self: *Serial, data: u8) void {
        self.base.* = data;
    }
    pub fn get(self: *Serial) ?u8 {
        const ptr: [*]volatile u8 = @ptrCast(self.base);
        if (ptr[5] & 1 == 0) {
            return null;
        }
        return ptr[0];
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        var written: usize = 0;
        const self: *Serial = @fieldParentPtr("interface", w);
        for (w.buffered()) |c| {
            self.base.* = c;
        }
        _ = w.consumeAll();
        if (data.len > 1) {
            for (data[0 .. data.len - 1]) |buffer| {
                for (buffer) |c| {
                    written += 1;
                    self.base.* = c;
                }
            }
        }
        for (0..splat) |_| {
            for (data[data.len - 1]) |c| {
                written += 1;
                self.base.* = c;
            }
        }
        return written;
    }
    pub fn flush(w: *std.Io.Writer) std.Io.Writer.Error!void {
        const self: *Serial = @fieldParentPtr("interface", w);
        for (w.buffered()) |c| {
            self.base.* = c;
        }
        _ = w.consumeAll();
    }
};
