const std = @import("std");

pub fn _fw_entry() noreturn {
    @as(*volatile u32, @ptrFromInt(0x100000)).* = 0x5555;
    while (true) {
        asm volatile ("wfi");
    }
}
