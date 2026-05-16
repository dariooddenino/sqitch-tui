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

const Item = zz.List(PlanStep).Item;

// TODO help as a modal
pub const Model = struct {
    theme_manager: zz.ThemeManager,
    plan: external.Plan,
    steps: *VirtualList(PlanMigration),
    persistent_allocator: std.mem.Allocator,
    keymap: zz.KeyMap,
    // TODO: the todollist examples has owned_titles as a pattern I can study

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
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
        const plan = try external.Plan.init(self.persistent_allocator, "HEAD");

        self.plan = plan;
    }

    fn updateMigrations(self: *Model) !void {
        // self.steps.clear();
        self.steps.setItems = self.plan.migrations.items;
        // var index = self.headPlan.steps.len;
        // while (index > 0) : (index -= 1) {
        //     self.steps.addItem(Item.init(self.headPlan.steps[index - 1], self.headPlan.steps[index - 1].name)) catch {};
        // }
    }

    fn setCurrentMigration(self: *Model) !void {
        const current_migration = try external.CurrentMigration.init(self.persistent_allocator);

        self.current_migration = current_migration;
    }

    fn setBranches(self: *Model) !void {
        const branches = try external.Branches.init(self.persistent_allocator);

        self.branches = branches;
    }

    fn setBranchesPlans(self: *Model) !void {
        for (self.branches.branches) |branch| {
            const plan = try external.Plan.init(self.persistent_allocator, branch.name);

            try self.branchesPlans.append(self.persistent_allocator, plan);
        }
    }

    // This function is probably very wasteful
    fn updateBranches(self: *Model) !void {
        self.branches.deinit();
        try self.setBranches();

        // In theory I'd want to update only if/what needed
        for (self.branchesPlans.items) |branchPlan| {
            branchPlan.deinit();
        }
        self.branchesPlans.clearAndFree(self.persistent_allocator);

        try self.setBranchesPlans();
    }

    fn isStepCurrentMigration(self: Model, step: PlanStep) bool {
        return std.mem.eql(u8, step.name, self.current_migration.status.name);
    }

    pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
        // TODO: this should use the keymap
        switch (msg) {
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
                            // TODO store the currently selected migration, and after refresh try to
                            // reselect it somehow
                            // self.current_migration.update() catch return .none;
                            self.plan.update() catch return .none;
                            // self.updateSteps() catch return .none;
                            // self.updateBranches() catch return .none;
                            return .none;
                        },
                        else => {},
                    },
                    else => self.steps.update(k),
                }
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const alloc = ctx.allocator;
        const w: u16 = @intCast(@min(ctx.width, std.math.maxInt(u16)));
        const h: u16 = @intCast(@min(ctx.height, std.math.maxInt(u16)));

        // Outer vertical layout: header(3) | body(fill) | footer(3)
        const rows = zz.flex.layout(alloc, w, h, &.{
            .{ .constraint = .fill },
            .{ .constraint = .{ .fixed = 1 } },
            .{ .constraint = .{ .fixed = 1 } },
        }, .{ .direction = .column }) catch return "layout error";

        const theme = &self.theme_manager.current;
        const palette = &theme.palette;

        // const header = renderPanel(alloc, "SQITCH TUI", rows[0].width, rows[0].height, palette, false);

        var box_s = zz.Style{};

        const inner_h: u16 = if (rows[0].height > 2) rows[0].height - 5 else 1;
        self.steps.viewport_height = inner_h;
        const list_view = self.steps.view(ctx.allocator, rows[0].width, rows[0].height);
        const boxed_list = box_s.render(ctx.allocator, list_view) catch list_view;

        const body = renderPanel(alloc, boxed_list, rows[1].width, rows[1].height, palette, true);

        // TODO: Might want to center a little better and style
        var bar = zz.StatusBar.init(alloc);
        const inner_w: u16 = if (rows[1].width > 4) rows[1].width - 4 else 1;
        // const inner_w = rows[2].width;
        var status_style = zz.Style{};
        status_style = status_style.bg(palette.overlay);
        status_style = status_style.fg(palette.foreground);
        bar.setWidth(inner_w);
        bar.setLeft(self.plan.current_migration.status.name, status_style) catch {};
        bar.setCenter(self.plan.current_migration.status.change, status_style) catch {};
        bar.setRight(self.plan.current_migration.status.deployed, status_style) catch {};
        const status = bar.view(alloc) catch "";
        defer alloc.free(status);

        const status_bar = renderPanel(alloc, status, rows[2].width, rows[2].height, palette, false);

        // var help = zz.components.Help.fromKeyMap(alloc, &self.keymap) catch zz.components.Help.init(alloc);
        // defer help.deinit();
        // const help_view = help.view(alloc) catch "";
        var footer_style = zz.Style{};
        footer_style = footer_style.width(rows[2].width);
        footer_style = footer_style.fg(palette.subtle);
        footer_style = footer_style.alignH(zz.style.Align.center);
        const footer = footer_style.render(alloc, "SQITCH TUI - Press 'h' for help, 'q' to quit.") catch "";

        return zz.join.vertical(alloc, .left, &.{ body, status_bar, footer }) catch "render error";
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

    pub fn deinit(self: *Model) void {
        self.plan.deinit();
        self.keymap.deinit();
        self.persistent_allocator.destroy(self.steps);
    }
};
