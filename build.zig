const std = @import("std");

const lua_sources = [_][]const u8{
    "lapi.c",     "lcode.c",    "lctype.c",   "ldebug.c",  "ldo.c",
    "ldump.c",    "lfunc.c",    "lgc.c",      "llex.c",    "lmem.c",
    "lobject.c",  "lopcodes.c", "lparser.c",  "lstate.c",  "lstring.c",
    "ltable.c",   "ltm.c",      "lundump.c",  "lvm.c",     "lzio.c",
    "lauxlib.c",  "lbaselib.c", "lcorolib.c", "ldblib.c",  "liolib.c",
    "lmathlib.c", "loadlib.c",  "loslib.c",   "lstrlib.c", "ltablib.c",
    "lutf8lib.c", "linit.c",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // The OVR rule database is large; Debug startup takes ~5s while
    // ReleaseFast starts in ~0.2s. Ship the fast build by default;
    // `-Doptimize=Debug` still overrides it.
    b.release_mode = .fast;
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    // Lua 5.4.8 is vendored so the project builds without system packages.
    const lua = b.addLibrary(.{
        .name = "lua",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    lua.addIncludePath(b.path("vendor/lua/src"));
    lua.addCSourceFiles(.{
        .root = b.path("vendor/lua/src"),
        .files = &lua_sources,
        .flags = &.{"-DLUA_USE_LINUX"},
    });
    lua.linkLibC();
    b.installArtifact(lua);

    const exe = b.addExecutable(.{
        .name = "hexuma",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.linkLibC();
    exe.linkSystemLibrary("X11");
    exe.addIncludePath(b.path("vendor/lua/src"));
    exe.linkLibrary(lua);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run hexuma with arguments");
    run_step.dependOn(&run_cmd.step);
}
