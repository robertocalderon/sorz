const std = @import("std");

pub const DTB = struct {
    buffer: []const u8,
    header: *const FDTHeader,

    structure_block: []const u8,
    strings_block: []const u8,

    pub const Error = error{
        InvalidDTBMagic,
        DTBTooBig,
        InvalidVersion,
        StructSectionOutsideValidRange,
        StringSectionOutsideValidRange,
    };

    pub fn init(dtb: [*]const u8) Error!DTB {
        const header: *const FDTHeader = @ptrCast(@alignCast(dtb));
        try header.validate();
        const buffer: []const u8 = blk: {
            var tmp_buffer: []const u8 = undefined;
            tmp_buffer.len = std.mem.bigToNative(u32, header.total_size);
            tmp_buffer.ptr = dtb;
            break :blk tmp_buffer;
        };
        const structure: []const u8 = blk: {
            var tmp_buffer: []const u8 = undefined;
            tmp_buffer.len = std.mem.bigToNative(u32, header.size_dt_struct);
            tmp_buffer.ptr = @ptrCast(&buffer[std.mem.bigToNative(u32, header.off_dt_struct)]);
            break :blk tmp_buffer;
        };
        const strings: []const u8 = blk: {
            var tmp_buffer: []const u8 = undefined;
            tmp_buffer.len = std.mem.bigToNative(u32, header.size_dt_strings);
            tmp_buffer.ptr = @ptrCast(&buffer[std.mem.bigToNative(u32, header.off_dt_strings)]);
            break :blk tmp_buffer;
        };

        const s = @intFromPtr(buffer.ptr);
        const l = buffer.len;
        const buffer_end: usize = s + l;
        if (@intFromPtr(structure.ptr) >= buffer_end or (@intFromPtr(structure.ptr) + structure.len) >= buffer_end) {
            return Error.StructSectionOutsideValidRange;
        }
        if (@intFromPtr(strings.ptr) >= buffer_end or (@intFromPtr(strings.ptr) + strings.len) >= buffer_end) {
            return Error.StringSectionOutsideValidRange;
        }
        return .{
            .buffer = buffer,
            .header = header,
            .structure_block = structure,
            .strings_block = strings,
        };
    }
    pub fn get_struct_iter(self: DTB) StructTagsIter {
        return .{
            .buffer = self.structure_block,
            .strings = self.strings_block,
            .i = 0,
        };
    }
    pub fn get_root_device(self: DTB) FDTDevice {
        const iter = self.get_struct_iter().find_begin_node().?;
        const root_range = iter.get_self_device_range();
        return .{
            .inner = root_range.?,
            .strings = self.strings_block,
        };
    }
};

pub const FDTDevice = struct {
    inner: []const u8,
    strings: []const u8,

    pub const ChildIter = struct {
        level: usize,
        iter: StructTagsIter,

        pub fn next(self: *ChildIter) ?FDTDevice {
            var past_iter = self.iter;
            while (self.iter.next()) |node| {
                switch (node) {
                    .Begin => {
                        self.level += 1;
                        // Empty = level 0
                        // Root = level 1
                        // child = level 2
                        if (self.level == 2) {
                            const child_inner = past_iter.get_self_device_range();
                            return FDTDevice{
                                .inner = child_inner.?,
                                .strings = self.iter.strings,
                            };
                        }
                    },
                    .End => {
                        if (self.level <= 1) {
                            break;
                        }
                        self.level -= 1;
                    },
                    else => {},
                }
                past_iter = self.iter;
            }
            return null;
        }
    };
    pub const PropIter = struct {
        level: usize,
        iter: StructTagsIter,

        pub fn next(self: *PropIter) ?Prop {
            var past_iter = self.iter;
            while (self.iter.next()) |node| {
                switch (node) {
                    .Begin => {
                        self.level += 1;
                    },
                    .Prop => |data| {
                        // Empty = level 0
                        // Root = level 1
                        if (self.level == 1) {
                            return data;
                        }
                    },
                    .End => {
                        if (self.level <= 1) {
                            break;
                        }
                        self.level -= 1;
                    },
                    else => {},
                }
                past_iter = self.iter;
            }
            return null;
        }
    };

    pub fn name(self: FDTDevice) ?[]const u8 {
        var iter = StructTagsIter{
            .buffer = self.inner,
            .strings = self.strings,
            .i = 0,
        };
        switch (iter.next() orelse return null) {
            .Begin => |node_name| {
                if (node_name.len == 0) {
                    return "/";
                }
                return node_name;
            },
            else => unreachable,
        }
    }
    pub fn get_children(self: FDTDevice) ChildIter {
        return .{
            .level = 0,
            .iter = StructTagsIter{
                .buffer = self.inner,
                .strings = self.strings,
                .i = 0,
            },
        };
    }
    pub fn get_props(self: FDTDevice) PropIter {
        return .{
            .level = 0,
            .iter = StructTagsIter{
                .buffer = self.inner,
                .strings = self.strings,
                .i = 0,
            },
        };
    }
    pub fn find_child(self: FDTDevice, child_name: []const u8) ?FDTDevice {
        var iter = self.get_children();
        while (iter.next()) |c| {
            const cname = c.name() orelse continue;
            if (std.mem.eql(u8, cname, child_name)) {
                return c;
            }
            if (!std.mem.startsWith(u8, cname, child_name)) {
                continue;
            }
            // At least one character more
            if (cname.len <= (child_name.len + 1)) {
                continue;
            }
            // if that character is '@' then address come after it
            if (cname[child_name.len] == '@') {
                return c;
            }
        }
        return null;
    }
    pub fn find_device(self: FDTDevice, device_path: []const u8) ?FDTDevice {
        // Check if path starts with root node, abort if current node is not root
        var real_path = device_path;
        if (std.mem.startsWith(u8, device_path, "/")) {
            const n = self.name() orelse return null;
            if (!std.mem.eql(u8, n, "/")) {
                return null;
            }
            real_path = device_path[1..];
        }
        var path = std.mem.splitAny(u8, real_path, "/");
        var current_device = self;
        while (path.next()) |d| {
            const next_node = current_device.find_child(d) orelse return null;
            current_device = next_node;
        }
        return current_device;
    }
    pub fn find_prop(self: FDTDevice, prop_name: []const u8) ?Prop {
        var iter = self.get_props();
        while (iter.next()) |p| {
            if (std.mem.eql(u8, p.name, prop_name)) {
                return p;
            }
        }
        return null;
    }
    pub fn name_addr(self: FDTDevice) ?usize {
        const dname = self.name() orelse return null;
        var iter = std.mem.splitAny(u8, dname, "@");
        _ = iter.next() orelse return null;
        const addr = iter.next() orelse return null;
        return std.fmt.parseInt(usize, addr, 16) catch return null;
    }
    pub fn print_device_tree_recursive(self: FDTDevice, offset: usize, comptime level: std.log.Level) void {
        const prints = "\t\t\t\t\t\t\t\t\t\t";
        if (prints.len < offset) {
            return;
        }
        log_with_level(level, .DTB, "{s}{s}", .{ prints[0..offset], self.name() orelse "???" });
        var prop_iter = self.get_props();
        while (prop_iter.next()) |p| {
            if (std.mem.eql(u8, p.name, "compatible") or std.mem.eql(u8, p.name, "device_type")) {
                log_with_level(level, .DTB, "{s} =>{s}: {s}", .{ prints[0..offset], p.name, p.data });
                continue;
            }
            log_with_level(level, .DTB, "{s} =>{s}: {x}", .{ prints[0..offset], p.name, p.data });
        }
        var iter = self.get_children();
        while (iter.next()) |c| {
            c.print_device_tree_recursive(offset + 1, level);
        }
    }
};
fn log_with_level(comptime level: std.log.Level, comptime scope: @Type(.enum_literal), comptime fmt: []const u8, args: anytype) void {
    const log = std.log.scoped(scope);
    switch (level) {
        .err => log.err(fmt, args),
        .warn => log.warn(fmt, args),
        .info => log.info(fmt, args),
        .debug => log.debug(fmt, args),
    }
}

pub const FDTHeader = extern struct {
    magic: u32,
    total_size: u32,
    off_dt_struct: u32,
    off_dt_strings: u32,
    off_mem_rsvmap: u32,
    version: u32,
    last_comp_version: u32,
    boot_cpuid_phys: u32,
    size_dt_strings: u32,
    size_dt_struct: u32,

    pub fn validate(self: FDTHeader) DTB.Error!void {
        if (std.mem.bigToNative(u32, self.magic) != 0xd00dfeed) {
            return DTB.Error.InvalidDTBMagic;
        }
        if (std.mem.bigToNative(u32, self.total_size) >= 1024 * 1024) {
            return DTB.Error.DTBTooBig;
        }
        if (std.mem.bigToNative(u32, self.version) != 17) {
            return DTB.Error.InvalidVersion;
        }
        const last_comp_version = std.mem.bigToNative(u32, self.last_comp_version);
        if (last_comp_version < 16 or last_comp_version > 17) {
            return DTB.Error.InvalidVersion;
        }
    }
};

pub const StructTagsIter = struct {
    buffer: []const u8,
    strings: []const u8,
    i: usize,

    pub fn next_u32(self: *StructTagsIter) ?u32 {
        const id = self.i + 4;
        if (id >= self.buffer.len) {
            return null;
        }
        const ptr: [*]const u32 = @ptrCast(@alignCast(&self.buffer[self.i]));
        self.i += 4;
        return std.mem.bigToNative(u32, ptr[0]);
    }
    pub fn next_tag_type(self: *StructTagsIter) ?FDTNodeType {
        return @enumFromInt(self.next_u32() orelse return null);
    }
    pub fn next(self: *StructTagsIter) ?FDTStructNode {
        const ntype = self.next_tag_type() orelse return null;
        switch (ntype) {
            .Begin => {
                const name = self.next_string();
                return FDTStructNode{
                    .Begin = name,
                };
            },
            .End => return .{ .End = {} },
            .Nop => return .{ .Nop = {} },
            .TreeEnd => return .{ .TreeEnd = {} },
            .Prop => {
                const len = self.next_u32().?;
                const nameoff = self.next_u32().?;
                const name = get_string_at_offset(self.strings, nameoff);
                const buffer = self.buffer[self.i..(self.i + len)];
                self.i = std.mem.alignForward(u32, self.i + len, 4);
                return .{
                    .Prop = .{
                        .data = buffer,
                        .name = name,
                    },
                };
            },
            _ => {
                std.log.err("Invalid tag: {x}", .{@intFromEnum(ntype)});
                unreachable;
            },
        }
    }
    pub fn next_string(self: *StructTagsIter) []const u8 {
        const tmp = get_string_at_offset(self.buffer, self.i);
        self.i = std.mem.alignForward(usize, self.i + tmp.len + 1, 4);
        return tmp;
    }
    fn find_begin_node(iter: StructTagsIter) ?StructTagsIter {
        var past = iter;
        var tmp = iter;
        var v = tmp.next() orelse return null;
        while (true) {
            switch (v) {
                .Begin => {
                    return past;
                },
                else => {},
            }
            past = tmp;
            v = tmp.next() orelse return null;
        }
        return null;
    }
    fn get_self_device_range(self: StructTagsIter) ?[]const u8 {
        var s = self;
        const start_offset = s.i;
        var current_offset: usize = 0;
        while (s.next()) |nn| {
            switch (nn) {
                .Begin => {
                    current_offset += 1;
                },
                .End => {
                    if (current_offset <= 1) {
                        break;
                    }
                    current_offset -= 1;
                },
                else => {},
            }
        }
        const end_offset = s.i;
        return s.buffer[start_offset..end_offset];
    }
};
pub fn get_string_at_offset(buffer: []const u8, offset: usize) []const u8 {
    var current_offset = offset;
    const start_offset = current_offset;

    while (true) {
        if (current_offset >= buffer.len) {
            break;
        }
        if (buffer[current_offset] == 0) {
            break;
        }
        current_offset += 1;
    }
    return buffer[start_offset..current_offset];
}

pub const Prop = struct {
    data: []const u8,
    name: []const u8,

    pub fn get_u32(self: Prop, idx: usize) ?u32 {
        const end = idx + 4;
        if (end > self.data.len) {
            return null;
        }
        const data = &.{
            self.data[idx + 0],
            self.data[idx + 1],
            self.data[idx + 2],
            self.data[idx + 3],
        };
        const ret: u32 = (@as(u32, @intCast(data[0])) << 24);
        ret |= (@as(u32, @intCast(data[1])) << 16);
        ret |= (@as(u32, @intCast(data[2])) << 8);
        ret |= (@as(u32, @intCast(data[3])) << 0);
        return ret;
    }
    pub fn get_u64(self: Prop, idx: usize) ?u64 {
        const end = idx + 8;
        if (end > self.data.len) {
            return null;
        }
        const data = &.{
            self.data[idx + 0],
            self.data[idx + 1],
            self.data[idx + 2],
            self.data[idx + 3],
            self.data[idx + 4],
            self.data[idx + 5],
            self.data[idx + 6],
            self.data[idx + 7],
        };
        var ret: u64 = (@as(u64, @intCast(data[0])) << 56);
        ret |= (@as(u64, @intCast(data[1])) << 48);
        ret |= (@as(u64, @intCast(data[2])) << 40);
        ret |= (@as(u64, @intCast(data[3])) << 32);
        ret |= (@as(u64, @intCast(data[4])) << 24);
        ret |= (@as(u64, @intCast(data[5])) << 16);
        ret |= (@as(u64, @intCast(data[6])) << 8);
        ret |= (@as(u64, @intCast(data[7])) << 0);
        return ret;
    }
};
pub const FDTStructNode = union(FDTNodeType) {
    Begin: []const u8,
    End: void,
    Prop: Prop,
    Nop: void,
    TreeEnd: void,
};

pub const FDTNodeType = enum(u32) {
    Begin = 1,
    End = 2,
    Prop = 3,
    Nop = 4,
    TreeEnd = 9,
    _,
};
