const root = @import("root.zig");
const dev = root.dev;
const std = @import("std");

pub var SERIAL_BUFFER: [128]u8 = undefined;

pub fn kernel_main() !void {
    var serial = dev.serial.Serial.default(&SERIAL_BUFFER);
    root.log.init_logging(&serial.interface);
    std.log.info("Iniciando kernel...", .{});
}
