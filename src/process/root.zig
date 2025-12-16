const std = @import("std");
const AddressSpace = @import("../root.zig").virt_mem.AddressSpace;

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
