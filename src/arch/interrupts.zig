const std = @import("std");
const root = @import("root");

pub fn init(alloc: std.mem.Allocator, state: *root.KernelThreadState) !void {
    const interrupt_data = try alloc.create([4096]u8);
    asm volatile ("csrw sscratch, %[val]"
        :
        : [val] "r" (@intFromPtr(&interrupt_data[0]) + 4096),
    );
    asm volatile (
        \\  csrw    stvec, %[val]
        :
        : [val] "r" (@intFromPtr(&_interrupt_handler_entry)),
    );
    const interrupt_frame: *InterruptFrame = @ptrFromInt(@intFromPtr(interrupt_data) + 4096 - @sizeOf(InterruptFrame));
    interrupt_frame.thread_state = state;
    interrupt_frame.external_interrupt_handler = null;
    std.log.debug("Interrupt frame: {*}", .{interrupt_frame});
    std.log.debug("Interrupt ready", .{});
}

pub fn get_current_interrupt_frame() *InterruptFrame {
    const base = asm volatile ("csrr %[ret], sscratch"
        : [ret] "=r" (-> usize),
    );
    const interrupt_frame: *InterruptFrame = @ptrFromInt(base - @sizeOf(InterruptFrame));
    return interrupt_frame;
}

pub const Cause = enum(u32) {
    InstructionAddressMisaligned = 0,
    InstructionAccessFault = 1,
    IllegalInstruction = 2,
    Breakpoint = 3,
    LoadAddressMisaligned = 4,
    LoadAccessFault = 5,
    ExternalSupervisorInterrupt = 0x80000009,
    _,
};

pub const InterruptFrame = extern struct {
    thread_state: *root.KernelThreadState,
    external_interrupt_handler: ?*const fn (*InterruptFrame) void = null,
    sepc: u32,
    scause: Cause,
    registers: [32]u32,
};

export fn _interrupt_handler(frame: *InterruptFrame) usize {
    switch (frame.scause) {
        .InstructionAccessFault => std.log.err("Exception: {s}", .{@tagName(frame.scause)}),
        .InstructionAddressMisaligned => std.log.err("Exception: {s}", .{@tagName(frame.scause)}),
        .Breakpoint => std.log.err("Exception: {s}", .{@tagName(frame.scause)}),
        .IllegalInstruction => std.log.err("Exception: {s}", .{@tagName(frame.scause)}),
        .LoadAccessFault => std.log.err("Exception: {s}", .{@tagName(frame.scause)}),
        .LoadAddressMisaligned => std.log.err("Exception: {s}", .{@tagName(frame.scause)}),
        _ => std.log.err("Unknown exception: 0x{x:0>8}", .{@intFromEnum(frame.scause)}),

        .ExternalSupervisorInterrupt => {
            if (frame.external_interrupt_handler) |callback| {
                callback(frame);
            }
            return frame.sepc;
        },
    }
    std.log.err("STVAL: 0x{x:0>8}", .{asm volatile ("csrr %[ret], stval"
        : [ret] "=r" (-> usize),
    )});
    std.log.err("SEPC: 0x{x:0>8}", .{asm volatile ("csrr %[ret], sepc"
        : [ret] "=r" (-> usize),
    )});
    std.log.err("SEPC: 0x{x:0>8}", .{frame.sepc});
    @panic("Unhandled exception, aborting!!");
}

export fn _interrupt_handler_entry() align(4) callconv(.naked) void {
    // Prologo
    asm volatile (
        \\ csrrw    x1, sscratch, x1
        \\ addi     x1, x1, -128
        \\ sw       x0, 0(x1)
    );
    inline for (2..32) |i| {
        const instruction_arguments = comptime std.fmt.comptimePrint("x{d}, {d}(x1)", .{ i, i * 4 });
        asm volatile ("sw " ++ instruction_arguments);
    }
    asm volatile (
        \\  mv      a0, x1
        \\  csrr    x1, sscratch
        \\  sw      x1, 4(a0)
    ++ std.fmt.comptimePrint("\naddi  a0, a0, {d}\n", .{-(@sizeOf(InterruptFrame) - 128)}) //
    ++ std.fmt.comptimePrint("addi  t0, a0, {d}\n", .{@sizeOf(InterruptFrame)}) ++
        \\  csrw    sscratch, t0
        \\  mv      sp, a0
    );

    // handle interrupt
    asm volatile (
        \\  csrr    ra, sepc
        \\  addi    sp, sp, -0x10
        \\  sw      ra, 0xc(sp)
        \\  sw      s0, 0x8(sp)
        \\  addi    s0, sp, 0x10
        \\
    ++ std.fmt.comptimePrint("\nsw ra, {d}(a0)\n", .{@offsetOf(InterruptFrame, "sepc")}) ++
        \\  csrr    t0, scause
    ++ std.fmt.comptimePrint("\nsw t0, {d}(a0)\n", .{@offsetOf(InterruptFrame, "scause")}) ++
        \\  call    _interrupt_handler
        \\  csrw    sepc, a0
        \\  addi    sp, sp, 0x10
    );

    // epilogo
    asm volatile (
        \\  csrr    x1, sscratch
        \\  addi    x1, x1, -128
        \\  lw      t0, 4(x1)
        \\ csrw     sscratch, t0
    );
    inline for (2..32) |i| {
        @setEvalBranchQuota(20000);
        const instruction_arguments = comptime std.fmt.comptimePrint("x{d}, {d}(x1)", .{ i, i * 4 });
        asm volatile ("lw " ++ instruction_arguments);
    }
    asm volatile (
        \\  addi    x1, x1, 128
        \\  csrrw   x1, sscratch, x1
        \\  sret
    );
}
