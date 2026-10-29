// Copyright 2026 The Profbench Authors.
// SPDX-License-Identifier: Apache-2.0

//! Recursive-descent parser over the source bytes. Structure: the document
//! loop, table headers, key/value pairs, then one function per value type,
//! then the cursor helpers and error reporting at the bottom.

const std = @import("std");
const toml = @import("root.zig");
const Allocator = std.mem.Allocator;
const Array = toml.Array;
const Error = toml.Error;
const Table = toml.Table;
const Value = toml.Value;

const Parser = @This();

arena: Allocator,
src: []const u8,
pos: usize = 0,
diag: *toml.Diagnostic,

// Document structure.

pub fn document(p: *Parser) Error!*Table {
    if (!std.unicode.utf8ValidateSlice(p.src)) {
        p.pos = firstInvalidUtf8(p.src);
        return p.fail("invalid UTF-8");
    }
    const root = try p.newTable(.header);
    var current = root;
    while (true) {
        try p.skipBlankLines();
        if (p.atEnd()) return root;
        if (p.peek() == '[') {
            current = try p.tableHeader(root);
            try p.endOfLine("expected a newline after the table header");
        } else {
            try p.keyValue(current);
            try p.endOfLine("expected a newline after the value");
        }
    }
}

/// Parses a [table] or [[array of tables]] header and returns the table that
/// the following key/value pairs belong to.
fn tableHeader(p: *Parser, root: *Table) Error!*Table {
    const start = p.pos;
    p.pos += 1;
    const is_array = p.eat('[');
    p.skipWhitespace();
    const path = try p.key();
    p.skipWhitespace();
    if (!p.eat(']') or (is_array and !p.eat(']'))) {
        return p.fail(if (is_array) "expected ]] to close the header" else "expected ] to close the header");
    }
    const end = p.pos;
    p.pos = start + 1 + @intFromBool(is_array);

    var t = root;
    for (path[0 .. path.len - 1]) |name| t = try p.headerParent(t, name);
    const name = path[path.len - 1];
    const table = if (is_array) try p.appendTableArray(t, name) else try p.defineTable(t, name, path);
    p.pos = end;
    return table;
}

/// Descends into `name` as a parent in a header path such as [name.child].
fn headerParent(p: *Parser, t: *Table, name: []const u8) Error!*Table {
    const gop = try t.entries.getOrPut(p.arena, name);
    if (!gop.found_existing) {
        const child = try p.newTable(.implicit);
        gop.value_ptr.* = .{ .table = child };
        return child;
    }
    switch (gop.value_ptr.*) {
        .table => |child| {
            if (child.origin == .sealed) return p.failFmt("inline table \"{s}\" cannot be extended", .{name});
            return child;
        },
        .array => |a| if (a.of_tables) return a.items.items[a.items.items.len - 1].table,
        else => {},
    }
    return p.failFmt("\"{s}\" is not a table", .{name});
}

fn defineTable(p: *Parser, t: *Table, name: []const u8, path: []const []const u8) Error!*Table {
    const gop = try t.entries.getOrPut(p.arena, name);
    if (!gop.found_existing) {
        const child = try p.newTable(.header);
        gop.value_ptr.* = .{ .table = child };
        return child;
    }
    if (gop.value_ptr.* != .table) return p.failFmt("\"{s}\" is already defined as a value", .{name});
    const child = gop.value_ptr.table;
    switch (child.origin) {
        .implicit => {
            child.origin = .header;
            return child;
        },
        .header => return p.failFmt("table [{s}] is defined twice", .{try p.joinPath(path)}),
        .dotted => return p.failFmt("table [{s}] is already defined by dotted keys", .{try p.joinPath(path)}),
        .sealed => return p.failFmt("inline table \"{s}\" cannot be extended", .{name}),
    }
}

fn appendTableArray(p: *Parser, t: *Table, name: []const u8) Error!*Table {
    const gop = try t.entries.getOrPut(p.arena, name);
    if (!gop.found_existing) {
        const a = try p.arena.create(Array);
        a.* = .{ .of_tables = true };
        gop.value_ptr.* = .{ .array = a };
    } else if (gop.value_ptr.* != .array or !gop.value_ptr.array.of_tables) {
        return p.failFmt("\"{s}\" is not an array of tables", .{name});
    }
    const child = try p.newTable(.header);
    try gop.value_ptr.array.items.append(p.arena, .{ .table = child });
    return child;
}

/// Parses `key = value` into `t`. Dotted keys create intermediate tables.
fn keyValue(p: *Parser, t: *Table) Error!void {
    const start = p.pos;
    const path = try p.key();
    p.skipWhitespace();
    if (!p.eat('=')) return p.fail("expected = after the key");
    p.skipWhitespace();
    const value = try p.parseValue();
    const end = p.pos;
    p.pos = start;

    var target = t;
    for (path[0 .. path.len - 1]) |name| target = try p.dottedParent(target, name);
    const name = path[path.len - 1];
    const gop = try target.entries.getOrPut(p.arena, name);
    if (gop.found_existing) return p.failFmt("duplicate key \"{s}\"", .{name});
    gop.value_ptr.* = value;
    p.pos = end;
}

/// Descends into `name` as a parent in a dotted key such as name.child = 1.
/// Dotted keys may only extend tables that dotted keys created.
fn dottedParent(p: *Parser, t: *Table, name: []const u8) Error!*Table {
    const gop = try t.entries.getOrPut(p.arena, name);
    if (!gop.found_existing) {
        const child = try p.newTable(.dotted);
        gop.value_ptr.* = .{ .table = child };
        return child;
    }
    if (gop.value_ptr.* == .table and gop.value_ptr.table.origin == .dotted) return gop.value_ptr.table;
    return p.failFmt("\"{s}\" is already defined and cannot be extended with dotted keys", .{name});
}

// Keys.

/// A key, split into the parts of a dotted key.
fn key(p: *Parser) Error![]const []const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    while (true) {
        p.skipWhitespace();
        try parts.append(p.arena, try p.simpleKey());
        p.skipWhitespace();
        if (!p.eat('.')) return parts.items;
    }
}

fn simpleKey(p: *Parser) Error![]const u8 {
    if (p.startsWith("\"\"\"") or p.startsWith("'''")) return p.fail("multi-line strings cannot be keys");
    switch (p.peek() orelse return p.fail("expected a key")) {
        '"' => return p.basicString(),
        '\'' => return p.literalString(),
        else => {},
    }
    const start = p.pos;
    while (p.peek()) |c| {
        if (!isBareKeyChar(c)) break;
        p.pos += 1;
    }
    if (p.pos == start) return p.fail("expected a key");
    return p.src[start..p.pos];
}

fn isBareKeyChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '-';
}

// Values.

fn parseValue(p: *Parser) Error!Value {
    const c = p.peek() orelse return p.fail("expected a value");
    return switch (c) {
        '"' => .{ .string = if (p.startsWith("\"\"\"")) try p.multilineBasicString() else try p.basicString() },
        '\'' => .{ .string = if (p.startsWith("'''")) try p.multilineLiteralString() else try p.literalString() },
        '[' => .{ .array = try p.array() },
        '{' => .{ .table = try p.inlineTable() },
        't', 'f' => .{ .boolean = try p.boolean() },
        '0'...'9', '+', '-', 'i', 'n' => p.number(),
        else => p.fail("expected a value"),
    };
}

fn array(p: *Parser) Error!*Array {
    p.pos += 1;
    const a = try p.arena.create(Array);
    a.* = .{};
    while (true) {
        try p.skipBlankLines();
        if (p.eat(']')) return a;
        try a.items.append(p.arena, try p.parseValue());
        try p.skipBlankLines();
        if (p.eat(']')) return a;
        if (!p.eat(',')) return p.fail("expected , or ] after the array element");
    }
}

/// An inline table. TOML 1.1 allows newlines, comments and a trailing comma.
fn inlineTable(p: *Parser) Error!*Table {
    p.pos += 1;
    // Dotted keys inside the table may extend each other until it is closed.
    const t = try p.newTable(.dotted);
    while (true) {
        try p.skipBlankLines();
        if (p.eat('}')) break;
        try p.keyValue(t);
        try p.skipBlankLines();
        if (p.eat('}')) break;
        if (!p.eat(',')) return p.fail("expected , or } after the inline table entry");
    }
    seal(t);
    return t;
}

fn seal(t: *Table) void {
    t.origin = .sealed;
    for (t.entries.values()) |v| if (v == .table) seal(v.table);
}

fn boolean(p: *Parser) Error!bool {
    for ([_]struct { []const u8, bool }{ .{ "true", true }, .{ "false", false } }) |b| {
        if (p.startsWith(b[0]) and !p.isBareKeyCharAt(p.pos + b[0].len)) {
            p.pos += b[0].len;
            return b[1];
        }
    }
    return p.fail("expected a value");
}

fn isBareKeyCharAt(p: *Parser, i: usize) bool {
    return i < p.src.len and isBareKeyChar(p.src[i]);
}

fn number(p: *Parser) Error!Value {
    const start = p.pos;
    while (p.peek()) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '_' or c == '+' or c == '-' or c == '.' or c == ':')) break;
        p.pos += 1;
    }
    const text = p.src[start..p.pos];
    p.pos = start;
    if (looksLikeDateOrTime(text)) return p.unsupported("dates and times are not supported");
    if (text.len > 1 and text[0] == '0' and (text[1] == 'x' or text[1] == 'o' or text[1] == 'b')) {
        return p.unsupported("hexadecimal, octal and binary integers are not supported");
    }

    const value: ?Value = if (isDecimalInteger(text))
        if (std.fmt.parseInt(i64, try p.withoutUnderscores(text), 10)) |i| .{ .integer = i } else |_| null
    else if (isFloat(text))
        .{ .float = std.fmt.parseFloat(f64, try p.withoutUnderscores(text)) catch unreachable }
    else
        null;
    if (value) |v| {
        p.pos = start + text.len;
        return v;
    }
    if (isDecimalInteger(text)) return p.failFmt("integer {s} is out of range", .{text});
    if (std.mem.eql(u8, text, "") or std.mem.eql(u8, text, "+") or std.mem.eql(u8, text, "-")) {
        return p.fail("expected a value");
    }
    if (!std.ascii.isDigit(text[0]) and !std.ascii.isDigit(text[@min(1, text.len - 1)]) and
        std.mem.indexOf(u8, text, "inf") == null and std.mem.indexOf(u8, text, "nan") == null)
    {
        return p.fail("expected a value");
    }
    return p.failFmt("invalid number \"{s}\"", .{text});
}

fn withoutUnderscores(p: *Parser, text: []const u8) Error![]const u8 {
    return std.mem.replaceOwned(u8, p.arena, text, "_", "");
}

/// A date (1979-05-27) or a time (07:32), which TOML values otherwise never
/// start with.
fn looksLikeDateOrTime(text: []const u8) bool {
    const digits = std.mem.indexOfNone(u8, text, "0123456789") orelse text.len;
    if (digits == text.len) return false;
    return (digits == 4 and text[digits] == '-') or (digits == 2 and text[digits] == ':');
}

/// [+-]? and then 0 or a non-zero digit followed by digits, with single
/// underscores allowed between digits.
fn isDecimalInteger(text: []const u8) bool {
    const s = stripSign(text);
    if (s.len == 0) return false;
    if (s[0] == '0') return s.len == 1;
    return digitRun(s, 0) == s.len;
}

/// An integer part as above, then a fraction, an exponent, or both; or
/// [+-]?inf and [+-]?nan.
fn isFloat(text: []const u8) bool {
    const s = stripSign(text);
    if (std.mem.eql(u8, s, "inf") or std.mem.eql(u8, s, "nan")) return true;
    const int_end = digitRun(s, 0) orelse return false;
    if (s[0] == '0' and int_end != 1) return false;
    var i = int_end;
    var has_fraction_or_exponent = false;
    if (i < s.len and s[i] == '.') {
        i = digitRun(s, i + 1) orelse return false;
        has_fraction_or_exponent = true;
    }
    if (i < s.len and (s[i] == 'e' or s[i] == 'E')) {
        i += 1;
        if (i < s.len and (s[i] == '+' or s[i] == '-')) i += 1;
        i = digitRun(s, i) orelse return false;
        has_fraction_or_exponent = true;
    }
    return has_fraction_or_exponent and i == s.len;
}

fn stripSign(text: []const u8) []const u8 {
    return if (text.len > 0 and (text[0] == '+' or text[0] == '-')) text[1..] else text;
}

/// The end of a run of digits starting at `start`, with single underscores
/// allowed between digits, or null if there is no valid run.
fn digitRun(s: []const u8, start: usize) ?usize {
    var i = start;
    if (i >= s.len or !std.ascii.isDigit(s[i])) return null;
    while (i < s.len) : (i += 1) {
        if (std.ascii.isDigit(s[i])) continue;
        if (s[i] == '_' and i + 1 < s.len and std.ascii.isDigit(s[i + 1])) continue;
        break;
    }
    return i;
}

// Strings.

fn basicString(p: *Parser) Error![]const u8 {
    p.pos += 1;
    var out: std.ArrayList(u8) = .empty;
    while (true) {
        const c = p.peek() orelse return p.fail("unterminated string");
        switch (c) {
            '"' => {
                p.pos += 1;
                return out.items;
            },
            '\n', '\r' => return p.fail("unterminated string"),
            '\\' => {
                p.pos += 1;
                try p.escape(&out);
            },
            else => {
                if (isControl(c)) return p.fail("control characters must be escaped");
                try out.append(p.arena, c);
                p.pos += 1;
            },
        }
    }
}

fn multilineBasicString(p: *Parser) Error![]const u8 {
    p.pos += 3;
    _ = p.eatNewline();
    var out: std.ArrayList(u8) = .empty;
    while (true) {
        if (try p.closeMultiline('"', &out)) return out.items;
        const c = p.peek() orelse return p.fail("unterminated string");
        if (c == '\\') {
            p.pos += 1;
            // A backslash ending a line trims it and any whitespace after it.
            const after = p.pos;
            p.skipWhitespace();
            if (p.eatNewline()) {
                while (true) {
                    p.skipWhitespace();
                    if (!p.eatNewline()) break;
                }
            } else {
                p.pos = after;
                try p.escape(&out);
            }
        } else {
            try p.multilineChar(&out);
        }
    }
}

fn literalString(p: *Parser) Error![]const u8 {
    p.pos += 1;
    const start = p.pos;
    while (true) {
        const c = p.peek() orelse return p.fail("unterminated string");
        if (c == '\'') {
            p.pos += 1;
            return p.src[start .. p.pos - 1];
        }
        if (c == '\n' or c == '\r') return p.fail("unterminated string");
        if (isControl(c)) return p.fail("control characters are not allowed in literal strings");
        p.pos += 1;
    }
}

fn multilineLiteralString(p: *Parser) Error![]const u8 {
    p.pos += 3;
    _ = p.eatNewline();
    var out: std.ArrayList(u8) = .empty;
    while (true) {
        if (try p.closeMultiline('\'', &out)) return out.items;
        if (p.atEnd()) return p.fail("unterminated string");
        try p.multilineChar(&out);
    }
}

/// Handles a run of quotes in a multi-line string. Up to two quotes may sit
/// directly before the closing delimiter, so a run of three to five ends the
/// string. Returns whether it ended.
fn closeMultiline(p: *Parser, quote: u8, out: *std.ArrayList(u8)) Error!bool {
    var n: usize = 0;
    while (p.pos + n < p.src.len and p.src[p.pos + n] == quote) n += 1;
    if (n < 3) {
        try out.appendNTimes(p.arena, quote, n);
        p.pos += n;
        return false;
    }
    if (n > 5) return p.fail("too many quotes at the end of a multi-line string");
    try out.appendNTimes(p.arena, quote, n - 3);
    p.pos += n;
    return true;
}

/// A character in a multi-line string body. Newlines are kept, as \n.
fn multilineChar(p: *Parser, out: *std.ArrayList(u8)) Error!void {
    if (p.eatNewline()) return out.append(p.arena, '\n');
    const c = p.peek().?;
    if (isControl(c)) return p.fail("control characters must be escaped");
    try out.append(p.arena, c);
    p.pos += 1;
}

fn escape(p: *Parser, out: *std.ArrayList(u8)) Error!void {
    const start = p.pos - 1;
    const c = p.peek() orelse return p.fail("unterminated string");
    p.pos += 1;
    const simple: ?u8 = switch (c) {
        'b' => 0x08,
        't' => '\t',
        'n' => '\n',
        'f' => 0x0c,
        'r' => '\r',
        'e' => 0x1b,
        '"' => '"',
        '\\' => '\\',
        else => null,
    };
    if (simple) |b| return out.append(p.arena, b);
    const digits: usize = switch (c) {
        'x' => 2,
        'u' => 4,
        'U' => 8,
        else => {
            p.pos = start;
            return p.fail("invalid escape sequence");
        },
    };
    const hex = if (p.pos + digits <= p.src.len) p.src[p.pos..][0..digits] else "";
    const cp = std.fmt.parseInt(u21, hex, 16) catch null;
    if (hex.len != digits or std.mem.indexOfAny(u8, hex, "+-_") != null or cp == null) {
        p.pos = start;
        return p.fail("invalid escape sequence");
    }
    var buf: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(cp.?, &buf) catch {
        p.pos = start;
        return p.fail("escape is not a Unicode scalar value");
    };
    try out.appendSlice(p.arena, buf[0..n]);
    p.pos += digits;
}

/// Control characters other than tab, which strings and comments may not
/// contain literally.
fn isControl(c: u8) bool {
    return (c < 0x20 and c != '\t') or c == 0x7f;
}

// Cursor helpers.

fn newTable(p: *Parser, origin: Table.Origin) Error!*Table {
    const t = try p.arena.create(Table);
    t.* = .{ .origin = origin };
    return t;
}

fn joinPath(p: *Parser, path: []const []const u8) Error![]const u8 {
    return std.mem.join(p.arena, ".", path);
}

fn atEnd(p: *Parser) bool {
    return p.pos >= p.src.len;
}

fn peek(p: *Parser) ?u8 {
    return if (p.atEnd()) null else p.src[p.pos];
}

fn eat(p: *Parser, c: u8) bool {
    if (p.peek() != c) return false;
    p.pos += 1;
    return true;
}

fn startsWith(p: *Parser, s: []const u8) bool {
    return std.mem.startsWith(u8, p.src[p.pos..], s);
}

fn eatNewline(p: *Parser) bool {
    if (p.eat('\n')) return true;
    if (!p.startsWith("\r\n")) return false;
    p.pos += 2;
    return true;
}

fn skipWhitespace(p: *Parser) void {
    while (p.peek()) |c| {
        if (c != ' ' and c != '\t') break;
        p.pos += 1;
    }
}

fn skipComment(p: *Parser) Error!void {
    if (!p.eat('#')) return;
    while (p.peek()) |c| {
        if (c == '\n' or (c == '\r' and p.startsWith("\r\n"))) return;
        if (isControl(c)) return p.fail("control characters are not allowed in comments");
        p.pos += 1;
    }
}

/// Skips whitespace, comments and newlines.
fn skipBlankLines(p: *Parser) Error!void {
    while (true) {
        p.skipWhitespace();
        try p.skipComment();
        if (!p.eatNewline()) break;
    }
    if (p.peek() == '\r') return p.fail("carriage return must be followed by a newline");
}

fn endOfLine(p: *Parser, message: []const u8) Error!void {
    p.skipWhitespace();
    try p.skipComment();
    if (!p.atEnd() and !p.eatNewline()) return p.fail(message);
}

// Errors.

fn fail(p: *Parser, message: []const u8) Error {
    p.locate();
    p.diag.message = message;
    return error.Syntax;
}

fn failFmt(p: *Parser, comptime fmt: []const u8, args: anytype) Error {
    p.locate();
    p.diag.message = try std.fmt.allocPrint(p.arena, fmt, args);
    return error.Syntax;
}

fn unsupported(p: *Parser, message: []const u8) Error {
    p.locate();
    p.diag.message = message;
    return error.Unsupported;
}

fn locate(p: *Parser) void {
    const before = p.src[0..@min(p.pos, p.src.len)];
    const line_start = if (std.mem.lastIndexOfScalar(u8, before, '\n')) |i| i + 1 else 0;
    p.diag.line = std.mem.count(u8, before, "\n") + 1;
    p.diag.column = before.len - line_start + 1;
}

fn firstInvalidUtf8(s: []const u8) usize {
    var i: usize = 0;
    while (i < s.len) {
        const n = std.unicode.utf8ByteSequenceLength(s[i]) catch return i;
        if (i + n > s.len) return i;
        _ = std.unicode.utf8Decode(s[i..][0..n]) catch return i;
        i += n;
    }
    return s.len;
}
