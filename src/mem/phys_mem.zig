const std = @import("std");
const root = @import("root");

extern const HEAP_START: u8;
extern const HEAP_END: u8;
extern const HEAP_SIZE: u8;

const PhysicalMemory = struct {
    heap_start: usize,
    heap_end: usize,
    alloc_bitmap: []u8,
    raw_pages: []u8,
};

var PHYSICAL_MEMORY: root.spinlock.Spinlock(PhysicalMemory) = .init(undefined);

pub fn init_physical_alloc() void {
    const page_start = std.mem.alignForward(usize, @intFromPtr(&HEAP_START), 4096);
    const page_end = std.mem.alignBackward(usize, @intFromPtr(&HEAP_END), 4096);
    const heap_size = page_end - page_start;
    const n_pages = heap_size / 4096;

    std.log.debug("heap range 0x{x:0>8} -> 0x{x:0>8} ({d} paginas)", .{ page_start, page_end, n_pages });

    var pm = PhysicalMemory{
        .heap_start = page_start,
        .heap_end = page_end,
        .alloc_bitmap = &.{},
        .raw_pages = &.{},
    };
    if (n_pages < 2) {
        const lock = PHYSICAL_MEMORY.lock();
        lock.deref().* = pm;
        lock.deinit();
        return;
    }
    const required_bits = n_pages;
    const required_bytes = (required_bits + 7) / 8;
    const required_pages = (required_bytes + 4096 - 1) / 4096;

    std.log.debug("required pages for bitmap: {d} (max {d} pages per bitmap page)", .{ required_pages, 4096 * 8 });

    const bitmap_start = page_start;
    const bitmap_len = required_bytes;

    const free_pages_start = bitmap_start + (4096 * required_pages);
    const free_pages_end = page_end;

    const range_size_kib = (free_pages_end - free_pages_start) / 1024;
    const range_size_mib = range_size_kib / 1024;
    std.log.debug("Allocatable memory range 0x{x:0>8} -> 0x{x:0>8} ({d} KiB/{d} MiB)", .{ free_pages_start, free_pages_end, range_size_kib, range_size_mib });

    pm.alloc_bitmap.ptr = @ptrFromInt(bitmap_start);
    pm.alloc_bitmap.len = bitmap_len;

    pm.raw_pages.ptr = @ptrFromInt(free_pages_start);
    pm.raw_pages.len = free_pages_end - free_pages_start;

    std.log.debug("bitmap range: 0x{x:0>8} -> 0x{x:0>8}", .{ bitmap_start, bitmap_start + bitmap_len });

    const lock = PHYSICAL_MEMORY.lock();
    lock.deref().* = pm;
    lock.deinit();
}

fn allocate_single_bit() ?usize {
    // TODO: lock before doing this
    const lock = PHYSICAL_MEMORY.lock();
    defer lock.deinit();

    for (lock.deref().alloc_bitmap, 0..) |byte, idx| {
        if (byte == 0xff) {
            continue;
        }
        for (0..8) |bit| {
            if ((byte & (@as(u8, 1) << @intCast(bit))) == 0) {
                lock.deref().alloc_bitmap[idx] |= @as(u8, 1) << @intCast(bit);
                return (idx * 8) + bit;
            }
        }
        @panic("khe???, byte != 0xff pero no se encontro bit disponible");
    }
    return null;
}

pub fn alloc_page() std.mem.Allocator.Error![]u8 {
    const page_to_alloc = allocate_single_bit() orelse return std.mem.Allocator.Error.OutOfMemory;
    const page_offset = page_to_alloc * 4096;

    const lock = PHYSICAL_MEMORY.lock();
    defer lock.deinit();

    const memory_range = lock.deref().raw_pages[page_offset..(page_offset + 4096)];
    return memory_range;
}
pub fn free_page(page: []u8) void {
    const lock = PHYSICAL_MEMORY.lock();
    defer lock.deinit();

    const base_ptr: usize = @intFromPtr(page.ptr);
    const low: usize = @intFromPtr(lock.deref().raw_pages.ptr);
    const high: usize = low + lock.deref().raw_pages.len;

    if ((base_ptr < low) or (high <= base_ptr)) {
        std.log.err("free_page error, trying to dealloc page {*} but is outside heap area 0x{x:0>8} -> 0x{x:0>8}", .{ page.ptr, low, high });
        return;
    }

    const offset = base_ptr - low;
    const page_offset = offset / 4096;
    if (offset % 4096 != 0) {
        std.log.err("Trying to dealloc unaligned page {*}, aligning to {*} and using that", .{ page.ptr, @as([*]u8, @ptrFromInt(page_offset * 4096)) });
    }
    const byte_offset = page_offset / 8;
    const bit_offset = page_offset % 8;

    lock.deref().alloc_bitmap[byte_offset] &= ~(@as(u8, 1) << @intCast(bit_offset));
}
