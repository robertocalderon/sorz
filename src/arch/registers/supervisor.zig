const std = @import("std");

pub const ExtensionState = enum(u2) {
    Off = 0,
    Initial = 1,
    Dirty = 2,
    Wot = 3,
};
pub const PrivilegeMode = enum(u1) { User = 0, Supervisor = 1 };

pub const SStatus = packed struct {
    _0: u1,
    /// Supervisor Interrupt Enable bit
    ///
    /// Enable or disable interrupt handling in supervisor mode
    /// if disabled interrupts will still be generated for m-mode (if active)
    /// but will not be send to s-mode
    SIE: u1,
    _1: u3,
    /// Supervisor Previous Interrupt Enable
    ///
    /// Store the previous state of SIE to restore it after the interrupt is handled
    SPIE: u1,
    /// User Byte Endianess
    ///
    /// If set, user mode explicit reads will be made using big-endian, if clear then little-endian
    ///     0 => little-endian
    ///     1 => big-endian
    UBE: u1,
    _2: u1,
    /// Supervisor Previous Privilege
    ///
    /// When an interrupt is beign handled, store the privilege of the code that generated the trap/exception
    ///     0 => from user mode
    ///     1 => from supervisor mode
    SPP: PrivilegeMode,
    VS: ExtensionState,
    _3: u2,
    FS: ExtensionState,
    XS: ExtensionState,
    _4: u1,
    /// Supervisor User Memory access
    ///
    /// If set, allows supervisor mode code to access memory pages marked as user pages
    SUM: u1,
    /// Make eXecutable Readable
    ///
    /// If this bit is on memory pages that are marked as executable (but not readable) will
    /// not fault when reading that page even if not marked as readable
    MXR: u1,
    _5: u3,
    /// Supervisor Previous Expected Landing Pad
    ///
    /// Bity for Zicfilp
    SPELP: u1,
    /// S-mode Disable Trap
    ///
    /// The S-mode-disable-trap (SDT) bit is a WARL field introduced by the Ssdbltrp extension to address double trap
    /// at privilege modes lower than M.
    SDT: u1,
    _6: u6,
    /// State Dirty
    SD: u1,

    pub fn read() SStatus {
        comptime {
            if (@bitSizeOf(SStatus) != @bitSizeOf(u32)) {
                @compileError("Invalid size of SStatus, check definiton");
            }
        }

        const raw = asm volatile ("csrr %[ret], sstatus"
            : [ret] "=r" (-> usize),
        );
        return @bitCast(raw);
    }
    pub fn write(self: SStatus) void {
        asm volatile (
            \\  csrw    sstatus, %[val]
            :
            : [val] "r" (@as(usize, @bitCast(self))),
        );
    }
};

pub const SIE = packed union {
    raw: u32,
    bits: packed struct {
        _0: u1,
        supervisor_software: u1,
        _1: u3,
        supervisor_timer: u1,
        _2: u3,
        supervisor_external: u1,
        _3: u3,
        counter_overflow: u1,
    },

    pub fn read() SIE {
        comptime {
            if (@bitSizeOf(SIE) != @bitSizeOf(u32)) {
                @compileError("Invalid size of SIE, check definiton");
            }
        }

        const raw = asm volatile ("csrr %[ret], sie"
            : [ret] "=r" (-> usize),
        );
        return @bitCast(raw);
    }
    pub fn write(self: SIE) void {
        asm volatile (
            \\  csrw    sie, %[val]
            :
            : [val] "r" (@as(usize, @bitCast(self))),
        );
    }
};
