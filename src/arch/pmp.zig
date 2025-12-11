const std = @import("std");
const builtin = @import("builtin");

const log = std.log.scoped(.PMP);

const AccessType = enum(u2) {
    Off = 0,
    TOR = 1,
    NA4 = 2,
    MAPOT = 3,
};

const RWXConfig = packed struct {
    R: u1,
    W: u1,
    X: u1,
};

const PMPConfig = packed struct {
    R: u1,
    W: u1,
    X: u1,
    A: AccessType,
    reserved: u2 = 0,
    L: u1 = 0,
};

const MemoryArea = struct {
    start: usize,
    end: usize,
    access: RWXConfig,

    fn len(self: MemoryArea) usize {
        return self.end - self.start;
    }
};
const PMPEntry = struct {
    addr: usize,
    access: PMPConfig,
};
const PMPAreaConfig = struct {
    addr: usize,
    rwx: RWXConfig,
    access: AccessType,
    tor_end_area: usize = 0,
    tor_should_create_new_memory: bool = false,

    fn get_area_end(self: PMPAreaConfig) usize {
        switch (self.access) {
            .NA4 => return self.addr + 4,
            .TOR => return self.tor_end_area,
            else => @panic("PANIC!!"),
        }
    }
};

pub fn init_pmp() void {
    log.debug("PMP init", .{});
    // TODO:extract this from dtb
    const areas: []const MemoryArea = &.{
        // RAM 128M
        .{ .start = 0x8000_0000, .end = 0x8000_0000 + 128 * 1024 * 1024, .access = .{ .R = 1, .X = 1, .W = 1 } },
        // QEMU test devie
        .{ .start = 0x0010_0000, .end = 0x0010_1000, .access = .{ .R = 1, .X = 1, .W = 1 } },
        // CLINT
        .{ .start = 0x0200_0000, .end = 0x0201_0000, .access = .{ .R = 1, .X = 1, .W = 1 } },
        // UART
        .{ .start = 0x1000_0000, .end = 0x1000_0100, .access = .{ .R = 1, .X = 1, .W = 1 } },
        // .{ .start = 0x8000_0000, .end = 0x8000_0000, .access = .{ .R = 1, .X = 1, .W = 1 } },
        // .{ .start = 0x8000_0000, .end = 0x8000_0000, .access = .{ .R = 1, .X = 1, .W = 1 } },
        // All remaining address space
        .{ .start = 0, .end = 0xfffffff0, .access = .{ .R = 0, .X = 0, .W = 0 } },
    };
    const pmp_areas = comptime generate_pmp_area_config(areas);
    log.debug("{d} PMP Areas", .{pmp_areas.len});
    inline for (pmp_areas) |entry| {
        log.debug("\t{s}: 0x{x:0>8} -> 0x{x:0>8} ({any}) (0x{x})", .{ @tagName(entry.access), entry.addr, entry.get_area_end(), entry.rwx, entry.get_area_end() - entry.addr });
    }
    const pmp_entries = comptime generate_pmp_entries(areas);
    log.debug("Writing {d} PMP entries", .{pmp_entries.len});
    inline for (pmp_entries) |entry| {
        log.debug("\t@0x{x:0>8}: {any}", .{ entry.addr, entry.access });
    }
    write_pmpaddr(&pmp_entries);

    const pmpcfg_registers: [(pmp_entries.len + 3) / 4]usize = comptime blk: {
        std.debug.assert(builtin.cpu.features.isEnabled(@intFromEnum(std.Target.riscv.Feature.@"32bit")));
        var pmpcfg: [(pmp_entries.len + 3) / 4]usize = undefined;
        for (0..pmpcfg.len) |i| {
            const range = pmp_entries[(i * 4)..@min(i * 4 + 4, pmp_entries.len)];
            pmpcfg[i] = 0;
            for (range, 0..) |entry, j| {
                pmpcfg[i] |= @as(usize, @intCast(@as(u8, @bitCast(entry.access)))) << @intCast(j * 8);
            }
        }
        const pmpcfg_val: [(pmp_entries.len + 3) / 4]usize = pmpcfg;
        break :blk pmpcfg_val;
    };
    log.debug("Writing {d} PMPCFG regs", .{pmpcfg_registers.len});
    inline for (pmpcfg_registers) |entry| {
        log.debug("\t@0x{x:0>8}", .{entry});
    }
    write_pmpcfg(&pmpcfg_registers);
}

fn write_pmpaddr(comptime pmpaddr: []const PMPEntry) void {
    std.debug.assert(pmpaddr.len < 8 * 4);
    inline for (pmpaddr, 0..) |entry, i| {
        const pmpcfg_register = comptime std.fmt.comptimePrint("pmpaddr{d}", .{i});
        asm volatile ("csrw " ++ pmpcfg_register ++ ", %[val]"
            :
            : [val] "r" (entry.addr),
        );
    }
}
fn write_pmpcfg(comptime pmpcfgs: []const usize) void {
    std.debug.assert(pmpcfgs.len < 8);
    inline for (pmpcfgs, 0..) |entry, i| {
        const pmpcfg_register = comptime std.fmt.comptimePrint("pmpcfg{d}", .{i});
        asm volatile ("csrw " ++ pmpcfg_register ++ ", %[val]"
            :
            : [val] "r" (entry),
        );
    }
}

fn generate_pmp_entries(comptime memory_areas: []const MemoryArea) [calculate_entries_required(&generate_pmp_area_config(memory_areas))]PMPEntry {
    const entries = generate_pmp_area_config(memory_areas);
    var ret: [calculate_entries_required(&entries)]PMPEntry = undefined;

    var current_offset: usize = 0;
    for (entries) |area| {
        switch (area.access) {
            .TOR => {
                if (area.tor_should_create_new_memory) {
                    ret[current_offset] = PMPEntry{
                        .addr = area.addr / 4,
                        .access = .{
                            .R = 0,
                            .W = 0,
                            .X = 0,
                            .A = .Off,
                        },
                    };
                    ret[current_offset + 1] = PMPEntry{
                        .addr = area.tor_end_area / 4,
                        .access = .{
                            .R = area.rwx.R,
                            .W = area.rwx.W,
                            .X = area.rwx.X,
                            .A = area.access,
                        },
                    };
                    current_offset += 2;
                } else {
                    ret[current_offset] = PMPEntry{
                        .addr = area.tor_end_area / 4,
                        .access = .{
                            .R = area.rwx.r,
                            .W = area.rwx.w,
                            .X = area.rwx.x,
                            .A = area.access,
                        },
                    };
                    current_offset += 1;
                }
            },
            else => current_offset += 1,
        }
    }

    return ret;
}

fn generate_pmp_area_config(memory_areas: []const MemoryArea) [memory_areas.len]PMPAreaConfig {
    var entries: [memory_areas.len]PMPAreaConfig = undefined;
    var last_addr: usize = 0;
    for (memory_areas, 0..) |area, idx| {
        if (area.len() < 4) {
            @compileError("PMP areas cannot be smaller than 4 bytes");
        } else if (area.len() == 4) {
            entries[idx] = .{
                .addr = area.start,
                .rwx = area.access,
                .access = .NA4,
            };
            last_addr = area.start;
            // TODO: Set to 0 to disable for now, should fix later
        } else if (@popCount(area.len()) == 0) {
            const len = @ctz(area.len());
            entries[idx] = .{
                .addr = generate_napot(area.start, len),
                .rwx = area.access,
                .access = .NAPOT,
            };
            last_addr = area.start;
        } else {
            entries[idx] = .{
                .addr = area.start,
                .rwx = area.access,
                .access = .TOR,
                .tor_end_area = area.end,
                .tor_should_create_new_memory = last_addr != area.start,
            };
            last_addr = area.end;
        }
    }
    return entries;
}

fn calculate_entries_required(memory_areas: []const PMPAreaConfig) usize {
    var ret: usize = 0;
    for (memory_areas) |areas| {
        switch (areas.access) {
            .TOR => {
                if (areas.tor_should_create_new_memory) {
                    ret += 2;
                } else {
                    ret += 1;
                }
            },
            else => ret += 1,
        }
    }
    return ret;
}

fn generate_napot(start: usize, len: usize) usize {
    _ = start;
    _ = len;
    @compileError("Unimplemented");
    // return 0;
}
