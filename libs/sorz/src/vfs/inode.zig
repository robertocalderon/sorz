const std = @import("std");

const Self = @This();

dev_id: usize,
inode_number: u64,
file_len: u64,
// user_id: u32,
// group_id: u32,
// access: u16,
// mtime: u64,
// atime: u64,
// ctime: u64,
ref_count: u32,

simple_block_ptrs: [12]u64,
// indirect_block_ptrs: ?*[128]u64,
// double_indirect_block_ptrs: ?*[128]?*[128]u64,
// triple_indirect_block_ptrs: ?*[128]?*[128]?*[128]u64,

pub fn newCapacity(alloc: std.mem.Allocator, file_size: usize, n_blocks: usize) !Self {
    _ = alloc;
    const ret: Self = .{
        .dev_id = 0,
        .ctime = 0,
        .file_len = file_size,
        .access = 0,
        .atime = 0,
        .user_id = 0,
        .ref_count = 0,
        .mtime = 0,
        .inode_number = 0,
        .group_id = 0,
        .simple_block_ptrs = [1]usize{0} ** 12,
        // .indirect_block_ptrs = null,
        // .double_indirect_block_ptrs = null,
        // .triple_indirect_block_ptrs = null,
    };
    if (n_blocks <= 12) {
        return ret;
    }
    // ret.indirect_block_ptrs = try alloc.create([128]u64);
    // errdefer {
    //     alloc.destroy(ret.indirect_block_ptrs);
    //     ret.indirect_block_ptrs = null;
    // }
    // if (n_blocks <= (12 + 128)) {
    //     return ret;
    // }
    // const req_double_blocks = @min(n_blocks - 140, 128 * 128);
    // ret.double_indirect_block_ptrs = try alloc.create([128]?*[128]u64);
    // errdefer {
    //     alloc.destroy(ret.double_indirect_block_ptrs);
    //     ret.double_indirect_block_ptrs = null;
    // }
    // for (0..128) |i| {
    //     if (i < req_double_blocks) {
    //         ret.double_indirect_block_ptrs[i] = alloc.create([128]u64) catch |e| {
    //             for (0..i) |j| {
    //                 alloc.destroy(ret.double_indirect_block_ptrs[j]);
    //                 ret.double_indirect_block_ptrs[j] = null;
    //             }
    //             return e;
    //         };
    //     } else {
    //         ret.double_indirect_block_ptrs[i] = null;
    //     }
    // }
    // if (n_blocks < (12 + 128 + (128 * 128))) {
    //     return ret;
    // }
    @panic("Unimplemented triple indirect inode blocks");
}
