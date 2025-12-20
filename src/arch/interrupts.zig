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

const RegNumbers = struct {
    pub const ra = 1;
    pub const sp = 2;
    pub const gp = 3;
    pub const tp = 4;
    pub const t0 = 5;
    pub const t1 = 6;
    pub const t2 = 7;
    pub const s0 = 8;
    pub const fp = 8;
    pub const s1 = 9;
    pub const a0 = 10;
    pub const a1 = 11;
    pub const a2 = 12;
    pub const a3 = 13;
    pub const a4 = 14;
    pub const a5 = 15;
    pub const a6 = 16;
    pub const a7 = 17;
    pub const s2 = 18;
    pub const s3 = 19;
    pub const s4 = 20;
    pub const s5 = 21;
    pub const s6 = 22;
    pub const s7 = 23;
    pub const s8 = 24;
    pub const s9 = 25;
    pub const s10 = 26;
    pub const s11 = 27;
    pub const t3 = 28;
    pub const t4 = 29;
    pub const t5 = 30;
    pub const t6 = 31;
};

pub fn set_current_process(proc: *root.process.Process) void {
    const frame = get_current_interrupt_frame();
    frame.current_process = proc;
}

pub const Cause = enum(u32) {
    InstructionAddressMisaligned = 0,
    InstructionAccessFault = 1,
    IllegalInstruction = 2,
    Breakpoint = 3,
    LoadAddressMisaligned = 4,
    LoadAccessFault = 5,
    StoreAMOAddressMisaligned = 6,
    StoreAMOAccessFault = 7,
    EnvironmentCallFromUMode = 8,
    EnvironmentCallFromSMode = 9,
    ExternalSupervisorInterrupt = 0x80000009,
    _,
};

pub const InterruptFrame = extern struct {
    thread_state: *root.KernelThreadState,
    external_interrupt_handler: ?*const fn (*InterruptFrame) void = null,
    sepc: u32,
    scause: Cause,
    current_process: *root.process.Process,
    registers: [32]u32,
};

export fn _interrupt_handler(frame: *InterruptFrame) usize {
    switch (frame.scause) {
        .ExternalSupervisorInterrupt => {
            if (frame.external_interrupt_handler) |callback| {
                callback(frame);
            }
            return frame.sepc;
        },
        .EnvironmentCallFromUMode => {
            const system_call = frame.registers[RegNumbers.a7];
            if (system_call == 93) {
                std.log.debug("Exit syscall", .{});

                @memcpy(&frame.current_process.registers, &frame.registers);
                frame.current_process.ip = frame.sepc;
                frame.current_process.state = .Dead;

                var process_exists: ?*root.process.Process = null;
                var pidx: usize = 0;
                {
                    var guard = frame.thread_state.self_process_list.lock.lock();
                    defer guard.deinit();
                    const list = guard.deref();
                    for (list.items, 0..) |p, i| {
                        if (p.pid == frame.current_process.pid) {
                            process_exists = p;
                            pidx = i;
                            break;
                        }
                    }
                    if (process_exists) |_| {
                        const old_process = list.orderedRemove(pidx);
                        frame.thread_state.alloc.destroy(old_process);
                        std.log.debug("process found, removing fromlist", .{});
                    }
                }
                const next_process = root.process.schedule(frame.thread_state.self_process_list);
                @memcpy(&frame.registers, &next_process.registers);
                frame.sepc = next_process.ip;
                frame.current_process = next_process;
                return frame.sepc;
            }
            @panic("unimplemented");
        },

        else => std.log.err("Exception: {s}", .{@tagName(frame.scause)}),
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
