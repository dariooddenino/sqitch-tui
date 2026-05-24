const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const flex = @import("flex.zig");
const FlexColumn = flex.FlexColumn;
const FlexRow = flex.FlexRow;

// TODO:
// [ ] I think this should hold a widget or something similar
//     Then we can have a more generic rendering function that takes into account
//     the final size for the purpose of rendering the scrollbar correctly
pub const ListRowData = struct {
    main_text: []const u8,
    secondary_text: ?[]const u8,
};

// TODO:
// [ ] Figure out how to handle a "selected" item
// [ ] Draw all three sections of the item
// [ ] Wrap vs ellipsis
// [ ] Custom scrollbar with bar on the left
// [ ] The scrolling should be relative to the selected item's visibilty
// [ ] Disable mouse scroll?
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

        const children = try ctx.arena.alloc(vxfw.SubSurface, 3);

        const text_offset: i17 = 4;
        // const text_offset_u16: u16 = @intCast(text_offset);

        var selector: vxfw.Text = .{ .text = " " };
        if (self.idx == self.list.selected) {
            selector = .{ .text = ">" };
        }

        const selector_surf: vxfw.SubSurface = .{
            .origin = .{ .row = 0, .col = 2 },
            .surface = try selector.draw(ctx.withConstraints(
                ctx.min,
                .{ .width = 1, .height = 2 },
            )),
        };

        children[0] = selector_surf;

        const item_text: vxfw.Text = .{ .text = self.item.main_text };

        const text_surf: vxfw.SubSurface = .{
            .origin = .{ .row = 0, .col = text_offset },
            .surface = try item_text.draw(ctx.withConstraints(
                ctx.min,
                .{
                    .width = @intCast(self.item.main_text.len),
                    .height = ctx.max.height,
                },
                // .{ .width = if (ctx.max.width) |w| w - text_offset_u16 else null, .height = ctx.max.height },
            )),
        };

        children[1] = text_surf;

        const secondary_item_text: vxfw.Text = .{ .text = self.item.secondary_text.? };

        const secondary_offset = text_offset + text_surf.surface.size.width + 1;
        const secondary_offset_u16: u16 = @intCast(secondary_offset);

        const secondary_surf: vxfw.SubSurface = .{
            .origin = .{ .row = 1, .col = secondary_offset },
            .surface = try secondary_item_text.draw(ctx.withConstraints(
                ctx.min,
                .{ .width = if (ctx.max.width) |w| w - secondary_offset_u16 else null, .height = ctx.max.height },
            )),
        };

        children[2] = secondary_surf;

        return .{
            .size = .{
                .width = secondary_offset_u16 + secondary_surf.surface.size.width,
                .height = 3, // @max(secondary_surf.surface.size.height, @max(text_surf.surface.size.height, selector_surf.surface.size.height)),
            },
            .widget = self.widget(),
            .buffer = &.{},
            .children = children,
        };
    }
};

pub const List = struct {
    scroll_bars: vxfw.ScrollBars,
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

        const item_widget = self.rows.items[idx].widget();

        return item_widget;
    }
};
