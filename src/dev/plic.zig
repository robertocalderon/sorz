const std = @import("std");
const dev = @import("./root.zig");

pub const PLIC = struct {
    const Self = @This();

    const Registers = extern struct {
        interrupt_source_priority: [1024]u32 align(1),
        interrupt_pending_bits: [128]u8,
        _padding_0: [4096 - 128]u8,
        enable_bit_sources: [7936][2][128]u8,
        _padding_1: [0x200000 - 0x1f2000]u8,
        priority_threshold: [7936][2][1024]u32,

        pub fn new() *Registers {
            comptime {
                if (@offsetOf(Registers, "interrupt_source_priority") != 0) {
                    @compileError(std.fmt.comptimePrint("Invalid alignment, interrupt_source_priority(0x{x}) != 0x0", .{@offsetOf(Registers, "interrupt_source_priority")}));
                }
                if (@offsetOf(Registers, "interrupt_pending_bits") != 0x001000) {
                    @compileError(std.fmt.comptimePrint("Invalid alignment, interrupt_pending_bits(0x{x}) != 0x001000", .{@offsetOf(Registers, "interrupt_pending_bits")}));
                }
                if (@offsetOf(Registers, "enable_bit_sources") != 0x002000) {
                    @compileError(std.fmt.comptimePrint("Invalid alignment, enable_bit_sources(0x{x}) != 0x002000", .{@offsetOf(Registers, "enable_bit_sources")}));
                }
                if (@offsetOf(Registers, "priority_threshold") != 0x200000) {
                    @compileError(std.fmt.comptimePrint("Invalid alignment, priority_threshold(0x{x}) != 0x200000", .{@offsetOf(Registers, "priority_threshold")}));
                }
                if (@sizeOf(Registers) != 0x4000000) {
                    @compileError(std.fmt.comptimePrint("Invalid alignment, @sizeOf(PLIC) (0x{x}) != 0x4000000", .{@sizeOf(Registers)}));
                }
            }
            return @ptrFromInt(0x1000_0000);
        }
    };
    const Callback = struct {
        callback: *const fn (*anyopaque) void,
        ctx: *anyopaque,
    };

    registers: *Registers,
    callbacks: []Callback,

    pub fn new() Self {
        return .{
            .registers = .new(),
            .callbacks = undefined,
        };
    }

    fn init(_self: *anyopaque, alloc: std.mem.Allocator) dev.Device.Error!void {
        const self: *Self = @ptrCast(@alignCast(_self));
        self.callbacks = try alloc.alloc(Callback, 32);
    }

    pub fn get_device(self: *Self) dev.Device {
        return .{
            .ctx = @ptrCast(self),
            .vtable = &dev.Device.VTable{
                .init = &init,
            },
        };
    }
    pub fn get_interrupt_controller(self: *Self) dev.InterruptController {
        return .{
            .ctx = @ptrCast(self),
            .vtable = &dev.InterruptController.VTable{},
        };
    }
};
