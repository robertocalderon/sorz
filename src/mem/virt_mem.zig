const std = @import("std");
const root = @import("../root.zig");

pub const AddressSpace = struct {
    root_page: *PageTable,

    const SATP = packed struct {
        ppn: PhysicalPageNumber,
        ASID: u9,
        MODE: u1,
    };
    pub fn activate(self: *AddressSpace) void {
        const root_addr: PhysicalAddress = @bitCast(@as(u34, @intCast(@intFromPtr(self.root_page))));
        const satp: SATP = .{
            .ppn = root_addr.ppn,
            .ASID = 0,
            .MODE = 1,
        };
        asm volatile ("csrw satp, %[val]"
            :
            : [val] "r" (@as(usize, @bitCast(satp))),
        );
    }
};
pub const AccessFlags = packed struct {
    R: u1,
    W: u1,
    X: u1,
    U: u1,

    pub fn rwx_kernel() AccessFlags {
        return .{
            .R = 1,
            .W = 1,
            .X = 1,
            .U = 0,
        };
    }
    pub fn rw_kernel() AccessFlags {
        return .{
            .R = 1,
            .W = 1,
            .X = 0,
            .U = 0,
        };
    }
    pub fn r_kernel() AccessFlags {
        return .{
            .R = 1,
            .W = 0,
            .X = 0,
            .U = 0,
        };
    }
    pub fn rx_kernel() AccessFlags {
        return .{
            .R = 1,
            .W = 0,
            .X = 1,
            .U = 0,
        };
    }
    pub fn rwx_user() AccessFlags {
        return .{
            .R = 1,
            .W = 1,
            .X = 1,
            .U = 1,
        };
    }
    pub fn rw_user() AccessFlags {
        return .{
            .R = 1,
            .W = 1,
            .X = 0,
            .U = 1,
        };
    }
    pub fn r_user() AccessFlags {
        return .{
            .R = 1,
            .W = 0,
            .X = 0,
            .U = 1,
        };
    }
    pub fn rx_user() AccessFlags {
        return .{
            .R = 1,
            .W = 0,
            .X = 1,
            .U = 1,
        };
    }
    pub fn branch_kernel() AccessFlags {
        return .{
            .R = 0,
            .W = 0,
            .X = 0,
            .U = 0,
        };
    }
    pub fn branch_user() AccessFlags {
        return .{
            .R = 0,
            .W = 0,
            .X = 0,
            .U = 1,
        };
    }
};

const PhysicalPageNumber = packed struct {
    ppn0: u10,
    ppn1: u12,
};
const VirtualAddress = packed struct {
    offset: u12,
    vpn0: u10,
    vpn1: u10,
};
const PhysicalAddress = packed struct {
    offset: u12,
    ppn: PhysicalPageNumber,
};
const PageTableEntry = packed struct {
    V: u1,
    access_flags: AccessFlags,
    G: u1,
    A: u1 = 1,
    D: u1 = 1,
    RSW: u2,
    ppn: PhysicalPageNumber,

    pub fn is_branch(self: PageTableEntry) bool {
        if (self.access_flags.R != 0) return false;
        if (self.access_flags.W != 0) return false;
        if (self.access_flags.X != 0) return false;
        return true;
    }
    pub fn get_inner(self: PageTableEntry) *PageTable {
        return @bitCast(PhysicalAddress{
            .offset = 0,
            .ppn = self.ppn,
        });
    }
};
const PageTable = [1024]PageTableEntry;

pub const VirtualMemoryError = error{UnalignedAddress};

pub fn identity_map_range_huge_pages(table: *PageTable, access: AccessFlags, start: usize, range_size: usize) !void {
    const s_addr: PhysicalAddress = @bitCast(@as(u34, @intCast(start)));
    const e_addr: PhysicalAddress = @bitCast(@as(u34, @intCast(start)) + @as(u34, @intCast(range_size)));
    if (s_addr.ppn.ppn0 != 0 or s_addr.offset != 0) {
        return VirtualMemoryError.UnalignedAddress;
    }
    if (e_addr.ppn.ppn0 != 0 or e_addr.offset != 0) {
        return VirtualMemoryError.UnalignedAddress;
    }
    // TODO: check if entry is already in use and free memory if required
    for (s_addr.ppn.ppn1..e_addr.ppn.ppn1) |ppn1| {
        const entry: *PageTableEntry = &table[ppn1];
        const current_addr: u34 = @as(u34, @intCast(ppn1)) * 1024 * 4096;
        const current_physical_addr: PhysicalAddress = @bitCast(current_addr);
        entry.* = .{
            .V = 1,
            .G = 0,
            .RSW = 0,
            .access_flags = access,
            .ppn = current_physical_addr.ppn,
        };
    }
}

pub fn init(alloc: std.mem.Allocator) !AddressSpace {
    const root_table = try alloc.create(PageTable);
    errdefer alloc.destroy(root_table);
    std.log.debug("alloced page table at {*}", .{@as([*]PageTableEntry, @ptrCast(root_table))});

    @memset(root_table, PageTableEntry{ .G = 0, .RSW = 0, .V = 0, .access_flags = .r_user(), .ppn = .{ .ppn0 = 0, .ppn1 = 0 } });
    _ = try identity_map_range_huge_pages(root_table, .rwx_kernel(), 0, 0x1_0000_0000 - 1024 * 4096);
    std.log.debug("0x8000_0000: {any}: 0x{x:0>8}", .{ root_table[512], @as(u32, @bitCast(root_table[512])) });
    std.log.debug("0x8040_0000: {any}: 0x{x:0>8}", .{ root_table[513], @as(u32, @bitCast(root_table[513])) });
    return .{ .root_page = root_table };
}

/// Try to map a page, allocating memory if needed
pub fn map_page(alloc: ?std.mem.Allocator, as: AddressSpace, phys: PhysicalAddress, virt: VirtualAddress, flags: AccessFlags) !void {
    std.debug.assert(phys.offset == 0);
    std.debug.assert(virt.offset == 0);

    const table = as.root_page;
    const first_level_entry = table[virt.vpn1];
    var second_level_table: *PageTable = undefined;

    if (first_level_entry.is_branch()) {
        std.debug.assert(first_level_entry.ppn.ppn0 == 0);

        const r_alloc = alloc orelse return std.mem.Allocator.Error.OutOfMemory;
        var page = try r_alloc.create(PageTable);

        for (0..1024) |i| {
            const current_addr = PhysicalPageNumber{
                .ppn0 = @intCast(i),
                .ppn1 = first_level_entry.ppn.ppn1,
            };
            page[i] = PageTableEntry{
                .V = first_level_entry.V,
                .access_flags = first_level_entry.access_flags,
                .RSW = first_level_entry.RSW,
                .G = first_level_entry.G,
                .A = first_level_entry.A,
                .D = first_level_entry.D,
                .ppn = current_addr,
            };
        }

        second_level_table = page;
        const page_addr: PhysicalAddress = @bitCast(page);
        first_level_entry.V = 1;
        first_level_entry.access_flags = .{
            .R = 0,
            .W = 0,
            .X = 0,
            .U = first_level_entry.access_flags.U,
        };
        first_level_entry.ppn = page_addr;
    } else {
        second_level_table = first_level_entry.get_inner();
    }
    const second_level_entry = second_level_table[virt.vpn0];
    second_level_entry = .{
        .V = 1,
        .G = 0,
        .access_flags = flags,
        .RSW = 0,
        .ppn = phys.ppn,
        .A = 1,
        .D = 1,
    };
}

pub fn unmap_page(alloc: ?std.mem.Allocator, as: AddressSpace, virt: VirtualAddress) !void {
    std.debug.assert(virt.offset == 0);
    const table = as.root_page;
    const first_level_entry = table[virt.vpn1];
    var second_level_table: *PageTable = undefined;

    if (first_level_entry.is_branch()) {
        std.debug.assert(first_level_entry.ppn.ppn0 == 0);

        const r_alloc = alloc orelse return std.mem.Allocator.Error.OutOfMemory;
        var page = try r_alloc.create(PageTable);

        for (0..1024) |i| {
            const current_addr = PhysicalPageNumber{
                .ppn0 = @intCast(i),
                .ppn1 = first_level_entry.ppn.ppn1,
            };
            page[i] = PageTableEntry{
                .V = first_level_entry.V,
                .access_flags = first_level_entry.access_flags,
                .RSW = first_level_entry.RSW,
                .G = first_level_entry.G,
                .A = first_level_entry.A,
                .D = first_level_entry.D,
                .ppn = current_addr,
            };
        }

        second_level_table = page;
        const page_addr: PhysicalAddress = @bitCast(page);
        first_level_entry.V = 1;
        first_level_entry.access_flags = .{
            .R = 0,
            .W = 0,
            .X = 0,
            .U = first_level_entry.access_flags.U,
        };
        first_level_entry.ppn = page_addr;
    } else {
        second_level_table = first_level_entry.get_inner();
    }
    const second_level_entry = second_level_table[virt.vpn0];
    second_level_entry = .{
        .V = 0,
        .G = 0,
        .access_flags = .{
            .R = 0,
            .U = 0,
            .W = 0,
            .X = 0,
        },
        .RSW = 0,
        .ppn = .{
            .ppn0 = 0,
            .ppn1 = 0,
        },
        .A = 1,
        .D = 1,
    };
}

pub fn map_page_range(alloc: ?std.mem.Allocator, as: AddressSpace, phys: PhysicalAddress, virt: VirtualAddress, n_pages: usize, flags: AccessFlags) !void {
    std.debug.assert(virt.offset == 0);

    var mapped_pages: usize = 0;
    var failed: bool = false;

    for (0..n_pages) |i| {
        const start_addr: u32 = @bitCast(virt);
        const current_addr = start_addr + (i * 4096);
        const current_page: VirtualAddress = @bitCast(current_addr);

        const start_phys_addr: u32 = @as(u32, @bitCast(@as(u34, @bitCast(phys))));
        const current_phys_addr = start_phys_addr + (i * 4096);
        const current_phys_page: PhysicalAddress = @bitCast(current_phys_addr);

        map_page(alloc, as, current_phys_page, current_page, flags) catch {
            failed = true;
            break;
        };
        mapped_pages += 1;
    }
    if (failed) {
        for (0..failed) |i| {
            const start_addr: u32 = @bitCast(virt);
            const current_addr = start_addr + (i * 4096);
            const current_page: VirtualAddress = @bitCast(current_addr);
            unmap_page(alloc, as, current_page);
        }
        return std.mem.Allocator.Error.OutOfMemory;
    }
}
