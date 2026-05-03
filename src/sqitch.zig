const std = @import("std");
const sqitch_parser = @import("sqitch_parser.zig");
const child_process = @import("./child_process.zig");
const ArrayList = std.ArrayList;
const Plan = sqitch_parser.Plan;
const Status = sqitch_parser.Status;

const sqitchPlanCommand: [2][]const u8 =
    .{ "git", "show" };

const sqitchStatusCommand: [2][]const u8 =
    .{ "sqitch", "status" };

const planLocation = "migrations/sqitch.plan";

pub fn sqitchPlan(allocator: std.mem.Allocator, branch: []const u8) !Plan {
    var command: ArrayList(u8) = .empty;
    defer command.deinit(allocator);

    try command.appendSlice(allocator, branch);
    try command.appendSlice(allocator, ":");
    try command.appendSlice(allocator, planLocation);

    const res = try child_process.run(allocator, &.{ "git", "show", command.items });

    return try sqitch_parser.parsePlan(allocator, res);
}

pub fn sqitchStatus(allocator: std.mem.Allocator) !Status {
    const res = try child_process.run(allocator, &.{ "sqitch", "status" });

    return try sqitch_parser.parseStatus(allocator, res);
}

test {
    _ = sqitch_parser;
}
