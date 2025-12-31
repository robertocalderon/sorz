const std = @import("std");

pub fn Spinlock(comptime T: type) type {
    return struct {
        storage: T,
        inner_lock: std.atomic.Value(bool),

        const Self = @This();

        pub const Guard = struct {
            parent: *const Self,

            pub fn deinit(self: Guard) void {
                @constCast(&self.parent.inner_lock).store(false, .release);
            }
            pub fn deref(self: Guard) *T {
                return @constCast(&self.parent.storage);
            }
        };

        pub fn init(value: T) Self {
            return .{
                .storage = value,
                .inner_lock = .init(false),
            };
        }
        pub fn lock(self: *const Self) Guard {
            while (@constCast(&self.inner_lock).swap(true, .acquire) == false) {
                std.atomic.spinLoopHint();
            }
            return .{
                .parent = self,
            };
        }
        pub fn unlock(self: *const Self) void {
            @constCast(&self.inner_lock).store(false, .release);
        }
    };
}
