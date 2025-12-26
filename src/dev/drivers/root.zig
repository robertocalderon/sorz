const std = @import("std");
const Spinlock = @import("../../sync/spinlock.zig").Spinlock;
const DTB = @import("dtb");
const root = @import("../../root.zig");

const log = std.log.scoped(.DriverRegistry);
const dev = @import("../root.zig");

const SimpleBus = @import("simple_bus.zig").SimpleBus;

pub const Error = error{} || std.mem.Allocator.Error;

pub const DeviceReference = struct {
    handle: dev.Device,
    path: []const u8,
};
pub const DeviceDefinition = struct {
    name: []const u8,
    check_fn: *const fn (current_device: *const DTB.FDTDevice, device_registry: *DriverRegistry, alloc: std.mem.Allocator, current_path: [][]const u8) std.mem.Allocator.Error!?dev.Device,
};

pub const DriverRegistry = struct {
    alloc: std.mem.Allocator,
    lock: Spinlock(void),

    all_devices: std.array_list.Managed(DeviceReference),
    power_devices: std.array_list.Managed(DeviceReference),

    root_devices: std.array_list.Managed(DeviceReference),

    pub fn format_path(alloc: std.mem.Allocator, current_path: [][]const u8, cdev: ?[]const u8) ![]const u8 {
        var len: usize = 0;
        for (current_path) |cp| {
            len += cp.len;
        }
        if (cdev) |d| {
            len += d.len;
        }
        const buffer = try alloc.alloc(u8, len);
        var i: usize = 0;
        for (current_path) |cp| {
            buffer[i] = '/';
            @memcpy(buffer[i + 1 ..], cp);
            i += 1 + cp.len;
        }
        if (cdev) |d| {
            buffer[i] = '/';
            @memcpy(buffer[i + 1 ..], d);
        }
        return buffer;
    }

    pub fn init(alloc: std.mem.Allocator) DriverRegistry {
        return .{
            .alloc = alloc,
            .lock = .init({}),
            .all_devices = .init(alloc),
            .power_devices = .init(alloc),
            .root_devices = .init(alloc),
        };
    }
    pub fn device_init(self: *DriverRegistry, device: *const DTB.FDTDevice, alloc: std.mem.Allocator, current_path: [][]const u8) Error!DeviceReference {
        if (try self.init_root_device(device, alloc)) {
            return undefined;
        }
        log.debug("Trying to init dev: {s}", .{device.name() orelse "???"});
        for (AVAILABLE_DEVICES) |cdev| {
            const ndev = cdev.check_fn(device, self, alloc, current_path) catch continue orelse continue;
            // alloc.destroy(ndev)
            std.log.info("Deivce added: {s}", .{cdev.name});

            const def: DeviceReference = .{
                .handle = ndev,
                .path = try format_path(alloc, current_path, cdev.name),
            };
            return def;
        }
        var compatible: []const u8 = "???";
        if (device.find_prop("compatible")) |prop| {
            compatible = prop.data;
        }
        log.err("Device {s} (compatible with: {s}) couldn't be inited or it is unknown", .{ device.name() orelse "???", compatible });
        return undefined;
    }
    pub fn init_root_device(self: *DriverRegistry, device: *const DTB.FDTDevice, alloc: std.mem.Allocator) Error!bool {
        const dname = device.name() orelse return false;
        if (!std.mem.eql(u8, dname, "/")) {
            return false;
        }
        log.debug("Found root device, initing children", .{});
        var iter = device.get_children();
        while (iter.next()) |cdev| {
            const ndef = try self.device_init(&cdev, alloc, &.{});
            try self.root_devices.append(ndef);
        }
        return true;
    }
    pub fn build_dependency_graph(self: *DriverRegistry) ![]dev.DependencyNode {
        const nodes = try self.alloc.alloc(dev.DependencyNode, self.all_devices.items.len);
        for (0..nodes.len) |i| {
            nodes[i] = dev.DependencyNode{
                .inited = false,
                .dependencies = .init(self.alloc),
                .driver = &self.all_devices.items[i],
            };
        }
        for (0..nodes.len) |i| {
            try nodes[i].driver.handle.dependency_build(&nodes[i], nodes);
        }
        return nodes;
    }
    pub fn init_nodes(self: *DriverRegistry, state: *root.KernelThreadState) !void {
        const nodes = try self.build_dependency_graph();
        defer self.alloc.free(nodes);
        // TODO: better build order/less iteration
        while (!dep_grap_ready(nodes)) {
            for (nodes) |n| {
                if (n.inited) {
                    continue;
                }
                if (!dep_graph_node_ready(n)) {
                    continue;
                }
                try n.driver.handle.init(state);
            }
        }
    }
    fn dep_grap_ready(graph: []const dev.DependencyNode) bool {
        for (graph) |node| {
            if (!node.inited) {
                return false;
            }
        }
        return true;
    }
    fn dep_graph_node_ready(node: dev.DependencyNode) bool {
        for (node.dependencies.items) |dep| {
            if (!dep.inited) {
                return false;
            }
        }
        return true;
    }
};

pub const AVAILABLE_DEVICES: []const DeviceDefinition = &.{
    .{ .name = SimpleBus.dev_name, .check_fn = &SimpleBus.try_create_from_dtb },
    .{ .name = "NS16550a", .check_fn = &@import("ns16550a.zig").NS16550a.try_create_from_dtb },
};
