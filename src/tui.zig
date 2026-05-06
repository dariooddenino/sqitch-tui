const std = @import("std");
const Writer = std.Io.Writer;

const zz = @import("zigzag");

const sqitch_parser = @import("./sqitch_parser.zig");
const PlanStep = sqitch_parser.PlanStep;
const Status = sqitch_parser.Status;
const sqitch = @import("./sqitch.zig");

const Item = zz.List(PlanStep).Item;

pub const Model = struct {
    count: i32,
    plan: sqitch.Plan,
    steps: zz.List(PlanStep),
    current_migration: sqitch.CurrentMigration,
    persistent_allocator: std.mem.Allocator,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    fn setPlan(self: *Model) !void {
        const plan = try sqitch.Plan.init(self.persistent_allocator);

        self.plan = plan;
        try self.updateSteps();
    }

    fn updateSteps(self: *Model) !void {
        // const plan = try sqitch.Plan.init(self.persistent_allocator);

        // self.plan = plan;
        self.steps.clear();
        var index = self.plan.steps.len;
        while (index > 0) : (index -= 1) {
            self.steps.addItem(Item.init(self.plan.steps[index - 1], self.plan.steps[index - 1].name)) catch {};
        }
    }

    fn setCurrentMigration(self: *Model) !void {
        const current_migration = try sqitch.CurrentMigration.init(self.persistent_allocator);

        self.current_migration = current_migration;
    }

    fn isStepCurrentMigration(self: Model, step: PlanStep) bool {
        return std.mem.eql(u8, step.name, self.current_migration.status.name);
    }

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        self.steps = zz.List(PlanStep).init(ctx.persistent_allocator);
        self.persistent_allocator = ctx.persistent_allocator;

        self.setCurrentMigration() catch return .none;
        self.setPlan() catch return .none;

        return .none;
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                switch (k.key) {
                    .char => |c| switch (c) {
                        'q' => return .quit,
                        'r' => {
                            self.current_migration.update() catch return .none;

                            self.plan.update("HEAD") catch return .none;
                            self.updateSteps() catch return .none;
                            return .none;
                        },
                        else => {},
                    },
                    else => self.steps.handleKey(k),
                }
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.cyan);
        title_style = title_style.inline_style(true);

        var box_style = zz.Style{};
        box_style = box_style.borderAll(zz.Border.rounded);
        box_style = box_style.borderForeground(zz.Color.gray(15));
        box_style = box_style.paddingAll(1);

        const title = title_style.render(ctx.allocator, "Todo List") catch "Todo List";

        // Build todo list display using filtered_indices
        var list_content: Writer.Allocating = .init(ctx.allocator);
        const writer = &list_content.writer;

        const visible = self.steps.filtered_indices.items;

        for (visible, 0..) |item_idx, i| {
            if (i > 0) writer.writeByte('\n') catch {};

            const item = self.steps.items.items[item_idx];

            // Cursor indicator
            if (i == self.steps.cursor) {
                writer.writeAll("> ") catch {};
            } else {
                writer.writeAll("  ") catch {};
            }

            if (self.isStepCurrentMigration(item.value)) {
                writer.writeAll("* ") catch {};
            } else {
                writer.writeAll("  ") catch {};
            }

            // Checkbox
            // if (item.value.done) {
            //     writer.writeAll("[x] ") catch {};
            // } else {
            //     writer.writeAll("[ ] ") catch {};
            // }

            // Title with strikethrough if done
            // if (item.value.done) {
            //     var done_style = zz.Style{};
            //     done_style = done_style.strikethrough(true);
            //     done_style = done_style.fg(zz.Color.gray(12));
            //     done_style = done_style.inline_style(true);
            //     const styled = done_style.render(ctx.allocator, item.title) catch item.title;
            //     writer.writeAll(styled) catch {};
            // } else if (i == self.list.cursor) {
            //     var selected_style = zz.Style{};
            //     selected_style = selected_style.bold(true);
            //     selected_style = selected_style.fg(zz.Color.magenta);
            //     selected_style = selected_style.inline_style(true);
            //     const styled = selected_style.render(ctx.allocator, item.title) catch item.title;
            //     writer.writeAll(styled) catch {};
            // } else {
            writer.writeAll(item.title) catch {};
            // }
        }

        const list_view = list_content.toOwnedSlice() catch "";
        const boxed_list = box_style.render(ctx.allocator, list_view) catch list_view;

        // Help
        var help_style = zz.Style{};
        help_style = help_style.fg(zz.Color.gray(12));
        help_style = help_style.inline_style(true);
        const help_text = "Press q to quit";
        const help = help_style.render(ctx.allocator, help_text) catch "";

        // Get the max width of all elements for proper centering
        const box_width = zz.measure.maxLineWidth(boxed_list);
        const help_width = zz.measure.width(help);
        const title_width = zz.measure.width(title);
        const max_width = @max(box_width, @max(help_width, title_width));

        // Center all elements to the max width
        const centered_title = zz.place.place(
            ctx.allocator,
            max_width,
            1,
            .center,
            .top,
            title,
        ) catch title;

        const centered_box = zz.place.place(
            ctx.allocator,
            max_width,
            zz.measure.height(boxed_list),
            .center,
            .top,
            boxed_list,
        ) catch boxed_list;

        const centered_help = zz.place.place(
            ctx.allocator,
            max_width,
            1,
            .center,
            .top,
            help,
        ) catch help;

        // Build content
        const content = std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n\n{s}\n\n{s}",
            .{ centered_title, centered_box, centered_help },
        ) catch "Error";

        // Center the content in the terminal
        const centered = zz.place.place(
            ctx.allocator,
            ctx.width,
            ctx.height,
            .center,
            .middle,
            content,
        ) catch content;

        return centered;
    }

    pub fn deinit(self: *Model) void {
        // self.steps.items.deinit();
        self.steps.deinit();
        self.plan.deinit();
        self.current_migration.deinit();
    }
};
