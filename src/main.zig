const std = @import("std");
const experiment = @import("experiment.zig");

pub fn main(init: std.process.Init) !void {
    const tui = try experiment.TUIData.init(init.io, init.gpa);

    tui.deinit();
}

test {
    // _ = external;
}
