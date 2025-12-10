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

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    std.log.err("PANIC!!!!", .{});
    std.log.err("MSG: {s}", .{msg});
    _ = error_return_trace;
    _ = ret_addr;
    // for now exit qemu
    @as(*volatile u32, @ptrFromInt(0x100000)).* = 0x5555;
    while (true) {
        asm volatile ("wfi");
    }
}
