pub const SyscallNumber = enum(u32) {
    Exit = 93,
};
pub fn ecalll(call: SyscallNumber, a0: u32, a1: u32, a2: u32, a3: u32, a4: u32, a5: u32) linksection(".usermode") void {
    asm volatile (
        \\  ecall
        :
        : [_] "{a0}" (a0),
          [_] "{a1}" (a1),
          [_] "{a2}" (a2),
          [_] "{a3}" (a3),
          [_] "{a4}" (a4),
          [_] "{a5}" (a5),
          [_] "{a7}" (@intFromEnum(call)),
    );
}
pub fn exit(value: i32) linksection(".usermode") noreturn {
    ecalll(.Exit, @bitCast(value), 0, 0, 0, 0, 0);
    while (true) {
        asm volatile ("nop");
    }
}

var stack: [4096]u8 = undefined;

pub export fn _start() linksection(".text.start") callconv(.naked) void {
    @setRuntimeSafety(false);
    asm volatile (
        \\  csrw    satp, zero
        \\  addi    sp, sp, -16
        \\  sw      zero, 4(sp)
        \\  sw      zero, 0(sp)
        \\  addi    s0, sp, 16
        \\  call    init
        :
        : [_SP] "{sp}" (@as(usize, @intFromPtr(&stack)) + stack.len),
          [_RA] "{ra}" (0),
          [_S0] "{s0}" (0),
    );
}

pub export fn init() align(4096) linksection(".usermode.start") noreturn {
    exit(0);
}
