const std = @import("std");

/// The AGI picture container used by HEXPRG.EXE. Four related layouts were
/// observed; all of them store 8-bit palette indices with a 1024-byte VGA
/// palette (256 x R,G,B,pad) at the end of the file.
pub const SeqKind = enum {
    sprite_m1, // 4-byte w/h header, pixels, 30 00 af 00 + 4, palette
    screen_m2, // 4-byte w/h header, pixels, 00 00 ff 00, palette
    screen_full, // no header, 320 x N pixels, 00 00 ff 00, palette
    screen_hg, // no header, 320 x 110, b0 00 ef 00, palette
    wide_m1, // 4-byte header, 320 x 110 pixels, 30 00 af 00 + 4, palette
    frame, // 8-byte header (logical w/h, pixel w/h), pixels, no palette
};

pub const SeqImage = struct {
    kind: SeqKind,
    width: u32,
    height: u32,
    logical_width: u32 = 0,
    logical_height: u32 = 0,
    header_len: usize,
    pixels: []const u8,
    palette: ?[]const u8,
    marker: []const u8,
};

fn u16le(data: []const u8, off: usize) u16 {
    return std.mem.readInt(u16, data[off..][0..2], .little);
}

const M1 = [4]u8{ 0x30, 0x00, 0xaf, 0x00 };
const M2 = [4]u8{ 0x00, 0x00, 0xff, 0x00 };
const M3 = [4]u8{ 0xb0, 0x00, 0xef, 0x00 };

pub fn decodeSeq(data: []const u8) ?SeqImage {
    // FR / INTFR / MENUEFR frames have an 8-byte header and no palette.
    // They can be larger than the palette-bearing SEQ variants, so this check
    // must run before the length-based branch below.
    if (data.len >= 8) {
        const logical_w = u16le(data, 0);
        const logical_h = u16le(data, 2);
        const w = u16le(data, 4);
        const h = u16le(data, 6);
        if (w > 0 and h > 0 and data.len == 8 + @as(usize, w) * @as(usize, h)) {
            return .{
                .kind = .frame,
                .width = w,
                .height = h,
                .logical_width = logical_w,
                .logical_height = logical_h,
                .header_len = 8,
                .pixels = data[8..],
                .palette = null,
                .marker = &.{},
            };
        }
    }

    if (data.len < 1032) return null;

    const ps = data.len - 1024;
    const w0 = u16le(data, 0);
    const h0 = u16le(data, 2);

    if (std.mem.eql(u8, data[ps - 8 .. ps - 4], &M1)) {
        const pend = ps - 8;
        if (w0 > 0 and h0 > 0 and @as(usize, w0) * @as(usize, h0) == pend - 4) {
            return .{
                .kind = .sprite_m1,
                .width = w0,
                .height = h0,
                .header_len = 4,
                .pixels = data[4..pend],
                .palette = data[ps..],
                .marker = data[ps - 8 .. ps],
            };
        }
        if ((pend - 4) % 320 == 0) {
            return .{
                .kind = .wide_m1,
                .width = 320,
                .height = @intCast((pend - 4) / 320),
                .header_len = 4,
                .pixels = data[4..pend],
                .palette = data[ps..],
                .marker = data[ps - 8 .. ps],
            };
        }
        if (pend % 320 == 0) {
            return .{
                .kind = .wide_m1,
                .width = 320,
                .height = @intCast(pend / 320),
                .header_len = 0,
                .pixels = data[0..pend],
                .palette = data[ps..],
                .marker = data[ps - 8 .. ps],
            };
        }
    }

    if (std.mem.eql(u8, data[ps - 4 .. ps], &M2) or std.mem.eql(u8, data[ps - 4 .. ps], &M3)) {
        const pend = ps - 4;
        const kind: SeqKind = if (std.mem.eql(u8, data[ps - 4 .. ps], &M2)) .screen_m2 else .screen_hg;
        if (w0 > 0 and h0 > 0 and @as(usize, w0) * @as(usize, h0) == pend - 4) {
            return .{
                .kind = kind,
                .width = w0,
                .height = h0,
                .header_len = 4,
                .pixels = data[4..pend],
                .palette = data[ps..],
                .marker = data[ps - 4 .. ps],
            };
        }
        if (pend % 320 == 0) {
            return .{
                .kind = if (kind == .screen_hg) .screen_hg else .screen_full,
                .width = 320,
                .height = @intCast(pend / 320),
                .header_len = 0,
                .pixels = data[0..pend],
                .palette = data[ps..],
                .marker = data[ps - 4 .. ps],
            };
        }
    }
    return null;
}

pub const Aws = struct {
    field20: u16,
    sample_len_field: u16,
    flags: u16,
    samples: []const u8,
    header: []const u8,
};

pub fn decodeAws(data: []const u8) ?Aws {
    if (data.len < 512) return null;
    if (!std.mem.startsWith(u8, data, "AUDIOS WAVE SLAVE PC")) return null;
    const field20 = u16le(data, 0x14);
    const sample_len = u16le(data, 0x16);
    if (@as(usize, sample_len) + 512 != data.len) return null;
    return .{
        .field20 = field20,
        .sample_len_field = sample_len,
        .flags = u16le(data, 0x18),
        .samples = data[512..],
        .header = data[0..512],
    };
}

pub const ExtractedString = struct {
    offset: usize,
    text: []const u8,
};

fn printable(c: u8) bool {
    // CP437 letters live in 0x80..0x9F as well as 0xA0..0xFF. The original
    // German text uses 0x81 (ü), 0x84 (ä), 0x94 (ö) and 0xE1 (ß).
    return c >= 0x20 and c != 0x7f;
}

fn plausible(text: []const u8) bool {
    var letters: usize = 0;
    for (text) |c| {
        if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or c >= 0x80) letters += 1;
    }
    return letters * 3 >= text.len;
}

/// Recover the length-prefixed DOS strings used throughout HEXUMA.OVR.
/// The original engine stores them as: <length:u8><bytes>. We keep every
/// plausible run and report offsets so callers can verify against the artifact.
pub fn extractPrefixedStrings(allocator: std.mem.Allocator, data: []const u8, min_len: usize) ![]ExtractedString {
    var out = std.ArrayList(ExtractedString).empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        const n = data[i];
        if (n < min_len or n > 160 or i + 1 + n > data.len) continue;
        const candidate = data[i + 1 .. i + 1 + n];
        var ok = true;
        for (candidate) |c| {
            if (!printable(c)) {
                ok = false;
                break;
            }
        }
        if (!ok or !plausible(candidate)) continue;
        const utf8 = try @import("util.zig").latin1ToUtf8(allocator, candidate);
        try out.append(allocator, .{ .offset = i, .text = utf8 });
        i += n;
    }
    return out.toOwnedSlice(allocator);
}

/// Printable runs from TEXT*.REL. The RESOURCE files mix bytecode control
/// words with embedded Latin-1 text; this deliberately conservative scanner
/// only reports runs that look like natural language.
pub fn extractRelStrings(allocator: std.mem.Allocator, data: []const u8, min_len: usize) ![]ExtractedString {
    var out = std.ArrayList(ExtractedString).empty;
    errdefer out.deinit(allocator);
    var start: ?usize = null;
    var i: usize = 0;
    while (i <= data.len) : (i += 1) {
        const ok = i < data.len and printable(data[i]);
        if (ok and start == null) start = i;
        if (!ok and start != null) {
            const s = start.?;
            if (i - s >= min_len and plausible(data[s..i]) and !containsControlWord(data[s..i])) {
                const utf8 = try @import("util.zig").latin1ToUtf8(allocator, data[s..i]);
                try out.append(allocator, .{ .offset = s, .text = utf8 });
            }
            start = null;
        }
    }
    return out.toOwnedSlice(allocator);
}

fn containsControlWord(s: []const u8) bool {
    // Short runs made only from the high-range byte values typical of
    // bytecode operands are not text.
    var hi: usize = 0;
    for (s) |c| {
        if (c >= 0xf0) hi += 1;
    }
    return hi * 3 > s.len;
}
