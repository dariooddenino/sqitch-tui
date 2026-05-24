const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

pub const FlexItem = struct {
    widget: vxfw.Widget,
    flex_grow: u8 = 1,
    flex_shrink: u8 = 1,
};

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
        var total_flex_shrink: u16 = 0;
        for (self.children, 0..) |child, i| {
            const surf = try child.widget.draw(layout_ctx);
            first_pass_height += surf.size.height;
            total_flex_grow += child.flex_grow;
            total_flex_shrink += child.flex_shrink;
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
            const extra_space = first_pass_height -| ctx.max.height.?;
            for (self.children, 1..) |child, i| {
                const inherent_height = size_list[i - 1];
                const child_height = if (child.flex_shrink == 0)
                    inherent_height
                else
                    inherent_height -| (extra_space * child.flex_shrink) / total_flex_shrink;

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

        var first_pass_width: u16 = 0;
        var total_flex_grow: u16 = 0;
        var total_flex_shrink: u16 = 0;
        for (self.children, 0..) |child, i| {
            // if (child.flex_grow == 0) {
            const surf = try child.widget.draw(layout_ctx);
            first_pass_width += surf.size.width;
            size_list[i] = surf.size.width;
            // }
            total_flex_grow += child.flex_grow;
            total_flex_shrink += child.flex_shrink;
        }

        // std.debug.print("sizes {any}\n\n", .{size_list});
        // std.debug.print("first pass witdh: {any}\n\n", .{first_pass_width});

        // We are done with the layout arena
        layout_arena.deinit();

        // Draw again, but with distributed widths
        var second_pass_width: u16 = 0;
        var max_height: u16 = 0;

        const enough_space = ctx.max.width.? >= first_pass_width;
        // std.debug.print("enough {any}, ctx {any}, first {any}\n\n", .{ enough_space, ctx.max.width, first_pass_width });

        if (enough_space) {
            const remaining_space = ctx.max.width.? -| first_pass_width;
            // std.debug.print("+remaining space {any}\n\n", .{remaining_space});
            for (self.children, 0..) |child, i| {
                const inherent_width = size_list[i];
                const child_width = if (child.flex_grow == 0)
                    inherent_width
                else if (i == self.children.len - 1)
                    // If we are the last one, we just get the remainder
                    ctx.max.width.? -| second_pass_width
                else
                    inherent_width + (remaining_space * child.flex_grow) / total_flex_grow;

                // std.debug.print("child_width {any} inherent_width {any}\n\n", .{ child_width, inherent_width });
                // Create a context for the child
                const child_ctx = ctx.withConstraints(
                    .{ .width = child_width, .height = 0 },
                    .{ .width = child_width, .height = ctx.max.height.? },
                );
                // std.debug.print("child_ctx {any} {any}\n\n", .{ child_ctx.min, child_ctx.max });
                const surf = try child.widget.draw(child_ctx);
                // std.debug.print("child_surf {any}\n\n", .{surf.size});

                try children.append(ctx.arena, .{
                    .origin = .{ .col = second_pass_width, .row = 0 },
                    .surface = surf,
                    .z_index = 0,
                });
                // std.debug.print("ctx max {any} max_height {any} surf height {any}\n\n\n", .{ ctx.max, max_height, surf.size.height });
                max_height = @max(max_height, surf.size.height);
                second_pass_width += surf.size.width;
            }
        } else {
            const extra_space = first_pass_width -| ctx.max.width.?;
            for (self.children, 1..) |child, i| {
                const inherent_width = size_list[i - 1];
                const child_width = if (child.flex_shrink == 0)
                    inherent_width
                else
                    inherent_width -| (extra_space * child.flex_shrink) / total_flex_shrink;

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
}
test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
