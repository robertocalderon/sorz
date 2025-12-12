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

/// Physical memory allocator with multi-page contiguous allocation support
///
/// This allocator manages physical memory pages using a bitmap-based approach.
/// Each bit in the bitmap represents one 4KB page. The allocator supports:
/// - Single page allocation/freeing (backward compatibility)
/// - Multi-page contiguous allocation/freeing
/// - Thread-safe operations using spinlocks
/// - Efficient bitmap scanning for contiguous regions
///
/// Memory layout:
/// - Bitmap stored at beginning of heap
/// - Allocatable pages follow the bitmap
/// - All allocations are page-aligned (4KB boundaries)
var PHYSICAL_MEMORY: root.spinlock.Spinlock(PhysicalMemory) = .init(undefined);

pub fn init_physical_alloc() void {
    const page_start = std.mem.alignForward(usize, @intFromPtr(&HEAP_START), 4096);
    const page_end = std.mem.alignBackward(usize, @intFromPtr(&HEAP_END), 4096);
    const heap_size = page_end - page_start;
    const n_pages = heap_size / 4096;

    std.log.debug("heap range 0x{x:0>8} -> 0x{x:0>8} ({d} pages)", .{ page_start, page_end, n_pages });

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
        @panic("internal error: byte != 0xff but no free bit found");
    }
    return null;
}

/// Find contiguous free bits in the bitmap
fn find_contiguous_bits(bitmap: []u8, n_pages: usize) ?usize {
    if (n_pages == 0) unreachable;
    if (n_pages == 1) return find_free_bit(bitmap);

    const total_bits = bitmap.len * 8;
    if (n_pages > total_bits) return null;

    var current_start: ?usize = null;
    var current_count: usize = 0;

    for (bitmap, 0..) |byte, byte_index| {
        for (0..8) |bit| {
            const bit_index = byte_index * 8 + bit;
            if (bit_index >= total_bits) break;

            const is_free = (byte & (@as(u8, 1) << @intCast(bit))) == 0;

            if (is_free) {
                if (current_start == null) {
                    current_start = bit_index;
                    current_count = 1;
                } else {
                    current_count += 1;
                }

                if (current_count == n_pages) {
                    return current_start.?;
                }
            } else {
                current_start = null;
                current_count = 0;
            }
        }
    }

    return null;
}

/// Find the first free bit in the bitmap
fn find_free_bit(bitmap: []u8) ?usize {
    for (bitmap, 0..) |byte, byte_index| {
        if (byte != 0xFF) {
            // Find the first free bit in this byte
            for (0..8) |bit| {
                if (byte & (@as(u8, 1) << @intCast(bit)) == 0) {
                    return byte_index * 8 + bit;
                }
            }
        }
    }
    return null;
}

pub fn alloc_page() std.mem.Allocator.Error![]u8 {
    return alloc_pages(1);
}

/// Allocate multiple contiguous pages
///
/// Args:
///   n_pages: Number of 4KB pages to allocate (>= 0)
///
/// Returns:
///   Slice of allocated memory with length n_pages * 4096 bytes
///   Error.OutOfMemory if insufficient contiguous memory is available
///
/// Thread Safety: Safe - uses internal spinlock
pub fn alloc_pages(n_pages: usize) std.mem.Allocator.Error![]u8 {
    if (n_pages == 0) {
        var ret: []u8 = undefined;
        ret.ptr = @ptrFromInt(1);
        ret.len = 0;
        return ret;
    }

    const lock = PHYSICAL_MEMORY.lock();
    defer lock.deinit();

    const start_bit = find_contiguous_bits(lock.deref().alloc_bitmap, n_pages) orelse return std.mem.Allocator.Error.OutOfMemory;

    // Mark bits as allocated
    for (0..n_pages) |i| {
        const bit_index = start_bit + i;
        const byte_index = bit_index / 8;
        const bit_offset = bit_index % 8;
        lock.deref().alloc_bitmap[byte_index] |= @as(u8, 1) << @intCast(bit_offset);
    }

    const page_offset = start_bit * 4096;
    const total_size = n_pages * 4096;
    const memory_range = lock.deref().raw_pages[page_offset..(page_offset + total_size)];

    return memory_range;
}
pub fn free_page(page: []u8) void {
    free_pages(page);
}

/// Free multiple contiguous pages
///
/// Args:
///   pages: Slice of memory previously allocated by alloc_pages()
///          Must be page-aligned and length must be multiple of 4096
///
/// Thread Safety: Safe - uses internal spinlock
/// Note: Invalid parameters are logged but do not panic
/// Edge Cases: Memory ending exactly at heap boundary is allowed (high == base_ptr + pages.len)
pub fn free_pages(pages: []u8) void {
    if (pages.len == 0) return;

    const lock = PHYSICAL_MEMORY.lock();
    defer lock.deinit();

    const base_ptr: usize = @intFromPtr(pages.ptr);
    const low: usize = @intFromPtr(lock.deref().raw_pages.ptr);
    const high: usize = low + lock.deref().raw_pages.len;

    if ((base_ptr < low) or (high < base_ptr + pages.len)) {
        std.log.err("free_pages error, trying to dealloc pages {*} with length {} but is outside heap area 0x{x:0>8} -> 0x{x:0>8}", .{ pages.ptr, pages.len, low, high });
        return;
    }

    const offset = base_ptr - low;
    if (offset % 4096 != 0) {
        std.log.err("Trying to dealloc unaligned pages {*}, offset {} not page-aligned", .{ pages.ptr, offset });
        return;
    }

    if (pages.len % 4096 != 0) {
        std.log.err("Trying to dealloc pages with length {} not page-aligned", .{pages.len});
        return;
    }

    const start_page = offset / 4096;
    const n_pages = pages.len / 4096;

    // Free the corresponding bits
    for (0..n_pages) |i| {
        const page_index = start_page + i;
        const byte_offset = page_index / 8;
        const bit_offset = page_index % 8;
        lock.deref().alloc_bitmap[byte_offset] &= ~(@as(u8, 1) << @intCast(bit_offset));
    }
}

pub fn page_alloc() std.mem.Allocator {
    return .{
        .ptr = @ptrFromInt(1),
        .vtable = &.{
            .alloc = alloc,
            .free = free,

            .resize = resize,
            .remap = remap,
        },
    };
}

fn alloc(_: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    _ = alignment;
    _ = ret_addr;
    const n_pages = std.mem.alignForward(usize, len, 4096) / 4096;
    const page = alloc_pages(n_pages) catch return null;
    return page.ptr;
}

fn free(_: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
    _ = alignment;
    _ = ret_addr;
    free_pages(memory);
}

fn resize(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
    return false;
}

fn remap(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
    return null;
}
