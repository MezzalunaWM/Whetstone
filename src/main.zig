const std = @import("std");
const argsParser = @import("args");
const Linenoize = @import("linenoize").Linenoise;

const util = @import("util.zig");
const Remote = @import("remote.zig");

const gpa = std.heap.c_allocator;

var remote: Remote = undefined;

const usage =
    \\Usage: whet [options]
    \\
    \\   Sharpen your Mezzaluna via quick iterations.
    \\
    \\Options:
    \\   -c, --code           One shot sending code to Mezzaluna
    \\   -f, --follow-log     Follow the log as it grows
    \\   -h, --help           Print this help and exit
    \\
;

fn inputThreadRun() !void {
  const ln: *Linenoize = @constCast(&Linenoize.init(gpa));
  defer ln.deinit();

  while (true) {
    const in = ln.linenoise("> ") catch |err| switch (err) {
      error.CtrlC => std.process.exit(130),
      else => return err,
    } orelse continue;
    defer gpa.free(in);

    if (remote.remote_lua) |rl| {
      const w_sentinel = gpa.allocSentinel(u8, in.len, 0) catch util.oom();
      defer gpa.free(w_sentinel);
      std.mem.copyForwards(u8, w_sentinel, in[0..in.len]);

      rl.pushLua(w_sentinel);

      const err = remote.display.flush();
      if (err != .SUCCESS) util.fatal("lost connection to the wayland socket", .{});
    }
    try ln.history.add(in);
  }
}

pub fn main() !void {
  const options = argsParser.parseForCurrentProcess(struct {
    // long options
    code: ?[]const u8 = null,
    @"follow-log": bool = false,
    help: bool = false,

    // short-hand options
    pub const shorthands = .{
      .c = "code",
      .f = "follow-log",
      .h = "help",
    };
  }, gpa, .print) catch return;
  defer options.deinit();

  if (options.options.help) {
    try std.fs.File.stdout().writeAll(usage);
    std.process.exit(1);
  }

  // connect to the compositor
  remote = Remote.init();
  defer remote.deinit();
  var input_thread: std.Thread = undefined;

  // handle options
  if (options.options.code) |c| {
    remote.remote_lua.?.pushLua(@ptrCast(c[0..].ptr));
  } else if (!options.options.@"follow-log") {
    input_thread = try .spawn(.{}, inputThreadRun, .{});
  }

  while (remote.display.dispatch() == .SUCCESS) {}

  input_thread.join();
}
