pub const sorz = @import("sorz");
const std = @import("std");

extern var _fw_stack_end: u8;

pub export fn _start() linksection(".text.start") callconv(.naked) void {
    @setRuntimeSafety(false);
    asm volatile (
        \\  csrr    t0, mhartid
        \\  bnez    t0, ._start_other_cores
        \\  addi    sp, sp, -16
        \\  sw      zero, 4(sp)
        \\  sw      zero, 0(sp)
        \\  addi    s0, sp, 16
        \\  call    _fw_entry
        \\._start_other_cores:
        \\  wfi
        \\  j       ._start_other_cores
        :
        : [_SP] "{sp}" (@as(usize, @intFromPtr(&_fw_stack_end))),
          [_RA] "{ra}" (0),
          [_S0] "{s0}" (0),
    );
}

pub export fn _fw_entry() noreturn {
    sorz._fw_entry();
}

pub const std_options: std.Options = .{
    .logFn = sorz.log.log_fn,
};
