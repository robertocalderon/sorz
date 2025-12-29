const std = @import("std");

pub fn Spinlock(comptime T: type) type {
    return struct {
        storage: T,
        inner_lock: std.atomic.Value(bool),

        const Self = @This();

        pub const Guard = struct {
            parent: *Self,

            pub fn deinit(self: Guard) void {
                self.parent.inner_lock.store(false, .release);
            }
            pub fn deref(self: Guard) *T {
                return &self.parent.storage;
            }
        };

        pub fn init(value: T) Self {
            return .{
                .storage = value,
                .inner_lock = .init(false),
            };
        }
        pub fn lock(self: *Self) Guard {
            while (self.inner_lock.swap(true, .acquire) == false) {
                std.atomic.spinLoopHint();
            }
            return .{
                .parent = self,
            };
        }
    };
}
