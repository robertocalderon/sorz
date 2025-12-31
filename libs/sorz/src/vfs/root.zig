const std = @import("std");

pub const RamFS = @import("ramfs.zig");
const BlockDevice = @import("../dev/block_device.zig");
const INode = @import("inode.zig");
const sorz = @import("../root.zig");

const Self = @This();

alloc: std.mem.Allocator,
next_fs_id: std.atomic.Value(usize),

/// Maps from fs_id to FS structure
available_fs: std.hash_map.AutoHashMap(usize, FS),
root_fs: FS,

lock: sorz.RWLock,

pub fn new(alloc: std.mem.Allocator) !Self {
    return .{
        .alloc = alloc,
        .next_fs_id = .init(1),
        .available_fs = .init(alloc),
        .root_fs = .empty(),
        .lock = .init(),
    };
}
pub fn deinit(self: *Self) void {
    _ = self;
}
pub fn register_fs(self: *Self, fs: FS) !void {
    const lock = self.lock.write();
    defer lock.deinit();

    const look = self.available_fs.get(fs.fs_id);
    if (look) |_| {
        return error{FSIdAlreadyRegistered}.FSIdAlreadyRegistered;
    }
    try self.available_fs.put(fs.fs_id, fs);
}
pub fn set_root_fs(self: *Self, fs: FS) void {
    const lock = self.lock.write();
    defer lock.deinit();

    self.root_fs = fs;
}
pub fn generate_fs_id(self: *Self) usize {
    return self.next_fs_id.fetchAdd(1, .acq_rel);
}

pub fn open_file(self: Self, path: []const u8) FS.Error!INode {
    const lock = self.lock.read();
    defer lock.deinit();

    blk: {
        const inode = self.root_fs.open_file(path) catch |e| {
            switch (e) {
                FS.Error.FileDoesntExists => break :blk,
                else => return e,
            }
        };
        return inode;
    }
    // TODO: when failed to get the file from root_fs try with smaller paths
    // to try to find the containing folder/file and see if it is another fs
    return FS.Error.FileDoesntExists;
}

pub fn read_inode(self: Self, inode: INode, offset: usize, buffer: []u8) ![]u8 {
    const lock = self.lock.read();
    defer lock.deinit();

    const fs: FS = self.available_fs.get(inode.fs_id) orelse return FS.Error.SpecifiedFSDoesntExists;
    return fs.read_file(inode, offset, buffer);
}
pub fn write_inode(self: Self, inode: INode, offset: usize, buffer: []const u8) !usize {
    const fs: FS = self.available_fs.get(inode.fs_id) orelse return FS.Error.SpecifiedFSDoesntExists;
    return fs.write_file(inode, offset, buffer);
}

pub const FS = struct {
    pub const Error = error{
        FileDoesntExists,
        SpecifiedFSDoesntExists,
        ReadingOutsideOfFile,
        WritingOutsideOfFile,
    } || BlockDevice.Error || std.mem.Allocator.Error;
    pub const VTable = struct {
        open_file: *const fn (self: *anyopaque, path: []const u8) Error!INode,
        read_file: *const fn (self: *anyopaque, inode: INode, block_id: usize, buffer: []u8) Error![]u8,
        write_file: *const fn (self: *anyopaque, inode: INode, block_id: usize, buffer: []const u8) Error!usize,
    };
    ctx: *anyopaque,
    vtable: *const VTable,
    fs_id: usize,

    pub fn open_file(self: FS, path: []const u8) Error!INode {
        return self.vtable.open_file(self.ctx, path);
    }
    pub fn read_file(self: FS, inode: INode, offset: usize, buffer: []u8) Error![]u8 {
        return self.vtable.read_file(self.ctx, inode, offset, buffer);
    }
    pub fn write_file(self: FS, inode: INode, offset: usize, buffer: []const u8) Error!usize {
        return self.vtable.write_file(self.ctx, inode, offset, buffer);
    }

    pub fn empty() FS {
        return FS{
            .ctx = @ptrFromInt(1),
            .vtable = &.{
                .open_file = &empty_open_file,
                .read_file = &empty_read_file,
                .write_file = &empty_write_file,
            },
            .fs_id = 0,
        };
    }
    fn empty_open_file(_: *anyopaque, _: []const u8) Error!INode {
        return Error.FileDoesntExists;
    }
    fn empty_read_file(_: *anyopaque, _: INode, _: usize, _: []u8) Error![]u8 {
        return Error.FileDoesntExists;
    }
    fn empty_write_file(_: *anyopaque, _: INode, _: usize, buffer: []const u8) Error!usize {
        return buffer.len;
    }
};

pub const Reader = struct {
    inode: INode,
    vfs: *const Self,
    interface: std.Io.Reader,
    offset: usize,

    fn stream(r: *std.Io.Reader, w: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const self: *Reader = @fieldParentPtr("interface", r);
        var l: usize = 0;
        switch (limit) {
            .nothing => return 0,
            .unlimited => l = @intCast(self.inode.file_len),
            _ => |len| l = len,
        }
        var read_storage: [32]u8 = undefined;
        const read_buffer: []u8 = &read_storage;
        var total_readed = 0;
        while (l > 0) {
            if (self.offset >= self.inode.file_len) {
                return std.Io.Reader.StreamError.EndOfStream;
            }
            const readed = self.vfs.read_inode(self.inode, self.offset, read_buffer) catch |e| {
                if (e == FS.Error.ReadingOutsideOfFile) {
                    return std.Io.Reader.StreamError.EndOfStream;
                }
                return std.Io.Reader.StreamError.ReadFailed;
            };
            w.writeAll(read_buffer) catch {
                return std.Io.Reader.StreamError.WriteFailed;
            };
            self.offset += readed.len;
            l -= readed.len;
            total_readed += readed.len;
        }
        return total_readed;
    }
};
pub const Writer = struct {
    inode: INode,
    vfs: *const Self,
    interface: std.Io.Writer,
    offset: usize,

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *Writer = @fieldParentPtr("interface", w);
        while (w.buffered().len != 0) {
            const written = self.vfs.write_inode(self.inode, self.offset, w.buffered()) catch std.Io.Writer.Error.WriteFailed;
            self.offset += written;
            _ = w.consume(written);
        }
        var written: usize = 0;
        if (data.len > 1) {
            for (data[0 .. data.len - 1]) |buffer| {
                const next_written = self.vfs.write_inode(self.inode, self.offset, buffer) catch std.Io.Writer.Error.WriteFailed;
                self.offset += next_written;
                written += next_written;
                if (next_written != buffer.len) {
                    return written;
                }
            }
        }
        for (0..splat) |_| {
            const next_written = self.vfs.write_inode(self.inode, self.offset, data[data.len - 1]) catch std.Io.Writer.Error.WriteFailed;
            self.offset += next_written;
            written += next_written;
            if (next_written != data[data.len - 1].len) {
                return written;
            }
        }
        return written;
    }
    pub fn flush(w: *std.Io.Writer) std.Io.Writer.Error!void {
        const self: *Writer = @fieldParentPtr("interface", w);
        while (w.buffered().len != 0) {
            const written = self.vfs.write_inode(self.inode, self.offset, w.buffered()) catch std.Io.Writer.Error.WriteFailed;
            self.offset += written;
            _ = w.consume(written);
        }
    }
};

pub fn reader(self: *const Self, inode: INode, buffer: []u8) Reader {
    return .{
        .inode = inode,
        .vfs = self,
        .offset = 0,
        .interface = .{
            .buffer = buffer,
            .end = 0,
            .seek = 0,
            .vtable = &.{
                .stream = &Reader.stream,
            },
        },
    };
}
pub fn writer(self: *const Self, inode: INode, buffer: []u8) Writer {
    return .{
        .inode = inode,
        .vfs = self,
        .offset = 0,
        .interface = .{
            .buffer = buffer,
            .end = 0,
            .vtable = &.{
                .drain = &Writer.drain,
                .flush = &Writer.flush,
            },
        },
    };
}
