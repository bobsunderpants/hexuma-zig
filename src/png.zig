const std = @import("std");

fn crc32(bytes: []const u8) u32 {
    var crc: u32 = 0xffffffff;
    for (bytes) |b| {
        crc ^= b;
        var k: u4 = 0;
        while (k < 8) : (k += 1) {
            const mask: u32 = @as(u32, 0) -% (crc & 1);
            crc = (crc >> 1) ^ (0xedb88320 & mask);
        }
    }
    return ~crc;
}

fn writeBe32(buf: []u8, value: u32) void {
    buf[0] = @intCast((value >> 24) & 0xff);
    buf[1] = @intCast((value >> 16) & 0xff);
    buf[2] = @intCast((value >> 8) & 0xff);
    buf[3] = @intCast(value & 0xff);
}

fn adler32(bytes: []const u8) u32 {
    var s1: u32 = 1;
    var s2: u32 = 0;
    for (bytes) |b| {
        s1 = (s1 + b) % 65521;
        s2 = (s2 + s1) % 65521;
    }
    return (s2 << 16) | s1;
}

fn chunk(out: *std.ArrayList(u8), allocator: std.mem.Allocator, kind: *const [4]u8, data: []const u8) !void {
    var lenbuf: [4]u8 = undefined;
    std.mem.writeInt(u32, &lenbuf, @intCast(data.len), .big);
    try out.appendSlice(allocator, &lenbuf);
    try out.appendSlice(allocator, kind);
    try out.appendSlice(allocator, data);
    var crcbuf: [4]u8 = undefined;
    // CRC covers the chunk type followed by the chunk data.
    var crc_input = std.ArrayList(u8).empty;
    defer crc_input.deinit(allocator);
    try crc_input.appendSlice(allocator, kind);
    try crc_input.appendSlice(allocator, data);
    std.mem.writeInt(u32, &crcbuf, crc32(crc_input.items), .big);
    try out.appendSlice(allocator, &crcbuf);
}

/// Encode an 8-bit indexed PNG. `palette_rgba` must contain 256 four-byte
/// entries; the fourth byte is ignored (the original driver stores a zero pad).
pub fn encodeIndexed(
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    pixels: []const u8,
    palette_rgba: []const u8,
) ![]u8 {
    std.debug.assert(palette_rgba.len >= 1024);
    std.debug.assert(pixels.len >= @as(usize, width) * @as(usize, height));

    // Build the filtered raw scanlines (filter type 0 for every row).
    var raw = std.ArrayList(u8).empty;
    defer raw.deinit(allocator);
    const row_bytes: usize = width;
    var y: usize = 0;
    while (y < height) : (y += 1) {
        try raw.append(allocator, 0);
        try raw.appendSlice(allocator, pixels[y * row_bytes .. (y + 1) * row_bytes]);
    }

    // zlib wrapper around uncompressed (stored) DEFLATE blocks.
    var compressed = std.ArrayList(u8).empty;
    defer compressed.deinit(allocator);
    try compressed.append(allocator, 0x78);
    try compressed.append(allocator, 0x01);
    var pos: usize = 0;
    while (pos < raw.items.len) {
        const n = @min(@as(usize, 65535), raw.items.len - pos);
        const final: u8 = if (pos + n == raw.items.len) 1 else 0;
        try compressed.append(allocator, final); // BFINAL=final, BTYPE=00
        var lb: [2]u8 = undefined;
        std.mem.writeInt(u16, &lb, @intCast(n), .little);
        try compressed.appendSlice(allocator, &lb);
        std.mem.writeInt(u16, &lb, @intCast(~@as(u16, @intCast(n))), .little);
        try compressed.appendSlice(allocator, &lb);
        try compressed.appendSlice(allocator, raw.items[pos .. pos + n]);
        pos += n;
    }
    if (raw.items.len == 0) {
        try compressed.append(allocator, 0x01);
        try compressed.appendSlice(allocator, &.{ 0, 0, 0xff, 0xff });
    }
    var ab: [4]u8 = undefined;
    std.mem.writeInt(u32, &ab, adler32(raw.items), .big);
    try compressed.appendSlice(allocator, &ab);

    // PLTE: only the RGB channels, the driver's fourth byte is padding.
    var plte: [768]u8 = undefined;
    for (0..256) |i| {
        plte[i * 3 + 0] = palette_rgba[i * 4 + 0];
        plte[i * 3 + 1] = palette_rgba[i * 4 + 1];
        plte[i * 3 + 2] = palette_rgba[i * 4 + 2];
    }

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "\x89PNG\r\n\x1a\n");
    var ihdr: [13]u8 = undefined;
    writeBe32(ihdr[0..4], width);
    writeBe32(ihdr[4..8], height);
    ihdr[8] = 8; // bit depth
    ihdr[9] = 3; // indexed colour
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;
    try chunk(&out, allocator, "IHDR", &ihdr);
    try chunk(&out, allocator, "PLTE", &plte);
    try chunk(&out, allocator, "IDAT", compressed.items);
    try chunk(&out, allocator, "IEND", &.{});
    return out.toOwnedSlice(allocator);
}
