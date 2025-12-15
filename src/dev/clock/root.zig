const std = @import("std");

pub const ClockError = error{};

pub const Instant = struct {
    raw: u64,
};

pub const Clock = struct {
    pub const VTable = struct {
        init: *const fn (*Clock) ClockError!void = undefined,
        now: *const fn (*Clock) ClockError!Instant = undefined,
    };

    vtable: *const VTable,

    pub fn init(self: *Clock) ClockError!void {
        return self.vtable.init(self);
    }
    pub fn now(self: *Clock) ClockError!Instant {
        return self.vtable.now(self);
    }

    pub fn mtime() Clock {
        return .{
            .vtable = &.{
                .init = &mtime_init,
                .now = &mtime_now,
            },
        };
    }
};

const MTIME_LOW: *volatile u32 = @ptrFromInt(0x2000000 + 0xBFF8);
const MTIME_HIGH: *volatile u32 = @ptrFromInt(0x2000000 + 0xBFF8 + 4);

fn mtime_init(_: *Clock) ClockError!void {}
fn mtime_now(_: *Clock) ClockError!Instant {
    var low: u32 = undefined;
    var high: u32 = undefined;
    var high2: u32 = undefined;

    while (true) {
        high = asm volatile ("rdtimeh %[ret]"
            : [ret] "=r" (-> usize),
        );
        low = asm volatile ("rdtime %[ret]"
            : [ret] "=r" (-> usize),
        );
        high2 = asm volatile ("rdtimeh %[ret]"
            : [ret] "=r" (-> usize),
        );

        if (high == high2) {
            const raw = @as(u64, @intCast(low)) | (@as(u64, @intCast(high)) << 32);
            // QEMU clock runs at 10MHz
            const nanos = raw * 1000000000 / 10000000;
            return .{
                .raw = nanos,
            };
        }
    }
}
