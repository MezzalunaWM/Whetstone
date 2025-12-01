const std = @import("std");

pub fn fatal(comptime str: []const u8, opts: anytype) noreturn {
  std.log.err(str, opts);
  std.process.exit(1);
}

pub fn oom() noreturn {
  fatal("out of memory", .{});
}

pub fn not_advertised(comptime Global: type) noreturn {
  fatal("{s} not advertised", .{Global.interface.name});
}
