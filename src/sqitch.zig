const std = @import("std");
const sqitch_parser = @import("sqitch_parser.zig");
const child_process = @import("./child_process.zig");
const ArrayList = std.ArrayList;
const PlanStep = sqitch_parser.PlanStep;
const Status = sqitch_parser.Status;

const sqitchPlanCommand: [2][]const u8 =
    .{ "git", "show" };

const sqitchStatusCommand: [2][]const u8 =
    .{ "sqitch", "status" };

const planLocation = "migrations/sqitch.plan";

// TODO not working a at all...
pub const CurrentMigration = struct {
    allocator: std.mem.Allocator,
    status: *Status,
    res: []const u8,

    pub fn init(allocator: std.mem.Allocator) !CurrentMigration {
        const res, const status =
            try retrieveStatus(allocator);

        const statusPointer = try allocator.create(Status);

        statusPointer.* = status;
        return .{
            .allocator = allocator,
            .status = statusPointer,
            .res = res,
        };
    }

    fn retrieveStatus(allocator: std.mem.Allocator) !struct { []const u8, Status } {
        const res = try child_process.run(allocator, &.{ "sqitch", "status" });

        const status = try sqitch_parser.parseStatus(allocator, res);

        return .{ res, status };
    }

    pub fn update(self: *CurrentMigration) !void {
        const res, const status =
            try retrieveStatus(self.allocator);

        const oldRes = self.res;

        self.res = res;
        self.status.* = status;

        self.allocator.free(oldRes);
    }

    pub fn deinit(self: *CurrentMigration) void {
        self.allocator.destroy(self.status);
        self.allocator.free(self.res);
    }
};

pub const Plan = struct {
    allocator: std.mem.Allocator,
    // steps: std.ArrayList(PlanStep),
    steps: []PlanStep,
    res: []const u8,

    pub fn init(allocator: std.mem.Allocator) !Plan {
        const res, const steps =
            try retrieveSteps(allocator, "HEAD");

        // var stepsList: ArrayList(PlanStep) = .empty;

        // stepsList.clearAndFree(allocator);
        // try stepsList.appendSlice(allocator, steps);

        return .{ .allocator = allocator, .steps = steps, .res = res };
    }

    fn retrieveSteps(allocator: std.mem.Allocator, branch: []const u8) !struct { []const u8, []PlanStep } {
        var command: ArrayList(u8) = .empty;
        defer command.deinit(allocator);

        try command.appendSlice(allocator, branch);
        try command.appendSlice(allocator, ":");
        try command.appendSlice(allocator, planLocation);

        const res = try child_process.run(allocator, &.{ "git", "show", command.items });

        const steps = try sqitch_parser.parseSteps(allocator, res);

        return .{ res, steps };
    }

    pub fn update(self: *Plan, branch: []const u8) !void {
        const res, const steps =
            try retrieveSteps(self.allocator, branch);

        const oldSteps = self.steps;
        const oldRes = self.res;

        // self.step.clearAndFree(self.allocator);
        // self.steps.appendSlice(self.allocator, steps);
        self.steps = steps;
        self.res = res;

        self.allocator.free(oldSteps);
        self.allocator.free(oldRes);
    }

    pub fn deinit(self: *Plan) void {
        // self.steps.deinit(self.allocator);
        self.allocator.free(self.res);
        self.allocator.free(self.steps);
    }
};

pub fn sqitchPlan(allocator: std.mem.Allocator, branch: []const u8) !Plan {
    var command: ArrayList(u8) = .empty;
    defer command.deinit(allocator);

    try command.appendSlice(allocator, branch);
    try command.appendSlice(allocator, ":");
    try command.appendSlice(allocator, planLocation);

    const res = try child_process.run(allocator, &.{ "git", "show", command.items });

    return try sqitch_parser.parsePlan(allocator, res);
}

// pub fn sqitchStatus(allocator: std.mem.Allocator) !Status {
//     const res = try child_process.run(allocator, &.{ "sqitch", "status" });

//     return try sqitch_parser.parseStatus(allocator, res);
// }

test {
    _ = sqitch_parser;
}
