// Copyright 2026 The Profbench Authors.
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const cli = @import("cli");

const app: cli.App = .{
    .name = "profbench",
    .about = "Measure the cost of enabling a profiler.",
    .commands = &.{
        @import("commands/help.zig").command,
        @import("commands/version.zig").command,
    },
};

pub fn main(init: std.process.Init) !u8 {
    return cli.run(&app, init);
}
