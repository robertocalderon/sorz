const std = @import("std");
const root = @import("root.zig");
const dev = root.dev;

var DEFAULT_WRITTER: *std.Io.Writer = undefined;
var DEFAULT_CLOCK: ?dev.clock.Clock = null;

pub fn init_logging(logger: *std.Io.Writer) void {
    DEFAULT_WRITTER = logger;
    // DEFAULT_WRITTER.store(logger, .seq_cst);
    // @atomicStore(*std.Io.Writer, &DEFAULT_WRITTER, logger, .seq_cst);
}
pub fn set_default_clock(clock: dev.clock.Clock) void {
    DEFAULT_CLOCK = clock;
}
pub fn get_current_writer() *std.Io.Writer {
    return DEFAULT_WRITTER;
}

pub fn log_fn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    const color_scape_code = "\x1b[" ++ switch (message_level) {
        .debug => "34",
        .info => "32",
        .warn => "33",
        .err => "31",
    } ++ "m";
    // const w = DEFAULT_WRITTER.load(.acquire);
    // var w: *std.Io.Writer = @atomicLoad(*std.Io.Writer, &DEFAULT_WRITTER, .acquire);
    var w: *std.Io.Writer = DEFAULT_WRITTER;

    nosuspend {
        if (DEFAULT_CLOCK) |clock| blk: {
            var c = clock;
            const now = c.now() catch break :blk;
            const nanos = now.raw;
            const segundos = nanos / 1000000000;
            const solo_nanos = nanos % 1000000000;
            const solo_micros = solo_nanos / 1000;

            w.print("[\x1b[36m{d: >6}.{d:0>6}\x1b[0m]  ", .{ segundos, solo_micros }) catch break :blk;
        }
        w.print(color_scape_code ++ level_txt ++ "\x1b[0m" ++ prefix2 ++ format ++ "\n", args) catch return;
        w.flush() catch return;
    }
}
