const std = @import("std");
const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lauxlib.h");
    @cInclude("lualib.h");
});

fn version(L: ?*c.lua_State) callconv(.c) c_int {
    const state = L orelse return 0;
    _ = c.lua_pushstring(state, "hexuma-zig 0.1 (Lua 5.4)");
    return 1;
}

fn logInfo(L: ?*c.lua_State) callconv(.c) c_int {
    const state = L orelse return 0;
    const msg = c.lua_tolstring(state, 1, null);
    if (msg) |m| std.debug.print("[lua] {s}\n", .{std.mem.span(m)});
    return 0;
}

/// Execute a Lua script with the host table `hexuma` available. The generated
/// Lua modules in extracted/lua/ use this table for host services.
pub fn runFile(path: []const u8) !void {
    const L = c.luaL_newstate() orelse return error.LuaStateFailed;
    defer c.lua_close(L);
    c.luaL_openlibs(L);

    // Generated Lua modules live beside the script that starts the engine.
    const script_dir = std.fs.path.dirname(path) orelse ".";
    const lua_path = try std.fmt.allocPrintSentinel(
        std.heap.page_allocator,
        "{s}/?.lua;{s}/?/init.lua;./?.lua;./?/init.lua",
        .{ script_dir, script_dir },
        0,
    );
    defer std.heap.page_allocator.free(lua_path);
    _ = c.lua_getglobal(L, "package");
    _ = c.lua_pushstring(L, lua_path.ptr);
    c.lua_setfield(L, -2, "path");
    c.lua_pop(L, 1);

    c.lua_createtable(L, 0, 0);
    c.lua_pushcclosure(L, version, 0);
    c.lua_setfield(L, -2, "version");
    c.lua_pushcclosure(L, logInfo, 0);
    c.lua_setfield(L, -2, "log");
    c.lua_setglobal(L, "hexuma");

    const zpath = try std.heap.page_allocator.dupeZ(u8, path);
    defer std.heap.page_allocator.free(zpath);

    if (c.luaL_loadfilex(L, zpath.ptr, null) != c.LUA_OK) {
        const msg = c.lua_tolstring(L, -1, null);
        std.debug.print("lua load error: {s}\n", .{if (msg) |m| std.mem.span(m) else "unknown"});
        return error.LuaLoadFailed;
    }
    if (c.lua_pcallk(L, 0, c.LUA_MULTRET, 0, 0, null) != c.LUA_OK) {
        const msg = c.lua_tolstring(L, -1, null);
        std.debug.print("lua runtime error: {s}\n", .{if (msg) |m| std.mem.span(m) else "unknown"});
        return error.LuaRuntimeFailed;
    }
}
