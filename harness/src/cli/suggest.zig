// Copyright 2026 The Profbench Authors.
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const Command = @import("command.zig").Command;

/// The command whose name is closest to `name`, if it is plausibly a typo.
pub fn suggest(commands: []const Command, name: []const u8) ?[]const u8 {
    var best: ?[]const u8 = null;
    var best_dist: usize = 3;
    for (commands) |c| {
        const d = editDistance(c.name, name);
        if (d < best_dist) {
            best = c.name;
            best_dist = d;
        }
    }
    return best;
}

fn editDistance(a: []const u8, b: []const u8) usize {
    if (a.len > 32 or b.len > 32) return std.math.maxInt(usize);
    var prev: [33]usize = undefined;
    var cur: [33]usize = undefined;
    for (0..b.len + 1) |j| prev[j] = j;
    for (a, 0..) |ca, i| {
        cur[0] = i + 1;
        for (b, 0..) |cb, j| {
            const sub = prev[j] + @intFromBool(ca != cb);
            cur[j + 1] = @min(sub, @min(prev[j + 1] + 1, cur[j] + 1));
        }
        @memcpy(prev[0 .. b.len + 1], cur[0 .. b.len + 1]);
    }
    return prev[b.len];
}

test "suggest the closest command" {
    const noop = struct {
        fn run(_: *@import("command.zig").Context) anyerror!u8 {
            return 0;
        }
    }.run;
    const commands = [_]Command{
        .{ .name = "version", .group = .other, .summary = "", .run = noop },
        .{ .name = "help", .group = .other, .summary = "", .run = noop },
    };
    try std.testing.expectEqualStrings("version", suggest(&commands, "verison").?);
    try std.testing.expectEqual(null, suggest(&commands, "frobnicate"));
}
