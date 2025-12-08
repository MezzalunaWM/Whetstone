const std = @import("std");
const argsParser = @import("args");

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

fn loop(input: bool) !void {
  var pollfds: [2]std.posix.pollfd = undefined;

  pollfds[0] = .{ // wayland fd
    .fd = remote.display.getFd(),
    .events = std.posix.POLL.IN,
    .revents = 0,
  };
  if (input) {
    pollfds[1] = .{ // stdin
      .fd = std.posix.STDIN_FILENO,
      .events = std.posix.POLL.IN,
      .revents = 0,
    };
  }

  var buf: [2]u8 = undefined;
  var stdout_writer = std.fs.File.stdout().writer(&buf);
  const stdout = &stdout_writer.interface;
  while (true) {
    if (input) {
      try stdout.print("> ", .{});
      try stdout.flush();
    }

    _ = std.posix.poll(&pollfds, -1) catch |err| {
      util.fatal("poll() failed: {s}", .{@errorName(err)});
    };

    for (pollfds) |fd| {
      if (fd.revents & std.posix.POLL.IN == 1) {
        if (fd.fd == std.posix.STDIN_FILENO) {
          var in_buf: [1024]u8 = undefined;
          const len = std.posix.read(fd.fd, &in_buf) catch 0;

          if (len == 0) {
            try stdout.print("\n", .{});
            continue;
          }

          if (in_buf[len - 1] == '\n') in_buf[len - 1] = 0 else in_buf[len] = 0;
          if (remote.remote_lua) |rl| rl.pushLua(@ptrCast(in_buf[0..len].ptr));
        }

        // FIXME: we really shouldn't be reading from the socket
        if (fd.fd == remote.display.getFd()) {
          var in_buf: [1024]u8 = undefined;
          const len = std.posix.read(fd.fd, &in_buf) catch 0;
          std.debug.print("\n{s}", .{in_buf[0..len]});
        }
      }
    }

    try remote.flush();
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

  // handle options
  if (options.options.code) |c| {
    remote.remote_lua.?.pushLua(@ptrCast(c[0..].ptr));
  } else if (options.options.@"follow-log") {
    try loop(false);
  } else {
    try loop(true);
  }
}
