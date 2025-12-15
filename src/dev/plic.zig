const std = @import("std");
const dev = @import("./root.zig");

pub const PLIC = extern struct {
    interrupt_source_priority: [1024]u32 align(1),
    interrupt_pending_bits: [128]u8,
    _padding_0: [4096 - 128]u8,
    enable_bit_sources: [7936][2][128]u8,
    _padding_1: [0x200000 - 0x1f2000]u8,
    priority_threshold: [7936][2][1024]u32,

    const Self = @This();

    pub fn new() *Self {
        comptime {
            if (@offsetOf(Self, "interrupt_source_priority") != 0) {
                @compileError(std.fmt.comptimePrint("Invalid alignment, interrupt_source_priority(0x{x}) != 0x0", .{@offsetOf(Self, "interrupt_source_priority")}));
            }
            if (@offsetOf(Self, "interrupt_pending_bits") != 0x001000) {
                @compileError(std.fmt.comptimePrint("Invalid alignment, interrupt_pending_bits(0x{x}) != 0x001000", .{@offsetOf(Self, "interrupt_pending_bits")}));
            }
            if (@offsetOf(Self, "enable_bit_sources") != 0x002000) {
                @compileError(std.fmt.comptimePrint("Invalid alignment, enable_bit_sources(0x{x}) != 0x002000", .{@offsetOf(Self, "enable_bit_sources")}));
            }
            if (@offsetOf(Self, "priority_threshold") != 0x200000) {
                @compileError(std.fmt.comptimePrint("Invalid alignment, priority_threshold(0x{x}) != 0x200000", .{@offsetOf(Self, "priority_threshold")}));
            }
            if (@sizeOf(Self) != 0x4000000) {
                @compileError(std.fmt.comptimePrint("Invalid alignment, @sizeOf(PLIC) (0x{x}) != 0x4000000", .{@sizeOf(Self)}));
            }
        }
        return @ptrFromInt(0x1000_0000);
    }

    fn init(self: *Self) dev.Device.Error!void {
        _ = self;
    }

    pub fn get_device(self: *Self) dev.Device {
        return .{
            .ctx = @ptrCast(self),
            .vtable = &dev.Device.VTable{
                .init = @ptrCast(&init),
            },
        };
    }
};
