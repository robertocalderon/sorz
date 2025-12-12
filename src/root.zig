const std = @import("std");

pub const dev = @import("dev/root.zig");
pub const log = @import("log.zig");
pub const main = @import("main.zig");
pub const phys_mem = @import("mem/phys_mem.zig");
pub const spinlock = @import("./sync/spinlock.zig");
pub const pmp = @import("./arch/pmp.zig");
pub const interrupts = @import("./arch/interrupts.zig");

pub export fn _fw_entry() noreturn {
    main.kernel_main() catch {};
    @as(*volatile u32, @ptrFromInt(0x100000)).* = 0x5555;
    while (true) {
        asm volatile ("wfi");
    }
}

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

pub const std_options: std.Options = .{
    .logFn = log.log_fn,
    .page_size_max = 4096,
    .page_size_min = 4096,
};

pub const os = struct {
    pub const heap = struct {
        pub const page_allocator = phys_mem.page_alloc();
    };
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
