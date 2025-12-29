const std = @import("std");

pub const dev = @import("dev/root.zig");
pub const log = @import("log.zig");
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
pub const vfs = @import("vfs/root.zig");
pub const dtb = @import("dtb");

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
