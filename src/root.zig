const std = @import("std");

pub const dev = @import("dev/root.zig");
pub const log = @import("log.zig");
pub const main = @import("main.zig");
pub const phys_mem = @import("mem/phys_mem.zig");

pub fn _fw_entry() noreturn {
    main.kernel_main() catch {};
    @as(*volatile u32, @ptrFromInt(0x100000)).* = 0x5555;
    while (true) {
        asm volatile ("wfi");
    }
}
