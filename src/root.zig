const std = @import("std");

pub const dev = @import("dev/root.zig");
pub const log = @import("log.zig");
pub const main = @import("main.zig");
pub const mem = @import("mem/root.zig");
pub const phys_mem = mem.phys_mem;
pub const virt_mem = mem.virt_mem;
pub const spinlock = @import("./sync/spinlock.zig");
pub const interrupts = @import("./arch/interrupts.zig");
pub const qemu = @import("./arch/qemu.zig");
pub const registers = @import("./arch/registers.zig");
pub const process = @import("process/root.zig");
pub const options = @import("sorz_options");
pub const sbi = @import("arch/opensbi.zig");

pub const KERNEL_GPA = std.heap.GeneralPurposeAllocator(.{
    .backing_allocator_zeroes = false,
    .page_size = 4096,
    .thread_safe = false,
});
pub const KernelThreadState = struct {
    address_space: virt_mem.AddressSpace,
    gpa_alloc: KERNEL_GPA,
    alloc: std.mem.Allocator,
    hartid: usize,
    platform_interrupt_controller: dev.InterruptController,
    self_process_list: *process.CoreProcessList,
};

pub export fn _fw_entry(hartid: usize, dtb: *const u8) noreturn {
    main.kernel_main(hartid, dtb) catch {};
    qemu.exit(.Success);
}

extern var _fw_stack_end: u8;

pub export fn _start() linksection(".text.start") callconv(.naked) void {
    @setRuntimeSafety(false);
    asm volatile (
        \\  mv  t0, a0
        \\  mv  t1, a1
    );
    asm volatile (
        \\  mv      a0, a0
        \\  csrw    satp, zero
        \\  addi    sp, sp, -16
        \\  sw      zero, 4(sp)
        \\  sw      zero, 0(sp)
        \\  addi    s0, sp, 16
        \\  mv      a0, t0
        \\  mv      a1, t1
        \\  call    _fw_entry
        :
        : [_SP] "{sp}" (@as(usize, @intFromPtr(&_fw_stack_end))),
          [_RA] "{ra}" (0),
          [_S0] "{s0}" (0),
    );
}

pub const std_options: std.Options = .{
    .logFn = log.log_fn,
    .page_size_max = 4096,
    .page_size_min = 4096,
};

pub const os = struct {
    pub const heap = struct {
        pub const page_allocator = phys_mem.page_alloc();
    };
};

var PANIC_SERIAL_BUFFER: [128]u8 = undefined;

const PANIC = switch (options.trace) {
    true => struct {
        pub var PANIC_ALLOC: [16 * 1024 * 1024]u8 = undefined;
    },
    false => struct {},
};

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    var serial = dev.serial.Serial.default(&PANIC_SERIAL_BUFFER);
    log.init_logging(&serial.interface);

    std.log.err("PANIC!!!!", .{});
    std.log.err("MSG: {s}", .{msg});
    if (options.trace) blk: {
        var panic_alloc = std.heap.FixedBufferAllocator.init(&PANIC.PANIC_ALLOC);
        var debug_info = @import("freestanding").DebugInfo.init(panic_alloc.allocator(), .{}) catch |err| {
            std.log.err("panic: debug info err = {any}\n", .{err});
            qemu.exit(.Failure);
        };
        defer debug_info.deinit();

        debug_info.printStackTrace(log.get_current_writer() orelse break :blk, ret_addr orelse @returnAddress(), @frameAddress()) catch |err| {
            std.log.err("panic: stacktrace err = {any}\n", .{err});
            qemu.exit(.Failure);
        };
    } else {
        var iter = std.debug.StackIterator.init(ret_addr orelse @returnAddress(), @frameAddress());
        std.log.err("No support for debug self info, printing only addresses of stack trace", .{});
        var idx: usize = 0;
        while (iter.next()) |addr| {
            std.log.err("\t{d: >3}: 0x{x:0>8}", .{ idx, addr });
            idx += 1;
        }
    }

    serial.interface.flush() catch {};
    // for now exit qemu
    qemu.exit(.Failure);
}
