const Remote = @This();

const std = @import("std");
const posix = std.posix;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const mez = wayland.client.zmez;

const util = @import("util.zig");
const prompt = @import("main.zig").prompt;

display: *wl.Display,
registry: *wl.Registry,
compositor: ?*wl.Compositor,
remote_lua_manager: ?*mez.RemoteLuaManagerV1,
remote_lua: ?*mez.RemoteLuaV1,

pub fn init() Remote {
  var self: Remote = .{
    .registry = undefined,
    .compositor = null,
    .remote_lua = null,
    .remote_lua_manager = null,
    .display = wl.Display.connect(null) catch |err| {
      util.fatal("failed to connect to a wayland compositor: {s}", .{@errorName(err)});
    },
  };

  self.registry = self.display.getRegistry() catch unreachable;
  errdefer self.registry.destroy();
  self.registry.setListener(*Remote, registry_listener, &self);

  const errno = self.display.roundtrip();
  if (errno != .SUCCESS) {
    util.fatal("initial roundtrip failed: {s}", .{@tagName(errno)});
  }

  if (self.compositor == null) util.not_advertised(wl.Compositor);
  if (self.remote_lua_manager == null) util.not_advertised(mez.RemoteLuaManagerV1);

  self.remote_lua = self.remote_lua_manager.?.getRemote() catch util.oom();
  if (self.remote_lua) |rl| {
    rl.setListener(*Remote, handleRemote, @constCast(&self));
  } else {
    util.fatal("failed to setup the remote listener", .{});
  }

  return self;
}

pub fn deinit(self: *Remote) void {
  self.registry.destroy();
  if (self.remote_lua_manager) |rl_manager| rl_manager.destroy();
  if (self.remote_lua) |rl| rl.destroy();
  if (self.compositor) |comp| comp.destroy();
  self.display.disconnect();
}

fn registry_listener(
registry: *wl.Registry,
event: wl.Registry.Event,
remote: *Remote,
) void {
  registry_event(registry, event, remote) catch |err| switch (err) {
    error.OutOfMemory => util.oom(),
  };
}

fn registry_event(registry: *wl.Registry, event: wl.Registry.Event, remote: *Remote) !void {
  switch (event) {
    .global => |ev| {
      if (std.mem.orderZ(u8, ev.interface, wl.Compositor.interface.name) == .eq) {
        const ver = 1;
        if (ev.version < ver) {
          util.fatal("advertised wl_compositor version too old, version {} required", .{ver});
        }
        remote.compositor = try registry.bind(ev.name, wl.Compositor, ver);
      } else if (std.mem.orderZ(u8, ev.interface, mez.RemoteLuaManagerV1.interface.name) == .eq) {
        const ver = 1;
        if (ev.version < ver) {
          util.fatal("advertised remote_lua_manager version too old, version {} required", .{ver});
        }
        remote.remote_lua_manager = try registry.bind(ev.name, mez.RemoteLuaManagerV1, ver);
      }
    },
    .global_remove => {},
  }
}

fn handleRemote(_: *mez.RemoteLuaV1, event: mez.RemoteLuaV1.Event, _: *Remote) void {
  switch (event) {
    .new_log_entry => |e| {
      const buffer: [1024]u8 = undefined;
      const stdout = @constCast(&std.fs.File.stdout().writer(@constCast(&buffer)).interface);
      // HACK: to make the prompt look correct we just redraw it after logging
      // an entry.
      stdout.print("\r{s}\r\n" ++ prompt, .{e.text}) catch {};
      stdout.flush() catch {};
    },
  }
}
