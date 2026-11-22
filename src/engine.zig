const std = @import("std");
const locale_data = @import("locale_data.zig");
const util = @import("util.zig");
const overlay_rules = @import("overlay_rules.zig");
const overlay_eval = @import("overlay_eval.zig");

pub const Locale = enum { de, en };

pub const Choice = struct {
    label: []const u8,
    command: []const u8,
};

/// Conditional FR overlay recovered from the BILD loader at 0x2bffd. The
/// original draws every matching frame for the current scene in table order.
pub const Overlay = struct {
    scene: i64,
    file: []const u8,
    cond: []const u8,
};

pub const Region = struct {
    screen: i64,
    /// Original VORS.BIN action slot index (0..14). The original runtime
    /// overwrites selected slots at runtime based on room and game flags.
    slot: i32 = -1,
    x1: i32,
    y1: i32,
    x2: i32,
    y2: i32,
    action: []const u8,
};

/// Runtime action-slot override recovered from FUN_1c89_77fd (0x2408d).
/// The original overwrites VORS.BIN labels depending on the current picture,
/// room and a set of byte flags. An empty text blanks the slot (the original
/// sets the Pascal length byte to zero); a single space is a real one-character
/// command and is preserved.
const VorsOverride = struct {
    record: i64,
    slot: i32,
    cond: []const u8,
    text: []const u8,
};

/// Values are 0-based indices into each LAND.BIN record as stored in
/// `LAND.json`. The original runtime uses 1-based loader slots: the parser maps
/// direction verbs 10..15 to object ids 3..8, class-0 movement uses
/// `object - 1` as the loader slot, and the loader writes file word `slot - 1`
/// at `room*0xe + slot*2 - 0x52b0`. Therefore `süden` (object 4, loader slot 3)
/// reads file word 2.
const Direction = enum(u8) {
    north = 1,
    south = 2,
    east = 3,
    west = 4,
    up = 5,
    down = 6,
};

/// One decoded original noun/object record. The field names match the
/// REA-derived OBNINT/OBNBYT/OBNWOR layouts emitted by the extractor.
const VocabEntry = struct {
    id: i64,
    word: []const u8,
    prop: i64,
    room_gate: i64,
    class: i64,
    text_a: i64,
    text_b: i64,
};

fn asObject(v: std.json.Value) ?std.json.ObjectMap {
    return switch (v) {
        .object => |o| o,
        else => null,
    };
}

fn asArray(v: std.json.Value) ?std.json.Array {
    return switch (v) {
        .array => |a| a,
        else => null,
    };
}

fn asString(v: std.json.Value) []const u8 {
    return switch (v) {
        .string => |s| s,
        else => "",
    };
}

fn asInt(v: std.json.Value) i64 {
    return switch (v) {
        .integer => |n| n,
        .float => |n| @intFromFloat(n),
        else => 0,
    };
}

fn objectString(o: std.json.ObjectMap, key: []const u8) []const u8 {
    if (o.get(key)) |v| return asString(v);
    return "";
}

fn objectInt(o: std.json.ObjectMap, key: []const u8) i64 {
    if (o.get(key)) |v| return asInt(v);
    return 0;
}

fn lowerDup(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    // Mirrors the original canonicalizer at 0x23b24: A-Z fold by +0x20 and
    // CP437 umlauts fold to their lowercase forms. Input coming from JSON/CLI
    // is UTF-8, so the equivalent UTF-8 sequences are handled as well.
    var out = std.ArrayList(u8).empty;
    var i: usize = 0;
    while (i < s.len) {
        if (i + 1 < s.len and s[i] == 0xc3) {
            const lower: ?u8 = switch (s[i + 1]) {
                0x84 => 0xa4, // Ä -> ä
                0x96 => 0xb6, // Ö -> ö
                0x9c => 0xbc, // Ü -> ü
                else => null,
            };
            if (lower) |c| {
                try out.append(allocator, 0xc3);
                try out.append(allocator, c);
                i += 2;
                continue;
            }
        }
        const c = s[i];
        switch (c) {
            0x8e => try out.appendSlice(allocator, "ä"),
            0x99 => try out.appendSlice(allocator, "ö"),
            0x9a => try out.appendSlice(allocator, "ü"),
            else => try out.append(allocator, std.ascii.toLower(c)),
        }
        i += 1;
    }
    return out.toOwnedSlice(allocator);
}

fn eqIgnoreCase(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

/// The original parser accepts German verbs from VERBEN.SEQ. English aliases
/// come from the authored locale table; these extras cover common one-word
/// interactive-fiction phrasings whose original German counterpart is two
/// words in the locale data.
const extra_verb_aliases = [_]locale_data.Pair{
    .{ .de = "untersuche", .en = "look" },
    .{ .de = "untersuche", .en = "examine" },
    .{ .de = "untersuche", .en = "x" },
    .{ .de = "nimm", .en = "get" },
    .{ .de = "nimm", .en = "pick" },
    .{ .de = "lege", .en = "put" },
    .{ .de = "gehen", .en = "walk" },
    .{ .de = "gehen", .en = "move" },
    .{ .de = "inventur", .en = "inv" },
    .{ .de = "inventur", .en = "inventory" },
    .{ .de = "hilfe", .en = "help" },
    .{ .de = "hilfe", .en = "?" },
};

/// VORS.BIN labels use a few inflected forms that are absent from VERBEN.SEQ.
/// Map them to the semantic id of their original synonym.
const verb_word_overrides = [_]struct { word: []const u8, id: i64 }{
    .{ .word = "geh", .id = 7 },
    .{ .word = "gehe", .id = 7 },
    .{ .word = "schau", .id = 3 },
    .{ .word = "untersuch", .id = 3 },
    .{ .word = "steig", .id = 7 },
    .{ .word = "spring", .id = 119 },
    .{ .word = "süd", .id = 11 },
    .{ .word = "nord", .id = 10 },
    .{ .word = "ost", .id = 12 },
    .{ .word = "west", .id = 13 },
};

// The original tokenizer removes "und" and carries the previous verb into the
// next clause; articles are handled by the noun matcher's abbreviation path.
const skip_words = [_][]const u8{ "und", "and", "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "the", "a", "an", "at", "to", "with", "mit" };

/// Phrase-level substitutions for the original VORS.BIN click labels. The
/// command itself stays German so the original parser semantics are reused;
/// only the visible button text is translated.
const action_replacements = [_]locale_data.Pair{
    .{ .de = "Untersuche", .en = "Examine" },
    .{ .de = "untersuche", .en = "Examine" },
    .{ .de = "Betrachte", .en = "Observe" },
    .{ .de = "Schau", .en = "Look" },
    .{ .de = "Gehe", .en = "Go" },
    .{ .de = "gehe", .en = "Go" },
    .{ .de = "Nimm", .en = "Take" },
    .{ .de = "nimm", .en = "Take" },
    .{ .de = "Öffne", .en = "Open" },
    .{ .de = "Schließe", .en = "Close" },
    .{ .de = "Drücke", .en = "Press" },
    .{ .de = "Spiele", .en = "Play" },
    .{ .de = "Klettere", .en = "Climb" },
    .{ .de = "Grabe", .en = "Dig" },
    .{ .de = "Süd", .en = "South" },
    .{ .de = "Nord", .en = "North" },
    .{ .de = "Ost", .en = "East" },
    .{ .de = "West", .en = "West" },
    .{ .de = "rauf", .en = "up" },
    .{ .de = "runter", .en = "down" },
    .{ .de = "nach", .en = "" },
    .{ .de = "ins", .en = "into the" },
    .{ .de = "zum", .en = "to the" },
    .{ .de = "zur", .en = "to the" },
    .{ .de = "das", .en = "the" },
    .{ .de = "die", .en = "the" },
    .{ .de = "den", .en = "the" },
    .{ .de = "der", .en = "the" },
    .{ .de = "dem", .en = "the" },
    .{ .de = "im", .en = "in the" },
    .{ .de = "auf", .en = "on" },
    .{ .de = "an", .en = "at" },
};

pub const Game = struct {
    allocator: std.mem.Allocator,
    root: std.json.Value,
    locale: Locale,
    room: i64 = 1,
    /// Original globals 0xbe5c/0xbe5e for the current parser command.
    object_slot: i64 = 0,
    object2_slot: i64 = 0,
    /// Mutable copy of the seven i16 values per LAND.BIN room, indexed exactly
    /// as the original code indexes them (field 0 is the room id). The
    /// open/close handler negates exit signs in place, so the signed values
    /// cannot be read only from the immutable extracted JSON table.
    land_exits: [256][8]i64,
    /// OBNINT.field_a: raw 0-based LAND slot used by each door object. The
    /// original open/close handler indexes LAND with this value directly.
    door_slots: [1024]i64,
    /// Original global 0x32d0. Normally derived from the current BILD scene;
    /// kept separately so tools can inspect VORS records independently.
    picture_override: ?i64 = null,
    moves: usize = 0,
    score: usize = 0,
    quit_requested: bool = false,
    inventory: std.ArrayList([]const u8) = .empty,
    regions: []Region = &.{},
    verb_by_word: std.StringHashMap(i64),
    noun_by_word: std.StringHashMap(i64),
    vocab: []VocabEntry = &.{},
    vocab_by_id: std.AutoHashMap(i64, usize),
    text_by_id: std.AutoHashMap(i64, []const u8),
    code_msg_by_key: std.StringHashMap([]const u8),
    /// Original ';' command menus from OBLISTE.BIN, indexed by room id.
    action_menu: [][]const []const u8 = &.{},
    overlays: []Overlay = &.{},
    /// REA-derived compiled room-action rules from HEXUMA.OVR.
    overlay_db: ?overlay_rules.Database = null,
    /// Complete REA-derived runtime VORS label overrides, in original branch
    /// order. Later matching entries overwrite earlier ones.
    vors_overrides: []VorsOverride = &.{},
    /// Original VORS.BIN slot counts, indexed by picture/record id.
    vors_slot_counts: []i64 = &.{},
    /// Original runtime byte flags at their linear addresses. Unset flags are
    /// zero, matching the state after the original startup reset at 0x10b17.
    /// Keys are signed because several saved object/landscape arrays are
    /// addressed relative to a segment base and can be negative.
    flags: std.AutoHashMap(i64, u8),
    words: std.AutoHashMap(i64, u16),
    dword_flags: std.AutoHashMap(i64, u32),
    /// DAT symbols that live in an HEXUMA.OVR unit's own data segment. They
    /// persist between commands while the unit stays loaded but are not main
    /// module globals and are not written to saved games.
    overlay_locals: std.AutoHashMap(i64, i64),
    /// Pascal-string buffers written by the original .dat finalizer.
    strings: std.AutoHashMap(i64, []const u8),

    pub fn init(allocator: std.mem.Allocator, extracted_dir: []const u8, locale: Locale) !Game {
        const path = try util.join(allocator, &.{ extracted_dir, "data", "game.json" });
        const bytes = try util.readFile(allocator, path);
        const root = try std.json.parseFromSliceLeaky(std.json.Value, allocator, bytes, .{});

        var game = Game{
            .allocator = allocator,
            .root = root,
            .locale = locale,
            .land_exits = std.mem.zeroes([256][8]i64),
            .door_slots = std.mem.zeroes([1024]i64),
            .verb_by_word = std.StringHashMap(i64).init(allocator),
            .noun_by_word = std.StringHashMap(i64).init(allocator),
            .vocab_by_id = std.AutoHashMap(i64, usize).init(allocator),
            .text_by_id = std.AutoHashMap(i64, []const u8).init(allocator),
            .code_msg_by_key = std.StringHashMap([]const u8).init(allocator),
            .flags = std.AutoHashMap(i64, u8).init(allocator),
            .words = std.AutoHashMap(i64, u16).init(allocator),
            .dword_flags = std.AutoHashMap(i64, u32).init(allocator),
            .overlay_locals = std.AutoHashMap(i64, i64).init(allocator),
            .strings = std.AutoHashMap(i64, []const u8).init(allocator),
        };
        if (root.object.get("start_room")) |v| game.room = asInt(v);

        // Read the REA-derived startup globals (0x10b17) so overlay gates and
        // VORS overrides start from the original machine state, not all zeroes.
        const initial_path = try util.join(allocator, &.{ extracted_dir, "data", "initial_flags.json" });
        if (util.readFile(allocator, initial_path)) |initial_bytes| {
            const initial_root = try std.json.parseFromSliceLeaky(std.json.Value, allocator, initial_bytes, .{});
            if (asObject(initial_root)) |initial_obj| {
                if (initial_obj.get("bytes")) |bv| {
                    if (asObject(bv)) |byte_values| {
                        var it = byte_values.iterator();
                        while (it.next()) |entry| {
                            const address = std.fmt.parseInt(i64, entry.key_ptr.*, 10) catch continue;
                            try game.flags.put(address, @intCast(@mod(asInt(entry.value_ptr.*), 256)));
                        }
                    }
                }
                if (initial_obj.get("dwords")) |dv| {
                    if (asObject(dv)) |dword_values| {
                        var it = dword_values.iterator();
                        while (it.next()) |entry| {
                            const address = std.fmt.parseInt(i64, entry.key_ptr.*, 10) catch continue;
                            try game.dword_flags.put(address, @bitCast(@as(i32, @intCast(asInt(entry.value_ptr.*)))));
                        }
                    }
                }
            }
        } else |_| {}

        if (root.object.get("verbs")) |v| {
            if (asArray(v)) |verbs| {
                for (verbs.items) |entry| {
                    if (asObject(entry)) |o| {
                        const name = objectString(o, "name");
                        if (name.len == 0) continue;
                        try game.verb_by_word.put(try lowerDup(allocator, name), objectInt(o, "id"));
                    }
                }
            }
        }
        var vocab = std.ArrayList(VocabEntry).empty;
        if (root.object.get("vocabulary")) |v| {
            if (asArray(v)) |words| {
                for (words.items, 0..) |entry, idx| {
                    if (asObject(entry)) |o| {
                        const word = objectString(o, "word");
                        if (word.len == 0) continue;
                        // Store the compact array position; the JSON "index"
                        // preserves the original OBW line number including
                        // "ende" separators and is not an array index.
                        const key = try lowerDup(allocator, word);
                        if (!game.noun_by_word.contains(key)) {
                            try game.noun_by_word.put(key, @intCast(idx));
                        }
                        try vocab.append(allocator, .{
                            .id = objectInt(o, "id"),
                            .word = word,
                            .prop = objectInt(o, "prop"),
                            .room_gate = objectInt(o, "room_gate"),
                            .class = objectInt(o, "class"),
                            .text_a = objectInt(o, "text_a"),
                            .text_b = objectInt(o, "text_b"),
                        });
                    }
                }
            }
        }
        game.vocab = try vocab.toOwnedSlice(allocator);
        for (game.vocab, 0..) |entry, idx| {
            try game.vocab_by_id.put(entry.id, idx);
            // OBNBYT class bytes are copied into 0x5140 during startup. The
            // open/close handlers at 0x1755:0x31a1 read them from there.
            const class_addr = entry.id + 0x5140;
            if (!game.flags.contains(class_addr)) {
                try game.flags.put(class_addr, @intCast(@mod(entry.class, 256)));
            }
        }

        // LAND.BIN is loaded as seven signed 16-bit values per room. Keep a
        // mutable copy because door state is encoded in the exit sign. The
        // extracted columns are 0-based file word indices: original loader
        // slot n reads file word n-1 (`süden` uses loader slot 3, word 2).
        const land_path = try util.join(allocator, &.{ extracted_dir, "data", "tables", "LAND.json" });
        if (util.readFile(allocator, land_path)) |land_bytes| {
            const land_root = try std.json.parseFromSliceLeaky(std.json.Value, allocator, land_bytes, .{});
            if (asArray(land_root.object.get("values") orelse std.json.Value{ .null = {} })) |values| {
                var i: usize = 0;
                while (i + 6 < values.items.len and i / 7 + 1 < game.land_exits.len) : (i += 7) {
                    // The original file's first record belongs to room 1. The
                    // runtime address formula is room*0xe + slot*2 - 0x52b0,
                    // so room 1 starts 14 bytes after the table base.
                    const room = i / 7 + 1;
                    for (0..7) |slot| {
                        game.land_exits[room][slot] = switch (values.items[i + slot]) {
                            .integer => |n| n,
                            .float => |f| @intFromFloat(f),
                            else => 0,
                        };
                    }
                }
            }
        } else |_| {}

        // The first OBNINT field is the 1-based LAND loader slot stored in
        // original global 0x37fc and used by the door open/close handler.
        const obnint_path = try util.join(allocator, &.{ extracted_dir, "data", "tables", "OBNINT.json" });
        const obnint_bytes = util.readFile(allocator, obnint_path) catch &[_]u8{};
        if (obnint_bytes.len != 0) {
            const obnint_root = try std.json.parseFromSliceLeaky(std.json.Value, allocator, obnint_bytes, .{});
            if (asObject(obnint_root)) |obnint_obj| {
                if (asArray(obnint_obj.get("records") orelse std.json.Value{ .null = {} })) |records| {
                    for (records.items, 0..) |record_value, i| {
                        const hex = asString(record_value);
                        if (hex.len == 0) continue;
                        // Records are emitted as file-order bytes, so "0300" is
                        // the little-endian i16 value 3, not decimal 0x0300.
                        const parsed = std.fmt.parseInt(u16, hex, 16) catch continue;
                        const raw: i64 = @byteSwap(parsed);
                        const object_id = i / 2 + 1;
                        if (i % 2 == 0 and object_id < game.door_slots.len) {
                            game.door_slots[object_id] = raw;
                        }
                    }
                }
            }
        }

        // Original TEXT*.REL records are keyed by 1-based ids from OBNWOR*.BIN.
        const texts_path = try util.join(allocator, &.{ extracted_dir, "data", "texts.json" });
        if (util.readFile(allocator, texts_path)) |text_bytes| {
            const texts_root = try std.json.parseFromSliceLeaky(std.json.Value, allocator, text_bytes, .{});
            if (texts_root.object.get("texts")) |tv| {
                if (asArray(tv)) |texts| {
                    for (texts.items) |entry| {
                        const o = asObject(entry) orelse continue;
                        try game.text_by_id.put(objectInt(o, "id"), objectString(o, "text"));
                    }
                }
            }
        } else |_| {}

        // REA-derived packed Pascal strings from HEXPRG.EXE. These are the
        // original German message fragments used by the parser/action layer.
        const code_path = try util.join(allocator, &.{ extracted_dir, "data", "code_strings.json" });
        if (util.readFile(allocator, code_path)) |code_bytes| {
            const code_root = try std.json.parseFromSliceLeaky(std.json.Value, allocator, code_bytes, .{});
            if (asObject(code_root)) |code_obj| {
                if (code_obj.get("pools")) |pv| {
                    if (asArray(pv)) |pools| {
                        for (pools.items) |pool_value| {
                            const pool = asObject(pool_value) orelse continue;
                            const name = objectString(pool, "name");
                            const messages = pool.get("messages") orelse continue;
                            if (asArray(messages)) |items| {
                                for (items.items, 0..) |item, idx| {
                                    const text = objectString(asObject(item) orelse continue, "text");
                                    if (text.len == 0) continue;
                                    const key = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ name, idx });
                                    try game.code_msg_by_key.put(key, text);
                                }
                            }
                        }
                    }
                }
            }
        } else |_| {}

        // English aliases resolve through the German key, so they inherit the
        // original verb/object ids instead of introducing a second id space.
        for (locale_data.verb_labels) |pair| {
            if (game.verb_by_word.get(try lowerDup(allocator, pair.de))) |id| {
                try game.verb_by_word.put(try lowerDup(allocator, pair.en), id);
            }
        }
        for (extra_verb_aliases) |pair| {
            if (game.verb_by_word.get(try lowerDup(allocator, pair.de))) |id| {
                try game.verb_by_word.put(try lowerDup(allocator, pair.en), id);
            }
        }
        for (locale_data.noun_labels) |pair| {
            if (game.noun_by_word.get(try lowerDup(allocator, pair.de))) |idx| {
                try game.noun_by_word.put(try lowerDup(allocator, pair.en), idx);
                // Common single-word forms of multiword English labels.
                var it = std.mem.tokenizeAny(u8, pair.en, " -/");
                while (it.next()) |part| {
                    if (part.len > 2) try game.noun_by_word.put(try lowerDup(allocator, part), idx);
                }
            }
        }

        var regions = std.ArrayList(Region).empty;
        if (root.object.get("click_regions")) |v| {
            if (asArray(v)) |items| {
                for (items.items) |entry| {
                    if (asObject(entry)) |o| {
                        try regions.append(allocator, .{
                            .screen = objectInt(o, "screen"),
                            .slot = @intCast(objectInt(o, "slot")),
                            .x1 = @intCast(objectInt(o, "x1")),
                            .y1 = @intCast(objectInt(o, "y1")),
                            .x2 = @intCast(objectInt(o, "x2")),
                            .y2 = @intCast(objectInt(o, "y2")),
                            .action = objectString(o, "action"),
                        });
                    }
                }
            }
        }
        game.regions = try regions.toOwnedSlice(allocator);

        // Second original input path: the ';' command menu loaded from
        // OBLISTE.BIN by FUN_1c89_73be and displayed by FUN_1c89_50e1.
        var menus = try allocator.alloc([]const []const u8, 256);
        @memset(menus, &.{});
        const menu_path = try util.join(allocator, &.{ extracted_dir, "data", "action_menu.json" });
        if (util.readFile(allocator, menu_path)) |menu_bytes| {
            const menu_root = try std.json.parseFromSliceLeaky(std.json.Value, allocator, menu_bytes, .{});
            if (asObject(menu_root)) |menu_obj| {
                if (menu_obj.get("rooms")) |rv| {
                    if (asArray(rv)) |room_values| {
                        for (room_values.items) |room_value| {
                            const ro = asObject(room_value) orelse continue;
                            const idx = objectInt(ro, "room");
                            if (idx < 0 or idx >= 256) continue;
                            const av = ro.get("actions") orelse continue;
                            if (asArray(av)) |action_values| {
                                var actions = std.ArrayList([]const u8).empty;
                                for (action_values.items) |action_value| {
                                    if (asString(action_value).len != 0) try actions.append(allocator, asString(action_value));
                                }
                                menus[@intCast(idx)] = try actions.toOwnedSlice(allocator);
                            }
                        }
                    }
                }
            }
        } else |_| {}
        game.action_menu = menus;

        const overlay_path = try util.join(allocator, &.{ extracted_dir, "data", "overlays.json" });
        if (util.readFile(allocator, overlay_path)) |overlay_bytes| {
            const overlay_root = try std.json.parseFromSliceLeaky(std.json.Value, allocator, overlay_bytes, .{});
            if (asObject(overlay_root)) |overlay_obj| {
                if (overlay_obj.get("frames")) |fv| {
                    if (asArray(fv)) |frames| {
                        var list = std.ArrayList(Overlay).empty;
                        for (frames.items) |frame_value| {
                            const frame = asObject(frame_value) orelse continue;
                            const file = objectString(frame, "file");
                            if (file.len == 0) continue;
                            try list.append(allocator, .{
                                .scene = objectInt(frame, "scene"),
                                .file = file,
                                .cond = objectString(frame, "cond"),
                            });
                        }
                        game.overlays = try list.toOwnedSlice(allocator);
                    }
                }
            }
        } else |_| {}

        const overlay_rules_path = try util.join(allocator, &.{ extracted_dir, "data", "overlay_rules.json" });
        if (util.readFile(allocator, overlay_rules_path)) |rules_bytes| {
            game.overlay_db = overlay_rules.parse(allocator, rules_bytes) catch |err| blk: {
                std.debug.print("overlay rules parse error: {s}\n", .{@errorName(err)});
                break :blk null;
            };
        } else |_| {}

        const vors_path = try util.join(allocator, &.{ extracted_dir, "data", "vors_overrides.json" });
        if (util.readFile(allocator, vors_path)) |vors_bytes| {
            const vors_root = try std.json.parseFromSliceLeaky(std.json.Value, allocator, vors_bytes, .{});
            if (asObject(vors_root)) |vors_obj| {
                if (vors_obj.get("overrides")) |ov| {
                    if (asArray(ov)) |items| {
                        var list = std.ArrayList(VorsOverride).empty;
                        for (items.items) |value| {
                            const entry = asObject(value) orelse continue;
                            try list.append(allocator, .{
                                .record = objectInt(entry, "record"),
                                .slot = @intCast(objectInt(entry, "slot")),
                                .cond = objectString(entry, "cond"),
                                .text = objectString(entry, "text"),
                            });
                        }
                        game.vors_overrides = try list.toOwnedSlice(allocator);
                    }
                }
            }
        } else |_| {}

        const counts_path = try util.join(allocator, &.{ extracted_dir, "data", "vors_records.json" });
        if (util.readFile(allocator, counts_path)) |counts_bytes| {
            const counts_root = try std.json.parseFromSliceLeaky(std.json.Value, allocator, counts_bytes, .{});
            if (asObject(counts_root)) |counts_obj| {
                if (counts_obj.get("counts")) |cv| {
                    if (asArray(cv)) |counts| {
                        const list = try allocator.alloc(i64, counts.items.len);
                        for (counts.items, 0..) |count_value, i| {
                            const count = asInt(count_value);
                            list[i] = if (count > 14) 1 else count;
                        }
                        game.vors_slot_counts = list;
                    }
                }
            }
        } else |_| {}
        return game;
    }

    pub fn deinit(self: *Game) void {
        self.inventory.deinit(self.allocator);
        self.verb_by_word.deinit();
        self.noun_by_word.deinit();
        self.vocab_by_id.deinit();
        self.text_by_id.deinit();
        self.code_msg_by_key.deinit();
        self.flags.deinit();
        self.words.deinit();
        self.dword_flags.deinit();
        self.overlay_locals.deinit();
        self.strings.deinit();
        if (self.overlay_db) |*db| db.deinit();
    }

    fn tr(self: *const Game, german: []const u8) []const u8 {
        if (self.locale == .de) return german;
        return locale_data.lookup(&locale_data.ui_labels, german) orelse german;
    }

    fn germanForEnglish(pairs: []const locale_data.Pair, english: []const u8) ?[]const u8 {
        for (pairs) |pair| {
            if (eqIgnoreCase(pair.en, english)) return pair.de;
        }
        return null;
    }

    fn verbId(self: *const Game, token: []const u8) ?i64 {
        for (verb_word_overrides) |entry| {
            if (eqIgnoreCase(entry.word, token)) return entry.id;
        }
        if (self.verb_by_word.get(token)) |id| return id;
        if (germanForEnglish(&locale_data.verb_labels, token)) |de| {
            return self.verb_by_word.get(de);
        }
        for (extra_verb_aliases) |pair| {
            if (eqIgnoreCase(pair.en, token)) return self.verb_by_word.get(pair.de);
        }
        return null;
    }

    fn nounIndex(self: *const Game, token: []const u8) ?i64 {
        // The original matcher at 0x17d2f accepts exact words and proper
        // prefixes. The suffix rewriter at 0x17931 strips one German ending
        // from words longer than five characters before the noun pass.
        var forms: [2][]const u8 = .{ token, token };
        var form_count: usize = 1;
        if (token.len > 5) {
            const strip: usize = if (std.mem.endsWith(u8, token, "en") or std.mem.endsWith(u8, token, "es") or std.mem.endsWith(u8, token, "st"))
                2
            else if (std.mem.endsWith(u8, token, "s") or std.mem.endsWith(u8, token, "n"))
                1
            else
                0;
            if (strip > 0 and strip < token.len) {
                forms[1] = token[0 .. token.len - strip];
                form_count = 2;
            }
        }
        for (forms[0..form_count]) |form| {
            if (self.noun_by_word.get(form)) |idx| return idx;
            if (germanForEnglish(&locale_data.noun_labels, form)) |de| {
                if (self.noun_by_word.get(de)) |idx| return idx;
            }
        }
        for (self.vocab, 0..) |entry, idx| {
            if (entry.word.len == 0) continue;
            for (forms[0..form_count]) |form| {
                if (form.len > 0 and form.len < entry.word.len and std.mem.startsWith(u8, entry.word, form) and self.nounVisible(@intCast(idx))) {
                    return @intCast(idx);
                }
            }
        }
        return null;
    }

    fn roomObject(self: *const Game) ?std.json.ObjectMap {
        const rooms = asArray(self.root.object.get("rooms") orelse return null) orelse return null;
        const idx: usize = @intCast(self.room - 1);
        if (idx >= rooms.items.len) return null;
        return asObject(rooms.items[idx]);
    }

    fn exitTo(self: *const Game, dir: Direction) i64 {
        if (self.room < 0 or self.room >= self.land_exits.len) return 0;
        return self.land_exits[@intCast(self.room)][@intFromEnum(dir)];
    }

    fn exitSlot(self: *const Game, slot: i64) i64 {
        if (slot < 0 or slot >= self.land_exits[0].len) return 0;
        if (self.room < 0 or self.room >= self.land_exits.len) return 0;
        return self.land_exits[@intCast(self.room)][@intCast(slot)];
    }

    fn negateExitSlot(self: *Game, room_id: i64, slot: i64) void {
        if (room_id < 0 or room_id >= self.land_exits.len) return;
        if (slot < 0 or slot >= self.land_exits[0].len) return;
        const idx: usize = @intCast(slot);
        self.land_exits[@intCast(room_id)][idx] = -self.land_exits[@intCast(room_id)][idx];
    }

    /// Mirror 0x1755:0x31a1: open/close negates the current LAND entry and the
    /// matching reciprocal entry in the destination room. OBNINT.field_a is the
    /// original 1-based loader slot; the extracted LAND columns are file word
    /// indices, so the live column is `slot - 1`.
    fn toggleDoor(self: *Game, object_id: i64) void {
        const loader_slot = if (object_id >= 0 and object_id < self.door_slots.len) self.door_slots[@intCast(object_id)] else 0;
        const slot = loader_slot - 1;
        if (slot < 0 or slot >= self.land_exits[0].len) return;
        const value = self.exitSlot(slot);
        if (value == 0) return;
        const destination = if (value < 0) -value else value;
        self.negateExitSlot(self.room, slot);
        if (destination < 0 or destination >= self.land_exits.len) return;
        // The original searches loader slots 2..7, i.e. file words 1..6.
        for (1..7) |reciprocal| {
            const other = self.land_exits[@intCast(destination)][reciprocal];
            if (other == self.room or other == -self.room) {
                self.negateExitSlot(destination, @intCast(reciprocal));
                break;
            }
        }
    }

    /// The negative-exit branch of 0x1b27:011e only emits message 0x3c when it
    /// finds a class-4 door object in the current room whose 0x37fc slot matches
    /// the direction. Otherwise the original handler is silent, so null means
    /// "no parser response" rather than an invented error.
    fn blockedDoorMessage(self: *Game, dir: Direction) ?[]const u8 {
        const slot: i64 = @intFromEnum(dir);
        for (self.vocab) |entry| {
            if (entry.class != 4) continue;
            if (entry.room_gate != self.room) continue;
            if (self.door_slots[@intCast(@mod(entry.id, self.door_slots.len))] != slot + 1) continue;
            return self.textForId(0x3c) orelse self.message(
                "text.0x3c",
                "Das kann man nicht ausleeren.",
                "You cannot do that.",
            );
        }
        return null;
    }

    pub fn pictureValue(self: *const Game) i64 {
        if (self.picture_override) |picture| return picture;
        const pictures = asArray(self.root.object.get("pictures") orelse return 0) orelse return 0;
        const pic_i: usize = @intCast(self.room - 1);
        if (pic_i >= pictures.items.len) return 0;
        return objectInt(asObject(pictures.items[pic_i]) orelse return 0, "value");
    }

    fn flagIs(self: *const Game, address: u32, expected: u8) bool {
        if (address == 0) return true;
        return (self.flags.get(address) orelse 0) == expected;
    }

    fn byteValue(self: *const Game, address: u32) i64 {
        if (address == 0xbe1b) return @mod(self.room, 256);
        return self.flags.get(address) orelse 0;
    }

    fn dwordValue(self: *const Game, address: u32) i64 {
        return self.dword_flags.get(address) orelse 0;
    }

    /// Evaluate the small boolean expression language used by the extracted
    /// overlay table: room, byte(hex), dword(hex), decimal/hex constants,
    /// comparisons, && and ||. Unknown flags read as zero, matching the
    /// original startup reset in FUN_1c89_... at 0x10b17 for most addresses.
    const CondParser = struct {
        game: *const Game,
        text: []const u8,
        pos: usize = 0,

        fn skip(self: *CondParser) void {
            while (self.pos < self.text.len and std.ascii.isWhitespace(self.text[self.pos])) self.pos += 1;
        }

        fn take(self: *CondParser, token: []const u8) bool {
            self.skip();
            if (self.pos + token.len > self.text.len) return false;
            if (!std.mem.eql(u8, self.text[self.pos .. self.pos + token.len], token)) return false;
            self.pos += token.len;
            return true;
        }

        fn number(self: *CondParser) i64 {
            self.skip();
            const start = self.pos;
            while (self.pos < self.text.len) : (self.pos += 1) {
                const ch = self.text[self.pos];
                if (!(std.ascii.isAlphanumeric(ch) or ch == 'x')) break;
            }
            const token = self.text[start..self.pos];
            if (std.mem.startsWith(u8, token, "0x") or std.mem.startsWith(u8, token, "0X")) {
                return std.fmt.parseInt(i64, token[2..], 16) catch 0;
            }
            return std.fmt.parseInt(i64, token, 10) catch 0;
        }

        fn value(self: *CondParser) i64 {
            self.skip();
            if (self.take("(")) {
                const result = @intFromBool(self.orExpr());
                _ = self.take(")");
                return result;
            }
            if (self.take("room")) return self.game.room;
            if (self.take("byte")) {
                if (self.take("(")) {
                    const address: u32 = @intCast(@mod(self.number(), 0x100000000));
                    _ = self.take(")");
                    return self.game.byteValue(address);
                }
            }
            if (self.take("dword")) {
                if (self.take("(")) {
                    const address: u32 = @intCast(@mod(self.number(), 0x100000000));
                    _ = self.take(")");
                    return self.game.dwordValue(address);
                }
            }
            return self.number();
        }

        fn compare(self: *CondParser) bool {
            const left = self.value();
            if (self.take("==")) return left == self.value();
            if (self.take("!=")) return left != self.value();
            if (self.take("<=")) return left <= self.value();
            if (self.take(">=")) return left >= self.value();
            if (self.take("<")) return left < self.value();
            if (self.take(">")) return left > self.value();
            return left != 0;
        }

        fn andExpr(self: *CondParser) bool {
            var result = self.compare();
            while (self.take("&&")) {
                const right = self.compare();
                result = result and right;
            }
            return result;
        }

        fn orExpr(self: *CondParser) bool {
            var result = self.andExpr();
            while (self.take("||")) {
                const right = self.andExpr();
                result = result or right;
            }
            return result;
        }
    };

    /// FR overlays whose REA-derived condition currently holds, in original
    /// table order. The X11 frontend blits these over the BILD background.
    pub fn activeOverlays(self: *const Game, allocator: std.mem.Allocator) ![][]const u8 {
        var out = std.ArrayList([]const u8).empty;
        for (self.overlays) |overlay| {
            if (overlay.scene != self.room) continue;
            var parser = CondParser{ .game = self, .text = overlay.cond };
            const active = parser.orExpr();
            parser.skip();
            if (parser.pos != parser.text.len) continue;
            if (active) try out.append(allocator, overlay.file);
        }
        return out.toOwnedSlice(allocator);
    }

    fn conditionMatches(self: *const Game, condition: []const u8) bool {
        if (condition.len == 0) return true;
        var parser = CondParser{ .game = self, .text = condition };
        const result = parser.orExpr();
        parser.skip();
        return result and parser.pos == condition.len;
    }

    /// Original VORS slot count for a picture/record, after the 0x2408d clamp
    /// of `count > 14 -> 1`. Slot assignments beyond the count are inert.
    pub fn slotCount(self: *const Game, record: i64) usize {
        if (record < 0 or record >= self.vors_slot_counts.len) return 0;
        return @intCast(@max(0, self.vors_slot_counts[@intCast(record)]));
    }

    /// Apply the REA-derived runtime overrides to one VORS action slot.
    pub fn actionForSlot(self: *const Game, region: Region) []const u8 {
        const record = self.pictureValue();
        if (region.slot < 0 or @as(usize, @intCast(region.slot)) >= self.slotCount(record)) return "";
        var result = region.action;
        for (self.vors_overrides) |ov| {
            if (ov.record != record or ov.slot != region.slot) continue;
            if (!self.conditionMatches(ov.cond)) continue;
            result = ov.text;
        }
        return result;
    }

    fn vocabularyWord(self: *const Game, index: i64) []const u8 {
        const words = asArray(self.root.object.get("vocabulary") orelse return "") orelse return "";
        const idx: usize = @intCast(index);
        if (idx >= words.items.len) return "";
        return objectString(asObject(words.items[idx]) orelse return "", "word");
    }

    fn vocabEntry(self: *const Game, index: i64) ?VocabEntry {
        if (index < 0 or index >= @as(i64, @intCast(self.vocab.len))) return null;
        return self.vocab[@intCast(index)];
    }

    fn vocabularyId(self: *const Game, index: i64) ?i64 {
        if (self.vocabEntry(index)) |entry| return entry.id;
        return null;
    }

    fn textForId(self: *const Game, id: i64) ?[]const u8 {
        if (id == 0) return null;
        return self.text_by_id.get(id);
    }

    /// Prefer the exact German fragment recovered from HEXPRG.EXE; English is
    /// an authored alternative and always uses the supplied fallback.
    fn message(self: *const Game, key: []const u8, de_fallback: []const u8, en_fallback: []const u8) []const u8 {
        if (self.locale == .de) {
            return self.code_msg_by_key.get(key) orelse de_fallback;
        }
        return en_fallback;
    }

    /// Reproduce the original OBNINT.field_b gate closely enough for text
    /// lookups: current room, globally available, alias id, LAND adjacency,
    /// or a carried object. A zero gate is treated as globally available.
    fn nounVisible(self: *const Game, index: i64) bool {
        const entry = self.vocabEntry(index) orelse return false;
        if (self.hasInInventory(entry.word)) return true;
        const gate = entry.room_gate;
        if (gate == self.room or gate == 0 or gate == 0xffff) return true;
        if (gate < 0) {
            if (self.vocab_by_id.get(-gate)) |alias_idx| {
                const alias_gate = self.vocab[alias_idx].room_gate;
                if (alias_gate == self.room or alias_gate == 0 or alias_gate == 0xffff) return true;
            }
        }
        for (all_directions) |edge| {
            const target = self.exitTo(edge.dir);
            // The original parser compares against positive LAND exits only;
            // a negative exit is a closed door and its far side is not visible.
            if (target <= 0) continue;
            if (gate == target) return true;
        }
        return false;
    }

    fn objectDescription(self: *const Game, index: i64) ?[]const u8 {
        const entry = self.vocabEntry(index) orelse return null;
        const carried = self.hasInInventory(entry.word);
        const first = if (carried) entry.text_a else entry.text_b;
        const second = if (carried) entry.text_b else entry.text_a;
        return self.textForId(first) orelse self.textForId(second);
    }

    /// Reproduce the room scan of the original examine handler at
    /// 0x1755:0x277f: special TEXT records first, then a joined list of
    /// unnamed objects whose OBNINT gate is the current room.
    fn roomObjectListing(self: *const Game) ![]const u8 {
        var out = std.ArrayList(u8).empty;
        const w = out.writer(self.allocator);
        var names = std.ArrayList([]const u8).empty;
        for (self.vocab) |entry| {
            if (entry.room_gate != self.room or self.hasInInventory(entry.word)) continue;
            if (entry.class == 6) {
                if (self.textForId(entry.text_b)) |text| try w.print("{s}\n", .{text});
            }
            if (self.textForId(entry.text_a)) |text| try w.print("{s}\n", .{text});
            if (entry.class < 2 and entry.text_a == 0) {
                try names.append(self.allocator, self.localizedWord(entry.word));
            }
        }
        if (names.items.len == 0) return out.toOwnedSlice(self.allocator);
        const single = self.message("examine.7", "Hier befindet sich ", "You see ");
        const plural = self.message("examine.8", "Hier befinden sich ", "You see ");
        try w.writeAll(if (names.items.len == 1) single else plural);
        if (self.locale == .de) {
            const comma = self.message("examine.9", ", ", ", ");
            const and_word = self.message("examine.11", " und ", " and ");
            for (names.items, 0..) |name, idx| {
                if (idx > 0) try w.writeAll(if (idx + 1 == names.items.len) and_word else comma);
                try w.writeAll(name);
            }
            try w.writeAll(self.message("examine.10", ".", "."));
        } else {
            for (names.items, 0..) |name, idx| {
                if (idx > 0) try w.writeAll(if (idx + 1 == names.items.len) " and " else ", ");
                try w.writeAll(name);
            }
            try w.writeAll(".");
        }
        return out.toOwnedSlice(self.allocator);
    }

    fn containerSuffix(self: *const Game, entry: VocabEntry) ![]const u8 {
        if (entry.class != 2 and entry.class != 4) return "";
        if ((self.flags.get(entry.id + 0x5de4) orelse 0) == 1) {
            return self.message("examine.5", "ist zu.", "is closed.");
        }
        if (entry.class == 4) return self.message("examine.6", "ist offen.", "is open.");
        var names = std.ArrayList([]const u8).empty;
        for (self.vocab) |candidate| {
            if (candidate.room_gate == -entry.id and candidate.class != 3) {
                try names.append(self.allocator, self.localizedWord(candidate.word));
            }
        }
        const open_msg = std.mem.trimRight(u8, self.message("examine.12", "ist offen und enthält ", "is open and contains "), " ");
        if (names.items.len == 0) {
            return std.fmt.allocPrint(self.allocator, "{s} {s}", .{
                open_msg,
                self.message("examine.13", "nichts.", "nothing."),
            }) catch unreachable;
        }
        var out = std.ArrayList(u8).empty;
        const w = out.writer(self.allocator);
        try w.writeAll(open_msg);
        try w.writeAll(" ");
        for (names.items, 0..) |name, idx| {
            if (idx > 0) try w.writeAll(if (idx + 1 == names.items.len) self.message("examine.11", " und ", " and ") else self.message("examine.9", ", ", ", "));
            try w.writeAll(name);
        }
        try w.writeAll(self.message("examine.10", ".", "."));
        return out.toOwnedSlice(self.allocator);
    }

    fn localizedWord(self: *const Game, german: []const u8) []const u8 {
        if (self.locale == .de) return german;
        return locale_data.lookup(&locale_data.noun_labels, german) orelse
            locale_data.lookup(&locale_data.verb_labels, german) orelse german;
    }

    fn englishFor(pairs: []const locale_data.Pair, word: []const u8) ?[]const u8 {
        for (pairs) |pair| {
            if (eqIgnoreCase(pair.de, word)) return pair.en;
        }
        return null;
    }

    pub fn localizeAction(self: *Game, action: []const u8) ![]const u8 {
        if (self.locale == .de) return action;
        var out = std.ArrayList(u8).empty;
        var it = std.mem.tokenizeAny(u8, action, " \t,.;:!?");
        var first = true;
        while (it.next()) |token| {
            const lower = try lowerDup(self.allocator, token);
            const translated =
                englishFor(&action_replacements, lower) orelse
                englishFor(&locale_data.verb_labels, lower) orelse
                englishFor(&locale_data.noun_labels, lower) orelse token;
            if (translated.len == 0) continue; // German filler such as "nach"
            if (!first) try out.append(self.allocator, ' ');
            first = false;
            if (std.ascii.isUpper(token[0])) {
                try out.append(self.allocator, std.ascii.toUpper(translated[0]));
                try out.appendSlice(self.allocator, translated[1..]);
            } else {
                try out.appendSlice(self.allocator, translated);
            }
        }
        return out.toOwnedSlice(self.allocator);
    }

    fn hasInInventory(self: *const Game, word: []const u8) bool {
        for (self.inventory.items) |item| {
            if (eqIgnoreCase(item, word)) return true;
        }
        return false;
    }

    fn dropFromInventory(self: *Game, word: []const u8) bool {
        for (self.inventory.items, 0..) |item, i| {
            if (eqIgnoreCase(item, word)) {
                _ = self.inventory.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    fn directionName(self: *const Game, dir: Direction) []const u8 {
        return switch (dir) {
            .north => self.localizedWord("norden"),
            .south => self.localizedWord("süden"),
            .east => self.localizedWord("osten"),
            .west => self.localizedWord("westen"),
            .up => self.localizedWord("rauf"),
            .down => self.localizedWord("runter"),
        };
    }

    fn directionFromWord(self: *const Game, tokens: []const []const u8) ?Direction {
        for (tokens) |tok| {
            if (eqIgnoreCase(tok, "norden") or eqIgnoreCase(tok, "nord") or eqIgnoreCase(tok, "north")) return .north;
            if (eqIgnoreCase(tok, "süden") or eqIgnoreCase(tok, "süd") or eqIgnoreCase(tok, "south")) return .south;
            if (eqIgnoreCase(tok, "osten") or eqIgnoreCase(tok, "ost") or eqIgnoreCase(tok, "east")) return .east;
            if (eqIgnoreCase(tok, "westen") or eqIgnoreCase(tok, "west")) return .west;
            if (eqIgnoreCase(tok, "rauf") or eqIgnoreCase(tok, "hinauf") or eqIgnoreCase(tok, "up")) return .up;
            if (eqIgnoreCase(tok, "runter") or eqIgnoreCase(tok, "hinunter") or eqIgnoreCase(tok, "down")) return .down;
        }
        _ = self;
        return null;
    }

    fn directionFromId(id: i64) ?Direction {
        return switch (id) {
            10 => .north,
            11 => .south,
            12 => .east,
            13 => .west,
            14 => .up,
            15 => .down,
            else => null,
        };
    }

    const all_directions = [_]struct { name: []const u8, dir: Direction }{
        .{ .name = "north", .dir = .north },
        .{ .name = "south", .dir = .south },
        .{ .name = "east", .dir = .east },
        .{ .name = "west", .dir = .west },
        .{ .name = "up", .dir = .up },
        .{ .name = "down", .dir = .down },
    };

    pub fn look(self: *Game) ![]const u8 {
        const pic = self.pictureValue();
        return std.fmt.allocPrint(self.allocator, "{s} {d} ( {s} {d} )\n{s}\n{s}", .{
            self.tr("Du bist hier:"), self.room,                                                                         self.tr("Bild"), pic,
            try self.exitSummary(),   if (self.locale == .de) "Was möchtest du tun?" else "What would you like to do?",
        }) catch unreachable;
    }

    fn exitSummary(self: *Game) ![]const u8 {
        var out = std.ArrayList(u8).empty;
        const w = out.writer(self.allocator);
        try w.writeAll(self.tr("Ausgang"));
        try w.writeAll(":");
        var any = false;
        for (all_directions) |entry| {
            if (self.exitTo(entry.dir) != 0) {
                try w.print(" {s}", .{self.directionName(entry.dir)});
                any = true;
            }
        }
        if (!any) try w.writeAll(" -");
        return out.toOwnedSlice(self.allocator);
    }

    pub fn choices(self: *Game) ![]Choice {
        var out = std.ArrayList(Choice).empty;

        // The original point-and-click data lives in VORS.BIN: each screen has
        // up to 15 labelled hit rectangles. Use those labels verbatim as
        // commands so both input paths reach the same parser.
        // The original selects a VORS.BIN record with the picture id read from
        // the BILD resource (global 0x32d0), not with the room id.
        const vors_record = self.pictureValue();
        var region_count: usize = 0;
        for (self.regions) |region| {
            if (region.screen != vors_record) continue;
            const action = self.actionForSlot(region);
            if (action.len == 0) continue;
            var duplicate = false;
            for (out.items) |existing| {
                if (std.mem.eql(u8, existing.command, action)) duplicate = true;
            }
            if (duplicate) continue;
            const label = try self.localizeAction(action);
            try out.append(self.allocator, .{ .label = label, .command = action });
            region_count += 1;
        }
        // OBLISTE.BIN is the original ';' command menu. Its labels are fed to
        // the same parser as typed commands and VORS hotspot labels.
        var menu_count: usize = 0;
        if (self.room >= 0 and self.room < @as(i64, @intCast(self.action_menu.len))) {
            for (self.action_menu[@intCast(self.room)]) |action| {
                var duplicate = false;
                for (out.items) |existing| {
                    if (std.mem.eql(u8, existing.command, action)) duplicate = true;
                }
                if (duplicate) continue;
                const label = try self.localizeAction(action);
                try out.append(self.allocator, .{ .label = label, .command = action });
                menu_count += 1;
            }
        }
        if (region_count > 0 or menu_count > 0) {
            try out.append(self.allocator, .{ .label = self.tr("Inventar"), .command = "inventur" });
            try out.append(self.allocator, .{ .label = self.tr("Hilfe"), .command = "hilfe" });
            return out.toOwnedSlice(self.allocator);
        }

        for (all_directions) |entry| {
            const dir = entry.dir;
            if (self.exitTo(dir) == 0) continue;
            const label = try std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ self.tr("Ausgang"), self.directionName(dir) });
            const command = try std.fmt.allocPrint(self.allocator, "gehe {s}", .{self.localizedWord(switch (dir) {
                .north => "norden",
                .south => "süden",
                .east => "osten",
                .west => "westen",
                .up => "rauf",
                .down => "runter",
            })});
            try out.append(self.allocator, .{ .label = label, .command = command });
        }
        try out.append(self.allocator, .{ .label = self.tr("Inventar"), .command = "inventur" });
        try out.append(self.allocator, .{ .label = self.tr("Hilfe"), .command = "hilfe" });
        try out.append(self.allocator, .{ .label = self.localizedWord("untersuche"), .command = "untersuche" });

        // Object buttons are derived from the room's position in the original
        // OBW group structure. This is an interaction aid, not a claim that the
        // original game exposed this exact click target set.
        const words = asArray(self.root.object.get("vocabulary") orelse return out.toOwnedSlice(self.allocator)) orelse return out.toOwnedSlice(self.allocator);
        var groups: i64 = 0;
        for (words.items) |entry| {
            if (asObject(entry)) |o| groups = @max(groups, objectInt(o, "group"));
        }
        const wanted = @mod(self.room - 1, groups + 1);
        var added: usize = 0;
        for (words.items) |entry| {
            const o = asObject(entry) orelse continue;
            if (objectInt(o, "group") != wanted) continue;
            const german = objectString(o, "word");
            if (german.len == 0 or eqIgnoreCase(german, "ende")) continue;
            if (self.verb_by_word.contains(german)) continue;
            const label = self.localizedWord(german);
            const command = try std.fmt.allocPrint(self.allocator, "untersuche {s}", .{german});
            try out.append(self.allocator, .{ .label = label, .command = command });
            added += 1;
            if (added >= 6) break;
        }
        return out.toOwnedSlice(self.allocator);
    }

    /// Mutable view of the original globals that OVR rules read and write.
    const OverlayState = struct {
        room: i64,
        verb: i64,
        object: i64,
        object2: i64,
        score: i64,
    };

    const OverlayContext = struct {
        game: *Game,
        state: *OverlayState,

        fn context(self: *OverlayContext) overlay_eval.Context {
            return .{
                .ptr = @ptrCast(self),
                .read_var = readVar,
                .write_var = writeVar,
                .read_flag = readFlag,
                .write_flag = writeFlag,
                .message = messageForId,
            };
        }

        fn cast(ptr: *anyopaque) *OverlayContext {
            return @ptrCast(@alignCast(ptr));
        }

        fn readVar(ptr: *anyopaque, name: []const u8) i64 {
            const self = cast(ptr);
            if (std.mem.eql(u8, name, "room")) return self.state.room;
            if (std.mem.eql(u8, name, "verb")) return self.state.verb;
            if (std.mem.eql(u8, name, "object")) return self.state.object;
            if (std.mem.eql(u8, name, "object2")) return self.state.object2;
            if (std.mem.eql(u8, name, "score")) return self.state.score;
            if (std.mem.eql(u8, name, "scene")) return self.game.pictureValue();
            if (std.mem.eql(u8, name, "object_gate")) {
                // The main dispatcher compares the current room with
                // OBNINT.field_b for the active object (word table at 0x449e,
                // indexed by 1-based object id). Room 0x11 may have cleared
                // that runtime word, so prefer the live table over the asset.
                const address = 0x449e + self.state.object * 2;
                if (self.game.words.get(address)) |value| return value;
                if (self.game.flags.get(address)) |value| return value;
                if (self.game.vocab_by_id.get(self.state.object)) |idx| {
                    if (idx < self.game.vocab.len) return self.game.vocab[idx].room_gate;
                }
                return 0;
            }
            if (std.mem.eql(u8, name, "true")) return 1;
            if (std.mem.eql(u8, name, "pending_room")) {
                if (self.game.words.get(0xc9be)) |value| return value;
                return self.game.flags.get(0xc9be) orelse 0;
            }
            // Ghidra locals have no stable original-global counterpart.
            return 0;
        }

        fn writeVar(ptr: *anyopaque, name: []const u8, value: i64) void {
            const self = cast(ptr);
            if (std.mem.eql(u8, name, "room")) {
                self.state.room = value;
            } else if (std.mem.eql(u8, name, "verb")) {
                self.state.verb = value;
            } else if (std.mem.eql(u8, name, "object")) {
                self.state.object = value;
            } else if (std.mem.eql(u8, name, "object2")) {
                self.state.object2 = value;
            } else if (std.mem.eql(u8, name, "score")) {
                self.state.score = value;
            } else if (std.mem.eql(u8, name, "pending_room")) {
                self.game.words.put(0xc9be, @truncate(@as(u64, @bitCast(value)))) catch {};
            }
        }

        fn readFlag(ptr: *anyopaque, address: i64) i64 {
            const self = cast(ptr);
            if (address == 0xbe1b) return self.state.room;
            if (address == 0xcac2) return self.state.verb;
            if (address == 0xbe5c) return self.state.object;
            if (address == 0xbe5e) return self.state.object2;
            if (address == 0xcae4) return self.state.score;
            if (address == 0xc918) return self.game.pictureValue();
            if (self.game.overlay_db) |db| {
                if (db.isLocal(address)) return self.game.overlay_locals.get(address) orelse 0;
            }
            if (self.game.dword_flags.get(address)) |value| return @as(i32, @bitCast(value));
            if (self.game.words.get(address)) |value| return @as(i16, @bitCast(value));
            return self.game.flags.get(address) orelse 0;
        }

        fn writeFlag(ptr: *anyopaque, address: i64, value: i64) void {
            const self = cast(ptr);
            if (address == 0xbe1b) {
                self.state.room = value;
            } else if (address == 0xcac2) {
                self.state.verb = value;
            } else if (address == 0xbe5c) {
                self.state.object = value;
            } else if (address == 0xbe5e) {
                self.state.object2 = value;
            } else if (address == 0xcae4) {
                self.state.score = value;
            } else if (address == 0xc918) {
                self.game.picture_override = @mod(value, 256);
            }
            if (self.game.overlay_db) |db| {
                if (db.isLocal(address)) {
                    self.game.overlay_locals.put(address, value) catch {};
                    return;
                }
            }
            // Use the same width-aware store as the main prelude so overlay
            // writes to known word globals are not silently narrowed to bytes.
            self.game.writeGlobal(address, value);
        }

        fn messageForId(ptr: *anyopaque, id: i64) []const u8 {
            const self = cast(ptr);
            return self.game.textForId(id) orelse "";
        }
    };

    /// Apply the REA-derived HEXUMA.OVR room/action rules to one command.
    /// Overlay messages are appended after the verb handler response, matching
    /// the original shared output buffer. State-only rules leave base intact.
    const PreludeResult = struct { allowed: bool, early_text: ?[]const u8 = null };

    /// Globals whose width is fixed by the original decompilation. Using the
    /// right map matters for `.dat` parity and for sign-extension in guards.
    fn isWordGlobal(address: i64) bool {
        return switch (address) {
            0xcae8, 0xc9c0, 0xc9be, 0x3d94, 0x3dc6, 0x3e4a, 0x7d7e, 0xf352, 0xf3b6, 0xf452 => true,
            else => false,
        };
    }

    fn writeDwordGlobal(self: *Game, address: i64, value: i64) void {
        self.dword_flags.put(address, @truncate(@as(u64, @bitCast(value)))) catch {};
    }

    fn writeGlobal(self: *Game, address: i64, value: i64) void {
        if (isWordGlobal(address)) {
            self.words.put(address, @truncate(@as(u64, @bitCast(value)))) catch {};
        } else if (value > 0xffff or value < -0x80000000 or self.dword_flags.contains(address)) {
            self.dword_flags.put(address, @truncate(@as(u64, @bitCast(value)))) catch {};
        } else if (value > 0xff or value == -1 or value < -0x8000 or self.words.contains(address)) {
            self.words.put(address, @truncate(@as(u64, @bitCast(value)))) catch {};
        } else {
            self.flags.put(address, @truncate(@as(u64, @bitCast(value)))) catch {};
        }
    }

    /// Reproduce the prelude of the original effect dispatcher at 0x11be9.
    /// It resets per-command globals, derives the two hotspot-exclusion flags,
    /// handles the inline room 0x11/0x1a state machines, and reports the exact
    /// early-return message when the original never calls an overlay unit.
    fn overlayPrelude(self: *Game, verb: i64) !PreludeResult {
        var early_text: ?[]const u8 = null;
        if (self.room > 0xa0 and verb == 3 and self.object_slot == 0x24a) {
            if (self.textForId(0x8e)) |text| early_text = text;
        }
        self.writeGlobal(0xcae8, 0);
        self.writeGlobal(0xcaea, 0);
        self.writeGlobal(0xc9c0, 0);
        self.flags.put(0xf2f9, 0) catch {};
        self.flags.put(0xf2fa, 0) catch {};

        if (self.room == 0xb8) self.writeGlobal(0x3d94, 1);
        if (self.room == 0xbd) self.writeGlobal(0x3dc6, 1);
        if (self.room == 0xc2) self.writeGlobal(0x3e4a, 1);

        if ((self.flags.get(0x5e03) orelse 0) == 1) {
            const gate = self.readGlobal(0x44dc);
            if (gate == -1 or gate == self.room) {
                try self.flags.put(0xf2f9, 1);
                try self.flags.put(0xf2fa, 0);
            }
        }
        if ((self.flags.get(0x5f71) orelse 0) == 1) {
            const gate = self.readGlobal(0x47b8);
            if (gate == -1 or gate == self.room) {
                try self.flags.put(0xf2f9, (self.flags.get(0xf2f9) orelse 0) + 2);
                try self.flags.put(0xf2fa, 0);
            }
        }

        const f2f9 = self.flags.get(0xf2f9) orelse 0;
        const room = self.room;
        if (f2f9 == 0 and verb == 3) {
            const excluded = room == 0x11 or room == 0x10 or room == 0x0f or
                room == 0x0c or room == 0x0d or
                (room > 0x21 and room < 0x26) or room == 0x5e or room == 0x5f or
                (room > 0xa3 and room < 0xa9);
            if (excluded) {
                try self.flags.put(0xf2fa, 1);
                return .{ .allowed = false, .early_text = early_text };
            }
        }
        if ((self.flags.get(0xf2fa) orelse 0) != 1) try self.flags.put(0xf2fa, 0);

        // Room 0x11 has an inline state machine in 0x11be9 that is not part of
        // any HEXUMA.OVR unit. It first clears OBNINT.field_b for scenery
        // objects, then branches on 0xf330 before the normal overlay dispatch.
        if (room == 0x11) {
            for (self.vocab) |entry| {
                // The original loop at 0x11be9:111-136 walks 1-based object
                // ids, not compact array positions: it indexes the runtime
                // OBNINT table at `id * 2 + 0x449e` and the class bytes at
                // `id + 0x5140`.
                const object_id = entry.id;
                const excluded_object = object_id == 0x46 or object_id == 0x41 or
                    object_id == 0x1d or object_id == 0x62 or object_id == 0x1f or
                    object_id == 0x91 or object_id == 0x182 or object_id == 0xe1 or
                    object_id == 0xe6 or object_id == 0xe5 or object_id == 0xe7 or
                    object_id == 0xe9 or object_id == 0xea or object_id == 0xe8 or
                    object_id == 0xec or object_id == 0x60 or object_id == 0xbf or
                    object_id == 0x100;
                if (entry.class == 3 or excluded_object) continue;
                const gate_addr = 0x449e + object_id * 2;
                const gate = if (self.words.get(gate_addr)) |value|
                    value
                else if (self.vocab_by_id.get(object_id)) |idx|
                    self.vocab[idx].room_gate
                else
                    0;
                if (gate != -1) continue;
                self.words.put(gate_addr, 0) catch {};
            }
            const f330 = self.flags.get(0xf330) orelse 0;
            if (f330 == 0) {
                self.flags.put(0xf330, 2) catch {};
                if (self.textForId(0x67f)) |text| early_text = text;
                self.writeGlobal(0xcae8, 1);
                return .{ .allowed = false, .early_text = early_text };
            }
            if (f330 == 2) {
                if (self.textForId(0x686)) |text| early_text = text;
                self.writeGlobal(0xcae8, 1);
                self.flags.put(0xcbeb, 1) catch {};
                return .{ .allowed = false, .early_text = early_text };
            }
            self.flags.put(0xf2f4, 0) catch {};
        }

        // Room 0x1a resets a large block of inline globals before the overlay
        // call. The reload branch on 0xf2f5 is data-file reinitialisation and
        // has no additional observable effect on extracted-state-only play.
        if (room == 0x1a) {
            if ((self.flags.get(0xf2f3) orelse 0) == 0) {
                self.flags.put(0xf2f3, 1) catch {};
                self.writeDwordGlobal(0xcae4, self.readGlobal(0xcae4) + 0x32);
            }
            self.flags.put(0xc918, 1) catch {};
            const reset_bytes = [_]i64{
                0xf348, 0xf349, 0xf34a, 0xf34b, 0xf34c, 0xf34d, 0xf34e, 0xf34f,
                0xf350, 0xf354, 0xf355, 0xf356, 0xf357, 0xf358, 0xf359, 0xf35a,
                0xf35b, 0xf35c, 0xf35d, 0xf35e, 0xf35f, 0xf360, 0xf363, 0xf364,
                0xf365, 0xf366, 0xf367, 0xf368, 0xf369, 0xf36a, 0xf36b, 0xf36c,
                0xf36d, 0xf36e, 0xf36f, 0xf370, 0xf371, 0xf372, 0xf373, 0xf374,
                0xf375, 0xf378, 0xf37f, 0xf380, 0xf381, 0xf382, 0xf383, 0xf384,
                0xf387, 0xf388, 0xf389, 0xf38a, 0xf38b, 0xf38c, 0xf38d, 0xf38e,
                0xf38f, 0xf390, 0xf391, 0xf392, 0xf393, 0xf394, 0xf395, 0xf39d,
                0xf39e, 0xf39f, 0xf3a0, 0xf3a1, 0xf3a2, 0xf3a3, 0xf3a4, 0xf3a5,
                0xf3a6, 0xf3a7, 0xf3a8, 0xf3a9, 0xf3aa, 0xf3ab, 0xf3ac, 0xf3ad,
                0xf3ae, 0xf3af, 0xf3b0, 0xf3b1, 0xf3b2, 0xf3b3, 0xf3b4, 0xf3b5,
                0xf3b8, 0xf3b9, 0xf3c7, 0xf3c8, 0xf3c9, 0xf3ca, 0xf3cc, 0xf3cd,
                0xf3ce, 0xf3cf, 0xf3d0, 0xf3d1, 0xf3d2, 0xf3d3, 0xf3d4, 0xf3d5,
                0xf3d6, 0xf3d7, 0xf3d8, 0xf3d9, 0xf3da, 0xf3db, 0xf3dc, 0xf3dd,
                0xf3de, 0xf3df, 0xf3e0, 0xf3e1, 0xf3e2, 0xf3e3, 0xf3e4, 0xf3e5,
                0xf3e6, 0xf3e7, 0xf3e8, 0xf3e9, 0xf3ea, 0xf3eb, 0xf3ec, 0xf3ed,
                0xf3ee, 0xf3ef, 0xf3f0, 0xf3f1, 0xf3f2, 0xf3f3, 0xf3f4, 0xf3f5,
                0xf3f6, 0xf3f7, 0xf3f8, 0xf3f9, 0xf3fa, 0xf3fb, 0xf3fc, 0xf3fd,
                0xf3fe, 0xf3ff, 0xf400, 0xf401, 0xf414, 0xf415, 0xf417, 0xf418,
                0xf419, 0xf41a, 0xf41c, 0xf41d, 0xf41e, 0xf41f, 0xf420, 0xf421,
                0xf422, 0xf423, 0xf424, 0xf425, 0xf426, 0xf427, 0xf428, 0xf429,
                0xf42a, 0xf42b, 0xf42c, 0xf42d, 0xf42e, 0xf42f, 0xf430, 0xf431,
                0xf432, 0xf433, 0xf434, 0xf435, 0xf436, 0xf437, 0xf438, 0xf439,
                0xf43a, 0xf43b, 0xf43c, 0xf43d, 0xf43e, 0xf43f, 0xf440, 0xf442,
                0xf444, 0xf445, 0xf446, 0xf447, 0xf448, 0xf449, 0xf44a, 0xf44b,
                0xf44d, 0xf450, 0xf454, 0xf455, 0xf456, 0xf457, 0xf458, 0xf459,
                0xf45a, 0xf45b, 0xf45c, 0xf45d, 0xf45f, 0xf460, 0xf461, 0xf462,
                0xf463, 0xf464,
            };
            for (reset_bytes) |address| self.flags.put(address, 0) catch {};
            self.writeGlobal(0xf352, 0);
            self.writeGlobal(0xf3b6, 0);
            self.flags.put(0xf361, 6) catch {};
            self.flags.put(0xf362, 6) catch {};
            self.flags.put(0xf416, 0xa0) catch {};
            self.flags.put(0xf41b, 0xa2) catch {};
            self.flags.put(0xf385, 0x94) catch {};
            self.flags.put(0xf386, 0x97) catch {};
            self.flags.put(0xf443, 1) catch {};
            self.flags.put(0xf44c, 1) catch {};
            self.flags.put(0xf44e, 1) catch {};
            self.flags.put(0xf44f, 1) catch {};
            self.writeGlobal(0xf452, 0xc5);
            self.flags.put(0xf45e, 1) catch {};
        }

        // Rooms that belong to no compiled overlay unit reach the tail of the
        // main dispatcher at 0x11be9. It copies the Pascal string at
        // segment 0x119c:0 into 0xcaea and displays it. The extracted pool is
        // `dispatch.0`; there is no overlay rule database entry for these rooms.
        if (self.overlay_db) |db| {
            if (!db.containsRoom(room)) {
                if (early_text == null) {
                    if (self.code_msg_by_key.get("dispatch.0")) |text| early_text = text;
                }
                return .{ .allowed = false, .early_text = early_text };
            }
        }

        return .{ .allowed = true, .early_text = early_text };
    }

    fn readGlobal(self: *const Game, address: i64) i64 {
        if (self.dword_flags.get(address)) |value| return @as(i32, @bitCast(value));
        if (self.words.get(address)) |value| return @as(i16, @bitCast(value));
        return self.flags.get(address) orelse 0;
    }

    fn withOverlay(self: *Game, base: []const u8, verb: i64, object_id: i64) ![]const u8 {
        const prelude = try self.overlayPrelude(verb);
        var combined = base;
        if (prelude.early_text) |text| {
            var out = std.ArrayList(u8).empty;
            const w = out.writer(self.allocator);
            try w.writeAll(base);
            if (base.len != 0) try w.writeByte('\n');
            try w.writeAll(text);
            combined = try out.toOwnedSlice(self.allocator);
        }
        if (!prelude.allowed) return combined;
        const db = self.overlay_db orelse return combined;
        var state = OverlayState{
            .room = self.room,
            .verb = verb,
            .object = object_id,
            .object2 = self.object2_slot,
            .score = @intCast(self.score),
        };
        var context = OverlayContext{ .game = self, .state = &state };
        const result = try overlay_eval.run(self.allocator, db, context.context(), state.room);

        self.room = state.room;
        self.score = @intCast(@max(0, state.score));
        self.object_slot = state.object;
        self.object2_slot = state.object2;
        if (result.picture) |picture| self.picture_override = picture;
        if (result.messages.items.len == 0) return combined;

        // The original verb handler and the room effect dispatcher both write
        // into the same output buffer; overlay text is appended, not a
        // replacement for the parser response.
        var out = std.ArrayList(u8).empty;
        const w = out.writer(self.allocator);
        try w.writeAll(combined);
        if (combined.len != 0) try w.writeByte('\n');
        for (result.messages.items, 0..) |text, i| {
            if (i != 0) try w.writeByte('\n');
            try w.writeAll(text);
        }
        return out.toOwnedSlice(self.allocator);
    }

    /// Diagnostic entry point for the REA-derived rule database. It reports the
    /// messages and picture changes that would be produced for one command.
    pub fn overlayDebug(self: *Game, verb: i64, object: i64, object2: i64) ![]const u8 {
        // The diagnostic CLI passes the parser's object slots explicitly; the
        // live game stores them on `self` before the dispatcher runs.
        self.object_slot = object;
        self.object2_slot = object2;
        const prelude = try self.overlayPrelude(verb);
        var out = std.ArrayList(u8).empty;
        const w = out.writer(self.allocator);
        try w.print("room={d} verb={d} object={d} object2={d} allowed={s} f2f9={d} f2fa={d} returned={s}\n", .{
            self.room,
            verb,
            object,
            object2,
            if (prelude.allowed) "yes" else "no",
            self.flags.get(0xf2f9) orelse 0,
            self.flags.get(0xf2fa) orelse 0,
            "no",
        });
        if (prelude.early_text) |text| try w.print("msg early: {s}\n", .{text});
        if (!prelude.allowed) return out.toOwnedSlice(self.allocator);
        const db = self.overlay_db orelse return out.toOwnedSlice(self.allocator);
        var state = OverlayState{
            .room = self.room,
            .verb = verb,
            .object = object,
            .object2 = object2,
            .score = @intCast(self.score),
        };
        var context = OverlayContext{ .game = self, .state = &state };
        const result = try overlay_eval.run(self.allocator, db, context.context(), state.room);
        // Rewrite the header now that the real rule evaluation has completed.
        out.clearRetainingCapacity();
        try w.print("room={d} verb={d} object={d} object2={d} allowed={s} f2f9={d} f2fa={d} returned={s}\n", .{
            state.room,
            verb,
            object,
            object2,
            "yes",
            self.flags.get(0xf2f9) orelse 0,
            self.flags.get(0xf2fa) orelse 0,
            if (result.returned) "yes" else "no",
        });
        if (prelude.early_text) |text| try w.print("msg early: {s}\n", .{text});
        for (result.message_ids.items, 0..) |id, i| {
            const text = if (i < result.messages.items.len) result.messages.items[i] else "";
            try w.print("msg 0x{x}: {s}\n", .{ id, text });
        }
        if (result.picture) |picture| try w.print("picture {d}\n", .{picture});
        return out.toOwnedSlice(self.allocator);
    }

    pub fn execute(self: *Game, raw_input: []const u8) ![]const u8 {
        const input = std.mem.trim(u8, raw_input, " \t\r\n");
        if (input.len == 0) {
            return self.message("door.5", "Diesen Satz verstehe ich nicht.", "Please enter a command.");
        }

        if (std.fmt.parseInt(usize, input, 10)) |choice_num| {
            const list = try self.choices();
            if (choice_num >= 1 and choice_num <= list.len) {
                return self.execute(list[choice_num - 1].command);
            }
            return self.message("parser.0", "Ich kann Ihren Satz leider nicht verstehen.", "I cannot understand your sentence.");
        } else |_| {}

        const lower = try lowerDup(self.allocator, input);
        if (eqIgnoreCase(lower, "ende") or eqIgnoreCase(lower, "quit") or eqIgnoreCase(lower, "exit")) {
            self.quit_requested = true;
            return if (self.locale == .de) "Auf Wiedersehen." else "Goodbye.";
        }
        var tokens = std.ArrayList([]const u8).empty;
        var it = std.mem.tokenizeAny(u8, lower, " \t,.;!?");
        while (it.next()) |tok| {
            var skip = false;
            for (skip_words) |sw| {
                if (eqIgnoreCase(tok, sw)) skip = true;
            }
            if (!skip) try tokens.append(self.allocator, tok);
        }
        if (tokens.items.len == 0) {
            return self.message("parser.0", "Ich kann Ihren Satz leider nicht verstehen.", "I cannot understand your sentence.");
        }

        var verb: ?i64 = null;
        var verb_pos: usize = 0;
        for (tokens.items, 0..) |tok, i| {
            if (self.verbId(tok)) |id| {
                verb = id;
                verb_pos = i;
                break;
            }
        }
        if (verb == null) {
            if (self.nounIndex(tokens.items[0])) |_| {
                verb = 3; // original id for "untersuche"
                verb_pos = 0;
            }
        }
        if (verb == null) {
            return self.message("parser.0", "Ich kann Ihren Satz leider nicht verstehen.", "I cannot understand your sentence.");
        }

        const v = verb.?;
        self.moves += 1;

        const move_dir = directionFromId(v) orelse blk: {
            if (v == 7 or v == 119 or v == 3) {
                break :blk self.directionFromWord(tokens.items);
            }
            break :blk null;
        };
        if (move_dir) |dir| {
            // The original movement handler clears this word on every exit path.
            self.writeGlobal(0x7d7e, 0);
            const target = self.exitTo(dir);
            if (target == 0) {
                const no_way = self.textForId(0x61) orelse self.message(
                    "move.1",
                    "Das ist von hier aus nicht erreichbar.",
                    "You cannot reach it from here.",
                );
                return self.withOverlay(no_way, v, 0);
            }
            if (target < 0) {
                // The original movement handler leaves the room unchanged and
                // only reports a matching class-4 door; room 1 south (-2) has
                // no such object, so it is deliberately silent.
                const blocked = self.blockedDoorMessage(dir) orelse "";
                return self.withOverlay(blocked, v, 0);
            }
            self.room = target;
            self.score += 1;
            const move_text = std.fmt.allocPrint(self.allocator, "{s} {s}.", .{ self.tr("Du gehst"), self.directionName(dir) }) catch unreachable;
            self.object_slot = 0;
            self.object2_slot = 0;
            return self.withOverlay(move_text, v, 0);
        }

        var noun_index: ?i64 = null;
        var noun: []const u8 = "";
        var noun_token_pos: usize = 0;
        for (tokens.items, 0..) |tok, i| {
            if (i == verb_pos and self.verbId(tok) != null) continue;
            if (self.nounIndex(tok)) |idx| {
                if (!self.nounVisible(idx)) continue;
                noun_index = idx;
                noun_token_pos = i;
                noun = self.vocabularyWord(idx);
                break;
            }
        }
        const object_id: i64 = if (noun_index) |idx| (self.vocabularyId(idx) orelse 0) else 0;
        var object2_id: i64 = 0;
        if (noun_index) |first_idx| {
            for (tokens.items, 0..) |tok, i| {
                if (i <= noun_token_pos or i == verb_pos) continue;
                if (self.nounIndex(tok)) |idx| {
                    if (idx == first_idx or !self.nounVisible(idx)) continue;
                    object2_id = self.vocabularyId(idx) orelse 0;
                    break;
                }
            }
        }
        self.object_slot = object_id;
        self.object2_slot = object2_id;

        const base: []const u8 = switch (v) {
            5 => blk: { // inventur, original 0x1755:0x2e93
                const prefix = if (self.locale == .de)
                    (self.code_msg_by_key.get("inventory.1") orelse "Sie haben ")
                else
                    "You have ";
                if (self.inventory.items.len == 0) {
                    const nothing = if (self.locale == .de)
                        (self.code_msg_by_key.get("inventory.3") orelse "nichts.")
                    else
                        "nothing.";
                    break :blk std.fmt.allocPrint(self.allocator, "{s}{s}", .{ prefix, nothing }) catch unreachable;
                }
                const comma = if (self.locale == .de)
                    (self.code_msg_by_key.get("inventory.2") orelse ", ")
                else
                    ", ";
                const and_word = if (self.locale == .de)
                    (self.code_msg_by_key.get("inventory.5") orelse "und ")
                else
                    "and ";
                var out = std.ArrayList(u8).empty;
                const w = out.writer(self.allocator);
                try w.writeAll(prefix);
                for (self.inventory.items, 0..) |item, idx| {
                    if (idx > 0) {
                        try w.writeAll(if (idx + 1 == self.inventory.items.len) and_word else comma);
                    }
                    try w.writeAll(self.localizedWord(item));
                }
                try w.writeAll(".");
                break :blk try out.toOwnedSlice(self.allocator);
            },
            24 => self.tr("Hilfe"), // hilfe
            25 => std.fmt.allocPrint(self.allocator, "{s}: {d}\n{s}: {d}", .{ self.tr("Punkte"), self.score, if (self.locale == .de) "Züge" else "Moves", self.moves }) catch unreachable,
            50 => blk: {
                self.quit_requested = true;
                break :blk if (self.locale == .de) "Auf Wiedersehen." else "Goodbye.";
            },
            1 => blk: { // nimm, original 0x1755:0x203d
                if (noun_index == null or noun.len == 0) {
                    break :blk self.message("take.0", "Bitte geben Sie genau an, was Sie nehmen wollen.", "Please specify exactly what you want to take.");
                }
                const entry = self.vocabEntry(noun_index.?) orelse {
                    break :blk self.message("parser.3", "Das ist leider nicht möglich.", "That is not possible.");
                };
                if (self.hasInInventory(noun)) {
                    if (self.locale == .de) {
                        const fragment = self.code_msg_by_key.get("take.1") orelse "haben Sie schon.";
                        break :blk std.fmt.allocPrint(self.allocator, "{s} {s}", .{ noun, fragment }) catch unreachable;
                    }
                    break :blk std.fmt.allocPrint(self.allocator, "You already have {s}.", .{self.localizedWord(noun)}) catch unreachable;
                }
                // OBNBYT[0] at 0x5140: 0 is scenery, 1 portable, 2 a
                // container. The original rejects every other class here.
                if (entry.class != 1 and entry.class != 2) {
                    if (self.locale == .de) {
                        const fragment = self.code_msg_by_key.get("take.2") orelse "können Sie nicht nehmen!";
                        break :blk std.fmt.allocPrint(self.allocator, "{s} {s}", .{ noun, fragment }) catch unreachable;
                    }
                    break :blk std.fmt.allocPrint(self.allocator, "You cannot take {s}.", .{self.localizedWord(noun)}) catch unreachable;
                }
                try self.inventory.append(self.allocator, try self.allocator.dupe(u8, noun));
                self.score += 1;
                if (self.locale == .de) {
                    const prefix = self.code_msg_by_key.get("take.3") orelse "Sie haben ";
                    const suffix = self.code_msg_by_key.get("take.4") orelse "genommen.";
                    break :blk std.fmt.allocPrint(self.allocator, "{s}{s} {s}", .{ prefix, noun, suffix }) catch unreachable;
                }
                break :blk std.fmt.allocPrint(self.allocator, "You take {s}.", .{self.localizedWord(noun)}) catch unreachable;
            },
            4, 6 => blk: { // öffne / schließe, original 0x1755:0x31a1
                if (noun_index == null or noun.len == 0) {
                    break :blk self.message("parser.0", "Ich kann Ihren Satz leider nicht verstehen.", "I cannot understand your sentence.");
                }
                const id = self.vocabularyId(noun_index.?) orelse 0;
                const class = self.flags.get(id + 0x5140) orelse 0;
                const state = self.flags.get(id + 0x5de4) orelse 0;
                const closing = v == 6;
                const key: []const u8 = if (closing)
                    (if (class != 2 and class != 4) "openclose.4" else if (state == 1) "openclose.5" else "openclose.3")
                else
                    (if (class != 2 and class != 4) "openclose.0" else if (state == 0) "openclose.1" else "openclose.2");
                const english: []const u8 = if (closing)
                    (if (class != 2 and class != 4) "cannot be closed." else if (state == 1) "is already closed." else "is now closed.")
                else
                    (if (class != 2 and class != 4) "cannot be opened." else if (state == 0) "is already open." else "is now open.");
                if (class == 2 or class == 4) {
                    const desired: u8 = if (closing) 1 else 0;
                    if (state != desired) {
                        try self.flags.put(id + 0x5de4, desired);
                        // 0x1755:0x31a1 changes the sign of the LAND exit for
                        // this door and the reciprocal exit on the far side.
                        self.toggleDoor(id);
                    }
                }
                if (self.locale == .de) {
                    const fragment = self.code_msg_by_key.get(key) orelse english;
                    break :blk std.fmt.allocPrint(self.allocator, "{s} {s}", .{ noun, fragment }) catch unreachable;
                }
                break :blk std.fmt.allocPrint(self.allocator, "{s} {s}", .{ self.localizedWord(noun), english }) catch unreachable;
            },
            2 => blk: { // lege, original 0x1755:0x2362
                if (noun.len == 0) {
                    break :blk if (self.locale == .de)
                        (self.code_msg_by_key.get("drop.0") orelse "Bitte geben Sie genau an, was Sie weglegen wollen.")
                    else
                        "Please specify exactly what you want to put down.";
                }
                if (!self.dropFromInventory(noun)) {
                    if (self.locale == .de) {
                        const fragment = self.code_msg_by_key.get("drop.1") orelse "haben Sie ja gar nicht!";
                        break :blk std.fmt.allocPrint(self.allocator, "{s} {s}", .{ noun, fragment }) catch unreachable;
                    }
                    break :blk std.fmt.allocPrint(self.allocator, "You do not have {s}.", .{self.localizedWord(noun)}) catch unreachable;
                }
                if (self.locale == .de) {
                    const fragment = self.code_msg_by_key.get("parser.1") orelse "liegt jetzt hier auf dem Boden.";
                    break :blk std.fmt.allocPrint(self.allocator, "{s} {s}", .{ noun, fragment }) catch unreachable;
                }
                break :blk std.fmt.allocPrint(self.allocator, "{s} is now on the floor.", .{self.localizedWord(noun)}) catch unreachable;
            },
            8, 9 => "", // original handlers 0x1755:0x38cf and 0x373a are empty
            48 => if (self.locale == .de)
                (self.code_msg_by_key.get("ignite.0") orelse "Das kann man nicht anzünden.")
            else
                "That cannot be lit.",
            3, 57 => blk: { // untersuche / betrachte, original 0x1755:0x277f
                if (noun.len == 0) break :blk try self.roomObjectListing();
                if (self.locale == .de) {
                    if (noun_index) |idx| {
                        const desc = self.objectDescription(idx);
                        const entry = self.vocabEntry(idx);
                        const suffix = if (entry) |e| try self.containerSuffix(e) else "";
                        if (desc) |text| {
                            if (suffix.len == 0) break :blk text;
                            break :blk std.fmt.allocPrint(self.allocator, "{s} {s}", .{ text, suffix }) catch unreachable;
                        }
                        const fragment = self.message("examine.4", "hat keine besonderen Merkmale.", "has no special features.");
                        const base_text = std.fmt.allocPrint(self.allocator, "{s} {s}", .{ noun, fragment }) catch unreachable;
                        if (suffix.len == 0) break :blk base_text;
                        break :blk std.fmt.allocPrint(self.allocator, "{s} {s}", .{ base_text, suffix }) catch unreachable;
                    }
                }
                if (self.hasInInventory(noun) or noun_index != null) {
                    if (self.locale == .en) {
                        break :blk std.fmt.allocPrint(self.allocator, "You see: {s}.", .{self.localizedWord(noun)}) catch unreachable;
                    }
                    break :blk std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ noun, self.localizedWord(noun) }) catch unreachable;
                }
                if (self.locale == .de) {
                    const fragment = self.code_msg_by_key.get("examine.4") orelse "hat keine besonderen Merkmale.";
                    break :blk std.fmt.allocPrint(self.allocator, "{s} {s}", .{ noun, fragment }) catch unreachable;
                }
                break :blk "You see nothing special.";
            },
            else => blk: {
                if (v == 68 or eqIgnoreCase(lower, "quit") or eqIgnoreCase(lower, "ende")) {
                    self.quit_requested = true;
                    break :blk if (self.locale == .de) "Auf Wiedersehen." else "Goodbye.";
                }
                break :blk self.message("parser.3", "Das ist leider nicht möglich.", "That is not possible.");
            },
        };
        return self.withOverlay(base, v, object_id);
    }

    /// Original `.dat` field descriptor. The compact table is REA-derived from
    /// the 395 static call sites of the save finalizer at 0x2d100.
    const SaveField = struct {
        kind: []const u8,
        addr: i64 = 0,
        from: i64 = 0,
        to: i64 = 0,
        offset: i64 = 0,
        width: usize = 0,
        base: i64 = 0,
        stride: i64 = 0,
        count: usize = 0,
    };

    const SaveLayout = struct {
        fields: []SaveField,
        landscapes: usize,
        objects: usize,
        slots: usize,
    };

    const SaveLineReader = struct {
        data: []const u8,
        pos: usize = 0,

        fn next(self: *SaveLineReader) ![]const u8 {
            if (self.pos >= self.data.len) return error.InvalidSave;
            var end = self.pos;
            while (end < self.data.len and self.data[end] != '\n') end += 1;
            const line = std.mem.trimRight(u8, self.data[self.pos..end], "\r\n");
            self.pos = if (end < self.data.len) end + 1 else end;
            return line;
        }

        fn int(self: *SaveLineReader) !i64 {
            const line = try self.next();
            return std.fmt.parseInt(i64, std.mem.trim(u8, line, " \t"), 10) catch error.InvalidSave;
        }

        fn string(self: *SaveLineReader, width: usize) ![]const u8 {
            const line = try self.next();
            return line[0..@min(line.len, width)];
        }
    };

    fn readSaveLayout(self: *const Game) !SaveLayout {
        const root = try std.json.parseFromSliceLeaky(std.json.Value, self.allocator, @embedFile("data/save_layout.json"), .{});
        const obj = asObject(root) orelse return error.InvalidSaveLayout;
        const counts = asObject(obj.get("counts") orelse return error.InvalidSaveLayout) orelse return error.InvalidSaveLayout;
        const arr = asArray(obj.get("fields") orelse return error.InvalidSaveLayout) orelse return error.InvalidSaveLayout;
        const fields = try self.allocator.alloc(SaveField, arr.items.len);
        for (arr.items, 0..) |item, i| {
            const o = asObject(item) orelse return error.InvalidSaveLayout;
            fields[i] = .{
                .kind = objectString(o, "kind"),
                .addr = objectInt(o, "addr"),
                .from = objectInt(o, "from"),
                .to = objectInt(o, "to"),
                .offset = objectInt(o, "offset"),
                .width = @intCast(@max(0, objectInt(o, "width"))),
                .base = objectInt(o, "base"),
                .stride = objectInt(o, "stride"),
                .count = @intCast(@max(0, objectInt(o, "count"))),
            };
        }
        return .{
            .fields = fields,
            .landscapes = @intCast(@max(0, objectInt(counts, "landscapes"))),
            .objects = @intCast(@max(0, objectInt(counts, "objects"))),
            .slots = @intCast(@max(0, objectInt(counts, "slots"))),
        };
    }

    fn savedByte(self: *const Game, addr: i64) i64 {
        if (addr == 0xbe1b) return @mod(self.room, 256);
        return self.flags.get(addr) orelse 0;
    }

    fn savedWord(self: *const Game, addr: i64) i64 {
        return self.words.get(addr) orelse 0;
    }

    fn siblingPath(self: *const Game, path: []const u8, ext: []const u8) ![]const u8 {
        const dir = std.fs.path.dirname(path);
        const stem = std.fs.path.stem(path);
        if (dir) |d| return std.fmt.allocPrint(self.allocator, "{s}/{s}.{s}", .{ d, stem, ext });
        return std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ stem, ext });
    }

    fn writePascalLine(w: anytype, text: []const u8, width: usize) !void {
        try w.writeAll(text[0..@min(text.len, width)]);
        try w.writeAll("\r\n");
    }

    /// Original save: `<slot>.dat` is a line-oriented decimal state dump and
    /// `<slot>.sav` is a 0x18d8-byte VRAM thumbnail plus a 0x404-byte driver
    /// block. All numeric fields are unpadded decimal with CRLF terminators.
    fn saveOriginal(self: *const Game, path: []const u8) !void {
        const layout = try self.readSaveLayout();
        var b = std.ArrayList(u8).empty;
        const w = b.writer(self.allocator);

        for (layout.fields) |f| {
            if (std.mem.eql(u8, f.kind, "landscape_word")) {
                var i: usize = 1;
                while (i <= layout.landscapes) : (i += 1) {
                    var j: usize = 1;
                    while (j <= 7) : (j += 1) {
                        // File word j-1 of room i is loaded to original offset
                        // i*0xe + j*2 - 0x52b0. The live copy is land_exits[i][j-1];
                        // it reflects door toggles that do not exist in `words`.
                        try w.print("{d}\r\n", .{self.land_exits[@intCast(i)][j - 1]});
                    }
                }
            } else if (std.mem.eql(u8, f.kind, "landscape_byte")) {
                var i: usize = 1;
                while (i <= layout.landscapes) : (i += 1) {
                    try w.print("{d}\r\n", .{self.savedByte(@as(i64, @intCast(i)) - 0x32f8)});
                }
            } else if (std.mem.eql(u8, f.kind, "object_word")) {
                var i: usize = 1;
                while (i <= layout.objects) : (i += 1) {
                    try w.print("{d}\r\n", .{self.savedWord(@as(i64, @intCast(i)) * 2 + f.offset)});
                }
            } else if (std.mem.eql(u8, f.kind, "object_byte")) {
                var i: usize = 1;
                while (i <= layout.objects) : (i += 1) {
                    try w.print("{d}\r\n", .{self.savedByte(@as(i64, @intCast(i)) + f.offset)});
                }
            } else if (std.mem.eql(u8, f.kind, "object_string")) {
                var i: usize = 1;
                while (i <= layout.objects) : (i += 1) {
                    const addr = @as(i64, @intCast(i)) * 4 + f.offset;
                    try writePascalLine(w, self.strings.get(addr) orelse "", f.width);
                }
            } else if (std.mem.eql(u8, f.kind, "string")) {
                try writePascalLine(w, self.strings.get(f.addr) orelse "", f.width);
            } else if (std.mem.eql(u8, f.kind, "slot_string")) {
                var i: usize = 0;
                while (i < f.count) : (i += 1) {
                    const addr = f.base + @as(i64, @intCast(i)) * f.stride;
                    const value = if (i < self.inventory.items.len) self.inventory.items[i] else (self.strings.get(addr) orelse "");
                    try writePascalLine(w, value, f.width);
                }
            } else if (std.mem.eql(u8, f.kind, "byte") or std.mem.eql(u8, f.kind, "word")) {
                const is_word = std.mem.eql(u8, f.kind, "word");
                if (f.to > f.from) {
                    var addr = f.from;
                    while (addr <= f.to) : (addr += 1) {
                        try w.print("{d}\r\n", .{if (is_word) self.savedWord(addr) else self.savedByte(addr)});
                    }
                } else {
                    try w.print("{d}\r\n", .{if (is_word) self.savedWord(f.addr) else self.savedByte(f.addr)});
                }
            } else return error.InvalidSaveLayout;
        }
        try util.writeFile(path, b.items);

        // No VGA VRAM exists in the Zig frontend. Emit the exact original
        // lengths; the thumbnail contents are not part of game state.
        const sav = try self.allocator.alloc(u8, 0x18d8 + 0x404);
        @memset(sav, 0);
        try util.writeFile(try self.siblingPath(path, "sav"), sav);
    }

    /// Original load: parse the decimal lines in finalizer order, then apply
    /// the room/object globals used by the Zig engine.
    fn loadOriginal(self: *Game, path: []const u8) !void {
        const layout = try self.readSaveLayout();
        const bytes = try util.readFile(self.allocator, path);
        const sav_path = try self.siblingPath(path, "sav");
        if (util.readFile(self.allocator, sav_path)) |sav| {
            if (sav.len < 0x18d8) return error.InvalidSave;
        } else |_| {}

        var reader = SaveLineReader{ .data = bytes };
        var inventory = std.ArrayList([]const u8).empty;
        errdefer inventory.deinit(self.allocator);

        for (layout.fields) |f| {
            if (std.mem.eql(u8, f.kind, "landscape_word")) {
                var i: usize = 1;
                while (i <= layout.landscapes) : (i += 1) {
                    var j: usize = 1;
                    while (j <= 7) : (j += 1) {
                        const addr: i64 = @as(i64, @intCast(i)) * 0xe + @as(i64, @intCast(j)) * 2 - 0x52b0;
                        const value: i16 = @bitCast(@as(u16, @truncate(@as(u64, @bitCast(try reader.int())))));
                        try self.words.put(addr, @as(u16, @bitCast(value)));
                        self.land_exits[@intCast(i)][j - 1] = value;
                    }
                }
            } else if (std.mem.eql(u8, f.kind, "landscape_byte")) {
                var i: usize = 1;
                while (i <= layout.landscapes) : (i += 1) {
                    try self.flags.put(@as(i64, @intCast(i)) - 0x32f8, @truncate(@as(u64, @bitCast(try reader.int()))));
                }
            } else if (std.mem.eql(u8, f.kind, "object_word")) {
                var i: usize = 1;
                while (i <= layout.objects) : (i += 1) {
                    try self.words.put(@as(i64, @intCast(i)) * 2 + f.offset, @truncate(@as(u64, @bitCast(try reader.int()))));
                }
            } else if (std.mem.eql(u8, f.kind, "object_byte")) {
                var i: usize = 1;
                while (i <= layout.objects) : (i += 1) {
                    try self.flags.put(@as(i64, @intCast(i)) + f.offset, @truncate(@as(u64, @bitCast(try reader.int()))));
                }
            } else if (std.mem.eql(u8, f.kind, "object_string")) {
                var i: usize = 1;
                while (i <= layout.objects) : (i += 1) {
                    const addr = @as(i64, @intCast(i)) * 4 + f.offset;
                    try self.strings.put(addr, try self.allocator.dupe(u8, try reader.string(f.width)));
                }
            } else if (std.mem.eql(u8, f.kind, "string")) {
                try self.strings.put(f.addr, try self.allocator.dupe(u8, try reader.string(f.width)));
            } else if (std.mem.eql(u8, f.kind, "slot_string")) {
                var i: usize = 0;
                while (i < f.count) : (i += 1) {
                    const addr = f.base + @as(i64, @intCast(i)) * f.stride;
                    const text = try reader.string(f.width);
                    try self.strings.put(addr, try self.allocator.dupe(u8, text));
                    if (text.len > 0) try inventory.append(self.allocator, text);
                }
            } else if (std.mem.eql(u8, f.kind, "byte") or std.mem.eql(u8, f.kind, "word")) {
                const is_word = std.mem.eql(u8, f.kind, "word");
                if (f.to > f.from) {
                    var addr = f.from;
                    while (addr <= f.to) : (addr += 1) {
                        const value: u16 = @truncate(@as(u64, @bitCast(try reader.int())));
                        if (is_word) try self.words.put(addr, value) else try self.flags.put(addr, @truncate(value));
                    }
                } else {
                    const value: u16 = @truncate(@as(u64, @bitCast(try reader.int())));
                    if (is_word) try self.words.put(f.addr, value) else try self.flags.put(f.addr, @truncate(value));
                }
            } else return error.InvalidSaveLayout;
        }

        if (self.flags.get(0xbe1b)) |room| self.room = room;
        if (self.flags.get(0xc918)) |scene| self.picture_override = scene;
        self.inventory.deinit(self.allocator);
        self.inventory = inventory;
        self.moves = 0;
        self.score = 0;
        self.quit_requested = false;
    }

    /// Portable JSON state remains available for tooling and scripts that do
    /// not want to create the sibling `.sav` file.
    fn savePortable(self: *const Game, path: []const u8) !void {
        var b = std.ArrayList(u8).empty;
        const w = b.writer(self.allocator);
        try w.print("{{\"room\":{d},\"moves\":{d},\"score\":{d},\"inventory\":[", .{ self.room, self.moves, self.score });
        for (self.inventory.items, 0..) |item, i| {
            if (i > 0) try w.writeByte(',');
            try util.jsonString(w, item);
        }
        try w.writeAll("]}");
        try util.writeFile(path, b.items);
    }

    fn loadPortable(self: *Game, path: []const u8) !void {
        const bytes = try util.readFile(self.allocator, path);
        const root = try std.json.parseFromSliceLeaky(std.json.Value, self.allocator, bytes, .{});
        if (root.object.get("room")) |v| self.room = asInt(v);
        if (root.object.get("moves")) |v| self.moves = @intCast(@max(0, asInt(v)));
        if (root.object.get("score")) |v| self.score = @intCast(@max(0, asInt(v)));
        self.inventory.clearRetainingCapacity();
        if (root.object.get("inventory")) |v| {
            if (asArray(v)) |items| {
                for (items.items) |entry| {
                    const word = asString(entry);
                    if (word.len > 0) try self.inventory.append(self.allocator, try self.allocator.dupe(u8, word));
                }
            }
        }
        self.quit_requested = false;
    }

    fn isOriginalSavePath(path: []const u8) bool {
        const ext = std.fs.path.extension(path);
        return std.ascii.eqlIgnoreCase(ext, ".dat") or std.ascii.eqlIgnoreCase(ext, ".sav");
    }

    pub fn save(self: *const Game, path: []const u8) !void {
        if (isOriginalSavePath(path)) return self.saveOriginal(path);
        return self.savePortable(path);
    }

    pub fn load(self: *Game, path: []const u8) !void {
        if (isOriginalSavePath(path)) return self.loadOriginal(path);
        const bytes = util.readFile(self.allocator, path) catch return self.loadOriginal(path);
        if (bytes.len > 0 and bytes[0] == '{') return self.loadPortable(path);
        return self.loadOriginal(path);
    }
};
