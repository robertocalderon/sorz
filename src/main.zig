const root = @import("root.zig");
const dev = root.dev;
const std = @import("std");
const DTB = @import("dtb");

pub var SERIAL_BUFFER: [128]u8 = undefined;
var EARLY_ALLOC_BUFFER: [4 * 1024]u8 = undefined;

extern var __kernel_start: u8;
extern var __kernel_end: u8;

pub fn kernel_main(hartid: usize, _dtb: *const u8) !void {
    var fba = std.heap.FixedBufferAllocator.init(&EARLY_ALLOC_BUFFER);
    const early_alloc = fba.allocator();

    const clock = dev.clock.Clock.mtime();
    var serial = dev.serial.Serial.default(&SERIAL_BUFFER);

    root.log.init_logging(&serial.interface);
    root.log.set_default_clock(clock);

    std.log.info("Iniciando kernel... (hartid = {})", .{hartid});

    std.log.info("Leyendo DTB...", .{});
    const dtb = try DTB.DTB.init(@ptrCast(_dtb));
    const root_dev = dtb.get_root_device();

    var reserved_areas = std.array_list.Managed(root.mem.MemoryArea).init(early_alloc);
    const rsvmem = root_dev.find_device("/reserved-memory");
    var iter = rsvmem.?.get_children();
    while (iter.next()) |i| {
        std.log.debug("=>{s}", .{i.name().?});
        if (i.find_prop("reg")) |prop| {
            const start = prop.get_u64(0) orelse continue;
            const size = prop.get_u64(8) orelse continue;
            std.log.debug("\t=>{s}: {x:0>8} @0x{x:0>8}", .{ prop.name, size, start });
            try reserved_areas.append(.{
                .start = start,
                .end = start + size,
            });
        }
    }
    try reserved_areas.append(.{
        .start = @intFromPtr(&__kernel_start),
        .end = @intFromPtr(&__kernel_end),
    });
    std.log.info("Reserved areas:", .{});
    for (reserved_areas.items) |area| {
        std.log.info("\t0x{x:0>8}->0x{x:0>8}", .{ area.start, area.end });
    }
    var memory_dev = root_dev.find_device("/memory").?;
    std.log.info("mem type: {s}", .{memory_dev.find_prop("device_type").?.data});
    std.log.info("reg: {x}", .{memory_dev.find_prop("reg").?.data});
    const memory_area = root.mem.MemoryArea{
        .start = memory_dev.find_prop("reg").?.get_u64(0).?,
        .end = memory_dev.find_prop("reg").?.get_u64(0).? + memory_dev.find_prop("reg").?.get_u64(8).?,
    };
    std.log.info("Memory range: 0x{x:0>8} -> 0x{x:0>8}", .{ memory_area.start, memory_area.end });
    var valid_memories_ranges = std.array_list.Managed(root.mem.MemoryArea).init(early_alloc);
    try valid_memories_ranges.append(memory_area);
    try root.mem.MemoryArea.remove_areas(&valid_memories_ranges, reserved_areas.items);
    for (valid_memories_ranges.items) |area| {
        std.log.info("Valid area: 0x{x:0>8} -> 0x{x:0>8}", .{ area.start, area.end });
    }
    std.debug.assert(valid_memories_ranges.items.len > 0);

    var bigger_area: root.mem.MemoryArea = .{
        .start = 0,
        .end = 0,
    };
    for (valid_memories_ranges.items) |i| {
        if (bigger_area.len() < i.len()) {
            bigger_area = i;
        }
    }
    std.log.info("Iniciando reservador de memoria fisica", .{});
    root.phys_mem.init_physical_alloc(bigger_area);

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

    const kernel_threat_state: *root.KernelThreadState = try alloc.create(root.KernelThreadState);

    std.log.info("Iniciando interrupciones", .{});
    try root.interrupts.init(root.phys_mem.page_alloc(), kernel_threat_state);
    var kernel_as = try root.virt_mem.init(alloc);
    kernel_as.activate();

    const log = std.log.scoped(.SMODE);
    log.info("Desde modo supervisor!!", .{});
    log.debug("Configurando sstatus...", .{});
    var sstatus = root.registers.supervisor.SStatus.read();
    log.debug("sstatus = {any}", .{sstatus});
    sstatus.write();

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

    log.debug("Doing real serial initialization after interrupt controller is ready", .{});

    var serial_dev = serial.get_device();
    try serial_dev.init(kernel_threat_state);

    log.info("Creando primer proceso", .{});
    var proc = try root.process.Process.new(alloc);
    const init = &@import("init.zig").init;
    proc.ip = @intFromPtr(init);
    proc.address_space.map_all_kernel_identity();
    try proc.address_space.map_page(alloc, @bitCast(@as(u34, @intCast(@intFromPtr(init)))), @bitCast(@intFromPtr(init)), .rwx_user());
    log.debug("init loc = 0x{x:0>8}", .{@intFromPtr(init)});
    proc.address_space.activate();

    // drop to u-mode
    sstatus = root.registers.supervisor.SStatus.read();
    sstatus.SPP = .User;
    sstatus.write();
    asm volatile (
        \\  csrw    sepc, %[val]
        \\  mv      sp, %[nsp]
        \\  sret
        :
        : [val] "r" (proc.ip),
          [nsp] "r" (@intFromPtr(init) + 4096),
    );

    log.err("Alcanzdo final del kernel... terminando", .{});
}

var plic: dev.plic.PLIC = undefined;
