const root = @import("root.zig");
const dev = root.dev;

pub var SERIAL_BUFFER: [128]u8 = undefined;

pub fn kernel_main() !void {
    var serial = dev.serial.Serial.default(&SERIAL_BUFFER);
    try serial.interface.print("Iniciando kernel...\n", .{});
    try serial.interface.flush();
}
