const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const scroll_list = @import("widgets/scroll_list.zig");
const experiment = @import("experiment.zig");
const TUIData = experiment.TUIData;

const ListRow = scroll_list.ListRow;
const ListRowData = scroll_list.ListRowData;
const List = scroll_list.List;

// TODO:
// [ ] Finish ListRow
// [ ] Layouts
// [ ] Status bar
// [ ] Update data
// [ ] Notifications
// [ ] Side panel with change details
// [ ] Remove hardcoded paths
// [ ] Add safety around edge cases
// [ ] Styling
// [ ] Show diffs between branches
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.gpa;

    var buffer: [1024]u8 = undefined;
    var app: vxfw.App = try .init(io, alloc, init.environ_map, &buffer);
    defer app.deinit();

    var arena: std.heap.ArenaAllocator = .init(alloc);
    defer arena.deinit();

    const model = try alloc.create(List);
    defer alloc.destroy(model);

    const tui_data = try TUIData.init(io, alloc);
    defer tui_data.deinit();
    const changes = tui_data.head.changes;

    model.* = .{
        .scroll_bars = .{
            .scroll_view = .{
                .children = .{
                    .builder = .{
                        .userdata = model,
                        .buildFn = List.widgetBuilder,
                    },
                },
            },
            .estimated_content_height = @intCast(changes.len),
        },
        .rows = .empty,
    };
    defer model.rows.deinit(alloc);

    for (changes, 0..) |change, i| {
        try model.rows.append(alloc, .{ .idx = i, .item = .{ .selected_symbol = null, .main_text = change.name, .secondary_text = change.date } });
    }

    try app.run(model.widget(), .{});
}

test {
    std.testing.refAllDecls(@This());
}
