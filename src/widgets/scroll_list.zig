const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const flex = @import("flex.zig");
const FlexColumn = flex.FlexColumn;
const FlexRow = flex.FlexRow;
const ScrollBars = @import("scroll_bars.zig").ScrollBars;

pub const ListRowData = struct {
    is_current: bool,
    migration_name: []const u8,
    branches: ?[]const u8,
};

pub const ListRow = struct {
    item: ListRowData,
    idx: usize,
    list: *List,

    pub fn widget(self: *ListRow) vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = ListRow.typeErasedDrawFn,
        };
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *ListRow = @ptrCast(@alignCast(ptr));
        // NOTE: for some reason ctx.max is null here, so I can't use flex for these rows.

        const children = try ctx.arena.alloc(vxfw.SubSurface, 2);

        const max_label_width = self.list.getMaxElementWidth();

        const fg: vaxis.Color = .{ .rgb = [_]u8{ 202, 202, 245 } };
        var style: vaxis.Style = .{ .fg = fg };
        if (self.item.is_current) {
            style = .{
                .fg = .{ .rgb = [_]u8{ 202, 245, 202 } },
                .bold = true,
                .bg = .{ .rgb = [_]u8{ 80, 50, 80 } },
            };
        }

        const item_text: vxfw.Text = .{ .text = self.item.migration_name, .style = style };

        const text_surf: vxfw.SubSurface = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = try item_text.draw(ctx.withConstraints(
                ctx.min,
                .{
                    .width = @intCast(self.item.migration_name.len), // @intCast(max_label_width),
                    .height = ctx.max.height,
                },
            )),
        };

        children[0] = text_surf;
        const padding = 2;

        const s_fg: vaxis.Color = .{ .rgb = [_]u8{ 100, 100, 100 } };
        const s_style: vaxis.Style = .{ .fg = s_fg };
        const secondary_item_text: vxfw.Text = .{ .text = self.item.branches.?, .style = s_style };

        const secondary_surf: vxfw.SubSurface = .{
            .origin = .{ .row = 0, .col = @intCast(text_surf.surface.size.width + padding) },
            .surface = try secondary_item_text.draw(ctx.withConstraints(
                ctx.min,
                .{
                    .width = @intCast(if (self.item.branches) |text| text.len else 0),
                    .height = ctx.max.height,
                },
            )),
        };

        children[1] = secondary_surf;

        return .{
            .size = .{
                .width = @as(u16, @intCast(max_label_width)) + secondary_surf.surface.size.width,
                .height = 1, // @max(secondary_surf.surface.size.height, @max(text_surf.surface.size.height, selector_surf.surface.size.height)),
            },
            .widget = self.widget(),
            .buffer = &.{},
            .children = children,
        };
    }
};

pub const List = struct {
    scroll_bars: ScrollBars,
    rows: std.ArrayList(ListRow),
    selected: usize = 0,

    pub fn widget(self: *List) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = List.typeErasedEventHandler,
            .drawFn = List.typeErasedDrawFn,
        };
    }

    pub fn handleEvent(self: *List, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        switch (event) {
            .key_press => |key| {
                if (key.matches('j', .{})) {
                    if (self.selected < self.rows.items.len) {
                        self.selected += 1;
                    }
                }
                if (key.matches('k', .{})) {
                    if (self.selected > 0) {
                        self.selected -= 1;
                    }
                }

                return self.scroll_bars.scroll_view.handleEvent(ctx, event);
            },
            else => {},
        }
    }

    // This calculatates the max width for the main text of all the elements
    pub fn getMaxElementWidth(self: List) usize {
        var max: usize = 0;
        for (self.rows.items) |item| {
            max = @max(max, item.item.migration_name.len);
        }

        return max;
    }

    pub fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        const self: *List = @ptrCast(@alignCast(ptr));

        return self.handleEvent(ctx, event);
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *List = @ptrCast(@alignCast(ptr));
        const max = ctx.max.size();

        const scroll_view: vxfw.SubSurface = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = try self.scroll_bars.draw(ctx),
        };

        // _ = scroll_view;
        const children = try ctx.arena.alloc(vxfw.SubSurface, 1);
        children[0] = scroll_view;

        return .{
            .size = max,
            .widget = self.widget(),
            .buffer = &.{},
            .children = children,
        };
    }

    pub fn widgetBuilder(ptr: *const anyopaque, idx: usize, _: usize) ?vxfw.Widget {
        const self: *const List = @ptrCast(@alignCast(ptr));
        if (idx >= self.rows.items.len) return null;

        return self.rows.items[idx].widget();
    }
};
