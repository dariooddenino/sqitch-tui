const std = @import("std");
const vaxis = @import("vaxis");
const scroll_list = @import("widgets/scroll_list.zig");
const ListRow = scroll_list.ListRow;
const ListRowData = scroll_list.ListRowData;
const List = scroll_list.List;
const tui_data = @import("tui_data.zig");
const TUIData = tui_data.TUIData;
const vxfw = vaxis.vxfw;
const flex = @import("widgets/flex.zig");
const FlexColumn = flex.FlexColumn;
const FlexRow = flex.FlexRow;

pub const TUI = struct {
    io: std.Io,
    alloc: std.mem.Allocator,
    tui_data: *TUIData,
    changes_list: *List,

    pub fn init(io: std.Io, alloc: std.mem.Allocator) !TUI {
        const tui_data_ = try alloc.create(TUIData);
        const changes_list = try alloc.create(List);

        return .{
            .io = io,
            .alloc = alloc,
            .tui_data = tui_data_,
            .changes_list = changes_list,
        };
    }

    pub fn deinit(self: TUI) void {
        self.alloc.destroy(self.tui_data);
        self.changes_list.rows.deinit(self.alloc);
        self.alloc.destroy(self.changes_list);
        // self.alloc.destroy(self.layout);
        self.tui_data.deinit();
    }

    pub fn widget(self: *TUI) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = TUI.typeErasedEventHandler,
            .drawFn = TUI.typeErasedDrawFn,
        };
    }

    // TODO: this feel very inefficient, I could just update the data on success, or do nothing on error.
    fn logOnlyMigrate(self: *TUI, ctx: *vxfw.EventContext) !void {
        const cursor = self.changes_list.scroll_bars.scroll_view.cursor;
        // TODO: this is very brittle, I should retrieve the change name and use that instead of relying on the indices matching
        try self.tui_data.logOnlyMigrate(cursor);
        try self.update(ctx);
    }

    // TODO: not entirely sure about this approach
    fn update(self: *TUI, ctx: *vxfw.EventContext) !void {
        const alloc = self.alloc;

        const cursor = self.changes_list.scroll_bars.scroll_view.cursor;

        self.changes_list.rows.deinit(alloc);
        self.tui_data.deinit();

        try self.initData();

        // TODO: very questionable
        self.changes_list.scroll_bars.scroll_view.cursor = cursor;
        ctx.redraw = true;
    }

    fn initData(self: *TUI) !void {
        const alloc = self.alloc;

        const tui_data_ = try TUIData.init(self.io, self.alloc);
        self.tui_data.* = tui_data_;

        const changes = self.tui_data.head.changes;

        // Can I move this into init?
        self.changes_list.* = .{
            .scroll_bars = .{
                .scroll_view = .{
                    .children = .{
                        .builder = .{
                            .userdata = self.changes_list,
                            .buildFn = List.widgetBuilder,
                        },
                    },
                    .draw_cursor = true,
                },
                .draw_horizontal_scrollbar = false,
                .estimated_content_height = @intCast(changes.len),
            },
            .rows = .empty,
        };

        for (changes, 0..) |change, i| {
            // I think the arena allocator is deallocating this, but not sure if it's ok
            var change_branches: std.ArrayList(u8) = .empty;
            for (self.tui_data.branches) |branch| {
                if (std.mem.eql(u8, branch.changes[0].name, change.name)) {
                    // I'm sure there's a better way
                    if (change_branches.items.len > 0) {
                        try change_branches.append(alloc, ' ');
                    }
                    try change_branches.appendSlice(alloc, branch.name);
                }
            }
            try self.changes_list.rows.append(alloc, .{
                .idx = i,
                .list = self.changes_list,
                .item = .{
                    .is_current = std.mem.eql(u8, change.name, self.tui_data.status.status.name),
                    .main_text = change.name,
                    .secondary_text = try change_branches.toOwnedSlice(alloc),
                },
            });
        }
    }

    pub fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        const self: *TUI = @ptrCast(@alignCast(ptr));
        switch (event) {
            .init => {
                try self.initData();
            },
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    ctx.quit = true;
                    return;
                }
                if (key.matches('u', .{})) {
                    try self.update(ctx);
                    return;
                }
                // TODO: need a key that makes more sense
                if (key.matches('w', .{})) {
                    try self.logOnlyMigrate(ctx);
                    return;
                }

                try self.changes_list.handleEvent(ctx, event);
            },
            else => {},
        }
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *TUI = @ptrCast(@alignCast(ptr));
        const max = ctx.max.size();

        const status: vxfw.Text = .{ .text = "Status" };

        // Create the flex column
        const layout: FlexColumn = .{
            .children = &.{
                .{ .widget = self.changes_list.widget() }, // flex=0 means we are our inherent size
                .{ .widget = status.widget(), .flex_shrink = 0 },
            },
        };

        const tui_widget = layout.widget();
        // const tui_widget = self.changes_list.widget();
        const surface = try tui_widget.draw(ctx);

        const tui_child: vxfw.SubSurface = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = surface,
        };

        const children = try ctx.arena.alloc(vxfw.SubSurface, 1);
        children[0] = tui_child;

        return .{
            .size = max,
            .widget = self.widget(),
            .buffer = &.{},
            .children = children,
        };
    }
};
