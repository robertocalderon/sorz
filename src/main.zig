const sorz = @import("sorz");
const dev = sorz.dev;
const std = @import("std");
const DTB = @import("sorz").dtb;

var EARLY_ALLOC_BUFFER: [4 * 1024]u8 = undefined;

extern var __kernel_start: u8;
extern var __kernel_end: u8;
var INITRD: []u8 = undefined;

pub fn kernel_main(hartid: usize, _dtb: *const u8) !void {
    const root_dev = try early_init(hartid, _dtb);

    var gpa = sorz.KERNEL_GPA{};
    const alloc = gpa.allocator();

    var ramdev: sorz.dev.Ramdisk = sorz.dev.Ramdisk.newWithBuffer(512, INITRD);
    const ramdev_bd = (try ramdev.get_device().get_block_device()).?;
    var fs: sorz.vfs.RamFS = try .new(alloc, ramdev_bd, 1);

    std.log.debug("Allocating test file...", .{});
    std.log.debug("==========================================================", .{});
    std.log.debug("Test looking for file...", .{});
    const find_id = try fs.search_file_block_id("/init");
    std.log.debug("Result file search: {any}", .{find_id});
    var inode = try fs.get_fs().open_file("/init");
    std.log.debug("Results through FS interface:  {any}", .{inode.simple_block_ptrs});
    var vfs = try sorz.vfs.new(alloc);
    fs.fs_id = vfs.generate_fs_id();
    try vfs.register_fs(fs.get_fs());
    vfs.set_root_fs(fs.get_fs());
    inode = try vfs.open_file("/init");
    std.log.debug("Results through VFS interface: {any}", .{inode.simple_block_ptrs});
    var buffer: [32]u8 = undefined;
    _ = try vfs.read_inode(inode, 0, &buffer);
    std.log.debug("Primer bloque: {s}", .{buffer});

    const kernel_threat_state: *sorz.KernelThreadState = try alloc.create(sorz.KernelThreadState);

    std.log.info("Iniciando interrupciones", .{});
    try sorz.interrupts.init(sorz.phys_mem.page_alloc(), kernel_threat_state);
    std.log.info("Iniciando memoria virtual", .{});
    var kernel_as = try sorz.virt_mem.init(alloc);
    kernel_as.activate();

    kernel_threat_state.* = .{
        .address_space = kernel_as,
        .alloc = alloc,
        .gpa_alloc = gpa,
        .hartid = hartid,
        .platform_interrupt_controller = undefined,
        .self_process_list = try alloc.create(sorz.process.CoreProcessList),
    };
    kernel_threat_state.self_process_list.* = .init(alloc);

    const device_registry = try alloc.create(sorz.dev.drivers.DriverRegistry);
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
    // var serial = sorz.dev.serial.Serial.default(&.{});
    // var serial_dev = serial.get_device();
    // try serial_dev.init(kernel_threat_state);
    // sorz.log.init_logging(&serial.interface);

    while (true) {
        asm volatile ("wfi");
    }

    // std.log.info("Creando primer proceso", .{});
    // var proc = try alloc.create(sorz.process.Process);
    // proc.* = try .new(alloc);
    // const init = &@import("init.zig").init;
    // proc.ip = @intFromPtr(init);
    // proc.address_space.map_all_kernel_identity();
    // try proc.address_space.map_page(alloc, @bitCast(@as(u34, @intCast(@intFromPtr(init)))), @bitCast(@intFromPtr(init)), .rwx_user());
    // std.log.debug("init loc = 0x{x:0>8}", .{@intFromPtr(init)});
    // proc.address_space.activate();
    //
    // {
    //     var guard = kernel_threat_state.self_process_list.lock.lock();
    //     defer guard.deinit();
    //     var list = guard.deref();
    //     try list.append(proc);
    // }
    // sorz.interrupts.set_current_process(proc);
    // // drop to u-mode
    // var sstatus = sorz.registers.supervisor.SStatus.read();
    // sstatus.SPP = .User;
    // sstatus.write();
    // asm volatile (
    //     \\  csrw    sepc, %[val]
    //     \\  mv      sp, %[nsp]
    //     \\  sret
    //     :
    //     : [val] "r" (proc.ip),
    //       [nsp] "r" (@intFromPtr(init) + 4096),
    // );
    //
    // std.log.err("Alcanzdo final del kernel... terminando", .{});
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
    sorz.phys_mem.init_physical_alloc(physical_memory_area);
    std.log.info("Obteniendo initrd", .{});
    const chosen = root_dev.find_device("/chosen") orelse @panic("No chosen device!! (no initrd)");
    const initrd_start = (chosen.find_prop("linux,initrd-start") orelse @panic("No linux,initrd-start found!!")).get_u64(0).?;
    const initrd_end = (chosen.find_prop("linux,initrd-end") orelse @panic("No linux,initrd-end found!!")).get_u64(0).?;
    var iter = initrd_start;
    while (iter < std.mem.alignForward(u64, initrd_end, 4096)) {
        sorz.phys_mem.mark_page_as_used(@intCast(iter));
        iter += 4096;
    }
    std.log.info("Found initrd: 0x{x:0>8} -> 0x{x:0>8}", .{ initrd_start, initrd_end });
    INITRD.ptr = @ptrFromInt(@as(usize, @intCast(initrd_start)));
    INITRD.len = @intCast(initrd_end - initrd_start);

    return root_dev;
}

fn init_logging(alloc: std.mem.Allocator) !void {
    const clock = dev.clock.Clock.mtime();
    sorz.log.set_default_clock(clock);

    if (try sorz.sbi.sbi_probe_extension(.DebugConsoleExtension)) {
        // SBI debug writer doesn't reference
        const buffer = try alloc.alloc(u8, 128);
        const sbi_writer: *sorz.sbi.SBIDebugWriter = try alloc.create(sorz.sbi.SBIDebugWriter);
        sbi_writer.* = .init(buffer);

        sorz.log.init_logging(&sbi_writer.interface);
        std.log.info("Using sbi debug interface for writing logs", .{});

        // TODO: register this somehow, right now this will just leak and live forever
    } else {
        // Make sure to disable logging if writting is disabled
        sorz.log.init_logging(null);
    }
}

fn find_physical_memory_region(alloc: std.mem.Allocator, root_dev: *const DTB.FDTDevice) !sorz.mem.MemoryArea {
    var reserved_areas = std.array_list.Managed(sorz.mem.MemoryArea).init(alloc);
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
    const memory_area = sorz.mem.MemoryArea{
        .start = memory_dev.find_prop("reg").?.get_u64(0).?,
        .end = memory_dev.find_prop("reg").?.get_u64(0).? + memory_dev.find_prop("reg").?.get_u64(8).?,
    };
    std.log.info("Memory range: 0x{x:0>8} -> 0x{x:0>8}", .{ memory_area.start, memory_area.end });
    var valid_memories_ranges = std.array_list.Managed(sorz.mem.MemoryArea).init(alloc);
    defer valid_memories_ranges.deinit();

    try valid_memories_ranges.append(memory_area);
    try sorz.mem.MemoryArea.remove_areas(&valid_memories_ranges, reserved_areas.items);
    for (valid_memories_ranges.items) |area| {
        std.log.info("Valid area: 0x{x:0>8} -> 0x{x:0>8}", .{ area.start, area.end });
    }
    std.debug.assert(valid_memories_ranges.items.len > 0);

    var bigger_area: sorz.mem.MemoryArea = .{
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

pub export fn _fw_entry(hartid: usize, dtb: *const u8) noreturn {
    kernel_main(hartid, dtb) catch {};
    sorz.qemu.exit(.Success);
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
    .logFn = sorz.log.log_fn,
    .page_size_max = 4096,
    .page_size_min = 4096,
};

pub const os = struct {
    pub const heap = struct {
        pub const page_allocator = sorz.phys_mem.page_alloc();
    };
};

var PANIC_SERIAL_BUFFER: [128]u8 = undefined;

const PANIC = switch (sorz.options.trace) {
    true => struct {
        pub var PANIC_ALLOC: [16 * 1024 * 1024]u8 = undefined;
    },
    false => struct {},
};

var handling_panic: bool = false;

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    var serial = dev.serial.Serial.default(&PANIC_SERIAL_BUFFER);
    sorz.log.init_logging(&serial.interface);

    std.log.err("PANIC!!!!", .{});
    std.log.err("MSG: {s}", .{msg});
    if (handling_panic) {
        std.log.err("PANIC WHILE HANDLING PANIC!!!!!!", .{});
        std.log.err("Aborting real handling of panic!!!!", .{});
        sorz.qemu.exit(.Failure);
    }
    handling_panic = true;
    if (sorz.options.trace) blk: {
        var panic_alloc = std.heap.FixedBufferAllocator.init(&PANIC.PANIC_ALLOC);
        var debug_info = @import("freestanding").DebugInfo.init(panic_alloc.allocator(), .{}) catch |err| {
            std.log.err("panic: debug info err = {any}\n", .{err});
            sorz.qemu.exit(.Failure);
        };
        defer debug_info.deinit();

        debug_info.printStackTrace(sorz.log.get_current_writer() orelse break :blk, ret_addr orelse @returnAddress(), @frameAddress()) catch |err| {
            std.log.err("panic: stacktrace err = {any}\n", .{err});
            sorz.qemu.exit(.Failure);
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
    sorz.qemu.exit(.Failure);
}
