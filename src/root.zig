const std = @import("std");

pub const dev = @import("dev/root.zig");
pub const log = @import("log.zig");
pub const main = @import("main.zig");
pub const phys_mem = @import("mem/phys_mem.zig");
pub const virt_mem = @import("mem/virt_mem.zig");
pub const spinlock = @import("./sync/spinlock.zig");
pub const interrupts = @import("./arch/interrupts.zig");
pub const qemu = @import("./arch/qemu.zig");
pub const registers = @import("./arch/registers.zig");

pub var KERNEL_AS: virt_mem.AddressSpace = undefined;
pub var MEMORY_ALLOCATOR: std.mem.Allocator = undefined;
pub var GPA_ALLOC_INFO: std.heap.GeneralPurposeAllocator(.{
    .backing_allocator_zeroes = false,
    .page_size = 4096,
    .thread_safe = false,
}) = undefined;

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
pub var PANIC_ALLOC: [16 * 1024 * 1024]u8 = undefined;

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    var serial = dev.serial.Serial.default(&PANIC_SERIAL_BUFFER);
    log.init_logging(&serial.interface);
    var panic_alloc = std.heap.FixedBufferAllocator.init(&PANIC_ALLOC);

    std.log.err("PANIC!!!!", .{});
    std.log.err("MSG: {s}", .{msg});
    var debug_info = @import("freestanding").DebugInfo.init(panic_alloc.allocator(), .{}) catch |err| {
        std.log.err("panic: debug info err = {any}\n", .{err});
        qemu.exit(.Failure);
    };
    defer debug_info.deinit();

    debug_info.printStackTrace(log.get_current_writer(), ret_addr orelse @returnAddress(), @frameAddress()) catch |err| {
        std.log.err("panic: stacktrace err = {any}\n", .{err});
        qemu.exit(.Failure);
    };

    serial.interface.flush() catch {};
    // for now exit qemu
    qemu.exit(.Failure);
}
