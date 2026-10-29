// Copyright 2026 The Profbench Authors.
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    // The generic CLI library, kept as its own module so it cannot depend on
    // the rest of the harness.
    const cli = b.createModule(.{
        .root_source_file = b.path("src/cli/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "profbench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "cli", .module = cli }},
        }),
    });
    b.installArtifact(exe);

    const test_step = b.step("test", "Run the harness unit tests");
    for ([_]*std.Build.Module{ cli, exe.root_module }) |m| {
        test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = m })).step);
    }
}
