pub const serial = @import("serial.zig");
pub const clock = @import("clock/root.zig");
pub const plic = @import("plic.zig");

pub const Device = struct {
    pub const Error = error{};

    pub const VTable = struct {
        init: *const fn (self: *anyopaque) Error!void,
    };
    vtable: *const VTable,
    ctx: *anyopaque,

    pub fn init(self: *Device) Error!void {
        return self.vtable.init(self.ctx);
    }
};
