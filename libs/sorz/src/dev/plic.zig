const std = @import("std");
const dev = @import("./root.zig");
const registers = @import("../arch/registers.zig");
const root = @import("../root.zig");

pub const PLIC = struct {
    const Self = @This();

    const Registers = extern struct {
        interrupt_source_priority: [1024]u32 align(1),
        interrupt_pending_bits: [128 / 4]u32,
        _padding_0: [4096 - 128]u8,
        enable_bit_sources: [7936][2][128 / 4]u32,
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
            return @ptrFromInt(0x0c00_0000);
        }
    };
    const Callback = struct {
        fun: *const fn (*anyopaque, *root.KernelThreadState) void,
        ctx: *anyopaque,
    };

    registers: *Registers,
    callbacks: []?Callback,

    pub fn new() Self {
        return .{
            .registers = .new(),
            .callbacks = undefined,
        };
    }

    fn init(_self: *anyopaque, state: *root.KernelThreadState) dev.Device.Error!void {
        const self: *Self = @ptrCast(@alignCast(_self));
        self.callbacks = try state.alloc.alloc(?Callback, 32);
        for (0..self.callbacks.len) |i| {
            self.callbacks[i] = null;
        }
    }
    fn init_interrupt_controller(_self: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(_self));
        _ = self;

        const iframe = root.interrupts.get_current_interrupt_frame();
        iframe.external_interrupt_handler = &handle_external_supervisor_interrpt;

        var sie = registers.supervisor.SIE.read();
        sie.bits.supervisor_external = 1;
        sie.write();
        std.log.debug("SIE = {b:0>8}", .{asm volatile ("csrr %[ret], sie"
            : [ret] "=r" (-> usize),
        )});
        var sstatus = registers.supervisor.SStatus.read();
        sstatus.SIE = 1;
        sstatus.write();
    }
    fn handle_external_supervisor_interrpt(frame: *root.interrupts.InterruptFrame) void {
        const ictrl: *Self = @ptrCast(@alignCast(frame.thread_state.platform_interrupt_controller.ctx));
        const id = ictrl.claim_interrupt(frame.thread_state) orelse return;
        if (id > 0 and id < ictrl.callbacks.len) {
            if (ictrl.callbacks[id]) |callback| {
                callback.fun(callback.ctx, frame.thread_state);
            }
        }
        ictrl.complete_interrupt(id, frame.thread_state);
    }

    pub fn enable_interrupt_with_id(_self: *anyopaque, id: usize, state: *root.KernelThreadState) dev.InterruptController.Error!void {
        const self: *Self = @ptrCast(@alignCast(_self));
        std.log.debug("Enabling PLIC interrupt bit {d} on hart {d} {*}", .{ id, state.hartid, &self.registers.enable_bit_sources[state.hartid][1][id / 32] });
        self.registers.enable_bit_sources[state.hartid][1][id / 32] |= @as(u32, 1) << @intCast(id % 32);
    }
    pub fn enable_threshold(_self: *anyopaque, tsh: u3, state: *root.KernelThreadState) dev.InterruptController.Error!void {
        const self: *Self = @ptrCast(@alignCast(_self));
        std.log.debug("Set PLIC threshold = {}, on hart {d} {*}", .{ tsh, state.hartid, &self.registers.priority_threshold[state.hartid][1][0] });
        self.registers.priority_threshold[state.hartid][1][0] = @intCast(tsh);
    }
    pub fn enable_priority_with_id(_self: *anyopaque, id: usize, pri: u3, _: *root.KernelThreadState) dev.InterruptController.Error!void {
        const self: *Self = @ptrCast(@alignCast(_self));
        std.log.debug("Set PLIC interrupt bit {d} threshold = {} {*}", .{ id, pri, &self.registers.interrupt_source_priority[id] });
        self.registers.interrupt_source_priority[id] = @intCast(pri);
    }
    pub fn register_interrupt_callback(_self: *anyopaque, id: usize, callback: *const fn (*anyopaque, *root.KernelThreadState) void, ctx: *anyopaque, state: *root.KernelThreadState) dev.InterruptController.Error!void {
        const self: *Self = @ptrCast(@alignCast(_self));
        if (id == 0) {
            return dev.InterruptController.Error.non_existant_interrupt;
        }
        if (id >= self.callbacks.len) {
            return dev.InterruptController.Error.non_existant_interrupt;
        }
        self.callbacks[id] = .{
            .fun = callback,
            .ctx = ctx,
        };
        _ = state;
    }

    pub fn claim_interrupt(self: *Self, state: *root.KernelThreadState) ?usize {
        const next = self.registers.priority_threshold[state.hartid][1][1];
        if (next == 0)
            return null;
        return next;
    }
    pub fn complete_interrupt(self: *Self, id: usize, state: *root.KernelThreadState) void {
        self.registers.priority_threshold[state.hartid][1][1] = @intCast(id);
    }

    fn get_device_type(_: *anyopaque) dev.Device.Error!dev.DeviceType {
        return dev.DeviceType.InterruptController;
    }
    pub fn get_device_name(_: *anyopaque, buffer: []u8) dev.Device.Error![]u8 {
        const device_name = "PLIC";
        if (buffer.len < device_name.len) {
            @memcpy(buffer, device_name[0..buffer.len]);
            return dev.Device.Error.BufferTooSmall;
        } else {
            @memcpy(buffer, device_name);
            return buffer[0..device_name.len];
        }
    }
    pub fn get_device(self: *Self) dev.Device {
        return .{
            .ctx = @ptrCast(self),
            .vtable = &dev.Device.VTable{
                .init = &init,
                .get_device_type = &get_device_type,
                .get_device_name = &get_device_name,
            },
        };
    }
    pub fn get_interrupt_controller(self: *Self) dev.InterruptController {
        return .{
            .ctx = @ptrCast(self),
            .vtable = &dev.InterruptController.VTable{
                .init = &init_interrupt_controller,
                .enable_interrupt_with_id = &enable_interrupt_with_id,
                .enable_priority_with_id = &enable_priority_with_id,
                .enable_threshold = &enable_threshold,
                .register_interrupt_callback = &register_interrupt_callback,
            },
        };
    }
};
