const std = @import("std");

pub const Serial = struct {
    base: *volatile u8,
    interface: std.Io.Writer,

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

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        var written: usize = 0;
        const self: *Serial = @fieldParentPtr("interface", w);
        for (w.buffered()) |c| {
            self.base.* = c;
        }
        _ = w.consumeAll();
        for (data, 0..data.len - 1) |buffer, _| {
            for (buffer) |c| {
                written += 1;
                self.base.* = c;
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
