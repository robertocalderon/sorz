const std = @import("std");

pub const SBIError = error{
    ErrFailed,
    NotSupported,
    InvalidParam,
    Denied,
    InvalidAddress,
    AlreadyAvailable,
    AlreadyStarted,
    AlreadyStopped,
    Unknown,
};

pub const EID = enum(u32) {
    ConsolePutchar = 0x01,
    Base = 0x10,
    DebugConsoleExtension = 0x4442434E,
};
pub const BaseFID = enum(u32) {
    GetSpecVersion = 0,
    ImplId = 1,
    ImplVersion = 2,
    ProbeExtension = 3,
    MachineVendorId = 4,
    MachineArchId = 5,
    MachineImplId = 6,
};

fn sbi_ecall(eid: EID, fid: usize, a0: usize, a1: usize, a2: usize) SBIError!usize {
    var ra0: isize = undefined;
    var ra1: usize = undefined;
    asm volatile (
        \\  ecall
        : [ra0] "={x10}" (ra0),
          [ra1] "={x11}" (ra1),
        : [a0] "{x10}" (a0),
          [a1] "{x11}" (a1),
          [a2] "{x12}" (a2),
          [a7] "{x17}" (@intFromEnum(eid)),
          [a6] "{x16}" (fid),
        : .{ .memory = true });
    if (ra0 != 0) {
        switch (ra0) {
            -1 => return SBIError.ErrFailed,
            -2 => return SBIError.NotSupported,
            -3 => return SBIError.InvalidParam,
            -4 => return SBIError.Denied,
            -5 => return SBIError.InvalidAddress,
            -6 => return SBIError.AlreadyAvailable,
            -7 => return SBIError.AlreadyStarted,
            -8 => return SBIError.AlreadyStopped,

            else => return SBIError.Unknown,
        }
    }
    return ra1;
}

fn sbi_base_ecall(fid: BaseFID, a0: usize, a1: usize) SBIError!usize {
    return sbi_ecall(.Base, @intFromEnum(fid), a0, a1, 0);
}

pub const SBISpecVersion = packed struct {
    minor: u24,
    major: u8,
};

pub fn sbi_get_spec_version() SBIError!SBISpecVersion {
    return @bitCast(try sbi_base_ecall(.GetSpecVersion, 0, 0));
}
pub fn sbi_get_impl_id() SBIError!usize {
    return sbi_base_ecall(.ImplId, 0, 0);
}
pub fn sbi_get_impl_version() SBIError!usize {
    return sbi_base_ecall(.ImplVersion, 0, 0);
}
pub fn sbi_probe_extension(eid: EID) SBIError!bool {
    return (try sbi_base_ecall(.ProbeExtension, @intFromEnum(eid), 0)) != 0;
}
pub fn sbi_get_mvendorid() SBIError!usize {
    return sbi_base_ecall(.MachineVendorId, 0, 0);
}
pub fn sbi_get_marchid() SBIError!usize {
    return sbi_base_ecall(.MachineArchId, 0, 0);
}
pub fn sbi_get_mimpid() SBIError!usize {
    return sbi_base_ecall(.MachineImplId, 0, 0);
}

pub fn sbi_debug_console_write(buffer: []const u8) SBIError!usize {
    return sbi_ecall(.DebugConsoleExtension, 0, buffer.len, @intFromPtr(buffer.ptr), 0);
}
pub fn sbi_debug_console_write_byte(byte: u8) SBIError!usize {
    return sbi_ecall(.DebugConsoleExtension, 2, byte, 0, 0);
}
pub const SBIDebugWriter = struct {
    interface: std.Io.Writer,

    pub fn init(buffer: []u8) SBIDebugWriter {
        return .{ .interface = std.Io.Writer{
            .buffer = buffer,
            .end = 0,
            .vtable = &std.Io.Writer.VTable{
                .drain = &SBIDebugWriter.drain,
                .flush = &SBIDebugWriter.flush,
            },
        } };
    }

    pub fn write_buffer(buffer: []const u8) !void {
        var writen: usize = 0;
        while (writen < buffer.len) {
            const more = try sbi_debug_console_write(buffer[writen..]);
            writen += more;
        }
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        var written: usize = 0;
        write_buffer(w.buffer[0..w.end]) catch return std.Io.Writer.Error.WriteFailed;
        _ = w.consumeAll();
        if (data.len > 1) {
            for (data[0 .. data.len - 1]) |buffer| {
                written += buffer.len;
                write_buffer(buffer) catch return std.Io.Writer.Error.WriteFailed;
            }
        }
        for (0..splat) |_| {
            written += data[data.len - 1].len;
            write_buffer(data[data.len - 1]) catch return std.Io.Writer.Error.WriteFailed;
        }
        return written;
    }
    pub fn flush(w: *std.Io.Writer) std.Io.Writer.Error!void {
        write_buffer(w.buffer[0..w.end]) catch return std.Io.Writer.Error.WriteFailed;
        _ = w.consumeAll();
    }
};
