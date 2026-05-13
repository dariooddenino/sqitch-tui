// Useful examples:
// todo_list
// file_browser
// dashboard
// focus_form
// flex_layout
// async_tasks

// TODOS:
// [] Change plan parsing to the file format
// [] Replace function to parse plan to use the file
// [] Create git wrapper to get status of plan at different branches
// [] Create git wrapper to get list of all local branches
// [] Implement simple list display in TUI
// [] match each branch to a migration
// [] display the migrations with each branch
// [] open the migration files on the side
// [] select a migration to move there (both log and commit)
// [] BONUS: edit the migration files, maybe with the editor?

const std = @import("std");
const zz = @import("zigzag");
// const model = @import("./model.zig");
const external = @import("./external.zig");
const tui = @import("tui.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // var gpa = std.heap.DebugAllocator(.{ .verbose_log = true }){};
    defer _ = gpa.deinit();
    var program = try zz.Program(tui.Model).init(gpa.allocator());
    defer program.deinit();

    try program.run();
}

test {
    _ = external;
}
