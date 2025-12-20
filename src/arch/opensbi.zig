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
    _,
};

pub const EID = enum(u32) {
    Base = 0x10,
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

fn sbi_ecall(eid: EID, fid: usize, a0: usize, a1: usize) SBIError!usize {
    var ra0: isize = undefined;
    var ra1: usize = undefined;
    asm volatile (
        \\  ecall
        \\  mv      %[ra0], a0
        \\  mv      %[ra1], a1
        : [ra0] "=r" (ra0),
          [ra1] "=r" (ra1),
        : [a0] "{a0}" (a0),
          [a1] "{a1}" (a1),
          [a7] "{a7}" (@intFromEnum(eid)),
          [a6] "{a6}" (fid),
    );
    if (ra0 != 0) {
        return @enumFromInt(ra0);
    }
    return ra1;
}

fn sbi_base_ecall(fid: BaseFID, a0: usize, a1: usize) SBIError!usize {
    return sbi_ecall(.Base, @intFromEnum(fid), a0, a1);
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
