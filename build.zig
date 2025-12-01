const std = @import("std");

const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) void {
  const target = b.standardTargetOptions(.{});
  const optimize = b.standardOptimizeOption(.{});

  const scanner = Scanner.create(b, .{});
  scanner.addCustomProtocol(b.path("protocol/mez-remote-lua-unstable-v1.xml"));
  scanner.generate("wl_compositor", 1);
  scanner.generate("zmez_remote_lua_manager_v1", 1);

  const wayland = b.createModule(.{ .root_source_file = scanner.result });
  const wlroots = b.dependency("wlroots", .{}).module("wlroots");
  const zlua = b.dependency("zlua", .{}).module("zlua");
  const zargs = b.dependency("args", .{ .target = target, .optimize = optimize }).module("args");

  wlroots.addImport("wayland", wayland);
  wlroots.resolved_target = target;
  wlroots.linkSystemLibrary("wlroots-0.19", .{});

  const whet = b.addExecutable(.{
    .name = "whet",
    .root_module = b.createModule(.{
      .root_source_file = b.path("src/main.zig"),
      .target = target,
      .optimize = optimize,
    }),
  });

  whet.linkLibC();

  whet.root_module.addImport("wayland", wayland);
  whet.root_module.addImport("wlroots", wlroots);
  whet.root_module.addImport("zlua", zlua);
  whet.root_module.addImport("args", zargs);

  whet.root_module.linkSystemLibrary("wayland-client", .{});

  b.installArtifact(whet);

  const run_step = b.step("run", "Run the app");

  const run_cmd = b.addRunArtifact(whet);
  run_step.dependOn(&run_cmd.step);

  run_cmd.step.dependOn(b.getInstallStep());

  if (b.args) |args| {
    run_cmd.addArgs(args);
  }
}
