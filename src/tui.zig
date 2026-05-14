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

// TODO:
// [ ] flip lists when building them
// [ ] each step should already contain the branches there, so I can visualize them properly
// [ ] I should also store if it's the current migration, so that I can flag it properly
const Item = zz.List(PlanStep).Item;

pub const Model = struct {
    theme_manager: zz.ThemeManager,
    plan: external.Plan,
    // branchesPlans: std.ArrayList(external.Plan) = .empty,
    steps: VirtualList(PlanMigration),
    // current_migration: external.CurrentMigration,
    persistent_allocator: std.mem.Allocator,
    // TODO: the todollist examples has owned_titles as a pattern I can study
    // branches: external.Branches,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        self.persistent_allocator = ctx.persistent_allocator;

        self.theme_manager = zz.ThemeManager.init();

        ctx.setTheme(self.theme_manager.current.palette);

        self.setPlan() catch return .none;

        self.steps = .{ .theme_manager = &self.theme_manager };
        self.steps.viewport_height = 20;
        self.steps.items = self.plan.migrations;

        return .none;
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
            .{ .constraint = .{ .fixed = 1 } },
            .{ .constraint = .fill },
            .{ .constraint = .{ .fixed = 3 } },
        }, .{ .direction = .column }) catch return "layout error";

        const theme = &self.theme_manager.current;
        const palette = &theme.palette;

        const header = renderPanel(alloc, "SQITCH TUI", rows[0].width, rows[0].height, palette, true);

        var box_s = zz.Style{};
        // box_s = box_s.borderAll(zz.Border.rounded);
        // box_s = box_s.borderForeground(zz.Color.cyan);

        const list_view = self.steps.view(ctx.allocator, rows[1].width, rows[1].height);
        const boxed_list = box_s.render(ctx.allocator, list_view) catch list_view;

        const body = renderPanel(alloc, boxed_list, rows[1].width, rows[1].height, palette, true);

        // Help
        var help_style = zz.Style{};
        help_style = help_style.fg(zz.Color.gray(12));
        help_style = help_style.inline_style(true);
        const help_text = "Press q to quit";
        const help = help_style.render(ctx.allocator, help_text) catch "";

        const footer = renderPanel(alloc, help, rows[2].width, rows[2].height, palette, false);

        return zz.join.vertical(alloc, .left, &.{ header, body, footer }) catch "render error";

        // var title_style = zz.Style{};
        // title_style = title_style.bold(true);
        // title_style = title_style.fg(zz.Color.cyan);
        // title_style = title_style.inline_style(true);

        // var help_style = zz.Style{};
        // help_style = help_style.fg(zz.Color.gray(12));
        // help_style = help_style.inline_style(true);

        // const title = title_style.render(ctx.allocator, "external TUI") catch "external TUI";

        // var box_s = zz.Style{};
        // box_s = box_s.borderAll(zz.Border.rounded);
        // box_s = box_s.borderForeground(zz.Color.cyan);

        // const list_view = self.steps.view(ctx.allocator);
        // const boxed_list = box_s.render(ctx.allocator, list_view) catch list_view;

        // // Help
        // const help_text = "Press q to quit";
        // const help = help_style.render(ctx.allocator, help_text) catch "";

        // // Get the max width of all elements for proper centering
        // const box_width = zz.measure.maxLineWidth(boxed_list);
        // const help_width = zz.measure.width(help);
        // const title_width = zz.measure.width(title);
        // const max_width = @max(box_width, @max(help_width, title_width));

        // // Center all elements to the max width
        // const centered_title = zz.place.place(
        //     ctx.allocator,
        //     max_width,
        //     1,
        //     .center,
        //     .top,
        //     title,
        // ) catch title;

        // const centered_box = zz.place.place(
        //     ctx.allocator,
        //     max_width,
        //     zz.measure.height(boxed_list),
        //     .center,
        //     .top,
        //     boxed_list,
        // ) catch boxed_list;

        // const centered_help = zz.place.place(
        //     ctx.allocator,
        //     max_width,
        //     1,
        //     .center,
        //     .top,
        //     help,
        // ) catch help;

        // // Build content
        // const content = std.fmt.allocPrint(
        //     ctx.allocator,
        //     "{s}\n\n{s}\n\n{s}",
        //     .{ centered_title, centered_box, centered_help },
        // ) catch "Error";

        // // Center the content in the terminal
        // const centered = zz.place.place(
        //     ctx.allocator,
        //     ctx.width,
        //     ctx.height,
        //     .center,
        //     .middle,
        //     content,
        // ) catch content;

        // return centered;
    }

    fn renderPanel(alloc: std.mem.Allocator, content: []const u8, w: u16, h: u16, palette: *const zz.Palette, highlight: bool) []const u8 {
        var s = zz.Style{};
        s = s.borderAll(zz.Border.rounded);
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
    }
};
