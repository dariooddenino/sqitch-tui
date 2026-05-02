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
// [] open the sqitch.plan file directly (or use a plan command, better)
// [] parse sqitch plan content
// [] match each branch to a migration
// [] display the migrations with each branch
// [] open the migration files on the side
// [] select a migration to move there (both log and commit)
// [] figure out how to find the current migration
// [] BONUS: edit the migration files, maybe with the editor?

const std = @import("std");
const zz = @import("zigzag");
const model = @import("./model.zig");
const sqitch = @import("./sqitch.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // var program = try zz.Program(model.Model).init(gpa.allocator());
    // defer program.deinit();

    // try program.run();
}

test {
    _ = sqitch;
}
