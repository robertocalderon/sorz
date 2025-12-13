const std = @import("std");
const root = @import("../root.zig");

pub noinline fn lower_to_s_mode(ptr: *const fn () noreturn) noreturn {
    asm volatile (
        \\  csrw    mepc, %[val]
        // Save current frame so @panic stack trace walker can give accurate info
        \\  addi    sp, sp, -0x10
        \\  sw      ra, 0xc(sp)
        \\  sw      s0, 0x8(sp)
        \\  addi    s0, sp, 0x10
        \\  la      ra, .lower_to_s_mode_ret
        \\  csrw    mstatus, %[val2]
        \\  mret
        \\ .lower_to_s_mode_ret:
        :
        : [val] "r" (@intFromPtr(ptr)),
          [val2] "r" (@as(usize, 1 << 11)),
    );
    root.qemu.exit(.Failure);
}
