const root = @import("root.zig");
const dev = root.dev;
const std = @import("std");

pub var SERIAL_BUFFER: [128]u8 = undefined;

pub fn kernel_main(hartid: usize, dtb: *const u8) !void {
    _ = dtb;

    const clock = dev.clock.Clock.mtime();
    var serial = dev.serial.Serial.default(&SERIAL_BUFFER);

    root.log.init_logging(&serial.interface);
    root.log.set_default_clock(clock);

    std.log.info("Iniciando kernel... (hartid = {})", .{hartid});

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

    var gpa = root.KERNEL_GPA{};
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

    std.log.info("Iniciando interrupciones", .{});
    try root.interrupts.init(root.phys_mem.page_alloc());
    var kernel_as = try root.virt_mem.init(alloc);
    kernel_as.activate();

    const log = std.log.scoped(.SMODE);
    log.info("Desde modo supervisor!!", .{});
    log.debug("Configurando sstatus...", .{});
    const sstatus = root.registers.supervisor.SStatus.read();
    log.debug("sstatus = {any}", .{sstatus});
    sstatus.write();

    const kernel_threat_state: *root.KernelThreatState = try alloc.create(root.KernelThreatState);
    kernel_threat_state.* = .{
        .address_space = kernel_as,
        .alloc = alloc,
        .gpa_alloc = gpa,
        .hartid = hartid,
        .platform_interrupt_controller = undefined,
    };

    log.debug("Iniciando PLIC...", .{});
    plic = dev.plic.PLIC.new();
    var plic_dev = plic.get_device();
    try plic_dev.init(kernel_threat_state);
    kernel_threat_state.platform_interrupt_controller = plic.get_interrupt_controller();
    kernel_threat_state.platform_interrupt_controller.init();

    std.log.debug("Doing real serial initialization after interrupt controller is ready", .{});

    var serial_dev = serial.get_device();
    try serial_dev.init(kernel_threat_state);

    while (true) {
        asm volatile ("wfi");
    }

    log.err("Alcanzdo final del kernel... terminando", .{});
}

var plic: dev.plic.PLIC = undefined;
