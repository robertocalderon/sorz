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

pub fn init() align(4096) linksection(".usermode.start") noreturn {
    exit(0);
}
