const std = @import("std");
const rules = @import("overlay_rules.zig");

/// Runtime view of the original globals referenced by HEXUMA.OVR. The Zig
/// engine supplies these callbacks; the evaluator stays independent of the
/// save/load and parser implementation.
pub const Context = struct {
    ptr: *anyopaque,
    read_var: *const fn (*anyopaque, []const u8) i64,
    write_var: *const fn (*anyopaque, []const u8, i64) void,
    read_flag: *const fn (*anyopaque, i64) i64,
    write_flag: *const fn (*anyopaque, i64, i64) void,
    message: *const fn (*anyopaque, i64) []const u8,
};

pub const Result = struct {
    messages: std.ArrayList([]const u8) = .empty,
    message_ids: std.ArrayList(i64) = .empty,
    picture: ?i64 = null,
    dialog_count: usize = 0,
    clear_input: bool = false,
    returned: bool = false,

    /// True when the overlay produced player-visible output. State-only rules
    /// leave the generic command response in place.
    pub fn hasOutput(self: *const Result) bool {
        return self.messages.items.len != 0 or self.picture != null or self.dialog_count != 0;
    }
};

pub fn run(allocator: std.mem.Allocator, db: rules.Database, context: Context, room: i64) !Result {
    for (db.units) |unit| {
        if (!unit.containsRoom(room)) continue;
        return runUnit(allocator, unit, context);
    }
    return .{};
}

fn runUnit(allocator: std.mem.Allocator, unit: rules.Unit, context: Context) !Result {
    var result = Result{};
    for (unit.rules) |rule| {
        if (evalExpr(context, rule.when) == 0) continue;
        for (rule.actions) |action| {
            switch (action) {
                .message => |id| {
                    const text = context.message(context.ptr, id);
                    try result.message_ids.append(allocator, id);
                    if (text.len != 0) try result.messages.append(allocator, text);
                },
                .picture => |id| result.picture = id,
                .dialog => result.dialog_count += 1,
                .clear_input => result.clear_input = true,
                .set => |set| writeTarget(context, set.target, evalValue(context, set.value)),
                .add => |add| {
                    const current = readTarget(context, add.target);
                    writeTarget(context, add.target, current +% add.value);
                },
                .return_ => {
                    result.returned = true;
                    break;
                },
            }
        }
        if (result.returned) break;
    }
    return result;
}

fn evalValue(context: Context, value: rules.Value) i64 {
    return switch (value) {
        .number => |n| n,
        .expr => |expr| evalExpr(context, expr),
    };
}

fn readTarget(context: Context, target: rules.Target) i64 {
    return switch (target) {
        .variable => |name| context.read_var(context.ptr, name),
        .flag => |text| context.read_flag(context.ptr, parseAddress(text)),
    };
}

fn writeTarget(context: Context, target: rules.Target, value: i64) void {
    switch (target) {
        .variable => |name| context.write_var(context.ptr, name, value),
        .flag => |text| context.write_flag(context.ptr, parseAddress(text), value),
    }
}

fn parseAddress(text: []const u8) i64 {
    if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) {
        return std.fmt.parseInt(i64, text[2..], 16) catch 0;
    }
    return std.fmt.parseInt(i64, text, 10) catch 0;
}

fn evalExpr(context: Context, expr: *const rules.Expr) i64 {
    return switch (expr.*) {
        .number => |n| n,
        .variable => |name| context.read_var(context.ptr, name),
        .flag => |text| context.read_flag(context.ptr, parseAddress(text)),
        .raw => 0,
        .unary => |unary| evalUnary(unary.op, evalExpr(context, unary.child)),
        .binary => |binary| evalBinary(context, binary.op, binary.left, binary.right),
        .call => 0,
    };
}

fn evalUnary(op: []const u8, value: i64) i64 {
    if (std.mem.eql(u8, op, "!")) return @intFromBool(value == 0);
    if (std.mem.eql(u8, op, "~")) return ~value;
    if (std.mem.eql(u8, op, "-")) return -%value;
    return value;
}

fn evalBinary(context: Context, op: []const u8, left_expr: *const rules.Expr, right_expr: *const rules.Expr) i64 {
    // Short-circuit boolean operators so flag guards never evaluate irrelevant
    // branches with synthetic local variables.
    if (std.mem.eql(u8, op, "&&")) {
        if (evalExpr(context, left_expr) == 0) return 0;
        return @intFromBool(evalExpr(context, right_expr) != 0);
    }
    if (std.mem.eql(u8, op, "||")) {
        if (evalExpr(context, left_expr) != 0) return 1;
        return @intFromBool(evalExpr(context, right_expr) != 0);
    }

    const left = evalExpr(context, left_expr);
    const right = evalExpr(context, right_expr);
    if (std.mem.eql(u8, op, "==")) return @intFromBool(left == right);
    if (std.mem.eql(u8, op, "!=")) return @intFromBool(left != right);
    if (std.mem.eql(u8, op, "<")) return @intFromBool(left < right);
    if (std.mem.eql(u8, op, "<=")) return @intFromBool(left <= right);
    if (std.mem.eql(u8, op, ">")) return @intFromBool(left > right);
    if (std.mem.eql(u8, op, ">=")) return @intFromBool(left >= right);
    if (std.mem.eql(u8, op, "+")) return left +% right;
    if (std.mem.eql(u8, op, "-")) return left -% right;
    if (std.mem.eql(u8, op, "*")) return left *% right;
    if (std.mem.eql(u8, op, "/")) return if (right == 0) 0 else @divTrunc(left, right);
    if (std.mem.eql(u8, op, "%")) return if (right == 0) 0 else @rem(left, right);
    if (std.mem.eql(u8, op, "&")) return left & right;
    if (std.mem.eql(u8, op, "|")) return left | right;
    if (std.mem.eql(u8, op, "^")) return left ^ right;
    if (std.mem.eql(u8, op, "<<")) {
        const amount: u6 = @intCast(@mod(right, 64));
        return @as(i64, @bitCast(@as(u64, @bitCast(left)) << amount));
    }
    if (std.mem.eql(u8, op, ">>")) {
        const amount: u6 = @intCast(@mod(right, 64));
        return @as(i64, @bitCast(@as(u64, @bitCast(left)) >> amount));
    }
    return 0;
}
