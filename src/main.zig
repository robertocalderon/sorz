const root = @import("root.zig");
const dev = root.dev;
const std = @import("std");
const DTB = @import("dtb");

var EARLY_ALLOC_BUFFER: [4 * 1024]u8 = undefined;

extern var __kernel_start: u8;
extern var __kernel_end: u8;

pub fn kernel_main(hartid: usize, _dtb: *const u8) !void {
    const root_dev = try early_init(hartid, _dtb);

    var gpa = root.KERNEL_GPA{};
    const alloc = gpa.allocator();

    const kernel_threat_state: *root.KernelThreadState = try alloc.create(root.KernelThreadState);

    std.log.info("Iniciando interrupciones", .{});
    try root.interrupts.init(root.phys_mem.page_alloc(), kernel_threat_state);
    std.log.info("Iniciando memoria virtual", .{});
    var kernel_as = try root.virt_mem.init(alloc);
    kernel_as.activate();

    kernel_threat_state.* = .{
        .address_space = kernel_as,
        .alloc = alloc,
        .gpa_alloc = gpa,
        .hartid = hartid,
        .platform_interrupt_controller = undefined,
        .self_process_list = try alloc.create(root.process.CoreProcessList),
    };
    kernel_threat_state.self_process_list.* = .init(alloc);

    const device_registry = try alloc.create(root.dev.drivers.DriverRegistry);
    device_registry.* = .init(alloc);
    _ = try device_registry.device_init(&root_dev, alloc, &.{});
    try device_registry.init_nodes(kernel_threat_state);

    // std.log.debug("Iniciando PLIC...", .{});
    // plic = dev.plic.PLIC.new();
    // var plic_dev = plic.get_device();
    // try plic_dev.init(kernel_threat_state);
    // kernel_threat_state.platform_interrupt_controller = plic.get_interrupt_controller();
    // kernel_threat_state.platform_interrupt_controller.init();
    //
    // std.log.debug("Doing real serial initialization after interrupt controller is ready", .{});
    //
    // var serial = root.dev.serial.Serial.default(&.{});
    // var serial_dev = serial.get_device();
    // try serial_dev.init(kernel_threat_state);
    // root.log.init_logging(&serial.interface);

    std.log.info("Creando primer proceso", .{});
    var proc = try alloc.create(root.process.Process);
    proc.* = try .new(alloc);
    const init = &@import("init.zig").init;
    proc.ip = @intFromPtr(init);
    proc.address_space.map_all_kernel_identity();
    try proc.address_space.map_page(alloc, @bitCast(@as(u34, @intCast(@intFromPtr(init)))), @bitCast(@intFromPtr(init)), .rwx_user());
    std.log.debug("init loc = 0x{x:0>8}", .{@intFromPtr(init)});
    proc.address_space.activate();

    {
        var guard = kernel_threat_state.self_process_list.lock.lock();
        defer guard.deinit();
        var list = guard.deref();
        try list.append(proc);
    }
    root.interrupts.set_current_process(proc);
    // drop to u-mode
    var sstatus = root.registers.supervisor.SStatus.read();
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

    std.log.err("Alcanzdo final del kernel... terminando", .{});
}

fn early_init(hartid: usize, _dtb: *const u8) !DTB.FDTDevice {
    var fba = std.heap.FixedBufferAllocator.init(&EARLY_ALLOC_BUFFER);
    const alloc = fba.allocator();
    try init_logging(alloc);

    std.log.info("Iniciando kernel... (hartid = {})", .{hartid});
    std.log.info("Leyendo DTB...", .{});
    const dtb = try DTB.DTB.init(@ptrCast(_dtb));
    const root_dev = dtb.get_root_device();
    // root_dev.print_device_tree_recursive(0, .debug);

    const physical_memory_area = try find_physical_memory_region(alloc, &root_dev);
    std.log.info("Iniciando reservador de memoria fisica", .{});
    root.phys_mem.init_physical_alloc(physical_memory_area);

    return root_dev;
}

fn init_logging(alloc: std.mem.Allocator) !void {
    const clock = dev.clock.Clock.mtime();
    root.log.set_default_clock(clock);

    if (try root.sbi.sbi_probe_extension(.DebugConsoleExtension)) {
        // SBI debug writer doesn't reference
        const buffer = try alloc.alloc(u8, 128);
        const sbi_writer: *root.sbi.SBIDebugWriter = try alloc.create(root.sbi.SBIDebugWriter);
        sbi_writer.* = .init(buffer);

        root.log.init_logging(&sbi_writer.interface);
        std.log.info("Using sbi debug interface for writing logs", .{});

        // TODO: register this somehow, right now this will just leak and live forever
    } else {
        // Make sure to disable logging if writting is disabled
        root.log.init_logging(null);
    }
}

fn find_physical_memory_region(alloc: std.mem.Allocator, root_dev: *const DTB.FDTDevice) !root.mem.MemoryArea {
    var reserved_areas = std.array_list.Managed(root.mem.MemoryArea).init(alloc);
    defer reserved_areas.deinit();

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
    var valid_memories_ranges = std.array_list.Managed(root.mem.MemoryArea).init(alloc);
    defer valid_memories_ranges.deinit();

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
    return bigger_area;
}

var plic: dev.plic.PLIC = undefined;
