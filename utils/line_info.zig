const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len != 3) {
        std.debug.print("Invalid inputs!!", .{});
        std.process.exit(1);
    }

    const input_file_path = args[1];
    const _kernel_file = args[2];
    const kernel_file = try alloc.alloc(u8, _kernel_file.len);
    defer alloc.free(kernel_file);
    @memcpy(kernel_file, _kernel_file);

    const input_file = try std.fs.cwd().openFile(input_file_path, .{});
    const len = try input_file.getEndPos();

    const file_buffer = try alloc.alloc(u8, len);
    defer alloc.free(file_buffer);
    _ = try input_file.readAll(file_buffer);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var lines = std.mem.splitAny(u8, file_buffer, "\n\r");
    var n_lines: usize = 0;
    while (lines.next()) |l| {
        if (!std.mem.containsAtLeast(u8, l, 1, " F ")) {
            continue;
        }
        n_lines += 1;
    }

    var ranges = try std.array_list.Managed(FunctionRange).initCapacity(alloc, n_lines);
    defer ranges.deinit();

    lines = std.mem.splitAny(u8, file_buffer, "\n\r");
    while (lines.next()) |l| {
        if (!std.mem.containsAtLeast(u8, l, 1, " F ")) {
            continue;
        }
        //try stdout.print("==>", .{});
        var elements = std.mem.splitAny(u8, l, " \t");

        var tmp: ?[]const u8 = undefined;
        tmp = elements.next();
        const addr = tmp orelse break;
        if (addr.len == 0) {
            continue;
        }
        //try stdout.print("addr: 0x{s}-", .{addr});

        while (elements.next()) |e| {
            tmp = e;
            if (e.len > 1) {
                break;
            }
        }
        if (tmp == null) {
            continue;
        }
        if (!(tmp.?[0] >= '0' and tmp.?[0] <= '9')) {
            tmp = null;
            while (elements.next()) |e| {
                tmp = e;
                if (e.len <= 1) {
                    continue;
                }
                if (!(tmp.?[0] >= '0' and tmp.?[0] <= '9')) {
                    continue;
                }
                break;
            }
        }
        if (tmp == null) {
            continue;
        }
        const line_len = tmp.?;
        //try stdout.print("\n\tlen: {s}", .{line_len});

        while (elements.next()) |e| {
            tmp = e;
            if (e.len > 1) {
                break;
            }
        }
        if (std.mem.startsWith(u8, tmp.?, ".")) {
            while (elements.next()) |e| {
                tmp = e;
                if (e.len > 1) {
                    break;
                }
            }
        }
        const name = tmp.?;
        //try stdout.print("\n\tname: {s}", .{name});

        try ranges.append(.{
            .start = try std.fmt.parseInt(usize, addr, 16),
            .len = try std.fmt.parseInt(usize, line_len, 16),
            .name = name,
        });
        //while (elements.next()) |e| {
        //    try stdout.print("-->{s}<-", .{e});
        //}
        //try stdout.print("\n", .{});
    }

    for (ranges.items, 0..) |_, idx| {
        if (idx % 4 != 0) {
            continue;
        }
        const start = idx;
        const end = @min(idx + 4, ranges.items.len);

        const addr0 = try std.fmt.allocPrint(alloc, "0x{x}", .{if (start + 0 < end) ranges.items[start + 0].start else 0});
        const addr1 = try std.fmt.allocPrint(alloc, "0x{x}", .{if (start + 1 < end) ranges.items[start + 1].start else 0});
        const addr2 = try std.fmt.allocPrint(alloc, "0x{x}", .{if (start + 2 < end) ranges.items[start + 2].start else 0});
        const addr3 = try std.fmt.allocPrint(alloc, "0x{x}", .{if (start + 3 < end) ranges.items[start + 3].start else 0});

        defer alloc.free(addr0);
        defer alloc.free(addr1);
        defer alloc.free(addr2);
        defer alloc.free(addr3);

        const out = try std.process.Child.run(.{
            .allocator = alloc,
            .argv = &.{
                "addr2line",
                "-e",
                kernel_file,
                "-f",
                addr0,
                addr1,
                addr2,
                addr3,
            },
            .cwd_dir = std.fs.cwd(),
        });
        defer alloc.free(out.stderr);
        defer alloc.free(out.stdout);

        if (out.term != .Exited) {
            try stdout.print("=>[{d}/{d}]\n", .{ idx, ranges.items.len });
            try stdout.flush();
            continue;
        }

        var line_info: [8][]const u8 = undefined;
        var iter = std.mem.splitAny(u8, out.stdout, "\n\r");
        for (0..line_info.len) |i| {
            line_info[i] = iter.next().?;
        }
        ranges.items[start + 0].file_loc = line_info[1];
        if (start + 1 < end) {
            ranges.items[start + 1].file_loc = line_info[3];
        }
        if (start + 2 < end) {
            ranges.items[start + 2].file_loc = line_info[5];
        }
        if (start + 3 < end) {
            ranges.items[start + 3].file_loc = line_info[7];
        }
    }
    try stdout.flush();
}

const FunctionRange = struct {
    start: usize,
    len: usize,
    name: []const u8,
    file_loc: ?[]const u8 = null,
};
