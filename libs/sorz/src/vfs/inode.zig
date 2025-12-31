const std = @import("std");
const fs = @import("root.zig");
const File = @import("file.zig");

const Self = @This();

pub const INodeType = enum {
    RegularFile,
};

fs_id: usize,
inode_number: u64,
file_len: u64,
n_blocks: usize,
// user_id: u32,
// group_id: u32,
// access: u16,
// mtime: u64,
// atime: u64,
// ctime: u64,
ref_count: u32,

ftype: INodeType,

simple_block_ptrs: [12]u64,
indirect_block_ptrs: ?*[128]u64,
double_indirect_block_ptrs: ?*[128]?*[128]u64,
// triple_indirect_block_ptrs: ?*[128]?*[128]?*[128]u64,

pub fn newCapacity(ftype: INodeType, alloc: std.mem.Allocator, file_size: usize, n_blocks: usize) !Self {
    var ret: Self = .{
        .fs_id = 0,
        // .ctime = 0,
        .file_len = file_size,
        .n_blocks = n_blocks,
        // .access = 0,
        // .atime = 0,
        // .user_id = 0,
        .ref_count = 0,
        .ftype = ftype,
        // .mtime = 0,
        .inode_number = 0,
        // .group_id = 0,
        .simple_block_ptrs = [1]u64{0} ** 12,
        .indirect_block_ptrs = null,
        .double_indirect_block_ptrs = null,
        // .triple_indirect_block_ptrs = null,
    };
    if (n_blocks <= 12) {
        return ret;
    }

    ret.indirect_block_ptrs = try alloc.create([128]u64);
    errdefer alloc.destroy(ret.indirect_block_ptrs.?);
    for (0..128) |i| {
        ret.indirect_block_ptrs.?[i] = 0;
    }
    if (n_blocks <= 12 + 128) {
        return ret;
    }
    const max_nodes_only_indirect = 12 + 128;
    const remaining_nodes = n_blocks - max_nodes_only_indirect;
    const required_double_indirect_blocks = @min(128, (remaining_nodes + 127) / 128);

    ret.double_indirect_block_ptrs = try alloc.create([128]?*[128]u64);
    errdefer alloc.destroy(ret.double_indirect_block_ptrs.?);

    for (0..required_double_indirect_blocks) |i| {
        ret.double_indirect_block_ptrs.?[i] = alloc.create([128]u64) catch |e| {
            for (0..i) |j| {
                alloc.destroy(ret.double_indirect_block_ptrs.?[j].?);
            }
            return e;
        };
    }
    if (n_blocks <= 12 + 128 + (128 * 128)) {
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

pub fn set_block_at_offset(self: *Self, offset: usize, block_id: u64) !void {
    var current_offset = offset;
    if (current_offset >= self.n_blocks) {
        return fs.FS.Error.BufferTooSmall;
    }
    if (current_offset < 12) {
        self.simple_block_ptrs[current_offset] = block_id;
        return;
    }
    current_offset -= 12;
    if (current_offset < 128) {
        self.indirect_block_ptrs.?[current_offset] = block_id;
        return;
    }
    current_offset -= 128;
    if (current_offset < 128 * 128) {
        const idx = current_offset / 128;
        self.double_indirect_block_ptrs.?[idx].?[current_offset % 128] = block_id;
        return;
    }
    return fs.FS.Error.BufferTooSmall;
}

pub fn get_block_at_offset(self: Self, offset: usize) !u64 {
    var current_offset = offset;
    if (current_offset >= self.n_blocks) {
        return fs.FS.Error.ReadingOutsideOfFile;
    }
    if (current_offset < 12) {
        return self.simple_block_ptrs[current_offset];
    }
    current_offset -= 12;
    if (current_offset < 128) {
        return self.indirect_block_ptrs.?[current_offset];
    }
    current_offset -= 128;
    if (current_offset < 128 * 128) {
        const idx = current_offset / 128;
        return self.double_indirect_block_ptrs.?[idx].?[current_offset % 128];
    }
    return fs.FS.Error.BufferTooSmall;
}
