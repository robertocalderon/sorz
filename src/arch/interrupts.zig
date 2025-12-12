const std = @import("std");
const root = @import("root");

pub fn init(alloc: std.mem.Allocator) !void {
    const interrupt_date = try alloc.create([4096]u8);
    asm volatile ("csrw mscratch, %[val]"
        :
        : [val] "r" (@intFromPtr(&interrupt_date[0]) + 4096),
    );
    const interrupt_pointer = @intFromPtr(&_interrupt_handler);
    asm volatile (
        \\  csrw    mtvec, %[val]
        :
        : [val] "r" (interrupt_pointer),
    );
    std.log.debug("Interrupt ready", .{});
}

const InterruptFrame = struct {
    mepc: u32,
    registers: [32]u32,
};

export fn _interrupt_handler(frame: *InterruptFrame) void {
    _ = frame;
    @panic("Unhandled exception, aborting!!");
}

export fn _interrupt_handler_entry() align(4) callconv(.naked) void {
    // Prologo
    asm volatile (
        \\ csrrw    x1, mscratch, x1
        \\ addi     x1, x1, -128
        \\ sw       x0, 0(x1)
    );
    inline for (2..32) |i| {
        const instruction_arguments = comptime std.fmt.comptimePrint("x{d}, {d}(x1)", .{ i, i * 4 });
        asm volatile ("sw " ++ instruction_arguments);
    }
    asm volatile (
        \\  mv      a0, x1
        \\  csrr    x1, mscratch
        \\  sw      x1, 4(a0)
    ++ std.fmt.comptimePrint("\naddi  a0, a0, {d}\n", .{-(@sizeOf(InterruptFrame) - 128)}) //
    ++ std.fmt.comptimePrint("addi  t0, a0, {d}\n", .{@sizeOf(InterruptFrame)}) ++
        \\  csrw    mscratch, t0
        \\  mv      sp, a0
    );

    // handle interrupt
    asm volatile (
        \\  csrr    ra, mepc
        \\  addi    sp, sp, -0x10
        \\  sw      ra, 0xc(sp)
        \\  sw      s0, 0x8(sp)
        \\  addi    s0, sp, 0x10
        \\
        \\  sw      ra, 0(a0)
        \\  call    _interrupt_handler
        \\  lw      ra, 0(a0)
        \\  csrw    mepc, ra
        \\  addi    sp, sp, 0x10
    );

    // epilogo
    asm volatile (
        \\  csrr    x1, mscratch
        \\  addi    x1, x1, -128
        \\  lw      t0, 4(x4)
        \\ csrw     mscratch, t0
    );
    inline for (2..32) |i| {
        @setEvalBranchQuota(20000);
        const instruction_arguments = comptime std.fmt.comptimePrint("x{d}, {d}(x1)", .{ i, i * 4 });
        asm volatile ("lw " ++ instruction_arguments);
    }
    asm volatile (
        \\  addi    x1, x1, 128
        \\  csrrw   x1, mscratch, x1
        \\  mret
    );
}
