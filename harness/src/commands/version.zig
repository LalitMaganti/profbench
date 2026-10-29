// Copyright 2026 The Profbench Authors.
// SPDX-License-Identifier: Apache-2.0

const cli = @import("cli");
const version = @import("../version.zig").version;

pub const command: cli.Command = .{
    .name = "version",
    .group = .other,
    .summary = "Print version information",
    .run = run,
};

fn run(ctx: *cli.Context) anyerror!u8 {
    if (ctx.args.has("json")) {
        try ctx.out.print("{{\"version\":\"{s}\"}}\n", .{version});
    } else {
        try ctx.out.print("profbench {s}\n", .{version});
    }
    return 0;
}
