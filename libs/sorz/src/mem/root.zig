const std = @import("std");
pub const phys_mem = @import("phys_mem.zig");
pub const virt_mem = @import("virt_mem.zig");

pub const MemoryArea = struct {
    start: u64,
    end: u64,

    pub fn len(self: MemoryArea) u64 {
        return self.end - self.start;
    }
    pub fn try_remove_side(self: MemoryArea, side: MemoryArea) ?MemoryArea {
        if (side.start <= self.start and side.end < self.end) {
            // at left side
            return MemoryArea{
                .start = side.end,
                .end = self.end,
            };
        }
        if (self.start < side.start and self.end <= side.end) {
            // at right side
            return MemoryArea{
                .start = self.start,
                .end = side.start,
            };
        }
        return null;
    }
    pub const AreaPair = struct {
        l: MemoryArea,
        r: MemoryArea,
    };
    pub fn try_remove_inside(self: MemoryArea, inside: MemoryArea) ?AreaPair {
        if (self.start < inside.start and inside.end < self.end) {
            return AreaPair{
                .l = .{
                    .start = self.start,
                    .end = inside.start,
                },
                .r = .{
                    .start = inside.end,
                    .end = self.end,
                },
            };
        }
        return null;
    }
    pub fn remove_areas(valid_areas: *std.array_list.Managed(MemoryArea), invalid_areas: []const MemoryArea) !void {
        for (invalid_areas) |ia| {
            var i: usize = 0;
            while (i < valid_areas.items.len) {
                const va = valid_areas.items[i];
                if (va.start == ia.start and va.end == ia.end) {
                    _ = valid_areas.orderedRemove(i);
                    continue;
                }
                if (va.try_remove_side(ia)) |new_area| {
                    valid_areas.items[i] = new_area;
                } else if (va.try_remove_inside(ia)) |new_areas| {
                    valid_areas.items[i] = new_areas.l;
                    i += 1;
                    try valid_areas.insert(i, new_areas.r);
                } else {
                    // Outside area
                }
                i += 1;
            }
        }
    }
};
