const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const flex = @import("flex.zig");
const FlexColumn = flex.FlexColumn;
const FlexRow = flex.FlexRow;

pub const ListRowData = struct {
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
    is_selected: bool,
    wrap_lines: bool = false,

    pub fn widget(self: *ListRow) vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = ListRow.typeErasedDrawFn,
        };
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *ListRow = @ptrCast(@alignCast(ptr));

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

        // TODO: there's something bugged with this
        if (self.is_selected) {
            const arrow: vxfw.Text = .{ .text = ">" };

            const layout: FlexRow = .{
                .children = &.{
                    .{ .widget = arrow.widget() },
                    .{ .widget = text_widget.widget() },
                },
            };
            const layout_surf: vxfw.SubSurface = .{
                .origin = .{ .row = 0, .col = 0 },
                .surface = try layout.draw(ctx),
            };
            const children = try ctx.arena.alloc(vxfw.SubSurface, 1);
            children[0] = layout_surf;
            return .{
                .size = .{
                    .width = 6 + layout_surf.surface.size.width,
                    .height = layout_surf.surface.size.height,
                },
                .widget = self.widget(),
                .buffer = &.{},
                .children = children,
            };
        }

        const children = try ctx.arena.alloc(vxfw.SubSurface, 1);
        children[1] = text_surf;

        return .{
            .size = .{
                .width = 6 + text_surf.surface.size.width,
                .height = text_surf.surface.size.height,
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

    pub fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        const self: *List = @ptrCast(@alignCast(ptr));
        switch (event) {
            .key_press => |key| {
                if (key.matches('j', .{})) {
                    if (self.selected > 0) {
                        self.selected -= 1;
                    }
                }
                if (key.matches('k', .{})) {
                    if (self.selected < self.rows.items.len) {
                        self.selected += 1;
                    }
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

        std.log.debug("view\n", .{});

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
