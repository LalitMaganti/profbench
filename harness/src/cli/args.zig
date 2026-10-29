// Copyright 2026 The Profbench Authors.
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const Flag = @import("command.zig").Flag;

/// Flags every command accepts.
pub const global_flags = [_]Flag{
    .{ .long = "help", .short = 'h', .help = "show help" },
    .{ .long = "json", .help = "machine-readable output" },
    .{ .long = "color", .value = "WHEN", .help = "auto, always or never (default auto)" },
    .{ .long = "verbose", .short = 'v', .help = "more detail (repeatable)" },
};

pub const Parsed = struct {
    const Entry = struct { flag: []const u8, value: ?[]const u8 };

    entries: []const Entry,
    positionals: []const []const u8,

    pub fn count(p: Parsed, flag: []const u8) usize {
        var n: usize = 0;
        for (p.entries) |e| n += @intFromBool(std.mem.eql(u8, e.flag, flag));
        return n;
    }

    pub fn has(p: Parsed, flag: []const u8) bool {
        return p.count(flag) > 0;
    }

    /// The last value given for a flag.
    pub fn get(p: Parsed, flag: []const u8) ?[]const u8 {
        var v: ?[]const u8 = null;
        for (p.entries) |e| if (std.mem.eql(u8, e.flag, flag)) {
            v = e.value;
        };
        return v;
    }
};

pub const Error = error{ UnknownFlag, MissingValue, UnexpectedValue, OutOfMemory };

/// Identifies the argument that caused a parse error.
pub const Diagnostic = struct { arg: []const u8 = "" };

/// Parses `args` against a command's flags plus the global flags, allocating
/// the result in `arena`. Accepts
/// --flag value, --flag=value, grouped short flags such as -vv, and -- to end
/// flag parsing.
pub fn parse(
    arena: std.mem.Allocator,
    flags: []const Flag,
    args: []const []const u8,
    diag: *Diagnostic,
) Error!Parsed {
    var entries: std.ArrayList(Parsed.Entry) = .empty;
    var positionals: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        diag.arg = arg;
        if (std.mem.eql(u8, arg, "--")) {
            try positionals.appendSlice(arena, args[i + 1 ..]);
            break;
        }
        if (std.mem.startsWith(u8, arg, "--")) {
            const body = arg[2..];
            const eq = std.mem.indexOfScalar(u8, body, '=');
            const name = if (eq) |e| body[0..e] else body;
            const flag = findLong(flags, name) orelse return error.UnknownFlag;
            if (flag.value == null) {
                if (eq != null) return error.UnexpectedValue;
                try entries.append(arena, .{ .flag = flag.long, .value = null });
            } else if (eq) |e| {
                try entries.append(arena, .{ .flag = flag.long, .value = body[e + 1 ..] });
            } else {
                i += 1;
                if (i == args.len) return error.MissingValue;
                try entries.append(arena, .{ .flag = flag.long, .value = args[i] });
            }
        } else if (arg.len > 1 and arg[0] == '-') {
            // A value-taking short flag must come last in a group, and takes
            // the rest of the argument or the next one.
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                const flag = findShort(flags, arg[j]) orelse return error.UnknownFlag;
                if (flag.value == null) {
                    try entries.append(arena, .{ .flag = flag.long, .value = null });
                    continue;
                }
                if (j + 1 < arg.len) {
                    try entries.append(arena, .{ .flag = flag.long, .value = arg[j + 1 ..] });
                } else {
                    i += 1;
                    if (i == args.len) return error.MissingValue;
                    try entries.append(arena, .{ .flag = flag.long, .value = args[i] });
                }
                break;
            }
        } else {
            try positionals.append(arena, arg);
        }
    }
    return .{ .entries = entries.items, .positionals = positionals.items };
}

fn findLong(flags: []const Flag, name: []const u8) ?Flag {
    for (flags) |f| if (std.mem.eql(u8, f.long, name)) return f;
    for (global_flags) |f| if (std.mem.eql(u8, f.long, name)) return f;
    return null;
}

fn findShort(flags: []const Flag, c: u8) ?Flag {
    for (flags) |f| if (f.short == c) return f;
    for (global_flags) |f| if (f.short == c) return f;
    return null;
}

test "parse long, short, grouped and positional arguments" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const flags = [_]Flag{
        .{ .long = "reps", .value = "N", .help = "" },
        .{ .long = "quick", .short = 'q', .help = "" },
    };
    var diag: Diagnostic = .{};
    const p = try parse(arena.allocator(), &flags, &.{
        "perf", "--reps", "3", "--color=never", "-vvq", "--", "--json",
    }, &diag);
    try std.testing.expectEqualStrings("3", p.get("reps").?);
    try std.testing.expectEqualStrings("never", p.get("color").?);
    try std.testing.expectEqual(2, p.count("verbose"));
    try std.testing.expect(p.has("quick"));
    try std.testing.expect(!p.has("json"));
    try std.testing.expectEqual(2, p.positionals.len);
    try std.testing.expectEqualStrings("--json", p.positionals[1]);
}

test "parse errors" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    try std.testing.expectError(error.UnknownFlag, parse(arena.allocator(), &.{}, &.{"--nope"}, &diag));
    try std.testing.expectEqualStrings("--nope", diag.arg);
    try std.testing.expectError(error.MissingValue, parse(arena.allocator(), &.{}, &.{"--color"}, &diag));
    try std.testing.expectError(error.UnexpectedValue, parse(arena.allocator(), &.{}, &.{"--json=1"}, &diag));
}
