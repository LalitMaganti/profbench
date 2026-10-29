// Copyright 2026 The Profbench Authors.
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const Io = std.Io;

const App = @import("app.zig").App;
const Parsed = @import("args.zig").Parsed;
const Painter = @import("color.zig").Painter;

/// Where a command is listed in the top-level help.
pub const Group = enum {
    common,
    resources,
    maintenance,
    other,

    pub fn title(g: Group) []const u8 {
        return switch (g) {
            .common => "Common commands",
            .resources => "Resources",
            .maintenance => "Maintenance",
            .other => "Other",
        };
    }
};

pub const Flag = struct {
    long: []const u8,
    short: ?u8 = null,
    /// Placeholder shown in help for flags that take a value, such as "WHEN".
    value: ?[]const u8 = null,
    help: []const u8,
};

pub const Command = struct {
    name: []const u8,
    aliases: []const []const u8 = &.{},
    group: Group,
    summary: []const u8,
    /// Positional arguments, as shown after the command name in usage.
    usage: []const u8 = "",
    flags: []const Flag = &.{},
    run: *const fn (*Context) anyerror!u8,

    pub fn matches(c: Command, name: []const u8) bool {
        if (std.mem.eql(u8, c.name, name)) return true;
        for (c.aliases) |a| if (std.mem.eql(u8, a, name)) return true;
        return false;
    }
};

/// Everything a command needs to run. Normal output goes to `out`; errors,
/// warnings and progress go to `err`. Each stream has its own painter because
/// one may be a terminal and the other a pipe.
pub const Context = struct {
    app: *const App,
    io: Io,
    arena: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    args: Parsed,
    out: *Io.Writer,
    err: *Io.Writer,
    out_color: Painter,
    err_color: Painter,

    /// Prints "error: <message>" to `err`.
    pub fn fail(ctx: *Context, comptime fmt: []const u8, args: anytype) !void {
        try ctx.err_color.write(ctx.err, .err, "error:");
        try ctx.err.print(" " ++ fmt ++ "\n", args);
    }

    /// Prints "warning: <message>" to `err`.
    pub fn warn(ctx: *Context, comptime fmt: []const u8, args: anytype) !void {
        try ctx.err_color.write(ctx.err, .warning, "warning:");
        try ctx.err.print(" " ++ fmt ++ "\n", args);
    }
};
