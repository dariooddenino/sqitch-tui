const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

pub const ListRowData = struct {
    selected_symbol: ?[]const u8,
    main_text: []const u8,
    secondary_text: ?[]const u8,
};

// TODO:
// [ ] Figure out how to handle a "selected" item
// [ ] Draw all three sections of the item
// [ ] Wrap vs ellipsis
pub const ListRow = struct {
    item: ListRowData,
    idx: usize,
    wrap_lines: bool = true,

    pub fn widget(self: *ListRow) vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = ListRow.typeErasedDrawFn,
        };
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *ListRow = @ptrCast(@alignCast(ptr));

        const idx_text = try std.fmt.allocPrint(ctx.arena, "{d: >4}", .{self.idx});
        const idx_widget: vxfw.Text = .{ .text = idx_text };

        const idx_surf: vxfw.SubSurface = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = try idx_widget.draw(ctx.withConstraints(
                // We're only interested in constraining the width, and we know the height will
                // always be 1 row.
                .{ .width = 1, .height = 1 },
                .{ .width = 4, .height = 1 },
            )),
        };

        const text_widget: vxfw.Text = .{ .text = self.item.main_text, .softwrap = self.wrap_lines };
        const text_surf: vxfw.SubSurface = .{
            .origin = .{ .row = 0, .col = 6 },
            .surface = try text_widget.draw(ctx.withConstraints(
                ctx.min,
                // We've shifted the origin over 6 columns so we need to take that into account or
                // we'll draw outside the window.
                if (self.wrap_lines)
                    .{ .width = ctx.min.width -| 6, .height = ctx.max.height }
                else
                    .{ .width = if (ctx.max.width) |w| w - 6 else null, .height = ctx.max.height },
            )),
        };

        const children = try ctx.arena.alloc(vxfw.SubSurface, 2);
        children[0] = idx_surf;
        children[1] = text_surf;

        return .{
            .size = .{
                .width = 6 + text_surf.surface.size.width,
                .height = @max(idx_surf.surface.size.height, text_surf.surface.size.height),
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

    pub fn widget(self: *List) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = List.typeErasedEventHandler,
            .drawFn = List.typeErasedDrawFn,
        };
    }

    pub fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        const self: *List = @ptrCast(@alignCast(ptr));
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    ctx.quit = true;
                    return;
                }

                return self.scroll_bars.scroll_view.handleEvent(ctx, event);
            },
            else => {},
        }
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *List = @ptrCast(@alignCast(ptr));
        const max = ctx.max.size();

        const scroll_view: vxfw.SubSurface = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = try self.scroll_bars.draw(ctx),
        };

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
