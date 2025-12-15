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

    root.GPA_ALLOC_INFO = .{};
    const alloc = root.GPA_ALLOC_INFO.allocator();
    root.MEMORY_ALLOCATOR = alloc;
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
    std.log.debug("mtvec = 0x{x:0>8}", .{asm volatile ("csrr %[ret], mtvec"
        : [ret] "=r" (-> usize),
    )});
    try root.interrupts.init(root.phys_mem.page_alloc());
    std.log.debug("mtvec = 0x{x:0>8}", .{asm volatile ("csrr %[ret], mtvec"
        : [ret] "=r" (-> usize),
    )});
    var kernel_as = try root.virt_mem.init(alloc);
    kernel_as.activate();
    std.log.info("Intentando saltar a modo supervisor...", .{});
    root.KERNEL_AS = kernel_as;
    root.privilege.lower_to_s_mode(smode_kernel_entry);
}

fn smode_kernel_entry() noreturn {
    smode_kernel_main() catch |e| {
        std.debug.panic("Panic on smode_kernel_main!!! err: {}", .{e});
    };
    root.qemu.exit(.Success);
}

fn smode_kernel_main() !void {
    const log = std.log.scoped(.SMODE);
    log.info("Desde modo supervisor!!", .{});
    log.debug("Configurando sstatus...", .{});
    const sstatus = root.registers.supervisor.SStatus.read();
    log.debug("sstatus = {any}", .{sstatus});
    sstatus.write();

    log.debug("Iniciando PLIC...", .{});
    var plic = dev.plic.PLIC.new();
    var plic_dev = plic.get_device();
    try plic_dev.init();

    log.err("Alcanzdo final del kernel... terminando", .{});
}
