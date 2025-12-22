const std = @import("std");
const Spinlock = @import("../../sync/spinlock.zig").Spinlock;
const DTB = @import("dtb");

const log = std.log.scoped(.DriverRegistry);

pub const Error = error{};

pub const DriverRegistry = struct {
    alloc: std.mem.Allocator,
    lock: Spinlock(void),

    pub fn init(alloc: std.mem.Allocator) DriverRegistry {
        return .{
            .alloc = alloc,
            .lock = .init({}),
        };
    }
    pub fn device_init(device: *const DTB.FDTDevice) Error!void {
        if (try init_root_device(device)) {
            return;
        }
        log.debug("Trying to init dev: {s}", .{device.name() orelse "???"});
    }
    pub fn init_root_device(device: *const DTB.FDTDevice) Error!bool {
        const dname = device.name() orelse return false;
        if (!std.mem.eql(u8, dname, "/")) {
            return false;
        }
        log.debug("Found root device, initing children", .{});
        var iter = device.get_children();
        while (iter.next()) |dev| {
            try device_init(&dev);
        }
        return true;
    }
};
