pub const ExitState = enum(u32) {
    Success = 0x5555,
    Failure = 0x3333,
    Reset = 0x7777,
    _,
};

pub fn exit(exit_code: ExitState) noreturn {
    const real_code = switch (exit_code) {
        else => @intFromEnum(exit_code),
        _ => (@intFromEnum(exit_code) << 16) | @intFromEnum(ExitState.Failure),
    };
    @as(*volatile u32, @ptrFromInt(0x100000)).* = real_code;
    while (true) {
        asm volatile ("wfi");
    }
}
