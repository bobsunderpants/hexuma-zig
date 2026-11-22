const std = @import("std");

fn appendU16(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u16) !void {
    var b: [2]u8 = undefined;
    std.mem.writeInt(u16, &b, value, .little);
    try out.appendSlice(allocator, &b);
}

fn appendU32(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var b: [4]u8 = undefined;
    std.mem.writeInt(u32, &b, value, .little);
    try out.appendSlice(allocator, &b);
}

/// 8-bit unsigned mono PCM WAV - the AWS payload is already unsigned 8-bit
/// sample data, so no sample conversion is required.
pub fn encodePcm8(allocator: std.mem.Allocator, samples: []const u8, sample_rate: u32) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "RIFF");
    try appendU32(&out, allocator, @intCast(36 + samples.len));
    try out.appendSlice(allocator, "WAVEfmt ");
    try appendU32(&out, allocator, 16); // fmt chunk size
    try appendU16(&out, allocator, 1); // PCM
    try appendU16(&out, allocator, 1); // mono
    try appendU32(&out, allocator, sample_rate);
    try appendU32(&out, allocator, sample_rate); // byte rate
    try appendU16(&out, allocator, 1); // block align
    try appendU16(&out, allocator, 8); // bits per sample
    try out.appendSlice(allocator, "data");
    try appendU32(&out, allocator, @intCast(samples.len));
    try out.appendSlice(allocator, samples);
    return out.toOwnedSlice(allocator);
}
