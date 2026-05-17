const std = @import("std");
const Writer = std.Io.Writer;

const zz = @import("zigzag");

const parser = @import("./parser.zig");
const PlanStep = parser.PlanStep;
const Status = parser.Status;
const external = @import("./external.zig");
// const VirtualList = zz.components.virtual
const virtual_list = @import("./tui_virtual_list.zig");
const VirtualList = virtual_list.VirtualList;
const PlanMigration = external.PlanMigration;
const child_process = @import("./child_process.zig");

const Item = zz.List(PlanStep).Item;

// TODOS:
// - style for the message in the stauts bar
// - the message in the status bar is not disappearing
// - help modal (might not be able to do because of my issues with layers)
// - actually run migrations
// - verify mode in status bar
// - fix all the memory leaks (looks for patterns in StatusBar and the todo list example)
// - handle more complex git statuses
pub const Model = struct {
    theme_manager: zz.ThemeManager,
    plan: external.Plan,
    steps: *VirtualList(PlanMigration),
    persistent_allocator: std.mem.Allocator,
    keymap: zz.KeyMap,
    // toast: zz.Toast,
    status_bar: StatusBar,
    // last_elapsed: u64,
    // TODO: the todollist examples has owned_titles as a pattern I can study

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
        tick: zz.msg.Tick,
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        self.persistent_allocator = ctx.persistent_allocator;

        self.theme_manager = zz.ThemeManager.init();

        ctx.setTheme(self.theme_manager.current.palette);

        self.setPlan() catch return .none;

        const steps: *VirtualList(PlanMigration) = self.persistent_allocator.create(VirtualList(PlanMigration)) catch return .none;

        steps.* = .{ .theme_manager = &self.theme_manager };
        steps.viewport_height = 20;
        steps.items = self.plan.migrations;
        self.steps = steps;
        self.keymap = initKeys(self.persistent_allocator) catch return .none;
        self.status_bar = StatusBar.init(ctx.persistent_allocator);
        // self.toast = zz.Toast.init(ctx.persistent_allocator);
        // self.toast.position = .top_right;
        // self.toast.show_countdown = true;

        // self.last_elapsed = 0;

        return .none;
    }

    fn initKeys(allocator: std.mem.Allocator) !zz.KeyMap {
        var keymap = zz.KeyMap.init(allocator);
        try keymap.addChar('q', "Quit");
        // try keymap.addCtrl('s', "Save");
        try keymap.addChar('n', "Next theme");
        try keymap.addChar('p', "Previous theme");
        try keymap.add(.{
            .key_event = zz.KeyEvent{ .key = .up },
            .description = "Move up",
            .short_desc = "up",
        });
        return keymap;
    }

    fn setPlan(self: *Model) !void {
        const plan = try external.Plan.init(self.persistent_allocator);

        self.plan = plan;
    }

    fn isStepCurrentMigration(self: Model, step: PlanStep) bool {
        return std.mem.eql(u8, step.name, self.current_migration.status.name);
    }

    pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
        // TODO: this should use the keymap
        switch (msg) {
            .tick => {
                // self.last_elapsed = ctx.elapsed;
                self.status_bar.update(ctx.elapsed);
            },
            .key => |k| {
                switch (k.key) {
                    .char => |c| switch (c) {
                        'q' => return .quit,
                        'n' => {
                            self.theme_manager.nextBuiltin();
                            ctx.setTheme(self.theme_manager.current.palette);
                        },
                        'p' => {
                            self.theme_manager.prevBuiltin();
                            ctx.setTheme(self.theme_manager.current.palette);
                        },
                        'r' => {
                            self.plan.update() catch return .none;
                            self.steps.items = self.plan.migrations;
                            self.pushStatusMessage(ctx, .info, "Refreshed", 3000);

                            return .none;
                        },
                        'l' => {
                            self.migrateTo(self.steps.items[self.steps.cursor]) catch return .none;
                            self.plan.update() catch return .none;
                            self.steps.items = self.plan.migrations;
                            self.pushStatusMessage(ctx, .info, "Migrated", 3000);
                        },
                        else => {},
                    },
                    else => self.steps.update(k),
                }
            },
        }
        return .none;
    }

    // TODO: I don't like having logic tied to the model, need a refactor
    fn migrateTo(self: *Model, migration: PlanMigration) !void {
        if (migration.is_current_migration) return {};

        const current_migration = self.plan.getCurrentPlanMigration();
        if (current_migration) |current| {
            if (migration.index < current.index) {
                const command = external.sqitchDeployCommand(migration.step.name);
                const res = try child_process.run(self.persistent_allocator, &command);
                defer self.persistent_allocator.free(res);
            } else {
                const command = external.sqitchRevertCommand(migration.step.name);
                const res = try child_process.run(self.persistent_allocator, &command);
                defer self.persistent_allocator.free(res);
            }
        }
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const alloc = ctx.allocator;
        const w: u16 = @intCast(@min(ctx.width, std.math.maxInt(u16)));
        const h: u16 = @intCast(@min(ctx.height, std.math.maxInt(u16)));

        // var stack = zz.layout.layer.LayerStack.init(alloc);
        // stack.setSize(w, h);

        // Outer vertical layout: header(3) | body(fill) | footer(3)
        const rows = zz.flex.layout(alloc, w, h, &.{
            .{ .constraint = .fill },
            .{ .constraint = .{ .fixed = 1 } },
            .{ .constraint = .{ .fixed = 1 } },
        }, .{ .direction = .column }) catch return "layout error";

        const theme = &self.theme_manager.current;
        const palette = &theme.palette;

        var box_s = zz.Style{};

        const inner_h: u16 = if (rows[0].height > 2) rows[0].height - 5 else 1;
        self.steps.viewport_height = inner_h;
        const list_view = self.steps.view(ctx.allocator, rows[0].width, rows[0].height);
        const boxed_list = box_s.render(ctx.allocator, list_view) catch list_view;

        const body = renderPanel(alloc, boxed_list, rows[1].width, rows[1].height, palette, true);

        const inner_w: u16 = if (rows[1].width > 4) rows[1].width - 4 else 1;
        const status = self.status_bar.view(
            palette,
            inner_w,
            self.plan.current_migration.status.name,
            self.plan.current_migration.status.deployed,
        );

        defer self.persistent_allocator.free(status);

        const status_bar = renderPanel(alloc, status, rows[2].width, rows[2].height, palette, false);

        // var help = zz.components.Help.fromKeyMap(alloc, &self.keymap) catch zz.components.Help.init(alloc);
        // defer help.deinit();
        // const help_view = help.view(alloc) catch "";
        var footer_style = zz.Style{};
        footer_style = footer_style.width(rows[2].width);
        footer_style = footer_style.fg(palette.subtle);
        footer_style = footer_style.alignH(zz.style.Align.center);
        const footer = footer_style.render(alloc, "SQITCH TUI - Press 'h' for help, 'q' to quit.") catch "";

        const base = zz.join.vertical(alloc, .left, &.{ body, status_bar, footer }) catch "render error";

        // stack.push(.{ .content = base, .z = 0, .transparent = false }) catch {};

        // Render toast notifications
        // TODO: stacks mess with the output for some reason
        // const toast_view = self.toast.viewPositioned(ctx.allocator, ctx.width, ctx.height -| 8, self.last_elapsed) catch "";

        // stack.push(.{ .content = toast_view, .z = 1, .transparent = true }) catch {};

        // return std.fmt.allocPrint(
        //     ctx.allocator,
        //     "{s}\n\n{s}",
        //     .{ base, toast_view },
        // ) catch "Error";

        return base;
        // return stack.render(alloc);
    }

    fn renderPanel(alloc: std.mem.Allocator, content: []const u8, w: u16, h: u16, palette: *const zz.Palette, highlight: bool) []const u8 {
        var s = zz.Style{};
        s = s.borderAll(zz.Border.double);
        if (highlight) {
            s = s.borderForeground(palette.border_focus);
        } else {
            s = s.borderForeground(palette.border_color);
        }
        // Account for border (2 cells each side)
        const inner_w: u16 = if (w > 4) w - 4 else 1;
        const inner_h: u16 = if (h > 2) h - 2 else 1;
        s = s.width(inner_w);
        s = s.height(inner_h);
        return s.render(alloc, content) catch content;
    }

    fn pushStatusMessage(self: *Model, ctx: *zz.Context, level: Level, content: []const u8, duration_ms: u64) void {
        // const text = std.fmt.allocPrint(ctx.allocator, fmt, .{self.msg_counter}) catch return;
        self.status_bar.pushMessage(content, level, duration_ms, ctx.elapsed) catch {};
    }

    pub fn deinit(self: *Model) void {
        self.plan.deinit();
        self.keymap.deinit();
        self.persistent_allocator.destroy(self.steps);
        self.status_bar.deinit();
    }
};

const Level = enum {
    info,
    success,
    warning,
    err,
};

const StatusMessage = struct {
    text: []const u8,
    level: Level,
    created_ns: u64,
    duration_ms: u64,
};

const StatusBar = struct {
    allocator: std.mem.Allocator,
    messages: std.array_list.Managed(StatusMessage),
    last_elapsed: u64,

    pub fn init(allocator: std.mem.Allocator) StatusBar {
        return .{
            .allocator = allocator,
            .messages = std.array_list.Managed(StatusMessage).init(allocator),
            .last_elapsed = 0,
        };
    }

    pub fn update(self: *StatusBar, current_ns: u64) void {
        self.last_elapsed = current_ns;
        var i: usize = 0;
        while (i < self.messages.items.len) {
            const msg = self.messages.items[i];

            const elapsed_ms = (current_ns -| msg.created_ns) / std.time.ns_per_ms;
            if (elapsed_ms >= msg.duration_ms) {
                self.removeAt(i);
            } else {
                i += 1;
            }
        }
    }

    pub fn pushMessage(self: *StatusBar, text: []const u8, level: Level, duration_ms: u64, current_ns: u64) !void {
        const owned_text = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned_text);

        try self.messages.append(.{
            .text = owned_text,
            .level = level,
            .created_ns = current_ns,
            .duration_ms = duration_ms,
        });
    }

    fn freeMessage(self: *StatusBar, msg: StatusMessage) void {
        self.allocator.free(msg.text);
    }

    fn removeAt(self: *StatusBar, idx: usize) void {
        const msg = self.messages.orderedRemove(idx);
        self.freeMessage(msg);
    }

    pub fn dismissAll(self: *StatusBar) void {
        for (self.messages.items) |msg| {
            self.freeMessage(msg);
        }
        self.messages.clearRetainingCapacity();
    }

    pub fn deinit(self: *StatusBar) void {
        self.dismissAll();
        self.messages.deinit();
    }

    // TODO find some colors
    fn colorFromLevel(palette: *const zz.Palette, level: Level) zz.style.Color {
        return switch (level) {
            .info => palette.primary,
            .success => palette.primary,
            .warning => palette.secondary,
            .err => palette.secondary,
        };
    }

    pub fn view(self: *const StatusBar, palette: *const zz.Palette, w: u16, left: []const u8, right: []const u8) []const u8 {
        var bar = zz.StatusBar.init(self.allocator);
        defer bar.deinit();
        var status_style = zz.Style{};
        // status_style = status_style.bg(palette.overlay);
        status_style = status_style.fg(palette.foreground);
        status_style = status_style.inline_style(true);
        bar.setWidth(w);
        bar.setLeft(left, status_style) catch {};
        const total = self.messages.items.len;
        if (total > 0) {
            const idx = total - 1;
            const msg = self.messages.items[idx];
            const active_style = status_style.fg(colorFromLevel(palette, msg.level));

            bar.setCenter(msg.text, active_style) catch {};
        }
        bar.setRight(right, status_style) catch {};
        return bar.view(self.allocator) catch "";
    }
};
