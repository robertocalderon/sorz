const std = @import("std");
const dev = @import("root.zig");
const root = @import("../root.zig");

pub const Serial = struct {
    base: *volatile u8,
    interface: std.Io.Writer,

    pub fn get_device(self: *Serial) dev.Device {
        return .{
            .ctx = @ptrCast(self),
            .vtable = &dev.Device.VTable{
                .init = &Serial.init,
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
