const std = @import("std");
const Spinlock = @import("spinlock.zig");

const Self = @This();

lock: Spinlock.Spinlock(void),
readers: std.atomic.Value(usize),

pub fn init() Self {
    return .{
        .lock = .init({}),
        .readers = .init(0),
    };
}

pub const WriteGuard = struct {
    parent: *const Self,

    pub fn deinit(self: WriteGuard) void {
        self.parent.lock.unlock();
    }
};
pub const ReadGuard = struct {
    parent: *const Self,

    pub fn deinit(self: ReadGuard) void {
        _ = @constCast(&self.parent.readers).fetchSub(1, .acq_rel);
    }
};

pub fn write(self: *const Self) WriteGuard {
    _ = self.lock.lock();
    // Wait until all readers finish
    while (@constCast(&self.readers).load(.acquire) > 0) {
        std.atomic.spinLoopHint();
    }
    return .{
        .parent = self,
    };
}
pub fn read(self: *const Self) ReadGuard {
    var l = self.lock.lock();
    defer l.deinit();
    _ = @constCast(&self.readers).fetchAdd(1, .acq_rel);
    return ReadGuard{
        .parent = self,
    };
}
