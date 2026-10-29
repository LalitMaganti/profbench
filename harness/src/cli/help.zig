// Copyright 2026 The Profbench Authors.
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const Io = std.Io;

const App = @import("app.zig").App;
const Command = @import("command.zig").Command;
const Flag = @import("command.zig").Flag;
const Group = @import("command.zig").Group;
const global_flags = @import("args.zig").global_flags;
const Painter = @import("color.zig").Painter;

pub fn writeAppHelp(w: *Io.Writer, p: Painter, app: *const App) !void {
    try w.print("{s}\n\n", .{app.about});
    try p.write(w, .heading, "Usage:");
    try w.writeAll("\n  ");
    try p.write(w, .command, app.name);
    try w.writeAll(" ");
    try p.write(w, .placeholder, "[command] [flags]");
    try w.writeAll("\n");
    for (std.enums.values(Group)) |g| {
        var width: usize = 0;
        for (app.commands) |c| if (c.group == g) {
            width = @max(width, namesLen(c));
        };
        if (width == 0) continue;
        try w.writeAll("\n");
        try p.print(w, .heading, "{s}:", .{g.title()});
        try w.writeAll("\n");
        for (app.commands) |c| if (c.group == g) {
            try w.writeAll("  ");
            try writeNames(w, p, c);
            try w.splatByteAll(' ', width - namesLen(c) + 2);
            try w.print("{s}\n", .{c.summary});
        };
    }
    try writeFlags(w, p, "Global flags", &global_flags);
}

pub fn writeCommandHelp(w: *Io.Writer, p: Painter, app: *const App, c: Command) !void {
    try w.print("{s}\n\n", .{c.summary});
    try p.write(w, .heading, "Usage:");
    try w.writeAll("\n  ");
    try p.print(w, .command, "{s} {s}", .{ app.name, c.name });
    if (c.usage.len > 0) {
        try w.writeAll(" ");
        try p.write(w, .placeholder, c.usage);
    }
    try w.writeAll(" ");
    try p.write(w, .placeholder, "[flags]");
    try w.writeAll("\n");
    if (c.aliases.len > 0) {
        try w.writeAll("\n");
        try p.write(w, .heading, "Aliases:");
        try w.writeAll("\n  ");
        try writeNames(w, p, c);
        try w.writeAll("\n");
    }
    if (c.flags.len > 0) try writeFlags(w, p, "Flags", c.flags);
    try writeFlags(w, p, "Global flags", &global_flags);
}

fn namesLen(c: Command) usize {
    var n = c.name.len;
    for (c.aliases) |a| n += a.len + 2;
    return n;
}

fn writeNames(w: *Io.Writer, p: Painter, c: Command) !void {
    try p.write(w, .command, c.name);
    for (c.aliases) |a| {
        try w.writeAll(", ");
        try p.write(w, .command, a);
    }
}

fn flagLen(f: Flag) usize {
    return 6 + f.long.len + if (f.value) |v| v.len + 1 else 0;
}

fn writeFlags(w: *Io.Writer, p: Painter, title: []const u8, flags: []const Flag) !void {
    var width: usize = 0;
    for (flags) |f| width = @max(width, flagLen(f));
    try w.writeAll("\n");
    try p.print(w, .heading, "{s}:", .{title});
    try w.writeAll("\n");
    for (flags) |f| {
        if (f.short) |s| {
            try w.writeAll("  ");
            try p.print(w, .flag, "-{c}", .{s});
            try w.writeAll(", ");
        } else {
            try w.writeAll("      ");
        }
        try p.print(w, .flag, "--{s}", .{f.long});
        if (f.value) |v| {
            try w.writeAll(" ");
            try p.write(w, .placeholder, v);
        }
        try w.splatByteAll(' ', width - flagLen(f) + 2);
        try w.print("{s}\n", .{f.help});
    }
}

test "help is aligned and unstyled when color is off" {
    const noop = struct {
        fn run(_: *@import("command.zig").Context) anyerror!u8 {
            return 0;
        }
    }.run;
    const app: App = .{ .name = "tool", .about = "About.", .commands = &.{
        .{ .name = "ls", .aliases = &.{"list"}, .group = .common, .summary = "List", .run = noop },
        .{ .name = "version", .group = .other, .summary = "Version", .run = noop },
    } };
    var buf: [2048]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try writeAppHelp(&w, .{ .enabled = false }, &app);
    const text = w.buffered();
    try std.testing.expect(std.mem.indexOf(u8, text, "  ls, list  List\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\x1b[") == null);
}
