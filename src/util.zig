const std = @import("std");

/// CP437 code points for bytes 0x80..0xFF. Kept for compatibility; the
/// German letters used by Hexuma (0x94=ö, 0x81=ü, 0x84=ä, 0xE1=ß) are the
/// same in CP437 and CP850. No ISO-8859-1 conversion is performed.
const cp437_high = [_]u21{ 0x00c7, 0x00fc, 0x00e9, 0x00e2, 0x00e4, 0x00e0, 0x00e5, 0x00e7, 0x00ea, 0x00eb, 0x00e8, 0x00ef, 0x00ee, 0x00ec, 0x00c4, 0x00c5, 0x00c9, 0x00e6, 0x00c6, 0x00f4, 0x00f6, 0x00f2, 0x00fb, 0x00f9, 0x00ff, 0x00d6, 0x00dc, 0x00a2, 0x00a3, 0x00a5, 0x20a7, 0x0192, 0x00e1, 0x00ed, 0x00f3, 0x00fa, 0x00f1, 0x00d1, 0x00aa, 0x00ba, 0x00bf, 0x2310, 0x00ac, 0x00bd, 0x00bc, 0x00a1, 0x00ab, 0x00bb, 0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556, 0x2555, 0x2563, 0x2551, 0x2557, 0x255d, 0x255c, 0x255b, 0x2510, 0x2514, 0x2534, 0x252c, 0x251c, 0x2500, 0x253c, 0x255e, 0x255f, 0x255a, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256c, 0x2567, 0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256b, 0x256a, 0x2518, 0x250c, 0x2588, 0x2584, 0x258c, 0x2590, 0x2580, 0x03b1, 0x00df, 0x0393, 0x03c0, 0x03a3, 0x03c3, 0x00b5, 0x03c4, 0x03a6, 0x0398, 0x03a9, 0x03b4, 0x221e, 0x03c6, 0x03b5, 0x2229, 0x2261, 0x00b1, 0x2265, 0x2264, 0x2320, 0x2321, 0x00f7, 0x2248, 0x00b0, 0x2219, 0x00b7, 0x221a, 0x207f, 0x00b2, 0x25a0, 0x00a0 };

/// CP850 code points for bytes 0x80..0xFF. REA disassembly of the original
/// TEXT*.REL dispatcher proves CP850 (`stored byte + 0x14`, then CP850 glyphs).
const cp850_high = [_]u21{
    0x00c7, 0x00fc, 0x00e9, 0x00e2, 0x00e4, 0x00e0, 0x00e5, 0x00e7, 0x00ea, 0x00eb, 0x00e8, 0x00ef, 0x00ee, 0x00ec, 0x00c4, 0x00c5,
    0x00c9, 0x00e6, 0x00c6, 0x00f4, 0x00f6, 0x00f2, 0x00fb, 0x00f9, 0x00ff, 0x00d6, 0x00dc, 0x00f8, 0x00a3, 0x00d8, 0x00d7, 0x0192,
    0x00e1, 0x00ed, 0x00f3, 0x00fa, 0x00f1, 0x00d1, 0x00aa, 0x00ba, 0x00bf, 0x00ae, 0x00ac, 0x00bd, 0x00bc, 0x00a1, 0x00ab, 0x00bb,
    0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x00c1, 0x00c2, 0x00c0, 0x00a9, 0x2563, 0x2551, 0x2557, 0x255d, 0x00a2, 0x00a5, 0x2510,
    0x2514, 0x2534, 0x252c, 0x251c, 0x2500, 0x253c, 0x00e3, 0x00c3, 0x255a, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256c, 0x00a4,
    0x00f0, 0x00d0, 0x00ca, 0x00cb, 0x00c8, 0x0131, 0x00cd, 0x00ce, 0x00cf, 0x2518, 0x250c, 0x2588, 0x2584, 0x00a6, 0x00cc, 0x2580,
    0x00d3, 0x00df, 0x00d4, 0x00d2, 0x00f5, 0x00d5, 0x00b5, 0x00fe, 0x00de, 0x00da, 0x00db, 0x00d9, 0x00fd, 0x00dd, 0x00af, 0x00b4,
    0x00ad, 0x00b1, 0x2017, 0x00be, 0x00b6, 0x00a7, 0x00f7, 0x00b8, 0x00b0, 0x00a8, 0x00b7, 0x00b9, 0x00b3, 0x00b2, 0x25a0, 0x00a0,
};

/// Write a JSON string literal (including quotes), escaping control bytes.
pub fn jsonString(w: anytype, s: []const u8) !void {
    try w.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try w.print("\\u{x:0>4}", .{c});
                } else {
                    try w.writeByte(c);
                }
            },
        }
    }
    try w.writeByte('"');
}

fn appendCodepoint(out: *std.ArrayList(u8), allocator: std.mem.Allocator, cp: u21) !void {
    if (cp < 0x80) {
        try out.append(allocator, @intCast(cp));
    } else if (cp < 0x800) {
        try out.append(allocator, @intCast(0xc0 | (cp >> 6)));
        try out.append(allocator, @intCast(0x80 | (cp & 0x3f)));
    } else if (cp < 0x10000) {
        try out.append(allocator, @intCast(0xe0 | (cp >> 12)));
        try out.append(allocator, @intCast(0x80 | ((cp >> 6) & 0x3f)));
        try out.append(allocator, @intCast(0x80 | (cp & 0x3f)));
    } else {
        try out.append(allocator, @intCast(0xf0 | (cp >> 18)));
        try out.append(allocator, @intCast(0x80 | ((cp >> 12) & 0x3f)));
        try out.append(allocator, @intCast(0x80 | ((cp >> 6) & 0x3f)));
        try out.append(allocator, @intCast(0x80 | (cp & 0x3f)));
    }
}

/// Convert original CP437 asset bytes to UTF-8.
pub fn cp437ToUtf8(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (s) |c| {
        const cp: u21 = if (c < 0x80) c else cp437_high[c - 0x80];
        try appendCodepoint(&out, allocator, cp);
    }
    return out.toOwnedSlice(allocator);
}

/// Convert CP850 asset bytes to UTF-8.
pub fn cp850ToUtf8(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (s) |c| {
        const cp: u21 = if (c < 0x80) c else cp850_high[c - 0x80];
        try appendCodepoint(&out, allocator, cp);
    }
    return out.toOwnedSlice(allocator);
}

/// Backwards-compatible name used by older extractor code.
pub fn latin1ToUtf8(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    return cp437ToUtf8(allocator, s);
}

pub fn hexByte(w: anytype, b: u8) !void {
    const digits = "0123456789abcdef";
    try w.writeByte(digits[b >> 4]);
    try w.writeByte(digits[b & 0xf]);
}

pub fn hexBytes(w: anytype, bytes: []const u8) !void {
    for (bytes) |b| try hexByte(w, b);
}

pub fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024 * 1024);
}

pub fn writeFile(path: []const u8, bytes: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        if (dir.len > 0) try std.fs.cwd().makePath(dir);
    }
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    try f.writeAll(bytes);
}

pub fn join(allocator: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    return std.fs.path.join(allocator, parts);
}

pub fn baseNameNoExt(name: []const u8) []const u8 {
    return std.fs.path.stem(name);
}
