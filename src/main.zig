const root = @import("root.zig");
const dev = root.dev;
const std = @import("std");

pub var SERIAL_BUFFER: [128]u8 = undefined;

pub fn kernel_main() !void {
    var clock = dev.clock.Clock.mtime();
    var serial = dev.serial.Serial.default(&SERIAL_BUFFER);

    root.log.init_logging(&serial.interface);
    root.log.set_default_clock(clock);

    std.log.info("Iniciando kernel...", .{});
    std.log.info("MTIME = {d}", .{(try clock.now()).raw});

    std.log.info("Iniciando reservador de memoria fisica", .{});
    root.phys_mem.init_physical_alloc();

    {
        const page = try root.phys_mem.alloc_page();
        std.log.debug("Alloc test 1: {*}", .{page});
        root.phys_mem.free_page(page);
    }
    {
        const page = try root.phys_mem.alloc_page();
        std.log.debug("Alloc test 2: {*}", .{page});
        root.phys_mem.free_page(page);
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{
        .backing_allocator_zeroes = false,
        .page_size = 4096,
        .thread_safe = false,
    }){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    {
        const a0 = try alloc.create(u8);
        std.log.debug("gpa test 0: {*}", .{a0});
        const a1 = try alloc.create(u8);
        std.log.debug("gpa test 1: {*}", .{a1});
        alloc.destroy(a0);
        const a2 = try alloc.create(u8);
        std.log.debug("gpa test 2: {*}", .{a2});
        alloc.destroy(a1);
        alloc.destroy(a2);
    }

    std.log.info("Iniciando PMPs", .{});
    root.pmp.init_pmp();

    std.log.info("Iniciando interrupciones", .{});
    try root.interrupts.init(root.phys_mem.page_alloc());
    asm volatile ("ecall");
}
