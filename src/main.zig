const std = @import("std");
const experiment = @import("experiment.zig");

pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    var tui_data = try experiment.TUIData.init(gpa.allocator());
    try tui_data.update();
    tui_data.deinit();
}

test {
    // _ = external;
}
