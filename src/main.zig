const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const tui = @import("tui.zig");

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
// [ ] Use libgit?
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    // const alloc = init.gpa;
    const arena = init.arena;
    const alloc = arena.allocator();

    var buffer: [1024]u8 = undefined;
    var app: vxfw.App = try .init(io, alloc, init.environ_map, &buffer);
    defer app.deinit();

    var tui_ = try alloc.create(tui.TUI);
    tui_.* = try tui.TUI.init(io, alloc);
    defer alloc.destroy(tui_);
    defer tui_.deinit();

    const widget: vxfw.Widget = tui_.widget();

    try app.run(widget, .{});
}

test {
    std.testing.refAllDecls(@This());
}
