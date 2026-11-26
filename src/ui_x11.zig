const std = @import("std");
const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xutil.h");
});
const engine = @import("engine.zig");

const Button = struct {
    x: c_int,
    y: c_int,
    w: c_int,
    h: c_int,
    command: []const u8,
    label: []const u8,
};

const RawImage = struct {
    x: usize,
    y: usize,
    w: usize,
    h: usize,
    pixels: []const u8,
};

const view_x: c_int = 16;
const view_y: c_int = 96;
const view_scale: c_int = 2;
const view_w: c_int = 320 * view_scale;
const view_h: c_int = 96 * view_scale;

const WindowUi = struct {
    allocator: std.mem.Allocator,
    extracted_dir: []const u8,
    game: *engine.Game,
    display: *c.Display,
    window: c.Window,
    gc: c.GC,
    font: ?*c.XFontStruct = null,
    buttons: []Button = &.{},
    message: []const u8 = "",
    image: []u8 = &.{},
    ximage: ?*c.XImage = null,
    image_pic: i64 = -1,

    fn drawText(self: *WindowUi, x: c_int, y: c_int, text: []const u8) void {
        if (text.len == 0) return;
        _ = c.XDrawString(self.display, self.window, self.gc, x, y, text.ptr, @intCast(text.len));
    }

    fn currentRegions(self: *WindowUi) []const engine.Region {
        // The original selects the VORS.BIN record from the current picture id
        // (global 0x32d0), not from the room id.
        var first: usize = 0;
        var last: usize = 0;
        const record = self.game.pictureValue();
        for (self.game.regions, 0..) |r, i| {
            if (r.screen == record) {
                if (last == first) first = i;
                last = i + 1;
            }
        }
        if (last == first) return &.{};
        // VORS regions for one screen are contiguous in game.json.
        return self.game.regions[first..last];
    }

    fn regionAction(self: *WindowUi, r: engine.Region) ?[]const u8 {
        const action = self.game.actionForSlot(r);
        return if (action.len == 0) null else action;
    }

    fn loadRawImage(self: *WindowUi, stem: []const u8) ?RawImage {
        const file_name = std.fmt.allocPrint(self.allocator, "{s}.raw", .{stem}) catch return null;
        const path = std.fs.path.join(self.allocator, &.{ self.extracted_dir, "images", file_name }) catch return null;
        defer self.allocator.free(path);
        const bytes = std.fs.cwd().readFileAlloc(self.allocator, path, 4 * 1024 * 1024) catch return null;
        var x: usize = 0;
        var y: usize = 0;
        var offset: usize = 0;
        if (bytes.len >= 14 and std.mem.eql(u8, bytes[0..6], "HXRAW2")) {
            x = std.mem.readInt(u16, bytes[6..8], .little);
            y = std.mem.readInt(u16, bytes[8..10], .little);
            // HXRAW2 is "magic,x,y,w,h,pixels": width and height live at
            // bytes 10..13, while HXRAW1 stores only "magic,w,h,pixels".
            offset = 10;
        } else if (bytes.len >= 10 and std.mem.eql(u8, bytes[0..6], "HXRAW1")) {
            offset = 10;
        } else return null;
        const w = std.mem.readInt(u16, @ptrCast(bytes[offset..].ptr), .little);
        offset += 2;
        const h = std.mem.readInt(u16, @ptrCast(bytes[offset..].ptr), .little);
        offset += 2;
        if (w == 0 or h == 0 or bytes.len < offset + @as(usize, w) * @as(usize, h) * 4) return null;
        return .{ .x = x, .y = y, .w = w, .h = h, .pixels = bytes[offset..] };
    }

    fn blitRaw(canvas: []u8, raw: RawImage) void {
        const scale: usize = @intCast(view_scale);
        const canvas_w: usize = @intCast(view_w);
        const canvas_h: usize = @intCast(view_h);
        var py: usize = 0;
        while (py < raw.h) : (py += 1) {
            var sy: usize = 0;
            while (sy < scale) : (sy += 1) {
                const dy = raw.y * scale + py * scale + sy;
                if (dy >= canvas_h) break;
                var px: usize = 0;
                while (px < raw.w) : (px += 1) {
                    const src = (py * raw.w + px) * 4;
                    var sx: usize = 0;
                    while (sx < scale) : (sx += 1) {
                        const dx = raw.x * scale + px * scale + sx;
                        if (dx >= canvas_w) break;
                        const dst = (dy * canvas_w + dx) * 4;
                        @memcpy(canvas[dst .. dst + 4], raw.pixels[src .. src + 4]);
                    }
                }
            }
        }
    }

    fn loadRoomImage(self: *WindowUi) void {
        const pic = self.game.pictureValue();
        if (pic == self.image_pic) return;
        self.image_pic = pic;
        if (self.ximage) |img| {
            if (img.*.f.destroy_image) |destroy| _ = destroy(img);
        }
        self.ximage = null;

        const canvas = self.allocator.alloc(u8, @as(usize, @intCast(view_w)) * @as(usize, @intCast(view_h)) * 4) catch return;
        @memset(canvas, 0x20);
        const n: u32 = @intCast(@max(0, pic));
        var bg_buf: [7]u8 = "BILD000".*;
        bg_buf[4] = @intCast('0' + (n / 100) % 10);
        bg_buf[5] = @intCast('0' + (n / 10) % 10);
        bg_buf[6] = @intCast('0' + n % 10);
        if (self.loadRawImage(&bg_buf)) |bg| {
            blitRaw(canvas, bg);
        } else {
            std.log.warn("gui: missing background {s} in {s}", .{ bg_buf[0..], self.extracted_dir });
        }

        // The BILD loader at 0x2bffd draws every FR overlay whose scene/flag
        // condition holds, in table order, over the background.
        const overlays = self.game.activeOverlays(self.allocator) catch &.{};
        defer self.allocator.free(overlays);
        var upper: [64]u8 = undefined;
        for (overlays) |file| {
            const dot = std.mem.lastIndexOfScalar(u8, file, '.') orelse file.len;
            if (dot == 0 or dot > upper.len - 4) continue;
            _ = std.ascii.upperString(upper[0..dot], file[0..dot]);
            @memcpy(upper[dot .. dot + 4], ".raw");
            if (self.loadRawImage(upper[0 .. dot + 4])) |frame| blitRaw(canvas, frame);
        }
        self.image = canvas;

        const screen = c.XDefaultScreen(self.display);
        const visual = c.XDefaultVisual(self.display, screen);
        const img = c.XCreateImage(self.display, visual, 24, c.ZPixmap, 0, @ptrCast(canvas.ptr), @intCast(view_w), @intCast(view_h), 32, 0) orelse return;
        img.*.red_mask = visual.*.red_mask;
        img.*.green_mask = visual.*.green_mask;
        img.*.blue_mask = visual.*.blue_mask;
        self.ximage = img;
    }

    fn redraw(self: *WindowUi) !void {
        _ = c.XClearWindow(self.display, self.window);
        self.loadRoomImage();

        const view = try self.game.look();
        var line_y: c_int = 20;
        var lines = std.mem.splitScalar(u8, view, '\n');
        while (lines.next()) |line| {
            self.drawText(16, line_y, line);
            line_y += 18;
        }
        self.drawText(16, line_y + 4, self.message);

        // Room picture area. The original VORS.BIN coordinates use a
        // 320x96 logical screen, enlarged here for readable click targets.
        if (self.ximage) |img| {
            _ = c.XPutImage(self.display, self.window, self.gc, img, 0, 0, view_x, view_y, view_w, view_h);
        } else {
            _ = c.XFillRectangle(self.display, self.window, self.gc, view_x, view_y, view_w, view_h);
        }
        _ = c.XDrawRectangle(self.display, self.window, self.gc, view_x, view_y, view_w, view_h);

        const regions = self.currentRegions();
        for (regions) |r| {
            const action = self.regionAction(r) orelse continue;
            const x = view_x + r.x1 * view_scale;
            const y = view_y + r.y1 * view_scale;
            const w = (r.x2 - r.x1) * view_scale;
            const h = (r.y2 - r.y1) * view_scale;
            _ = c.XDrawRectangle(self.display, self.window, self.gc, x, y, @intCast(w), @intCast(h));
            const label = try self.game.localizeAction(action);
            self.drawText(x + 3, y + 12, if (label.len > 28) label[0..28] else label);
        }

        const button_y: c_int = view_y + view_h + 24;
        var new_buttons = std.ArrayList(Button).empty;
        const choices = try self.game.choices();
        for (choices, 0..) |choice, i| {
            const col: c_int = @intCast(i % 2);
            const row: c_int = @intCast(i / 2);
            const b = Button{
                .x = 16 + col * 306,
                .y = button_y + row * 30,
                .w = 292,
                .h = 24,
                .command = choice.command,
                .label = try std.fmt.allocPrint(self.allocator, "{d}. {s}", .{ i + 1, choice.label }),
            };
            try new_buttons.append(self.allocator, b);
            _ = c.XFillRectangle(self.display, self.window, self.gc, b.x, b.y, @intCast(b.w), @intCast(b.h));
            _ = c.XDrawRectangle(self.display, self.window, self.gc, b.x, b.y, @intCast(b.w), @intCast(b.h));
            self.drawText(b.x + 6, b.y + 16, b.label);
        }
        self.buttons = try new_buttons.toOwnedSlice(self.allocator);
        _ = c.XFlush(self.display);
    }

    fn click(self: *WindowUi, x: c_int, y: c_int) !void {
        if (x >= view_x and x < view_x + view_w and y >= view_y and y < view_y + view_h) {
            const lx = @divTrunc(x - view_x, view_scale);
            const ly = @divTrunc(y - view_y, view_scale);
            for (self.currentRegions()) |r| {
                const action = self.regionAction(r) orelse continue;
                if (lx >= r.x1 and lx <= r.x2 and ly >= r.y1 and ly <= r.y2) {
                    self.message = try self.game.execute(action);
                    if (self.game.quit_requested) return;
                    try self.redraw();
                    return;
                }
            }
        }
        for (self.buttons) |b| {
            if (x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h) {
                self.message = try self.game.execute(b.command);
                if (self.game.quit_requested) return;
                try self.redraw();
                return;
            }
        }
    }

    fn run(self: *WindowUi) !void {
        try self.redraw();
        while (!self.game.quit_requested) {
            var event: c.XEvent = undefined;
            _ = c.XNextEvent(self.display, &event);
            switch (event.type) {
                c.Expose => try self.redraw(),
                c.ButtonPress => try self.click(event.xbutton.x, event.xbutton.y),
                c.KeyPress => {
                    var buf: [32]u8 = undefined;
                    const key = c.XLookupString(&event.xkey, &buf, buf.len, null, null);
                    if (key > 0) {
                        const line = std.mem.trimRight(u8, buf[0..@intCast(key)], "\r\n");
                        self.message = try self.game.execute(line);
                        try self.redraw();
                    }
                },
                else => {},
            }
        }
    }
};

pub fn run(allocator: std.mem.Allocator, extracted_dir: []const u8, locale: engine.Locale) !void {
    const display = c.XOpenDisplay(null) orelse return error.NoXDisplay;
    defer _ = c.XCloseDisplay(display);

    const root = c.XDefaultRootWindow(display);
    const window = c.XCreateSimpleWindow(display, root, 40, 40, 680, 720, 1, c.XBlackPixel(display, 0), c.XWhitePixel(display, 0));
    defer _ = c.XDestroyWindow(display, window);
    _ = c.XStoreName(display, window, "Hexuma");
    _ = c.XSelectInput(display, window, c.ExposureMask | c.ButtonPressMask | c.KeyPressMask);
    _ = c.XMapWindow(display, window);

    const gc = c.XCreateGC(display, window, 0, null) orelse return error.NoGraphicsContext;
    defer _ = c.XFreeGC(display, gc);

    const font_name = "-misc-fixed-medium-r-normal--13-120-75-75-C-70-iso10646-1";
    var ui = WindowUi{
        .allocator = allocator,
        .extracted_dir = extracted_dir,
        .game = undefined,
        .display = display,
        .window = window,
        .gc = gc,
    };
    ui.font = c.XLoadQueryFont(display, font_name);
    if (ui.font == null) ui.font = c.XLoadQueryFont(display, "fixed");
    if (ui.font) |f| _ = c.XSetFont(display, gc, f.fid);

    var game = try engine.Game.init(allocator, extracted_dir, locale);
    defer game.deinit();
    defer {
        if (ui.ximage) |img| {
            if (img.*.f.destroy_image) |destroy| _ = destroy(img);
        }
    }
    ui.game = &game;
    try ui.run();
}
