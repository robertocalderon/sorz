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
        const list = guard.deref();
        if (list.items.len == 0) {
            break :blk;
        }
        const next_process = find_valid_next_process(list.items);
        return next_process orelse break :blk;
    }
    // TODO: try yo steal processes from another core
    @panic("No more process to schedule!!");
}

fn find_valid_next_process(list: *std.array_list.Managed(*Process)) ?*Process {
    for (list.items, 0..) |p, i| {
        if (p.state == .Running) {
            const tmp = list.orderedRemove(i);
            list.appendAssumeCapacity(tmp);
            return p;
        }
    }
    return null;
}
