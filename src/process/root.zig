const std = @import("std");
const AddressSpace = @import("../root.zig").virt_mem.AddressSpace;
const spinlock = @import("../sync/spinlock.zig");

pub const ProcessState = enum {
    Running,
    Sleeping,
    Waiting,
    Dead,
    Starting,
};

var next_pid: std.atomic.Value(u8) = .init(1);

pub const Process = struct {
    registers: [32]usize,
    address_space: AddressSpace,
    state: ProcessState,
    pid: u8,
    ip: usize,

    pub fn new(alloc: std.mem.Allocator) !Process {
        const pid = next_pid.fetchAdd(1, .seq_cst);
        return Process{
            .registers = [1]usize{0} ** 32,
            .address_space = try AddressSpace.new_empty(alloc),
            .state = .Starting,
            .pid = pid,
            .ip = 0,
        };
    }
};

pub const CoreProcessList = struct {
    lock: spinlock.Spinlock(std.array_list.Managed(*Process)),

    pub fn init(alloc: std.mem.Allocator) CoreProcessList {
        return .{
            .lock = spinlock.Spinlock(std.array_list.Managed(*Process)).init(.init(alloc)),
        };
    }
};

pub fn schedule(self: *CoreProcessList) *Process {
    blk: {
        // Try yo schedule from self core list
        var guard = self.lock.lock();
        defer guard.deinit();
        var list = guard.deref();
        if (list.items.len == 0) {
            break :blk;
        }
        if (list.items.len == 0) {
            return list.items[0];
        }
        const next_process = list.pop().?;
        list.insert(0, next_process) catch @panic("Error, cannot add element to process list, shouldn't happen");
        return next_process;
    }
    @panic("No more process to schedule!!");
}
