// Copyright 2026 The Profbench Authors.
// SPDX-License-Identifier: Apache-2.0

//! Terminal colors. Output is styled by semantic role, never by raw color, so
//! the theme lives in one place.

const std = @import("std");
const Io = std.Io;

pub const Mode = enum { auto, always, never };

pub const Role = enum {
    heading,
    command,
    flag,
    placeholder,
    err,
    warning,
    success,
    dim,

    fn sgr(r: Role) []const u8 {
        return switch (r) {
            .heading => "1",
            .command => "36",
            .flag => "36",
            .placeholder => "2",
            .err => "1;31",
            .warning => "1;33",
            .success => "32",
            .dim => "2",
        };
    }
};

/// Writes text in a role's style when enabled, and plain text otherwise.
pub const Painter = struct {
    enabled: bool,

    pub fn begin(p: Painter, w: *Io.Writer, role: Role) !void {
        if (p.enabled) try w.print("\x1b[{s}m", .{role.sgr()});
    }

    pub fn end(p: Painter, w: *Io.Writer) !void {
        if (p.enabled) try w.writeAll("\x1b[0m");
    }

    pub fn write(p: Painter, w: *Io.Writer, role: Role, text: []const u8) !void {
        try p.begin(w, role);
        try w.writeAll(text);
        try p.end(w);
    }

    pub fn print(p: Painter, w: *Io.Writer, role: Role, comptime fmt: []const u8, args: anytype) !void {
        try p.begin(w, role);
        try w.print(fmt, args);
        try p.end(w);
    }
};

pub fn parseMode(s: []const u8) ?Mode {
    return std.meta.stringToEnum(Mode, s);
}

/// Whether to use color on a stream. An explicit --color wins; otherwise
/// NO_COLOR (no-color.org) disables, CLICOLOR_FORCE enables, and color is used
/// only on a terminal that is not TERM=dumb.
pub fn enabled(mode: Mode, is_tty: bool, environ: *const std.process.Environ.Map) bool {
    switch (mode) {
        .never => return false,
        .always => return true,
        .auto => {},
    }
    if (nonEmpty(environ.get("NO_COLOR"))) return false;
    if (environ.get("CLICOLOR_FORCE")) |v| {
        if (v.len > 0 and !std.mem.eql(u8, v, "0")) return true;
    }
    if (!is_tty) return false;
    if (environ.get("TERM")) |t| if (std.mem.eql(u8, t, "dumb")) return false;
    return true;
}

fn nonEmpty(v: ?[]const u8) bool {
    return if (v) |s| s.len > 0 else false;
}

test "color detection" {
    var env: std.process.Environ.Map = .init(std.testing.allocator);
    defer env.deinit();
    try std.testing.expect(enabled(.auto, true, &env));
    try std.testing.expect(!enabled(.auto, false, &env));
    try std.testing.expect(enabled(.always, false, &env));
    try std.testing.expect(!enabled(.never, true, &env));

    try env.put("TERM", "dumb");
    try std.testing.expect(!enabled(.auto, true, &env));
    try env.put("CLICOLOR_FORCE", "1");
    try std.testing.expect(enabled(.auto, false, &env));
    try env.put("NO_COLOR", "1");
    try std.testing.expect(!enabled(.auto, true, &env));
    try std.testing.expect(enabled(.always, true, &env));
}

test "painter" {
    var buf: [64]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try (Painter{ .enabled = true }).write(&w, .err, "x");
    try (Painter{ .enabled = false }).write(&w, .err, "y");
    try std.testing.expectEqualStrings("\x1b[1;31mx\x1b[0my", w.buffered());
}
