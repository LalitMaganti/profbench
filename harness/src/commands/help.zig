// Copyright 2026 The Profbench Authors.
// SPDX-License-Identifier: Apache-2.0

const cli = @import("cli");

pub const command: cli.Command = .{
    .name = "help",
    .group = .other,
    .summary = "Show help for profbench or a command",
    .usage = "[command]",
    .run = run,
};

fn run(ctx: *cli.Context) anyerror!u8 {
    if (ctx.args.positionals.len == 0) {
        try ctx.app.writeHelp(ctx.out, ctx.out_color);
        return 0;
    }
    const name = ctx.args.positionals[0];
    const c = ctx.app.find(name) orelse {
        try ctx.fail("unknown command \"{s}\"", .{name});
        return 2;
    };
    try ctx.app.writeCommandHelp(ctx.out, ctx.out_color, c);
    return 0;
}
