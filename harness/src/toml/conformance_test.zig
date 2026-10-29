// Copyright 2026 The Profbench Authors.
// SPDX-License-Identifier: Apache-2.0

//! Runs the toml-test suite (buildtools/toml-test) for TOML 1.1. Every invalid
//! document must be rejected. Every valid document must parse to the expected
//! value, unless it uses a feature the parser deliberately does not support.

const std = @import("std");
const toml = @import("root.zig");
const suite_dir = @import("build_options").toml_test_dir;

test "toml-test 1.1.0" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    var dir = std.Io.Dir.cwd().openDir(io, suite_dir, .{}) catch return error.SkipZigTest;
    defer dir.close(io);
    const list = try dir.readFileAlloc(io, "files-toml-1.1.0", gpa, .limited(1 << 20));
    defer gpa.free(list);

    var passed: usize = 0;
    var skipped: usize = 0;
    var failures: std.ArrayList(u8) = .empty;
    defer failures.deinit(gpa);

    var lines = std.mem.tokenizeScalar(u8, list, '\n');
    while (lines.next()) |path| {
        if (!std.mem.endsWith(u8, path, ".toml")) continue;
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        const a = arena.allocator();
        const source = try dir.readFileAlloc(io, path, a, .limited(1 << 20));
        var diag: toml.Diagnostic = .{};
        const result = toml.parse(a, source, &diag);

        if (std.mem.startsWith(u8, path, "invalid/")) {
            if (result) |_| {
                try appendFailure(gpa, &failures, path, "accepted an invalid document");
            } else |_| passed += 1;
            continue;
        }
        const root = result catch |err| switch (err) {
            error.Unsupported => {
                skipped += 1;
                continue;
            },
            else => {
                try appendFailure(gpa, &failures, path, try std.fmt.allocPrint(
                    a,
                    "rejected a valid document: {d}:{d}: {s}",
                    .{ diag.line, diag.column, diag.message },
                ));
                continue;
            },
        };
        const json_path = try std.mem.concat(a, u8, &.{ path[0 .. path.len - ".toml".len], ".json" });
        const json = try dir.readFileAlloc(io, json_path, a, .limited(1 << 20));
        const expected = try std.json.parseFromSliceLeaky(std.json.Value, a, json, .{});
        if (matches(.{ .table = root }, expected)) {
            passed += 1;
        } else {
            try appendFailure(gpa, &failures, path, "parsed to the wrong value");
        }
    }

    if (failures.items.len > 0) {
        std.debug.print("toml-test 1.1.0: {d} passed, {d} skipped as unsupported, failures:\n{s}", .{
            passed, skipped, failures.items,
        });
        return error.TestUnexpectedResult;
    }
}

fn appendFailure(gpa: std.mem.Allocator, failures: *std.ArrayList(u8), path: []const u8, why: []const u8) !void {
    try failures.print(gpa, "  {s}: {s}\n", .{ path, why });
}

/// Compares a parsed value with toml-test's JSON encoding, in which tables
/// are objects, arrays are arrays, and scalars are {"type": T, "value": S}.
fn matches(v: toml.Value, j: std.json.Value) bool {
    switch (v) {
        .table => |t| {
            if (j != .object or j.object.count() != t.entries.count()) return false;
            var it = t.entries.iterator();
            while (it.next()) |e| {
                const child = j.object.get(e.key_ptr.*) orelse return false;
                if (!matches(e.value_ptr.*, child)) return false;
            }
            return true;
        },
        .array => |a| {
            if (j != .array or j.array.items.len != a.items.items.len) return false;
            for (a.items.items, j.array.items) |item, child| if (!matches(item, child)) return false;
            return true;
        },
        else => {},
    }
    if (j != .object) return false;
    const ty = j.object.get("type") orelse return false;
    const value = j.object.get("value") orelse return false;
    if (ty != .string or value != .string) return false;
    const t = ty.string;
    const s = value.string;
    return switch (v) {
        .string => |x| std.mem.eql(u8, t, "string") and std.mem.eql(u8, x, s),
        .integer => |x| std.mem.eql(u8, t, "integer") and (std.fmt.parseInt(i64, s, 10) catch return false) == x,
        .float => |x| std.mem.eql(u8, t, "float") and floatEql(x, s),
        .boolean => |x| std.mem.eql(u8, t, "bool") and std.mem.eql(u8, s, if (x) "true" else "false"),
        .array, .table => unreachable,
    };
}

fn floatEql(x: f64, s: []const u8) bool {
    const expected = std.fmt.parseFloat(f64, s) catch return false;
    if (std.math.isNan(expected)) return std.math.isNan(x);
    return x == expected;
}
