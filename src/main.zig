const std = @import("std");
const util = @import("util.zig");
const formats = @import("formats.zig");
const png = @import("png.zig");
const wav = @import("wav.zig");
const lua_rt = @import("lua_runtime.zig");
const locale_data = @import("locale_data.zig");
const engine = @import("engine.zig");
const ui_x11 = @import("ui_x11.zig");

const VERSION = "hexuma-zig 0.1.0";

fn sha256Hex(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const digits = "0123456789abcdef";
    var out: [64]u8 = undefined;
    for (digest, 0..) |b, i| {
        out[i * 2] = digits[b >> 4];
        out[i * 2 + 1] = digits[b & 0xf];
    }
    return out;
}

fn isText(bytes: []const u8) bool {
    if (bytes.len == 0) return false;
    var printable: usize = 0;
    for (bytes) |c| {
        // 0x1a is the traditional DOS end-of-file marker used by the .SEQ
        // text tables in this game.
        if (c == '\r' or c == '\n' or c == '\t' or c == 0x1a) continue;
        if (c < 0x20) return false;
        printable += 1;
    }
    return printable * 4 >= bytes.len;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn listInputFiles(allocator: std.mem.Allocator, dir_path: []const u8) ![][]const u8 {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();
    var names = std.ArrayList([]const u8).empty;
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        try names.append(allocator, try allocator.dupe(u8, entry.name));
    }
    std.mem.sort([]const u8, names.items, {}, lessThan);
    return names.toOwnedSlice(allocator);
}

const Manifest = struct {
    lines: std.ArrayList([]const u8) = .empty,
    allocator: std.mem.Allocator,

    fn add(self: *Manifest, source: []const u8, data: []const u8, kind: []const u8, detail: []const u8, output: ?[]const u8) !void {
        var buf = std.ArrayList(u8).empty;
        const w = buf.writer(self.allocator);
        try w.writeAll("  {");
        try w.writeAll("\"source\":");
        try util.jsonString(w, source);
        try w.writeAll(",\"size\":");
        try w.print("{d}", .{data.len});
        try w.writeAll(",\"sha256\":");
        const hashbuf: [64]u8 = sha256Hex(data);
        try util.jsonString(w, &hashbuf);
        try w.writeAll(",\"kind\":");
        try util.jsonString(w, kind);
        try w.writeAll(",\"detail\":");
        try w.writeAll(detail);
        if (output) |o| {
            try w.writeAll(",\"output\":");
            try util.jsonString(w, o);
        }
        try w.writeAll("}");
        try self.lines.append(self.allocator, try buf.toOwnedSlice(self.allocator));
    }

    fn write(self: *Manifest, path: []const u8) !void {
        var buf = std.ArrayList(u8).empty;
        const w = buf.writer(self.allocator);
        try w.writeAll("{\n  \"generator\":");
        try util.jsonString(w, VERSION);
        try w.writeAll(",\n  \"files\":[\n");
        for (self.lines.items, 0..) |line, i| {
            try w.writeAll(line);
            try w.writeAll(if (i + 1 == self.lines.items.len) "\n" else ",\n");
        }
        try w.writeAll("  ]\n}\n");
        try util.writeFile(path, buf.items);
    }
};

fn detailSeq(allocator: std.mem.Allocator, img: formats.SeqImage) ![]const u8 {
    var b = std.ArrayList(u8).empty;
    const w = b.writer(allocator);
    try w.print("{{\"format\":\"seq\",\"layout\":\"{s}\",\"width\":{d},\"height\":{d}", .{
        @tagName(img.kind), img.width, img.height,
    });
    if (img.logical_width > 0) try w.print(",\"logical_width\":{d},\"logical_height\":{d}", .{ img.logical_width, img.logical_height });
    if (img.palette != null) try w.writeAll(",\"palette\":\"vga256-rgbx\"");
    try w.writeAll(",\"marker\":\"");
    try util.hexBytes(w, img.marker);
    try w.writeAll("\"}");
    return b.toOwnedSlice(allocator);
}

fn writeSeqText(allocator: std.mem.Allocator, name: []const u8, bytes: []const u8, out_dir: []const u8, manifest: *Manifest) !void {
    const utf8 = try util.latin1ToUtf8(allocator, bytes);
    const text = std.mem.trimRight(u8, utf8, "\x1a");
    const stem = util.baseNameNoExt(name);
    const path = try util.join(allocator, &.{ out_dir, "data", "text", try std.fmt.allocPrint(allocator, "{s}.json", .{stem}) });
    var b = std.ArrayList(u8).empty;
    const w = b.writer(allocator);
    try w.writeAll("{\n  \"source\":");
    try util.jsonString(w, name);
    try w.writeAll(",\n  \"text\":");
    try util.jsonString(w, text);
    try w.writeAll(",\n  \"lines\":[\n");
    var it = std.mem.splitScalar(u8, text, '\n');
    var first = true;
    while (it.next()) |line0| {
        const line = std.mem.trimRight(u8, line0, "\r");
        if (line.len == 0) continue;
        if (!first) try w.writeAll(",\n");
        first = false;
        try w.writeAll("    ");
        try util.jsonString(w, line);
    }
    try w.writeAll("\n  ]\n}\n");
    try util.writeFile(path, b.items);
    try manifest.add(name, bytes, "text", "{\"format\":\"dos-latin1-text\"}", try allocator.dupe(u8, path));
}

fn writePng(allocator: std.mem.Allocator, name: []const u8, bytes: []const u8, img: formats.SeqImage, out_dir: []const u8, global_palette: []const u8, manifest: *Manifest) !void {
    const palette = img.palette orelse global_palette;
    const encoded = try png.encodeIndexed(allocator, img.width, img.height, img.pixels, palette);
    const stem = util.baseNameNoExt(name);
    const rel = try std.fmt.allocPrint(allocator, "images/{s}.png", .{stem});
    const path = try util.join(allocator, &.{ out_dir, rel });
    try util.writeFile(path, encoded);

    // The X11 frontend uses this uncompressed sibling: "HXRAW2" + u16 x
    // + u16 y + u16 width + u16 height + BGRA pixels. FR frames store their
    // blit origin in the first two header words; backgrounds are drawn at 0,0.
    var raw = std.ArrayList(u8).empty;
    const w = raw.writer(allocator);
    try w.writeAll("HXRAW2");
    try w.writeInt(u16, @intCast(img.logical_width), .little);
    try w.writeInt(u16, @intCast(img.logical_height), .little);
    try w.writeInt(u16, @intCast(img.width), .little);
    try w.writeInt(u16, @intCast(img.height), .little);
    for (img.pixels) |index| {
        const p: usize = @as(usize, index) * 4;
        if (p + 2 < palette.len) {
            try w.writeByte(palette[p + 2]);
            try w.writeByte(palette[p + 1]);
            try w.writeByte(palette[p]);
        } else {
            try w.writeByte(0);
            try w.writeByte(0);
            try w.writeByte(0);
        }
        try w.writeByte(0xff);
    }
    const raw_rel = try std.fmt.allocPrint(allocator, "images/{s}.raw", .{stem});
    try util.writeFile(try util.join(allocator, &.{ out_dir, raw_rel }), raw.items);

    try manifest.add(name, bytes, "image", try detailSeq(allocator, img), rel);
}

fn writeAudio(allocator: std.mem.Allocator, name: []const u8, bytes: []const u8, aws: formats.Aws, out_dir: []const u8, manifest: *Manifest) !void {
    const encoded = try wav.encodePcm8(allocator, aws.samples, 8000);
    const stem = util.baseNameNoExt(name);
    const rel = try std.fmt.allocPrint(allocator, "audio/{s}.wav", .{stem});
    const path = try util.join(allocator, &.{ out_dir, rel });
    try util.writeFile(path, encoded);
    const detail = try std.fmt.allocPrint(allocator, "{{\"format\":\"aws\",\"header\":\"AUDIOS WAVE SLAVE PC\",\"sample_rate_hz\":8000,\"sample_rate_inferred\":true,\"samples\":{d},\"header_field_20\":{d},\"flags\":{d}}}", .{ aws.samples.len, aws.field20, aws.flags });
    try manifest.add(name, bytes, "audio", detail, rel);
}

fn writeU16Table(allocator: std.mem.Allocator, name: []const u8, bytes: []const u8, out_dir: []const u8, manifest: *Manifest, signed: bool) !void {
    const stem = util.baseNameNoExt(name);
    const rel = try std.fmt.allocPrint(allocator, "data/tables/{s}.json", .{stem});
    const path = try util.join(allocator, &.{ out_dir, rel });
    var b = std.ArrayList(u8).empty;
    const w = b.writer(allocator);
    try w.writeAll("{\n  \"source\":");
    try util.jsonString(w, name);
    try w.writeAll(",\n  \"encoding\":");
    try util.jsonString(w, if (signed) "i16-le-array" else "u16-le-array");
    try w.writeAll(",\n  \"count\":");
    try w.print("{d}", .{bytes.len / 2});
    try w.writeAll(",\n  \"values\":[");
    var i: usize = 0;
    while (i + 1 < bytes.len) : (i += 2) {
        if (i > 0) try w.writeByte(',');
        const v = std.mem.readInt(u16, bytes[i..][0..2], .little);
        if (signed) {
            try w.print("{d}", .{@as(i16, @bitCast(v))});
        } else {
            try w.print("{d}", .{v});
        }
    }
    try w.writeAll("]\n}\n");
    try util.writeFile(path, b.items);
    const detail = try std.fmt.allocPrint(allocator, "{{\"format\":\"binary-table\",\"entries\":{d}}}", .{bytes.len / 2});
    try manifest.add(name, bytes, "data", detail, rel);
}

fn writeHexRecords(allocator: std.mem.Allocator, name: []const u8, bytes: []const u8, record_len: usize, out_dir: []const u8, manifest: *Manifest, kind: []const u8) !void {
    const stem = util.baseNameNoExt(name);
    const rel = try std.fmt.allocPrint(allocator, "data/tables/{s}.json", .{stem});
    const path = try util.join(allocator, &.{ out_dir, rel });
    var b = std.ArrayList(u8).empty;
    const w = b.writer(allocator);
    try w.writeAll("{\n  \"source\":");
    try util.jsonString(w, name);
    try w.print(",\n  \"record_length\":{d},\n  \"records\":[", .{record_len});
    var i: usize = 0;
    while (i < bytes.len) : (i += record_len) {
        if (i > 0) try w.writeByte(',');
        try w.writeByte('"');
        try util.hexBytes(w, bytes[i..@min(i + record_len, bytes.len)]);
        try w.writeByte('"');
    }
    try w.writeAll("]\n}\n");
    try util.writeFile(path, b.items);
    const detail = try std.fmt.allocPrint(allocator, "{{\"format\":\"fixed-records\",\"record_length\":{d},\"records\":{d}}}", .{ record_len, bytes.len / record_len });
    try manifest.add(name, bytes, kind, detail, rel);
}

fn writeStringsJson(allocator: std.mem.Allocator, source: []const u8, strings: []const formats.ExtractedString, out_path: []const u8) !void {
    var b = std.ArrayList(u8).empty;
    const w = b.writer(allocator);
    try w.writeAll("{\n  \"source\":");
    try util.jsonString(w, source);
    try w.writeAll(",\n  \"strings\":[\n");
    for (strings, 0..) |s, i| {
        if (i > 0) try w.writeAll(",\n");
        try w.print("    {{\"offset\":{d},\"text\":", .{s.offset});
        try util.jsonString(w, s.text);
        try w.writeByte('}');
    }
    try w.writeAll("\n  ]\n}\n");
    try util.writeFile(out_path, b.items);
}

fn luaQuote(w: anytype, s: []const u8) !void {
    try util.jsonString(w, s); // JSON and Lua string escapes agree for these cases.
}

fn writeLuaModules(allocator: std.mem.Allocator, out_dir: []const u8, images: []const ImageInfo, dialogue: []const formats.ExtractedString, verbs: ?[]const u8, config: ?[]const u8) !void {
    const base = try util.join(allocator, &.{ out_dir, "lua" });

    // assets.lua - every decoded image, ready for a Lua-driven scene graph.
    {
        var b = std.ArrayList(u8).empty;
        const w = b.writer(allocator);
        try w.writeAll("-- Generated by hexuma extract. Asset registry for the rewritten engine.\n");
        try w.writeAll("local M = {}\nM.images = {\n");
        for (images) |img| {
            try w.print("  {s} = {{ width = {d}, height = {d}, layout = ", .{ img.lua_key, img.width, img.height });
            try luaQuote(w, img.layout);
            try w.writeAll(", path = ");
            try luaQuote(w, img.rel_path);
            try w.writeAll(" },\n");
        }
        try w.writeAll("}\nfunction M.get(name) return M.images[name] end\nreturn M\n");
        try util.writeFile(try util.join(allocator, &.{ base, "assets.lua" }), b.items);
    }

    // dialogue.lua - original German strings recovered from the overlay/text.
    {
        var b = std.ArrayList(u8).empty;
        const w = b.writer(allocator);
        try w.writeAll("-- Original dialogue text recovered from HEXUMA.OVR / TEXT*.REL.\n");
        try w.writeAll("-- Strings are data, not executable game logic.\n");
        try w.writeAll("return {\n");
        for (dialogue, 0..) |s, i| {
            try w.print("  [{d}] = {{ offset = 0x{x}, text = ", .{ i + 1, s.offset });
            try luaQuote(w, s.text);
            try w.writeAll(" },\n");
        }
        try w.writeAll("}\n");
        try util.writeFile(try util.join(allocator, &.{ base, "dialogue.lua" }), b.items);
    }

    // verbs.lua - the German verb table from VERBEN.SEQ.
    {
        var b = std.ArrayList(u8).empty;
        const w = b.writer(allocator);
        try w.writeAll("-- Verb table extracted from VERBEN.SEQ (name / id pairs).\nreturn {\n");
        if (verbs) |v| {
            var lines = std.mem.splitScalar(u8, v, '\n');
            var idx: usize = 0;
            while (lines.next()) |line0| {
                const line = std.mem.trim(u8, line0, "\r\x1a");
                if (line.len == 0) continue;
                idx += 1;
                if (idx % 2 == 1) {
                    const utf8 = try util.latin1ToUtf8(allocator, line);
                    try w.print("  {{ name = ", .{});
                    try luaQuote(w, utf8);
                } else {
                    try w.print(", id = {s} }},\n", .{line});
                }
            }
        }
        try w.writeAll("}\n");
        try util.writeFile(try util.join(allocator, &.{ base, "verbs.lua" }), b.items);
    }

    // config.lua - VOREIN.SEQ defaults.
    {
        var b = std.ArrayList(u8).empty;
        const w = b.writer(allocator);
        try w.writeAll("-- Defaults extracted from VOREIN.SEQ.\nreturn {\n  raw = ");
        if (config) |cfg| try luaQuote(w, cfg) else try w.writeAll("nil");
        try w.writeAll(",\n}\n");
        try util.writeFile(try util.join(allocator, &.{ base, "config.lua" }), b.items);
    }

    // locale.lua - authored English labels plus the original German side.
    {
        var b = std.ArrayList(u8).empty;
        const w = b.writer(allocator);
        try w.writeAll("-- German/English labels. German comes from the shipped tables;\n");
        try w.writeAll("-- English is authored because the original has no English release.\n");
        try w.writeAll("return {\n  verbs = {\n");
        for (locale_data.verb_labels) |pair| {
            try w.writeAll("    { de = ");
            try luaQuote(w, pair.de);
            try w.writeAll(", en = ");
            try luaQuote(w, pair.en);
            try w.writeAll(" },\n");
        }
        try w.writeAll("  },\n  nouns = {\n");
        for (locale_data.noun_labels) |pair| {
            try w.writeAll("    { de = ");
            try luaQuote(w, pair.de);
            try w.writeAll(", en = ");
            try luaQuote(w, pair.en);
            try w.writeAll(" },\n");
        }
        try w.writeAll("  },\n  ui = {\n");
        for (locale_data.ui_labels) |pair| {
            try w.writeAll("    { de = ");
            try luaQuote(w, pair.de);
            try w.writeAll(", en = ");
            try luaQuote(w, pair.en);
            try w.writeAll(" },\n");
        }
        try w.writeAll("  },\n}\n");
        try util.writeFile(try util.join(allocator, &.{ base, "locale.lua" }), b.items);
    }

    // init.lua - entry point for `hexuma run`.
    {
        const content =
            \\-- Hexuma rewritten engine entry point. Game logic lives in Lua.
            \\local assets = require("assets")
            \\local dialogue = require("dialogue")
            \\local verbs = require("verbs")
            \\local game = require("game")
            \\local texts = require("texts")
            \\local locale = require("locale")
            \\
            \\local M = {}
            \\
            \\function M.main()
            \\  hexuma.log("hexuma-zig Lua runtime ready")
            \\  local count = 0
            \\  for _ in pairs(assets.images) do count = count + 1 end
            \\  local verb_count = 0
            \\  for _ in pairs(game.verbs) do verb_count = verb_count + 1 end
            \\  local noun_count = 0
            \\  for _ in pairs(game.vocabulary) do noun_count = noun_count + 1 end
            \\  hexuma.log("decoded images: " .. count)
            \\  hexuma.log("dialogue strings: " .. #dialogue)
            \\  local text_count = 0
            \\  for _ in pairs(texts) do text_count = text_count + 1 end
            \\  hexuma.log("TEXT records: " .. text_count)
            \\  hexuma.log("verbs: " .. verb_count .. " / vocabulary: " .. noun_count)
            \\  hexuma.log("locale labels: " .. #locale.verbs .. " verbs")
            \\  return count, #dialogue, verb_count
            \\end
            \\
            \\M.main()
            \\return M
            \\
        ;
        try util.writeFile(try util.join(allocator, &.{ base, "init.lua" }), content);
    }
}

const ImageInfo = struct {
    lua_key: []const u8,
    rel_path: []const u8,
    width: u32,
    height: u32,
    layout: []const u8,
};

fn luaKey(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    // Lua identifiers must be alphanumeric/underscore and cannot start with
    // a digit. Original asset names contain dots and occasionally punctuation.
    const stem = if (std.mem.indexOfScalar(u8, name, '.')) |i| name[0..i] else name;
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    if (stem.len > 0 and std.ascii.isDigit(stem[0])) try out.append(allocator, '_');
    for (stem) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '_') {
            try out.append(allocator, c);
        } else {
            try out.append(allocator, '_');
        }
    }
    return out.toOwnedSlice(allocator);
}

fn readInputOptional(allocator: std.mem.Allocator, input: []const u8, name: []const u8) ?[]const u8 {
    const path = util.join(allocator, &.{ input, name }) catch return null;
    return util.readFile(allocator, path) catch null;
}

fn textLines(allocator: std.mem.Allocator, bytes: []const u8) ![][]const u8 {
    var lines = std.ArrayList([]const u8).empty;
    var it = std.mem.splitScalar(u8, bytes, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, "\r\x1a");
        if (line.len == 0) continue;
        try lines.append(allocator, try allocator.dupe(u8, line));
    }
    return lines.toOwnedSlice(allocator);
}

fn i16At(bytes: []const u8, byte_offset: usize) i16 {
    if (byte_offset + 2 > bytes.len) return 0;
    return std.mem.readInt(i16, bytes[byte_offset..][0..2], .little);
}

fn u16At(bytes: []const u8, byte_offset: usize) u16 {
    if (byte_offset + 2 > bytes.len) return 0;
    return std.mem.readInt(u16, bytes[byte_offset..][0..2], .little);
}

/// Emit a semantic, locale-independent game-data layer from the original
/// binary tables. The raw tables remain available verbatim as JSON for audit.
/// TEXT*.REL records are selected by a 1-based id decoded from OBNWOR*.BIN.
/// Returns the file and zero-based record inside that file.
const TextRef = struct { file: []const u8, record: usize };

fn textRef(value: u16) TextRef {
    const v: i64 = value;
    if (v == 0) return .{ .file = "", .record = 0 };
    const t = v - 1;
    const bounds = [_]struct { limit: i64, file: []const u8, sub: i64 }{
        .{ .limit = 0x9c3f, .file = "TEXT10.REL", .sub = 0x9c41 },
        .{ .limit = 0x88b7, .file = "TEXT9.REL", .sub = 0x88b9 },
        .{ .limit = 0x752f, .file = "TEXT8.REL", .sub = 0x7531 },
        .{ .limit = 0x61a7, .file = "TEXT5.REL", .sub = 0x61a9 },
        .{ .limit = 0x4e1f, .file = "TEXT7.REL", .sub = 0x4e1f },
        .{ .limit = 0x3a97, .file = "TEXT4.REL", .sub = 0x3a98 },
        .{ .limit = 0x270f, .file = "TEXT3.REL", .sub = 0x2710 },
        .{ .limit = 0x1387, .file = "TEXT2.REL", .sub = 0x1388 },
    };
    for (bounds) |b| {
        if (t > b.limit) {
            return .{ .file = b.file, .record = @intCast(t - b.sub) };
        }
    }
    return .{ .file = "TEXT1.REL", .record = @intCast(t) };
}

fn decodeTextRecord(allocator: std.mem.Allocator, bytes: []const u8, ref: TextRef) ![]const u8 {
    if (bytes.len == 0 or ref.file.len == 0) return "";
    const rec_len: usize = 0x4d;
    const off = ref.record * rec_len;
    if (off + rec_len > bytes.len) return "";
    const n = bytes[off];
    if (n == 0 or n > rec_len - 1) return "";
    var raw = try allocator.alloc(u8, n);
    for (bytes[off + 1 .. off + 1 + n], 0..) |b, i| {
        var c = b +% 0x14;
        if (c == 0x2f) c = 0x20;
        raw[i] = c;
    }
    var text = try util.cp850ToUtf8(allocator, raw);
    if (std.mem.indexOfScalar(u8, text, '@')) |at| text = text[0..at];
    return std.mem.trimRight(u8, text, " ");
}

fn writeTexts(allocator: std.mem.Allocator, input: []const u8, output: []const u8, manifest: *Manifest) !void {
    const files = [_][]const u8{ "TEXT1.REL", "TEXT2.REL", "TEXT3.REL", "TEXT4.REL", "TEXT5.REL", "TEXT7.REL", "TEXT8.REL", "TEXT9.REL", "TEXT10.REL" };
    var json = std.ArrayList(u8).empty;
    const jw = json.writer(allocator);
    var lua = std.ArrayList(u8).empty;
    const lw = lua.writer(allocator);
    try jw.writeAll("{\n  \"texts\": [\n");
    try lw.writeAll("-- Decoded TEXT*.REL resource strings, keyed by original 1-based text id.\nreturn {\n");
    var first = true;
    for (files) |name| {
        const bytes = readInputOptional(allocator, input, name) orelse continue;
        const count = bytes.len / 0x4d;
        var rec: usize = 0;
        while (rec < count) : (rec += 1) {
            const ref = textRefFromRecord(name, rec);
            const text = try decodeTextRecord(allocator, bytes, .{ .file = name, .record = rec });
            if (text.len == 0) continue;
            if (!first) try jw.writeAll(",\n");
            first = false;
            try jw.print("    {{\"id\":{d},\"file\":", .{ref});
            try util.jsonString(jw, name);
            try jw.print(",\"record\":{d},\"text\":", .{rec});
            try util.jsonString(jw, text);
            try jw.writeByte('}');
            try lw.print("  [{d}] = ", .{ref});
            try luaQuote(lw, text);
            try lw.writeAll(",\n");
        }
    }
    try jw.writeAll("\n  ]\n}\n");
    try lw.writeAll("}\n");
    const json_rel = "data/texts.json";
    const lua_rel = "lua/texts.lua";
    try util.writeFile(try util.join(allocator, &.{ output, json_rel }), json.items);
    try util.writeFile(try util.join(allocator, &.{ output, lua_rel }), lua.items);
    try manifest.add("derived:texts", json.items, "data", "{\"format\":\"decoded-text-rel\"}", json_rel);
}

/// Rea-derived in-code message pools. Each pointer is a far
/// `segment:offset` pair passed to the original string-copy helper at
/// `FUN_3a97_0644`; the bytes at the pointer are packed Pascal strings.
/// Mapping from a far pointer to an EXE file offset uses the MZ load module
/// base observed for HEXPRG.EXE: file_offset = segment * 16 + offset - 0x9a00.
const CodeStringPool = struct {
    name: []const u8,
    segment: u16,
    offset: u16,
    limit: usize,
};

const code_string_pools = [_]CodeStringPool{
    .{ .name = "take", .segment = 0x1755, .offset = 0x1fab, .limit = 8 },
    .{ .name = "parser", .segment = 0x1755, .offset = 0x22a5, .limit = 8 },
    .{ .name = "examine", .segment = 0x1755, .offset = 0x262b, .limit = 14 },
    .{ .name = "move", .segment = 0x1b27, .offset = 0x0000, .limit = 6 },
    .{ .name = "door", .segment = 0x1755, .offset = 0x0de0, .limit = 25 },
    .{ .name = "ignite", .segment = 0x1755, .offset = 0x1f6a, .limit = 1 },
    .{ .name = "openclose", .segment = 0x1755, .offset = 0x312e, .limit = 6 },
    .{ .name = "drop", .segment = 0x1755, .offset = 0x225a, .limit = 2 },
    .{ .name = "inventory", .segment = 0x1755, .offset = 0x2e61, .limit = 6 },
};

fn decodeCodeStrings(allocator: std.mem.Allocator, exe: []const u8, pool: CodeStringPool) ![]const []const u8 {
    const linear: usize = @as(usize, pool.segment) * 16 + pool.offset;
    if (linear < 0x9a00) return &.{};
    var pos = linear - 0x9a00;
    var out = std.ArrayList([]const u8).empty;
    var n: usize = 0;
    while (n < pool.limit) : (n += 1) {
        if (pos >= exe.len) break;
        const len = exe[pos];
        if (len == 0 or len > 120 or pos + 1 + len > exe.len) break;
        const raw = exe[pos + 1 .. pos + 1 + len];
        var valid = true;
        for (raw) |c| {
            if (c < 0x20 or c == 0x7f) {
                valid = false;
                break;
            }
        }
        if (!valid) break;
        try out.append(allocator, try util.cp850ToUtf8(allocator, raw));
        pos += 1 + len;
    }
    return out.toOwnedSlice(allocator);
}

fn writeCodeStrings(allocator: std.mem.Allocator, input: []const u8, output: []const u8, manifest: *Manifest) !void {
    const exe = readInputOptional(allocator, input, "HEXPRG.EXE") orelse return;
    if (exe.len < 0x40 or !std.mem.eql(u8, exe[0..2], "MZ")) return;

    var json = std.ArrayList(u8).empty;
    const jw = json.writer(allocator);
    var lua = std.ArrayList(u8).empty;
    const lw = lua.writer(allocator);
    try jw.writeAll("{\n  \"source\":\"HEXPRG.EXE\",\n  \"pointer_mapping\":\"segment * 16 + offset - 0x9a00\",\n  \"pools\":[\n");
    try lw.writeAll("-- REA-derived in-code message pools from HEXPRG.EXE.\nreturn {\n");
    var first_pool = true;
    for (code_string_pools) |pool| {
        const messages = try decodeCodeStrings(allocator, exe, pool);
        if (messages.len == 0) continue;
        if (!first_pool) try jw.writeAll(",\n");
        first_pool = false;
        try jw.print("    {{\"name\":", .{});
        try util.jsonString(jw, pool.name);
        try jw.print(",\"segment\":{d},\"offset\":{d},\"messages\":[", .{ pool.segment, pool.offset });
        try lw.print("  {s} = {{\n", .{pool.name});
        for (messages, 0..) |msg, i| {
            if (i > 0) try jw.writeByte(',');
            try jw.print("\n      {{\"key\":", .{});
            const key = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ pool.name, i });
            try util.jsonString(jw, key);
            try jw.writeAll(",\"text\":");
            try util.jsonString(jw, msg);
            try jw.writeByte('}');
            try lw.print("    [{d}] = ", .{i});
            try luaQuote(lw, msg);
            try lw.writeAll(",\n");
        }
        try jw.writeAll("\n    ]}");
        try lw.writeAll("  },\n");
    }
    try jw.writeAll("\n  ]\n}\n");
    try lw.writeAll("}\n");
    const json_rel = "data/code_strings.json";
    const lua_rel = "lua/code_strings.lua";
    try util.writeFile(try util.join(allocator, &.{ output, json_rel }), json.items);
    try util.writeFile(try util.join(allocator, &.{ output, lua_rel }), lua.items);
    try manifest.add("derived:code-strings", json.items, "data", "{\"format\":\"rea-derived-in-code-messages\"}", json_rel);
}

/// OBLISTE.BIN holds 256 u16 room offsets. At each offset the original
/// room-change loader (0x23c4e) reads a u16 count and then count+1 Pascal
/// strings into the six 101-byte command slots at 0x7d8e. Pressing ';' opens
/// that command menu (0x21971), so these are the game's own alternative to
/// typing a sentence.
fn decodeActionMenu(allocator: std.mem.Allocator, bytes: []const u8) ![]const []const []const u8 {
    if (bytes.len < 512) return &.{};
    var rooms = std.ArrayList([]const []const u8).empty;
    var room_i: usize = 0;
    while (room_i < 256) : (room_i += 1) {
        const off = u16At(bytes, room_i * 2);
        if (off + 2 > bytes.len) {
            try rooms.append(allocator, &.{});
            continue;
        }
        const count: usize = u16At(bytes, off);
        var pos = off + 2;
        var actions = std.ArrayList([]const u8).empty;
        var n: usize = 0;
        while (n <= count and pos + 2 <= bytes.len) : (n += 1) {
            const len = bytes[pos];
            pos += 1;
            if (len == 0 or pos + 1 + len > bytes.len) break;
            if (bytes[pos] != len) break; // the stored Pascal string repeats its length
            pos += 1;
            actions.append(allocator, try util.cp437ToUtf8(allocator, bytes[pos .. pos + len])) catch break;
            pos += len;
        }
        try rooms.append(allocator, try actions.toOwnedSlice(allocator));
    }
    return rooms.toOwnedSlice(allocator);
}

fn writeActionMenu(allocator: std.mem.Allocator, input: []const u8, output: []const u8, manifest: *Manifest) !void {
    const bytes = readInputOptional(allocator, input, "OBLISTE.BIN") orelse return;
    const rooms = try decodeActionMenu(allocator, bytes);
    var json = std.ArrayList(u8).empty;
    const jw = json.writer(allocator);
    var lua = std.ArrayList(u8).empty;
    const lw = lua.writer(allocator);
    try jw.writeAll("{\n  \"source\":\"OBLISTE.BIN\",\n  \"rooms\":[\n");
    try lw.writeAll("-- Original room command menus from OBLISTE.BIN.\nreturn {\n");
    var first = true;
    for (rooms, 0..) |actions, room_i| {
        if (actions.len == 0) continue;
        if (!first) try jw.writeAll(",\n");
        first = false;
        try jw.print("    {{\"room\":{d},\"actions\":[", .{room_i});
        try lw.print("  [{d}] = {{\n", .{room_i});
        for (actions, 0..) |action, i| {
            if (i > 0) try jw.writeByte(',');
            try util.jsonString(jw, action);
            try lw.print("    [{d}] = ", .{i});
            try luaQuote(lw, action);
            try lw.writeAll(",\n");
        }
        try jw.writeAll("]}");
        try lw.writeAll("  },\n");
    }
    try jw.writeAll("\n  ]\n}\n");
    try lw.writeAll("}\n");
    const json_rel = "data/action_menu.json";
    const lua_rel = "lua/action_menu.lua";
    try util.writeFile(try util.join(allocator, &.{ output, json_rel }), json.items);
    try util.writeFile(try util.join(allocator, &.{ output, lua_rel }), lua.items);
    try manifest.add("derived:action-menu", json.items, "data", "{\"format\":\"original-room-command-menu\"}", json_rel);
}

/// REA decoded the 57 conditional FR frames selected by the BILD loader at
/// 0x2bffd. Their filename table lives in HEXPRG.EXE at 0x22349 and the
/// condition chain is emitted as structured expressions in src/data/overlays.json.
fn writeOverlays(allocator: std.mem.Allocator, output: []const u8, manifest: *Manifest) !void {
    // The room-action rules are generated once from the REA decompilations and
    // live with the other derived data. Embed them so a fresh extract from the
    // original game directory is sufficient to play with full room actions.
    const rules = @embedFile("data/overlay_rules.json");
    const rules_rel = "data/overlay_rules.json";
    try util.writeFile(try util.join(allocator, &.{ output, rules_rel }), rules);
    try manifest.add("derived:overlay-rules", rules, "data", "{\"format\":\"rea-room-action-rules\"}", rules_rel);

    const table = @embedFile("data/overlays.json");
    const rel = "data/overlays.json";
    try util.writeFile(try util.join(allocator, &.{ output, rel }), table);
    try manifest.add("derived:conditional-overlays", table, "data", "{\"format\":\"rea-scene-overlay-table\",\"frames\":57}", rel);

    const initial = @embedFile("data/initial_flags.json");
    const initial_rel = "data/initial_flags.json";
    try util.writeFile(try util.join(allocator, &.{ output, initial_rel }), initial);
    try manifest.add("derived:initial-flags", initial, "data", "{\"format\":\"rea-startup-globals\",\"source\":\"0x10b17\"}", initial_rel);

    const vors = @embedFile("data/vors_overrides.json");
    const vors_rel = "data/vors_overrides.json";
    try util.writeFile(try util.join(allocator, &.{ output, vors_rel }), vors);
    try manifest.add("derived:vors-overrides", vors, "data", "{\"format\":\"rea-runtime-label-overrides\",\"source\":\"0x2408d\"}", vors_rel);

    const counts = @embedFile("data/vors_records.json");
    const counts_rel = "data/vors_records.json";
    try util.writeFile(try util.join(allocator, &.{ output, counts_rel }), counts);
    try manifest.add("derived:vors-record-counts", counts, "data", "{\"format\":\"vors-slot-counts\",\"source\":\"VORS.BIN\"}", counts_rel);
}

/// Inverse of `textRef`: the original id that selects this record.
fn textRefFromRecord(name: []const u8, record: usize) i64 {
    const sub: i64 = if (std.mem.eql(u8, name, "TEXT1.REL")) 0 else if (std.mem.eql(u8, name, "TEXT2.REL")) 0x1388 else if (std.mem.eql(u8, name, "TEXT3.REL")) 0x2710 else if (std.mem.eql(u8, name, "TEXT4.REL")) 0x3a98 else if (std.mem.eql(u8, name, "TEXT5.REL")) 0x61a9 else if (std.mem.eql(u8, name, "TEXT7.REL")) 0x4e1f else if (std.mem.eql(u8, name, "TEXT8.REL")) 0x7531 else if (std.mem.eql(u8, name, "TEXT9.REL")) 0x88b9 else if (std.mem.eql(u8, name, "TEXT10.REL")) 0x9c41 else 0;
    return sub + 1 + @as(i64, @intCast(record));
}

fn writeVocabJson(allocator: std.mem.Allocator, w: anytype, lines: []const []const u8, ints: []const u8, byts: []const u8, words: []const u8, source: []const u8) !void {
    var group: i64 = 0;
    var first = true;
    for (lines, 0..) |raw_word, i| {
        if (std.mem.eql(u8, raw_word, "ende")) {
            group += 1;
            continue;
        }
        if (!first) try w.writeAll(",\n");
        first = false;
        const utf8 = try util.cp850ToUtf8(allocator, raw_word);
        try w.print("    {{\"id\":{d},\"index\":{d},\"word\":", .{ i + 1, i });
        try util.jsonString(w, utf8);
        try w.print(",\"source\":", .{});
        try util.jsonString(w, source);
        try w.print(",\"group\":{d},\"prop\":{d},\"room_gate\":{d},\"class\":{d},\"text_a\":{d},\"text_b\":{d}}}", .{
            group,
            i16At(ints, i * 4),
            i16At(ints, i * 4 + 2),
            if (i < byts.len) byts[i] else 0,
            u16At(words, i * 4),
            u16At(words, i * 4 + 2),
        });
    }
}

fn writeVocabLua(allocator: std.mem.Allocator, w: anytype, lines: []const []const u8, ints: []const u8, byts: []const u8, words: []const u8, source: []const u8) !void {
    var group: i64 = 0;
    for (lines, 0..) |raw_word, i| {
        if (std.mem.eql(u8, raw_word, "ende")) {
            group += 1;
            continue;
        }
        const utf8 = try util.cp850ToUtf8(allocator, raw_word);
        try w.print("    [{d}] = {{ id = {d}, word = ", .{ i, i + 1 });
        try luaQuote(w, utf8);
        try w.print(", source = ", .{});
        try luaQuote(w, source);
        try w.print(", group = {d}, prop = {d}, room_gate = {d}, class = {d}, text_a = {d}, text_b = {d} }},\n", .{
            group,
            i16At(ints, i * 4),
            i16At(ints, i * 4 + 2),
            if (i < byts.len) byts[i] else 0,
            u16At(words, i * 4),
            u16At(words, i * 4 + 2),
        });
    }
}

fn writeGameData(allocator: std.mem.Allocator, input: []const u8, output: []const u8, manifest: *Manifest) !void {
    const land = readInputOptional(allocator, input, "LAND.BIN") orelse &.{};
    const obw_raw = readInputOptional(allocator, input, "OBW.SEQ") orelse &.{};
    const verben_raw = readInputOptional(allocator, input, "VERBEN.SEQ") orelse &.{};
    const bilddat_raw = readInputOptional(allocator, input, "BILDDAT.SEQ") orelse &.{};
    const obnint = readInputOptional(allocator, input, "OBNINT.BIN") orelse &.{};
    const obnbyt = readInputOptional(allocator, input, "OBNBYT.BIN") orelse &.{};
    const obnwor = readInputOptional(allocator, input, "OBNWOR.BIN") orelse &.{};
    const obw5_raw = readInputOptional(allocator, input, "OBW5.SEQ") orelse &.{};
    const obnint5 = readInputOptional(allocator, input, "OBNINT5.BIN") orelse &.{};
    const obnbyt5 = readInputOptional(allocator, input, "OBNBYT5.BIN") orelse &.{};
    const obnwor5 = readInputOptional(allocator, input, "OBNWOR5.BIN") orelse &.{};
    const obw6_raw = readInputOptional(allocator, input, "OBW6.SEQ") orelse &.{};
    const obnint6 = readInputOptional(allocator, input, "OBNINT6.BIN") orelse &.{};
    const obnbyt6 = readInputOptional(allocator, input, "OBNBYT6.BIN") orelse &.{};
    const obnwor6 = readInputOptional(allocator, input, "OBNWOR6.BIN") orelse &.{};
    const vors = readInputOptional(allocator, input, "VORS.BIN") orelse &.{};

    const obw_lines = try textLines(allocator, obw_raw);
    const obw5_lines = try textLines(allocator, obw5_raw);
    const obw6_lines = try textLines(allocator, obw6_raw);
    const verben_lines = try textLines(allocator, verben_raw);
    const bild_lines = try textLines(allocator, bilddat_raw);

    const json_rel = "data/game.json";
    const lua_rel = "lua/game.lua";
    const json_path = try util.join(allocator, &.{ output, json_rel });
    const lua_path = try util.join(allocator, &.{ output, lua_rel });

    var jb = std.ArrayList(u8).empty;
    const jw = jb.writer(allocator);
    try jw.writeAll("{\n  \"version\": 1,\n  \"description\": \"Semantic game data derived from the original Hexuma tables\",\n  \"start_room\": 1,\n  \"rooms\": [\n");
    var room_i: usize = 0;
    while (room_i + 1 < land.len) : (room_i += 14) {
        if (room_i > 0) try jw.writeAll(",\n");
        try jw.print("    {{\"id\":{d},\"exits\":{{\"north\":{d},\"south\":{d},\"east\":{d},\"west\":{d},\"up\":{d},\"down\":{d}}}}}", .{
            i16At(land, room_i),
            i16At(land, room_i + 2),
            i16At(land, room_i + 4),
            i16At(land, room_i + 6),
            i16At(land, room_i + 8),
            i16At(land, room_i + 10),
            i16At(land, room_i + 12),
        });
    }
    try jw.writeAll("\n  ],\n  \"verbs\": [\n");
    var verb_i: usize = 0;
    while (verb_i + 1 < verben_lines.len) : (verb_i += 2) {
        if (verb_i > 0) try jw.writeAll(",\n");
        const utf8 = try util.cp437ToUtf8(allocator, verben_lines[verb_i]);
        const id = std.fmt.parseInt(i64, verben_lines[verb_i + 1], 10) catch 0;
        try jw.writeAll("    {\"name\":");
        try util.jsonString(jw, utf8);
        try jw.print(",\"id\":{d}}}", .{id});
    }
    try jw.writeAll("\n  ],\n  \"vocabulary\": [\n");
    try writeVocabJson(allocator, jw, obw_lines, obnint, obnbyt, obnwor, "base");
    try jw.writeAll("\n  ],\n  \"vocabulary_5\": [\n");
    try writeVocabJson(allocator, jw, obw5_lines, obnint5, obnbyt5, obnwor5, "s5");
    try jw.writeAll("\n  ],\n  \"vocabulary_6\": [\n");
    try writeVocabJson(allocator, jw, obw6_lines, obnint6, obnbyt6, obnwor6, "s6");
    try jw.writeAll("\n  ],\n  \"pictures\": [\n");
    for (bild_lines, 0..) |line, pic_i| {
        if (pic_i > 0) try jw.writeAll(",\n");
        try jw.print("    {{\"index\":{d},\"value\":{d}}}", .{ pic_i, std.fmt.parseInt(i64, line, 10) catch 0 });
    }
    try jw.writeAll("\n  ],\n  \"click_regions\": [\n");
    var region_first = true;
    // VORS.BIN is 171 records of 0x377 bytes. Records 1..170 contain 15
    // (x1,y1,x2,y2) rectangles followed by 15 51-byte Pascal strings.
    const vors_record_len: usize = 0x377;
    var screen_i: usize = 1;
    while (screen_i * vors_record_len + vors_record_len <= vors.len) : (screen_i += 1) {
        const base = screen_i * vors_record_len;
        const count_raw = u16At(vors, base);
        const count: usize = if (count_raw > 14) 1 else count_raw;
        var slot_i: usize = 0;
        while (slot_i < count) : (slot_i += 1) {
            const rect_off = base + 2 + slot_i * 8;
            const x1 = i16At(vors, rect_off);
            const y1 = i16At(vors, rect_off + 2);
            const x2 = i16At(vors, rect_off + 4);
            const y2 = i16At(vors, rect_off + 6);
            if (x2 <= x1 or y2 <= y1) continue;
            const str_off = base + 0x7a + slot_i * 0x33;
            if (str_off >= vors.len) continue;
            const len = vors[str_off];
            if (len > 50 or str_off + 1 + len > vors.len) continue;
            // Keep length-zero and one-space Pascal strings. The original
            // runtime clears and overwrites slots by index, so an initially
            // blank slot can later become a real command.
            const action = try util.cp437ToUtf8(allocator, vors[str_off + 1 .. str_off + 1 + len]);
            if (!region_first) try jw.writeAll(",\n");
            region_first = false;
            try jw.print("    {{\"screen\":{d},\"slot\":{d},\"x1\":{d},\"y1\":{d},\"x2\":{d},\"y2\":{d},\"action\":", .{ screen_i, slot_i, x1, y1, x2, y2 });
            try util.jsonString(jw, action);
            try jw.writeByte('}');
        }
    }
    try jw.writeAll("\n  ]\n}\n");
    try util.writeFile(json_path, jb.items);
    try manifest.add("derived:game-data", jb.items, "data", "{\"format\":\"semantic-game-data\",\"rooms\":240}", json_rel);

    var lb = std.ArrayList(u8).empty;
    const lw = lb.writer(allocator);
    try lw.writeAll("-- Semantic game data derived from the original Hexuma binary tables.\n");
    try lw.writeAll("-- Generated by hexuma extract; the raw tables remain in data/tables/.\n");
    try lw.writeAll("return {\n  version = 1,\n  start_room = 1,\n  rooms = {\n");
    room_i = 0;
    while (room_i + 1 < land.len) : (room_i += 14) {
        const id = i16At(land, room_i);
        try lw.print("    [{d}] = {{ id = {d}, north = {d}, south = {d}, east = {d}, west = {d}, up = {d}, down = {d} }},\n", .{
            id,                       id,
            i16At(land, room_i + 2),  i16At(land, room_i + 4),
            i16At(land, room_i + 6),  i16At(land, room_i + 8),
            i16At(land, room_i + 10), i16At(land, room_i + 12),
        });
    }
    try lw.writeAll("  },\n  verbs = {\n");
    verb_i = 0;
    while (verb_i + 1 < verben_lines.len) : (verb_i += 2) {
        const utf8 = try util.cp437ToUtf8(allocator, verben_lines[verb_i]);
        try lw.writeAll("    { name = ");
        try luaQuote(lw, utf8);
        try lw.print(", id = {s} }},\n", .{verben_lines[verb_i + 1]});
    }
    try lw.writeAll("  },\n  vocabulary = {\n");
    try writeVocabLua(allocator, lw, obw_lines, obnint, obnbyt, obnwor, "base");
    try lw.writeAll("  },\n  vocabulary_5 = {\n");
    try writeVocabLua(allocator, lw, obw5_lines, obnint5, obnbyt5, obnwor5, "s5");
    try lw.writeAll("  },\n  vocabulary_6 = {\n");
    try writeVocabLua(allocator, lw, obw6_lines, obnint6, obnbyt6, obnwor6, "s6");
    try lw.writeAll("  },\n  pictures = {\n");
    for (bild_lines, 0..) |line, pic_i| {
        try lw.print("    [{d}] = {s},\n", .{ pic_i, line });
    }
    try lw.writeAll("  },\n  click_regions = {\n");
    screen_i = 1;
    while (screen_i * vors_record_len + vors_record_len <= vors.len) : (screen_i += 1) {
        const base = screen_i * vors_record_len;
        const count_raw = u16At(vors, base);
        const count: usize = if (count_raw > 14) 1 else count_raw;
        var slot_i: usize = 0;
        while (slot_i < count) : (slot_i += 1) {
            const rect_off = base + 2 + slot_i * 8;
            const x1 = i16At(vors, rect_off);
            const y1 = i16At(vors, rect_off + 2);
            const x2 = i16At(vors, rect_off + 4);
            const y2 = i16At(vors, rect_off + 6);
            if (x2 <= x1 or y2 <= y1) continue;
            const str_off = base + 0x7a + slot_i * 0x33;
            if (str_off >= vors.len) continue;
            const len = vors[str_off];
            if (len > 50 or str_off + 1 + len > vors.len) continue;
            const action = try util.cp437ToUtf8(allocator, vors[str_off + 1 .. str_off + 1 + len]);
            try lw.print("    {{ screen = {d}, slot = {d}, x1 = {d}, y1 = {d}, x2 = {d}, y2 = {d}, action = ", .{ screen_i, slot_i, x1, y1, x2, y2 });
            try luaQuote(lw, action);
            try lw.writeAll(" },\n");
        }
    }
    try lw.writeAll("  },\n}\n");
    try util.writeFile(lua_path, lb.items);
    try manifest.add("derived:game-data-lua", lb.items, "data", "{\"format\":\"lua-module\"}", lua_rel);
}

fn extract(allocator: std.mem.Allocator, input: []const u8, output: []const u8) !void {
    var manifest = Manifest{ .allocator = allocator };
    const names = try listInputFiles(allocator, input);
    var images = std.ArrayList(ImageInfo).empty;
    var audio_count: usize = 0;
    var dialogue = std.ArrayList(formats.ExtractedString).empty;
    var verbs: ?[]const u8 = null;
    var config: ?[]const u8 = null;
    var global_palette: ?[]const u8 = null;

    // A stable global palette for palette-less FR/INTFR/MENUEFR frames.
    for (names) |name| {
        if (!std.ascii.eqlIgnoreCase(std.fs.path.extension(name), ".seq")) continue;
        const path = try util.join(allocator, &.{ input, name });
        const bytes = util.readFile(allocator, path) catch continue;
        if (formats.decodeSeq(bytes)) |img| {
            if (img.palette) |p| {
                global_palette = p;
                break;
            }
        }
    }
    const fallback_palette = [_]u8{0} ** 1024;
    const palette = global_palette orelse &fallback_palette;

    for (names) |name| {
        const path = try util.join(allocator, &.{ input, name });
        const bytes = util.readFile(allocator, path) catch {
            std.debug.print("skip unreadable: {s}\n", .{name});
            continue;
        };
        const ext = std.fs.path.extension(name);

        if (std.ascii.eqlIgnoreCase(ext, ".seq")) {
            if (formats.decodeSeq(bytes)) |img| {
                try writePng(allocator, name, bytes, img, output, palette, &manifest);
                try images.append(allocator, .{
                    .lua_key = try luaKey(allocator, name),
                    .rel_path = try std.fmt.allocPrint(allocator, "images/{s}.png", .{util.baseNameNoExt(name)}),
                    .width = img.width,
                    .height = img.height,
                    .layout = @tagName(img.kind),
                });
            } else if (isText(bytes)) {
                try writeSeqText(allocator, name, bytes, output, &manifest);
                if (std.ascii.eqlIgnoreCase(name, "VERBEN.SEQ")) verbs = bytes;
                if (std.ascii.eqlIgnoreCase(name, "VOREIN.SEQ")) {
                    const cfg_utf8 = try util.latin1ToUtf8(allocator, bytes);
                    config = std.mem.trimRight(u8, cfg_utf8, "\x1a");
                }
            } else {
                const rel = try std.fmt.allocPrint(allocator, "original/{s}", .{name});
                try util.writeFile(try util.join(allocator, &.{ output, rel }), bytes);
                try manifest.add(name, bytes, "unknown", "{\"format\":\"unresolved\"}", rel);
            }
        } else if (std.ascii.eqlIgnoreCase(ext, ".aws")) {
            if (formats.decodeAws(bytes)) |aws| {
                try writeAudio(allocator, name, bytes, aws, output, &manifest);
                audio_count += 1;
            } else {
                const rel = try std.fmt.allocPrint(allocator, "original/{s}", .{name});
                try util.writeFile(try util.join(allocator, &.{ output, rel }), bytes);
                try manifest.add(name, bytes, "unknown", "{\"format\":\"unresolved-aws\"}", rel);
            }
        } else if (std.ascii.eqlIgnoreCase(ext, ".rel")) {
            const strings = try formats.extractRelStrings(allocator, bytes, 10);
            const rel = try std.fmt.allocPrint(allocator, "data/text/{s}.json", .{util.baseNameNoExt(name)});
            try writeStringsJson(allocator, name, strings, try util.join(allocator, &.{ output, rel }));
            for (strings) |s| try dialogue.append(allocator, s);
            const detail = try std.fmt.allocPrint(allocator, "{{\"format\":\"text-bytecode\",\"strings\":{d},\"bytes\":{d}}}", .{ strings.len, bytes.len });
            try manifest.add(name, bytes, "text-bytecode", detail, rel);
        } else if (std.ascii.eqlIgnoreCase(ext, ".ovr")) {
            const strings = try formats.extractPrefixedStrings(allocator, bytes, 12);
            const rel = "data/dialogue.json";
            try writeStringsJson(allocator, name, strings, try util.join(allocator, &.{ output, rel }));
            // Keep the longest dialogue strings for the generated Lua module.
            var sorted = try allocator.dupe(formats.ExtractedString, strings);
            std.mem.sort(formats.ExtractedString, sorted, {}, struct {
                fn lt(_: void, a: formats.ExtractedString, b: formats.ExtractedString) bool {
                    return a.text.len > b.text.len;
                }
            }.lt);
            for (sorted[0..@min(sorted.len, 250)]) |s| try dialogue.append(allocator, s);
            const detail = try std.fmt.allocPrint(allocator, "{{\"format\":\"dos-overlay\",\"strings\":{d},\"bytes\":{d}}}", .{ strings.len, bytes.len });
            try manifest.add(name, bytes, "overlay", detail, rel);
        } else if (std.ascii.eqlIgnoreCase(ext, ".fon")) {
            try writeHexRecords(allocator, name, bytes, 63, output, &manifest, "font");
        } else if (std.ascii.eqlIgnoreCase(ext, ".bin")) {
            if (std.ascii.startsWithIgnoreCase(name, "OBN")) {
                try writeHexRecords(allocator, name, bytes, 2, output, &manifest, "data");
            } else {
                try writeU16Table(allocator, name, bytes, output, &manifest, std.ascii.eqlIgnoreCase(name, "LAND.BIN"));
            }
        } else {
            const rel = try std.fmt.allocPrint(allocator, "original/{s}", .{name});
            try util.writeFile(try util.join(allocator, &.{ output, rel }), bytes);
            const kind = if (std.ascii.eqlIgnoreCase(ext, ".exe")) "executable" else if (std.ascii.eqlIgnoreCase(ext, ".bat")) "text" else "other";
            try manifest.add(name, bytes, kind, "{\"format\":\"copied-verbatim\"}", rel);
        }
    }

    try writeGameData(allocator, input, output, &manifest);
    try writeTexts(allocator, input, output, &manifest);
    try writeCodeStrings(allocator, input, output, &manifest);
    try writeActionMenu(allocator, input, output, &manifest);
    try writeOverlays(allocator, output, &manifest);
    try writeLuaModules(allocator, output, images.items, dialogue.items, verbs, config);
    try manifest.write(try util.join(allocator, &.{ output, "manifest.json" }));
    std.debug.print("extracted {d} images, {d} audio files, {d} dialogue strings -> {s}\n", .{ images.items.len, audio_count, dialogue.items.len, output });
}

fn lessI64(_: void, a: i64, b: i64) bool {
    return a < b;
}

fn traceSortedMap(writer: anytype, allocator: std.mem.Allocator, comptime name: []const u8, map: anytype) !void {
    var keys = std.ArrayList(i64).empty;
    defer keys.deinit(allocator);
    var it = map.iterator();
    while (it.next()) |entry| {
        const value = entry.value_ptr.*;
        if (value == 0) continue;
        try keys.append(allocator, entry.key_ptr.*);
    }
    std.mem.sort(i64, keys.items, {}, lessI64);
    try writer.writeByte('\t');
    try writer.writeAll(name);
    try writer.writeByte('=');
    for (keys.items, 0..) |key, i| {
        if (i != 0) try writer.writeByte(',');
        try writer.print("0x{x}:{d}", .{ @as(u64, @bitCast(key)), map.get(key).? });
    }
}

fn traceState(allocator: std.mem.Allocator, game: *const engine.Game, step: usize) void {
    var buf: [16384]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&buf);
    const out = &stderr_writer.interface;
    defer out.flush() catch {};
    out.print("TRACE\t{d}\troom={d}\tscore={d}\tmoves={d}\tobject={d}\tobject2={d}\tpicture={d}\tinventory=", .{
        step, game.room, game.score, game.moves, game.object_slot, game.object2_slot, game.pictureValue(),
    }) catch return;
    for (game.inventory.items, 0..) |item, i| {
        if (i != 0) out.writeByte('|') catch return;
        out.writeAll(item) catch return;
    }
    traceSortedMap(out, allocator, "flags", game.flags) catch return;
    traceSortedMap(out, allocator, "words", game.words) catch return;
    traceSortedMap(out, allocator, "dwords", game.dword_flags) catch return;
    out.writeByte('\n') catch return;
}

fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |c| switch (c) {
        '"' => try writer.writeAll("\\\""),
        '\\' => try writer.writeAll("\\\\"),
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        else => if (c < 0x20) {
            try writer.print("\\u{x:0>4}", .{c});
        } else {
            try writer.writeByte(c);
        },
    };
    try writer.writeByte('"');
}

fn writeJsonLines(writer: anytype, text: []const u8) !void {
    try writer.writeByte('[');
    var it = std.mem.splitScalar(u8, text, '\n');
    var first = true;
    while (it.next()) |line| {
        if (!first) try writer.writeByte(',');
        first = false;
        try writeJsonString(writer, line);
    }
    try writer.writeByte(']');
}

fn writeJsonMap(writer: anytype, allocator: std.mem.Allocator, comptime name: []const u8, map: anytype) !void {
    var keys = std.ArrayList(i64).empty;
    defer keys.deinit(allocator);
    var it = map.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* == 0) continue;
        try keys.append(allocator, entry.key_ptr.*);
    }
    std.mem.sort(i64, keys.items, {}, lessI64);
    try writer.print(",\"{s}\":{{", .{name});
    for (keys.items, 0..) |key, i| {
        if (i != 0) try writer.writeByte(',');
        try writer.print("\"0x{x}\":{d}", .{ @as(u64, @bitCast(key)), map.get(key).? });
    }
    try writer.writeByte('}');
}

fn writeTraceJson(file: std.fs.File, allocator: std.mem.Allocator, step: usize, command: ?[]const u8, text: []const u8, game: *const engine.Game) !void {
    var record = std.ArrayList(u8).empty;
    defer record.deinit(allocator);
    const out = record.writer(allocator);
    try out.print("{{\"step\":{d},\"kind\":", .{step});
    if (command) |cmd| {
        try writeJsonString(out, "command");
        try out.writeAll(",\"command\":");
        try writeJsonString(out, cmd);
        try out.writeAll(",\"response\":");
    } else {
        try writeJsonString(out, "initial");
        try out.writeAll(",\"look\":");
    }
    try writeJsonLines(out, text);
    try out.writeAll(",\"state\":{");
    try out.print("\"room\":{d},\"score\":{d},\"moves\":{d},\"object\":{d},\"object2\":{d},\"picture\":{d},\"inventory\":[", .{
        game.room, game.score, game.moves, game.object_slot, game.object2_slot, game.pictureValue(),
    });
    for (game.inventory.items, 0..) |item, i| {
        if (i != 0) try out.writeByte(',');
        try writeJsonString(out, item);
    }
    try out.writeByte(']');
    try writeJsonMap(out, allocator, "flags", game.flags);
    try writeJsonMap(out, allocator, "words", game.words);
    try writeJsonMap(out, allocator, "dwords", game.dword_flags);
    try out.writeAll("}}\n");
    try file.writeAll(record.items);
}

fn play(allocator: std.mem.Allocator, extracted_dir: []const u8, locale: engine.Locale, show_choices: bool, trace: bool, trace_path: ?[]const u8, script_path: ?[]const u8, load_path: ?[]const u8, save_path: ?[]const u8) !void {
    var game = try engine.Game.init(allocator, extracted_dir, locale);
    defer game.deinit();
    if (load_path) |p| try game.load(p);

    var trace_file: ?std.fs.File = null;
    if (trace_path) |p| trace_file = try std.fs.cwd().createFile(p, .{});
    defer if (trace_file) |f| f.close();

    var stdout_buf: [8192]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var stdin_buf: [4096]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
    const stdin = &stdin_reader.interface;

    const initial = try game.look();
    try stdout.print("{s}\n", .{initial});
    if (trace_file) |f| try writeTraceJson(f, allocator, 0, null, initial, &game);
    if (trace) traceState(allocator, &game, 0);

    var step: usize = 0;
    if (script_path) |path| {
        const script = try util.readFile(allocator, path);
        var lines = std.mem.splitScalar(u8, script, '\n');
        while (lines.next()) |raw| {
            if (game.quit_requested) break;
            const line = std.mem.trim(u8, raw, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;
            if (show_choices) {
                const list = try game.choices();
                try stdout.writeAll("\n");
                for (list, 1..) |choice, i| try stdout.print("  {d}. {s}\n", .{ i, choice.label });
            }
            try stdout.writeAll("\n> ");
            try stdout.flush();
            step += 1;
            const response = try game.execute(line);
            try stdout.print("{s}\n", .{response});
            if (trace_file) |f| try writeTraceJson(f, allocator, step, line, response, &game);
            if (trace) traceState(allocator, &game, step);
        }
    } else {
        while (!game.quit_requested) {
            if (show_choices) {
                const list = try game.choices();
                try stdout.writeAll("\n");
                for (list, 1..) |choice, i| try stdout.print("  {d}. {s}\n", .{ i, choice.label });
            }
            try stdout.writeAll("\n> ");
            try stdout.flush();
            const line_with_delim = stdin.takeDelimiterInclusive('\n') catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
            const line = std.mem.trimRight(u8, line_with_delim, "\r\n");
            step += 1;
            const response = try game.execute(line);
            try stdout.print("{s}\n", .{response});
            if (trace_file) |f| try writeTraceJson(f, allocator, step, line, response, &game);
            if (trace) traceState(allocator, &game, step);
        }
    }
    if (save_path) |p| try game.save(p);
}

fn info(allocator: std.mem.Allocator, path: []const u8) !void {
    const bytes = try util.readFile(allocator, path);
    const name = std.fs.path.basename(path);
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};
    try stdout.print("{s}: {d} bytes, sha256={s}\n", .{ name, bytes.len, sha256Hex(bytes) });
    const ext = std.fs.path.extension(name);
    if (std.ascii.eqlIgnoreCase(ext, ".seq")) {
        if (formats.decodeSeq(bytes)) |img| {
            try stdout.print("  SEQ layout={s} {d}x{d} header={d} palette={s} marker=", .{
                @tagName(img.kind),                       img.width, img.height, img.header_len,
                if (img.palette != null) "yes" else "no",
            });
            try util.hexBytes(stdout, img.marker);
            try stdout.writeByte('\n');
        } else {
            try stdout.print("  plain DOS text: {s}\n", .{if (isText(bytes)) "yes" else "no"});
        }
    } else if (std.ascii.eqlIgnoreCase(ext, ".aws")) {
        if (formats.decodeAws(bytes)) |aws| {
            try stdout.print("  AWS samples={d} field20={d} flags={d}\n", .{ aws.samples.len, aws.field20, aws.flags });
        }
    }
}

fn showOverlays(allocator: std.mem.Allocator, extracted_dir: []const u8, room: i64) !void {
    var game = try engine.Game.init(allocator, extracted_dir, .de);
    defer game.deinit();
    game.room = room;
    const overlays = try game.activeOverlays(allocator);
    defer allocator.free(overlays);
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    for (overlays) |name| try stdout.print("{s}\n", .{name});
    try stdout.flush();
}

fn showRules(
    allocator: std.mem.Allocator,
    extracted_dir: []const u8,
    room: i64,
    verb: i64,
    object: i64,
    object2: i64,
    byte_flags: []const []const u8,
    dword_flags: []const []const u8,
) !void {
    var game = try engine.Game.init(allocator, extracted_dir, .de);
    defer game.deinit();
    game.room = room;
    for (byte_flags) |spec| try applyFlagSpec(&game, spec, false);
    for (dword_flags) |spec| try applyFlagSpec(&game, spec, true);
    const report = try game.overlayDebug(verb, object, object2);
    var stdout_buf: [8192]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    try stdout.writeAll(report);
    try stdout.flush();
}

fn applyFlagSpec(game: *engine.Game, spec: []const u8, is_dword: bool) !void {
    const eq = std.mem.indexOfScalar(u8, spec, '=') orelse return error.InvalidFlagSpec;
    const address = std.fmt.parseInt(u32, spec[0..eq], 0) catch return error.InvalidFlagSpec;
    const value = std.fmt.parseInt(i64, spec[eq + 1 ..], 0) catch return error.InvalidFlagSpec;
    if (is_dword) {
        try game.dword_flags.put(address, @bitCast(@as(i32, @intCast(value))));
    } else if (engine.Game.isWordGlobal(address)) {
        try game.words.put(address, @truncate(@as(u16, @intCast(@mod(value, 65536)))));
    } else {
        try game.flags.put(address, @intCast(@mod(value, 256)));
    }
}

fn showVors(
    allocator: std.mem.Allocator,
    extracted_dir: []const u8,
    picture: i64,
    room: i64,
    byte_flags: []const []const u8,
    dword_flags: []const []const u8,
) !void {
    var game = try engine.Game.init(allocator, extracted_dir, .de);
    defer game.deinit();
    game.room = room;
    game.picture_override = picture;
    for (byte_flags) |spec| try applyFlagSpec(&game, spec, false);
    for (dword_flags) |spec| try applyFlagSpec(&game, spec, true);

    var stdout_buf: [8192]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    try stdout.print("record {d} count {d} room {d}\n", .{ picture, game.slotCount(picture), room });
    const count = game.slotCount(picture);
    var slot: usize = 0;
    while (slot < count) : (slot += 1) {
        var original: []const u8 = "(none)";
        for (game.regions) |region| {
            if (region.screen != picture or region.slot != @as(i32, @intCast(slot))) continue;
            original = region.action;
            break;
        }
        var effective: []const u8 = "";
        for (game.regions) |region| {
            if (region.screen != picture or region.slot != @as(i32, @intCast(slot))) continue;
            effective = game.actionForSlot(region);
            break;
        }
        try stdout.print("{d}\t{s}\t{s}\n", .{ slot, original, effective });
    }
    try stdout.flush();
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try std.process.argsAlloc(allocator);
    if (args.len < 2) {
        try std.fs.File.stdout().writeAll(
            \\hexuma-zig - asset extraction and Lua-driven runtime for the DOS game Hexuma
            \\
            \\usage:
            \\  hexuma extract --input DIR --output DIR   decode all original assets
            \\  hexuma info FILE                         describe one asset
            \\  hexuma run SCRIPT.lua                    run a Lua game-logic script
            \\  hexuma play [--lang de|en] [--choices] [--trace] [--trace-file FILE]
            \\             [--script FILE] [--extracted DIR] [--load FILE] [--save FILE]
            \\                                           play from extracted assets
            \\  hexuma gui [--lang de|en] [--extracted DIR]
            \\                                           point-and-click X11 window
            \\  hexuma overlays [--room N] [--extracted DIR]
            \\                                           list active FR overlays
            \\  hexuma rules [--room N] [--verb N] [--object N] [--object2 N]
            \\              [--flag ADDR=VAL] [--dword ADDR=VAL] [--extracted DIR]
            \\                                           inspect matching OVR rules
            \\  hexuma vors --picture N [--room N] [--flag ADDR=VAL]
            \\             [--dword ADDR=VAL] [--extracted DIR]
            \\                                           show runtime VORS slots
            \\
        );
        return;
    }
    const command = args[1];
    if (std.mem.eql(u8, command, "extract")) {
        var input: ?[]const u8 = null;
        var output: ?[]const u8 = null;
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--input") and i + 1 < args.len) {
                i += 1;
                input = args[i];
            } else if (std.mem.eql(u8, args[i], "--output") and i + 1 < args.len) {
                i += 1;
                output = args[i];
            }
        }
        if (input == null or output == null) return error.MissingArguments;
        try extract(allocator, input.?, output.?);
    } else if (std.mem.eql(u8, command, "info")) {
        if (args.len < 3) return error.MissingArguments;
        try info(allocator, args[2]);
    } else if (std.mem.eql(u8, command, "run")) {
        if (args.len < 3) return error.MissingArguments;
        try lua_rt.runFile(args[2]);
    } else if (std.mem.eql(u8, command, "play")) {
        var extracted_dir: []const u8 = "extracted";
        var locale: engine.Locale = .de;
        var show_choices = false;
        var trace = false;
        var trace_path: ?[]const u8 = null;
        var script_path: ?[]const u8 = null;
        var load_path: ?[]const u8 = null;
        var save_path: ?[]const u8 = null;
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--lang") and i + 1 < args.len) {
                i += 1;
                locale = if (std.ascii.eqlIgnoreCase(args[i], "en")) .en else .de;
            } else if (std.mem.eql(u8, args[i], "--extracted") and i + 1 < args.len) {
                i += 1;
                extracted_dir = args[i];
            } else if (std.mem.eql(u8, args[i], "--load") and i + 1 < args.len) {
                i += 1;
                load_path = args[i];
            } else if (std.mem.eql(u8, args[i], "--save") and i + 1 < args.len) {
                i += 1;
                save_path = args[i];
            } else if (std.mem.eql(u8, args[i], "--choices") or std.mem.eql(u8, args[i], "--click")) {
                show_choices = true;
            } else if (std.mem.eql(u8, args[i], "--trace")) {
                trace = true;
            } else if (std.mem.eql(u8, args[i], "--trace-file") and i + 1 < args.len) {
                i += 1;
                trace_path = args[i];
            } else if (std.mem.eql(u8, args[i], "--script") and i + 1 < args.len) {
                i += 1;
                script_path = args[i];
            }
        }
        try play(allocator, extracted_dir, locale, show_choices, trace, trace_path, script_path, load_path, save_path);
    } else if (std.mem.eql(u8, command, "gui")) {
        var extracted_dir: []const u8 = "extracted";
        var locale: engine.Locale = .de;
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--lang") and i + 1 < args.len) {
                i += 1;
                locale = if (std.ascii.eqlIgnoreCase(args[i], "en")) .en else .de;
            } else if (std.mem.eql(u8, args[i], "--extracted") and i + 1 < args.len) {
                i += 1;
                extracted_dir = args[i];
            }
        }
        try ui_x11.run(allocator, extracted_dir, locale);
    } else if (std.mem.eql(u8, command, "overlays")) {
        var extracted_dir: []const u8 = "extracted";
        var room: i64 = 1;
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--extracted") and i + 1 < args.len) {
                i += 1;
                extracted_dir = args[i];
            } else if (std.mem.eql(u8, args[i], "--room") and i + 1 < args.len) {
                i += 1;
                room = std.fmt.parseInt(i64, args[i], 10) catch room;
            }
        }
        try showOverlays(allocator, extracted_dir, room);
    } else if (std.mem.eql(u8, command, "rules")) {
        var extracted_dir: []const u8 = "extracted";
        var room: i64 = 1;
        var verb: i64 = 3;
        var object: i64 = 0;
        var object2: i64 = 0;
        var byte_flags = std.ArrayList([]const u8).empty;
        var dword_flags = std.ArrayList([]const u8).empty;
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--extracted") and i + 1 < args.len) {
                i += 1;
                extracted_dir = args[i];
            } else if (std.mem.eql(u8, args[i], "--room") and i + 1 < args.len) {
                i += 1;
                room = std.fmt.parseInt(i64, args[i], 0) catch room;
            } else if (std.mem.eql(u8, args[i], "--verb") and i + 1 < args.len) {
                i += 1;
                verb = std.fmt.parseInt(i64, args[i], 0) catch verb;
            } else if (std.mem.eql(u8, args[i], "--object") and i + 1 < args.len) {
                i += 1;
                object = std.fmt.parseInt(i64, args[i], 0) catch object;
            } else if (std.mem.eql(u8, args[i], "--object2") and i + 1 < args.len) {
                i += 1;
                object2 = std.fmt.parseInt(i64, args[i], 0) catch object2;
            } else if (std.mem.eql(u8, args[i], "--flag") and i + 1 < args.len) {
                i += 1;
                try byte_flags.append(allocator, args[i]);
            } else if (std.mem.eql(u8, args[i], "--dword") and i + 1 < args.len) {
                i += 1;
                try dword_flags.append(allocator, args[i]);
            }
        }
        try showRules(allocator, extracted_dir, room, verb, object, object2, byte_flags.items, dword_flags.items);
    } else if (std.mem.eql(u8, command, "vors")) {
        var extracted_dir: []const u8 = "extracted";
        var picture: i64 = -1;
        var room: i64 = 1;
        var byte_flags = std.ArrayList([]const u8).empty;
        var dword_flags = std.ArrayList([]const u8).empty;
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--extracted") and i + 1 < args.len) {
                i += 1;
                extracted_dir = args[i];
            } else if (std.mem.eql(u8, args[i], "--picture") and i + 1 < args.len) {
                i += 1;
                picture = std.fmt.parseInt(i64, args[i], 10) catch picture;
            } else if (std.mem.eql(u8, args[i], "--room") and i + 1 < args.len) {
                i += 1;
                room = std.fmt.parseInt(i64, args[i], 10) catch room;
            } else if (std.mem.eql(u8, args[i], "--flag") and i + 1 < args.len) {
                i += 1;
                try byte_flags.append(allocator, args[i]);
            } else if (std.mem.eql(u8, args[i], "--dword") and i + 1 < args.len) {
                i += 1;
                try dword_flags.append(allocator, args[i]);
            }
        }
        if (picture < 0) return error.MissingArguments;
        try showVors(allocator, extracted_dir, picture, room, byte_flags.items, dword_flags.items);
    } else if (std.mem.eql(u8, command, "version")) {
        var stdout_buf: [256]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
        try stdout_writer.interface.print("{s}\n", .{VERSION});
        try stdout_writer.interface.flush();
    } else {
        return error.UnknownCommand;
    }
}
