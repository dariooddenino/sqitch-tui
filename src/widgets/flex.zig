const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

pub const FlexItem = struct {
    widget: vxfw.Widget,
    flex_grow: u8 = 1,
    flex_shrink: u8 = 1,
};

// FIXME
// There's a bug with flex layouts when the extra space is just a single row/column.
// It's possible that the problem presents itself with any odd extra space value.
// Moreover, what to do with elements that area already 1 in size?
// I need more tests here to be sure that everything works fine.

pub const FlexColumn = struct {
    const Allocator = std.mem.Allocator;

    children: []const FlexItem,

    pub fn widget(self: *const FlexColumn) vxfw.Widget {
        return .{
            .userdata = @constCast(self),
            .drawFn = typeErasedDrawFn,
        };
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        const self: *const FlexColumn = @ptrCast(@alignCast(ptr));
        return self.draw(ctx);
    }

    pub fn draw(self: *const FlexColumn, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        std.debug.assert(ctx.max.height != null);
        std.debug.assert(ctx.max.width != null);
        if (self.children.len == 0) return vxfw.Surface.init(ctx.arena, self.widget(), ctx.min);

        // make our children list
        var children: std.ArrayList(vxfw.SubSurface) = .empty;

        const max_width, const second_pass_height = try self.calculateHeights(ctx, &children);

        const size: vxfw.Size = .{ .width = max_width, .height = second_pass_height };
        return .{
            .size = size,
            .widget = self.widget(),
            .buffer = &.{},
            .children = children.items,
        };
    }

    fn calculateHeights(self: *const FlexColumn, ctx: vxfw.DrawContext, children: *std.ArrayList(vxfw.SubSurface)) !struct { u16, u16 } {
        // Store the inherent size of each widget
        const size_list = try ctx.arena.alloc(u16, self.children.len);

        var layout_arena = std.heap.ArenaAllocator.init(ctx.arena);

        const layout_ctx: vxfw.DrawContext = .{
            .min = .{ .width = 0, .height = 0 },
            // NOTE: max height was null
            .max = .{ .width = ctx.max.width, .height = ctx.max.height },
            .arena = layout_arena.allocator(),
            .cell_size = ctx.cell_size,
        };
        // Store the inherent size of each widget
        var first_pass_height: u16 = 0;
        var total_flex_grow: u16 = 0;
        var total_height_shrink: f16 = 0;
        for (self.children, 0..) |child, i| {
            const surf = try child.widget.draw(layout_ctx);
            first_pass_height += surf.size.height;
            total_flex_grow += child.flex_grow;
            total_height_shrink += @floatFromInt(child.flex_shrink * surf.size.height);
            size_list[i] = surf.size.height;
        }

        // We are done with the layout arena
        layout_arena.deinit();

        // Draw again, but with distributed heights
        var second_pass_height: u16 = 0;
        var max_width: u16 = 0;

        const enough_space = ctx.max.height.? >= first_pass_height;

        if (enough_space) {
            const remaining_space = ctx.max.height.? - first_pass_height;
            for (self.children, 1..) |child, i| {
                const inherent_height = size_list[i - 1];
                const child_height = if (child.flex_grow == 0)
                    inherent_height
                else if (i == self.children.len)
                    // If we are the last one, we just get the remainder
                    ctx.max.height.? - second_pass_height
                else
                    inherent_height + (remaining_space * child.flex_grow) / total_flex_grow;

                // Create a context for the child
                const child_ctx = ctx.withConstraints(
                    .{ .width = 0, .height = child_height },
                    .{ .width = ctx.max.width.?, .height = child_height },
                );
                const surf = try child.widget.draw(child_ctx);

                try children.append(ctx.arena, .{
                    .origin = .{ .col = 0, .row = second_pass_height },
                    .surface = surf,
                    .z_index = 0,
                });
                max_width = @max(max_width, surf.size.width);
                second_pass_height += surf.size.height;
            }
        } else {
            const extra_space: f16 = @floatFromInt(first_pass_height -| ctx.max.height.?);
            const shrunk_size_list = try ctx.arena.alloc(u16, self.children.len);
            var total_shrunk_size: u16 = 0;

            // We do another pass to calculate the shrunk sizes
            for (self.children, 1..) |child, i| {
                const inherent_height: f16 = @floatFromInt(size_list[i - 1]);
                const shrinking: f16 = 1 - @as(f16, @floatFromInt(child.flex_shrink)) * extra_space / total_height_shrink;
                const shrunk_height = @max(1, @as(u16, @floor(inherent_height * shrinking)));
                shrunk_size_list[i - 1] = shrunk_height;
                total_shrunk_size += shrunk_height;
            }

            var remaining_space = ctx.max.height.? - total_shrunk_size;

            // The final pass allocates any remaining extra space and creates the surfaces
            for (self.children, 1..) |child, i| {
                var child_height = shrunk_size_list[i - 1];

                // If the child was shrunk and we have extra space
                const child_extra_space = size_list[i - 1] - child_height;
                if (remaining_space > 0 and child_extra_space > 0) {
                    const to_add = @min(remaining_space, child_extra_space);
                    child_height += to_add;
                    remaining_space -= to_add;
                }

                // Create a context for the child
                const child_ctx = ctx.withConstraints(
                    .{ .width = 0, .height = child_height },
                    .{ .width = ctx.max.width.?, .height = child_height },
                );
                const surf = try child.widget.draw(child_ctx);

                try children.append(ctx.arena, .{
                    .origin = .{ .col = 0, .row = second_pass_height },
                    .surface = surf,
                    .z_index = 0,
                });
                max_width = @max(max_width, surf.size.width);
                second_pass_height += surf.size.height;
            }
        }

        return .{ max_width, second_pass_height };
    }
};

pub const FlexRow = struct {
    const Allocator = std.mem.Allocator;

    children: []const FlexItem,

    pub fn widget(self: *const FlexRow) vxfw.Widget {
        return .{
            .userdata = @constCast(self),
            .drawFn = typeErasedDrawFn,
        };
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        const self: *const FlexRow = @ptrCast(@alignCast(ptr));
        return self.draw(ctx);
    }

    pub fn draw(self: *const FlexRow, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        std.debug.assert(ctx.max.height != null);
        std.debug.assert(ctx.max.width != null);
        if (self.children.len == 0) return vxfw.Surface.init(ctx.arena, self.widget(), ctx.min);

        // make our children list
        var children: std.ArrayList(vxfw.SubSurface) = .empty;

        const max_height, const second_pass_width = try self.calculateWidths(ctx, &children);

        const size: vxfw.Size = .{ .width = second_pass_width, .height = max_height };
        return .{
            .size = size,
            .widget = self.widget(),
            .buffer = &.{},
            .children = children.items,
        };
    }

    fn calculateWidths(self: *const FlexRow, ctx: vxfw.DrawContext, children: *std.ArrayList(vxfw.SubSurface)) !struct { u16, u16 } {
        // Store the inherent size of each widget
        const size_list = try ctx.arena.alloc(u16, self.children.len);

        var layout_arena = std.heap.ArenaAllocator.init(ctx.arena);

        const layout_ctx: vxfw.DrawContext = .{
            .min = .{ .width = 0, .height = 0 },
            // NOTE: this was width = null
            .max = .{ .width = ctx.max.width, .height = ctx.max.height },
            .arena = layout_arena.allocator(),
            .cell_size = ctx.cell_size,
        };

        // Store the inherent size of each widget
        var first_pass_width: u16 = 0;
        var total_flex_grow: u16 = 0;
        var total_width_shrink: f16 = 0;
        for (self.children, 0..) |child, i| {
            const surf = try child.widget.draw(layout_ctx);
            first_pass_width += surf.size.width;
            total_flex_grow += child.flex_grow;
            total_width_shrink += @floatFromInt(child.flex_shrink * surf.size.width);
            size_list[i] = surf.size.width;
        }

        // We are done with the layout arena
        layout_arena.deinit();

        // Draw again, but with distributed widths
        var second_pass_width: u16 = 0;
        var max_height: u16 = 0;

        const enough_space = ctx.max.width.? >= first_pass_width;

        if (enough_space) {
            const remaining_space = ctx.max.width.? -| first_pass_width;
            for (self.children, 0..) |child, i| {
                const inherent_width = size_list[i];
                const child_width = if (child.flex_grow == 0)
                    inherent_width
                else if (i == self.children.len - 1)
                    // If we are the last one, we just get the remainder
                    ctx.max.width.? -| second_pass_width
                else
                    inherent_width + (remaining_space * child.flex_grow) / total_flex_grow;

                // Create a context for the child
                const child_ctx = ctx.withConstraints(
                    .{ .width = child_width, .height = 0 },
                    .{ .width = child_width, .height = ctx.max.height.? },
                );
                const surf = try child.widget.draw(child_ctx);

                try children.append(ctx.arena, .{
                    .origin = .{ .col = second_pass_width, .row = 0 },
                    .surface = surf,
                    .z_index = 0,
                });
                max_height = @max(max_height, surf.size.height);
                second_pass_width += surf.size.width;
            }
        } else {
            const extra_space: f16 = @floatFromInt(first_pass_width -| ctx.max.width.?);
            const shrunk_size_list = try ctx.arena.alloc(u16, self.children.len);
            var total_shrunk_size: u16 = 0;

            // We do another pass to calculate the shrunk sizes
            for (self.children, 1..) |child, i| {
                const inherent_width: f16 = @floatFromInt(size_list[i - 1]);
                const shrinking: f16 = 1 - @as(f16, @floatFromInt(child.flex_shrink)) * extra_space / total_width_shrink;
                const shrunk_width = @max(1, @as(u16, @floor(inherent_width * shrinking)));
                shrunk_size_list[i - 1] = shrunk_width;
                total_shrunk_size += shrunk_width;
            }

            var remaining_space = ctx.max.width.? - total_shrunk_size;

            // The final pass allocates any remaining extra space and creates the surfaces
            for (self.children, 1..) |child, i| {
                var child_width = shrunk_size_list[i - 1];

                // If the child was shrunk and we have extra space
                const child_extra_space = size_list[i - 1] - child_width;
                if (remaining_space > 0 and child_extra_space > 0) {
                    const to_add = @min(remaining_space, child_extra_space);
                    child_width += to_add;
                    remaining_space -= to_add;
                }

                // Create a context for the child
                const child_ctx = ctx.withConstraints(
                    .{ .width = child_width, .height = 0 },
                    .{ .width = child_width, .height = ctx.max.height.? },
                );
                const surf = try child.widget.draw(child_ctx);

                try children.append(ctx.arena, .{
                    .origin = .{ .col = second_pass_width, .row = 0 },
                    .surface = surf,
                    .z_index = 0,
                });
                max_height = @max(max_height, surf.size.height);
                second_pass_width += surf.size.width;
            }
        }

        return .{ max_height, second_pass_width };
    }
};

test FlexColumn {
    const Text = vxfw.Text;
    // Will be height=1, width=3
    const abc: Text = .{ .text = "abc" };
    const def: Text = .{ .text = "def" };
    const ghi: Text = .{ .text = "ghi" };
    const jklmno: Text = .{ .text = "jkl\n\nmno" };

    // Create the flex column
    const flex_column: FlexColumn = .{
        .children = &.{
            .{ .widget = abc.widget(), .flex_grow = 0 }, // flex=0 means we are our inherent size
            .{ .widget = def.widget(), .flex_grow = 1 },
            .{ .widget = ghi.widget(), .flex_grow = 1 },
            .{ .widget = jklmno.widget(), .flex_grow = 1 },
        },
    };

    // Boiler plate draw context
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    vxfw.DrawContext.init(.unicode);

    const flex_widget = flex_column.widget();
    const ctx: vxfw.DrawContext = .{
        .arena = arena.allocator(),
        .min = .{},
        .max = .{ .width = 16, .height = 16 },
        .cell_size = .{ .width = 10, .height = 20 },
    };

    const surface = try flex_widget.draw(ctx);
    // FlexColumn expands to max height and widest child
    try std.testing.expectEqual(16, surface.size.height);
    try std.testing.expectEqual(3, surface.size.width);
    // We have four children
    try std.testing.expectEqual(4, surface.children.len);

    // We will track the row we are on to confirm the origins
    var row: u16 = 0;
    // First child has flex=0, it should be it's inherent height
    try std.testing.expectEqual(1, surface.children[0].surface.size.height);
    try std.testing.expectEqual(row, surface.children[0].origin.row);
    // Add the child height each time
    row += surface.children[0].surface.size.height;
    // Let's do some math
    // - We have 4 children to fit into 16 rows. 3 children will be 1 row tall, one will be 2 rows
    //   tall for a total height of 5 rows.
    // - The first child is 1 row and no flex. The rest of the height gets distributed evenly among
    //   the remaining 3 children. The remainder height is 16 - 5 = 11, so each child should get 11 /
    //   3 = 3 extra rows, and the last will receive the remainder
    try std.testing.expectEqual(1 + 3, surface.children[1].surface.size.height);
    try std.testing.expectEqual(row, surface.children[1].origin.row);
    row += surface.children[1].surface.size.height;

    try std.testing.expectEqual(1 + 3, surface.children[2].surface.size.height);
    try std.testing.expectEqual(row, surface.children[2].origin.row);
    row += surface.children[2].surface.size.height;

    try std.testing.expectEqual(2 + 3 + 2, surface.children[3].surface.size.height);
    try std.testing.expectEqual(row, surface.children[3].origin.row);

    // Testing that shrinking works fine
    //
    const tall: Text = .{ .text = "pqr\n\nstu\n\nvwx\n\nyz" };

    // We have two tall elements followed by a shorter one
    const flex_column_shrink: FlexColumn = .{ .children = &.{
        .{ .widget = abc.widget(), .flex_shrink = 1 },
        .{ .widget = def.widget(), .flex_shrink = 0 },
        .{ .widget = tall.widget(), .flex_shrink = 2 },
        .{ .widget = tall.widget(), .flex_shrink = 1 },
        .{ .widget = jklmno.widget(), .flex_shrink = 1 },
    } };

    // The context is smaller enough that it would have to render the last element with 0 height
    const ctx_shrink: vxfw.DrawContext = .{
        .arena = arena.allocator(),
        .min = .{},
        .max = .{ .width = 16, .height = 12 },
        .cell_size = .{ .width = 10, .height = 20 },
    };

    const surface_shrink = try flex_column_shrink.widget().draw(ctx_shrink);

    // Total height should be 12
    try std.testing.expectEqual(12, surface_shrink.size.height);

    // The first item should have the original height, despite the shrink being set to 1
    try std.testing.expectEqual(1, surface_shrink.children[0].surface.size.height);

    // Same height but different shrinks result in a different final height
    try std.testing.expectEqual(3, surface_shrink.children[2].surface.size.height);
    try std.testing.expectEqual(5, surface_shrink.children[3].surface.size.height);
}

test FlexRow {
    const Text = vxfw.Text;
    // Will be height=1, width=3
    const abc: Text = .{ .text = "abc" };
    const def: Text = .{ .text = "def" };
    const ghi: Text = .{ .text = "ghi" };
    const jklmno: Text = .{ .text = "jkl\n\nmno" };

    // Create the flex row
    const flex_row: FlexRow = .{
        .children = &.{
            .{ .widget = abc.widget(), .flex_grow = 0 }, // flex=0 means we are our inherent size
            .{ .widget = def.widget(), .flex_grow = 1 },
            .{ .widget = ghi.widget(), .flex_grow = 1 },
            .{ .widget = jklmno.widget(), .flex_grow = 1 },
        },
    };

    // Boiler plate draw context
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    vxfw.DrawContext.init(.unicode);

    const flex_widget = flex_row.widget();
    const ctx: vxfw.DrawContext = .{
        .arena = arena.allocator(),
        .min = .{},
        .max = .{ .width = 16, .height = 16 },
        .cell_size = .{ .width = 10, .height = 20 },
    };

    const surface = try flex_widget.draw(ctx);
    // FlexRow expands to max width and tallest child
    try std.testing.expectEqual(16, surface.size.width);
    try std.testing.expectEqual(3, surface.size.height);
    // We have four children
    try std.testing.expectEqual(4, surface.children.len);

    // We will track the column we are on to confirm the origins
    var col: u16 = 0;
    // First child has flex=0, it should be it's inherent width
    try std.testing.expectEqual(3, surface.children[0].surface.size.width);
    try std.testing.expectEqual(col, surface.children[0].origin.col);
    // Add the child height each time
    col += surface.children[0].surface.size.width;
    // Let's do some math
    // - We have 4 children to fit into 16 cols. All children will be 3 wide for a total width of 12
    // - The first child is 3 cols and no flex. The rest of the width gets distributed evenly among
    //   the remaining 3 children. The remainder width is 16 - 12 = 4, so each child should get 4 /
    //   3 = 1 extra cols, and the last will receive the remainder
    try std.testing.expectEqual(1 + 3, surface.children[1].surface.size.width);
    try std.testing.expectEqual(col, surface.children[1].origin.col);
    col += surface.children[1].surface.size.width;

    try std.testing.expectEqual(1 + 3, surface.children[2].surface.size.width);
    try std.testing.expectEqual(col, surface.children[2].origin.col);
    col += surface.children[2].surface.size.width;

    try std.testing.expectEqual(1 + 3 + 1, surface.children[3].surface.size.width);
    try std.testing.expectEqual(col, surface.children[3].origin.col);

    // Testing that shrinking works fine
    //
    const long: Text = .{ .text = "pqrstuvwxyz" };

    // We have two tall elements followed by a shorter one
    const flex_row_shrink: FlexRow = .{ .children = &.{
        .{ .widget = abc.widget(), .flex_shrink = 1 },
        .{ .widget = def.widget(), .flex_shrink = 0 },
        .{ .widget = long.widget(), .flex_shrink = 2 },
        .{ .widget = long.widget(), .flex_shrink = 1 },
        .{ .widget = jklmno.widget(), .flex_shrink = 1 },
    } };

    // The context is smaller enough that it would have to render the last element with 0 width
    const ctx_shrink: vxfw.DrawContext = .{
        .arena = arena.allocator(),
        .min = .{},
        .max = .{ .width = 16, .height = 12 },
        .cell_size = .{ .width = 10, .height = 20 },
    };

    const surface_shrink = try flex_row_shrink.widget().draw(ctx_shrink);

    // Total width should be 12
    try std.testing.expectEqual(16, surface_shrink.size.width);

    // The first item should have the original width, despite the shrink being set to 1
    try std.testing.expectEqual(3, surface_shrink.children[0].surface.size.width);

    // Same width but different shrinks result in a different final width
    try std.testing.expectEqual(3, surface_shrink.children[2].surface.size.width);
    try std.testing.expectEqual(6, surface_shrink.children[3].surface.size.width);
}
test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
