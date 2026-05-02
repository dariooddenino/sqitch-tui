// Useful examples:
// todo_list
// file_browser
// dashboard
// focus_form
// flex_layout
// async_tasks

// TODOS:
// [] how to run a command in a folder
// [] retrieve and parse all local git branches
// [] get the content of the sqitch.plan for each
// [] match each branch to a migration
// [] display the migrations with each branch
// [] open the migration files on the side
// [] select a migration to move there (both log and commit)
// [] BONUS: edit the migration files, maybe with the editor?

const std = @import("std");
const zz = @import("zigzag");
const model = @import("./model.zig");
const sqitch_parser = @import("./sqitch_parser.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // var program = try zz.Program(model.Model).init(gpa.allocator());
    // defer program.deinit();

    // try program.run();
}

test {
    _ = sqitch_parser;
}
