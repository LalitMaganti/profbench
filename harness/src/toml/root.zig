// Copyright 2026 The Profbench Authors.
// SPDX-License-Identifier: Apache-2.0

//! A TOML 1.1 parser for the subset profbench uses. Everything except dates,
//! times and non-decimal integers is supported, including the rules against
//! redefining tables; those features are rejected with error.Unsupported.

const std = @import("std");
const Parser = @import("Parser.zig");

pub const Value = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    array: *Array,
    table: *Table,
};

pub const Array = struct {
    items: std.ArrayList(Value) = .empty,
    /// Created by [[header]]s. Only these can be extended by more headers.
    of_tables: bool = false,
};

pub const Table = struct {
    entries: std.StringArrayHashMapUnmanaged(Value) = .empty,
    /// How the table came to exist, which decides how it may be extended.
    origin: Origin,

    pub const Origin = enum {
        /// Created as a parent of a [header]; may later get its own header.
        implicit,
        /// Defined by a [header] or [[header]], or the root table.
        header,
        /// Created by a dotted key such as a.b = 1.
        dotted,
        /// An inline table, or a table nested in one. Cannot be extended.
        sealed,
    };

    pub fn get(t: *const Table, key: []const u8) ?Value {
        return t.entries.get(key);
    }
};

pub const Diagnostic = struct {
    line: usize = 0,
    column: usize = 0,
    message: []const u8 = "",
};

pub const Error = error{ Syntax, Unsupported, OutOfMemory };

/// Parses `source` into its root table. Everything is allocated in `arena`,
/// which owns the result. On error, `diag` says what went wrong and where.
pub fn parse(arena: std.mem.Allocator, source: []const u8, diag: *Diagnostic) Error!*Table {
    var p: Parser = .{ .arena = arena, .src = source, .diag = diag };
    return p.document();
}

const testing = std.testing;

fn expectFailure(expected: Error, source: []const u8, line: usize, column: usize, message: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    try testing.expectError(expected, parse(arena.allocator(), source, &diag));
    try testing.expectEqualStrings(message, diag.message);
    try testing.expectEqual(line, diag.line);
    try testing.expectEqual(column, diag.column);
}

test "a profiler entry" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const root = try parse(arena.allocator(),
        \\# Metadata about the tool.
        \\[profiler]
        \\name = "mytool"   # trailing comment
        \\description = """
        \\Records kernel and \
        \\    userspace activity."""
        \\
        \\[questions]
        \\cpu-time = [
        \\  "sampling-fp",    # comments inside arrays
        \\  "sampling-dwarf",
        \\]
        \\
        \\[methods.sampling-fp]
        \\record = 'perf record -o {trace_dir}/perf.data -- {workload}'
        \\env = { PERF_PAGER = "cat", "quoted key" = 1, }
        \\requires.kernel.min = 5.15
        \\
        \\[[check]]
        \\tag = "a"
        \\[[check]]
        \\tag = "b"
        \\
    , &diag);
    const profiler = root.get("profiler").?.table;
    try testing.expectEqualStrings("mytool", profiler.get("name").?.string);
    try testing.expectEqualStrings("Records kernel and userspace activity.", profiler.get("description").?.string);

    const methods = root.get("questions").?.table.get("cpu-time").?.array.items.items;
    try testing.expectEqual(2, methods.len);
    try testing.expectEqualStrings("sampling-dwarf", methods[1].string);

    const m = root.get("methods").?.table.get("sampling-fp").?.table;
    try testing.expectEqualStrings("perf record -o {trace_dir}/perf.data -- {workload}", m.get("record").?.string);
    try testing.expectEqual(1, m.get("env").?.table.get("quoted key").?.integer);
    try testing.expectEqual(5.15, m.get("requires").?.table.get("kernel").?.table.get("min").?.float);

    const checks = root.get("check").?.array.items.items;
    try testing.expectEqual(2, checks.len);
    try testing.expectEqualStrings("b", checks[1].table.get("tag").?.string);
}

test "scalars" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const root = try parse(arena.allocator(),
        \\int = -1_000
        \\zero = +0
        \\float = 6.626e-34
        \\neg-inf = -inf
        \\yes = true
        \\escapes = "tab\t quote\" e\u00e9 \x41 \e"
        \\literal = 'C:\no\escapes'
        \\quotes = """two "" quotes"""
        \\
    , &diag);
    try testing.expectEqual(-1000, root.get("int").?.integer);
    try testing.expectEqual(0, root.get("zero").?.integer);
    try testing.expectEqual(6.626e-34, root.get("float").?.float);
    try testing.expect(std.math.isNegativeInf(root.get("neg-inf").?.float));
    try testing.expect(root.get("yes").?.boolean);
    try testing.expectEqualStrings("tab\t quote\" e\u{e9} A \x1b", root.get("escapes").?.string);
    try testing.expectEqualStrings("C:\\no\\escapes", root.get("literal").?.string);
    try testing.expectEqualStrings("two \"\" quotes", root.get("quotes").?.string);
}

test "errors say what and where" {
    try expectFailure(error.Syntax, "a = 1\na = 2\n", 2, 1, "duplicate key \"a\"");
    try expectFailure(error.Syntax, "a = \"open\n", 1, 10, "unterminated string");
    try expectFailure(error.Syntax, "\n\nb = nope\n", 3, 5, "expected a value");
    try expectFailure(error.Syntax, "x = 1 y = 2\n", 1, 7, "expected a newline after the value");
    try expectFailure(error.Syntax, "n = 01\n", 1, 5, "invalid number \"01\"");
    try expectFailure(error.Syntax, "[a]\n[a]\n", 2, 2, "table [a] is defined twice");
    try expectFailure(error.Syntax, "a.b = 1\n[a]\n", 2, 2, "table [a] is already defined by dotted keys");
    try expectFailure(error.Syntax, "t = {}\n[t.x]\n", 2, 2, "inline table \"t\" cannot be extended");
    try expectFailure(error.Syntax, "a = [1]\n[[a]]\n", 2, 3, "\"a\" is not an array of tables");
    try expectFailure(error.Unsupported, "d = 1979-05-27\n", 1, 5, "dates and times are not supported");
    try expectFailure(error.Unsupported, "h = 0xff\n", 1, 5, "hexadecimal, octal and binary integers are not supported");
}

test {
    _ = Parser;
}
