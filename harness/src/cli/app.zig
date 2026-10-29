// Copyright 2026 The Profbench Authors.
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const Io = std.Io;

const args_ = @import("args.zig");
const color = @import("color.zig");
const Command = @import("command.zig").Command;
const Context = @import("command.zig").Context;
const help = @import("help.zig");
const suggest = @import("suggest.zig").suggest;

pub const App = struct {
    name: []const u8,
    about: []const u8,
    commands: []const Command,

    pub fn find(app: *const App, name: []const u8) ?Command {
        for (app.commands) |c| if (c.matches(name)) return c;
        return null;
    }

    pub fn writeHelp(app: *const App, w: *Io.Writer, p: color.Painter) !void {
        try help.writeAppHelp(w, p, app);
    }

    pub fn writeCommandHelp(app: *const App, w: *Io.Writer, p: color.Painter, c: Command) !void {
        try help.writeCommandHelp(w, p, app, c);
    }
};

/// Parses the process arguments, dispatches to a command and returns the
/// exit code: the command's own, or 2 for usage errors.
pub fn run(app: *const App, init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(arena);
    const rest: []const []const u8 = argv[@min(argv.len, 1)..];

    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    var out_file: Io.File.Writer = .init(.stdout(), init.io, &out_buf);
    var err_file: Io.File.Writer = .init(.stderr(), init.io, &err_buf);
    defer out_file.interface.flush() catch {};
    defer err_file.interface.flush() catch {};

    // --color is needed before full parsing, so that parse errors are styled.
    const mode = colorMode(rest) orelse {
        try err_file.interface.print("error: --color must be auto, always or never\n", .{});
        return 2;
    };
    var ctx: Context = .{
        .app = app,
        .io = init.io,
        .arena = arena,
        .environ = init.environ_map,
        .args = .{ .entries = &.{}, .positionals = &.{} },
        .out = &out_file.interface,
        .err = &err_file.interface,
        .out_color = .{ .enabled = color.enabled(mode, try Io.File.stdout().isTty(init.io), init.environ_map) },
        .err_color = .{ .enabled = color.enabled(mode, try Io.File.stderr().isTty(init.io), init.environ_map) },
    };

    // Global flags may come before the command name, as in
    // `profbench --color=always help`.
    const lead = leadingFlags(rest);
    const after = rest[lead..];
    if (after.len == 0) {
        if (hasFlag(rest[0..lead], "--version")) return runNamed(app, &ctx, "version", rest[0..lead], &.{});
        try app.writeHelp(ctx.out, ctx.out_color);
        return 0;
    }
    return runNamed(app, &ctx, after[0], rest[0..lead], after[1..]);
}

fn runNamed(
    app: *const App,
    ctx: *Context,
    name: []const u8,
    before: []const []const u8,
    after: []const []const u8,
) !u8 {
    const command = app.find(name) orelse {
        try ctx.fail("unknown command \"{s}\"", .{name});
        if (suggest(app.commands, name)) |s| {
            try ctx.err.print("  did you mean \"{s}\"?\n", .{s});
        } else {
            try ctx.err.print("  see `{s} help`\n", .{app.name});
        }
        return 2;
    };

    // --version is only meaningful before a command name.
    var flags: std.ArrayList([]const u8) = .empty;
    for (before) |a| if (!std.mem.eql(u8, a, "--version")) try flags.append(ctx.arena, a);
    try flags.appendSlice(ctx.arena, after);

    var diag: args_.Diagnostic = .{};
    ctx.args = args_.parse(ctx.arena, command.flags, flags.items, &diag) catch |err| {
        const what = switch (err) {
            error.UnknownFlag => "unknown flag",
            error.MissingValue => "missing value for",
            error.UnexpectedValue => "unexpected value for",
            error.OutOfMemory => return err,
        };
        try ctx.fail("{s} {s}", .{ what, diag.arg });
        try ctx.err.print("  see `{s} help {s}`\n", .{ app.name, command.name });
        return 2;
    };
    if (ctx.args.has("help")) {
        try app.writeCommandHelp(ctx.out, ctx.out_color, command);
        return 0;
    }
    return command.run(ctx);
}

/// The number of leading arguments that are global flags, including the
/// values of flags that take one.
fn leadingFlags(args: []const []const u8) usize {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (a.len < 2 or a[0] != '-' or std.mem.eql(u8, a, "--")) break;
        if (std.mem.eql(u8, a, "--color")) i += 1;
    }
    return @min(i, args.len);
}

fn hasFlag(args: []const []const u8, flag: []const u8) bool {
    for (args) |a| if (std.mem.eql(u8, a, flag)) return true;
    return false;
}

/// The last --color value in `args`, or auto if there is none. Returns null
/// for an invalid value.
fn colorMode(args: []const []const u8) ?color.Mode {
    var mode: color.Mode = .auto;
    for (args, 0..) |a, i| {
        if (std.mem.eql(u8, a, "--")) break;
        const value = if (std.mem.startsWith(u8, a, "--color="))
            a["--color=".len..]
        else if (std.mem.eql(u8, a, "--color") and i + 1 < args.len)
            args[i + 1]
        else
            continue;
        mode = color.parseMode(value) orelse return null;
    }
    return mode;
}
