const std = @import("std");
const sorz = @import("sorz");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    const output_file = try std.fs.createFileAbsolute(args[1], .{});
    defer output_file.close();
    const input_files = args[2..];
    const block_size = 512;
    // 1 for superblock + N_FILES for headers + FILE_SIZE (rounded to block size)
    var required_size = 1 + input_files.len;
    const handles: []std.fs.File = try alloc.alloc(std.fs.File, input_files.len);
    defer alloc.free(handles);

    for (input_files, 0..) |input, i| {
        // std.debug.print("Trying to open file[{d}]: {s}\n", .{ i, input });
        handles[i] = try switch (std.mem.startsWith(u8, input, "/")) {
            true => std.fs.openFileAbsolute(input, .{}),
            false => std.fs.cwd().openFile(input, .{}),
        };
        const stat = try handles[i].stat();
        const n_blocks = std.mem.alignForward(u64, stat.size, block_size) / block_size;
        required_size += n_blocks;
    }
    var ramdisk = try sorz.dev.Ramdisk.new(alloc, block_size, required_size);
    defer ramdisk.deinit(alloc);
    var fs = try sorz.vfs.RamFS.new(alloc, (ramdisk.get_device().get_block_device() catch @panic("neve should happen")).?, 1);
    defer fs.deinit();
    try fs.format();

    for (input_files, 0..) |input, i| {
        var iter = std.mem.splitBackwardsScalar(u8, input, '/');
        const file_name = iter.next() orelse @panic(try std.fmt.allocPrint(alloc, "Couldn't find the file name of: \"{s}\"", .{input}));
        const path = try std.fmt.allocPrint(alloc, "/{s}", .{file_name});
        defer alloc.free(path);

        const stat = try handles[i].stat();

        const next_block_id = (fs.alloc_file(path, @intCast(stat.size), @intCast(stat.size)) catch @panic("Couldn't reserver file on ramdisk")) orelse @panic("Couldn't found free space on ramdisk");
        const start = (next_block_id + 1) * block_size;
        const end = start + @as(usize, @intCast(stat.size));
        _ = try handles[i].readAll(ramdisk.raw_data[start..end]);
        handles[i].close();
    }
    try output_file.writeAll(ramdisk.raw_data);
}
