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
const sqitch = @import("sqitch.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // var program = try zz.Program(model.Model).init(gpa.allocator());
    // defer program.deinit();

    // TODO: Confused about 0.15/0.16 allocators
    // try program.run();
    // const allocator = gpa.allocator();
    // defer allocator.deinit();
    const allocator = std.heap.page_allocator;
    const arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const status = try sqitch.sqitchStatus(allocator);
    std.debug.print("Current DB migration: {s}\n", .{status.name});
    const plan = try sqitch.sqitchPlan(allocator, "HEAD");
    std.debug.print("Latest migration on HEAD plan: {s}\n", .{plan.steps[plan.steps.len - 1].name});
    const devplan = try sqitch.sqitchPlan(allocator, "dev");
    std.debug.print("Latest migration on dev plan: {s}\n", .{devplan.steps[devplan.steps.len - 1].name});
}

test {
    _ = sqitch;
}
