const std = @import("std");
const sqitch_parser = @import("sqitch_parser.zig");
const child_process = @import("./child_process.zig");
const ArrayList = std.ArrayList;
const PlanStep = sqitch_parser.PlanStep;
const Status = sqitch_parser.Status;
const Branch = sqitch_parser.Branch;

const sqitchPlanCommand: [2][]const u8 =
    .{ "git", "show" };

const sqitchStatusCommand: [2][]const u8 =
    .{ "sqitch", "status" };

const planLocation = "migrations/sqitch.plan";

// TODO all these structs share functionalities, maybe I can abstract this somehow?

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

    pub fn init(allocator: std.mem.Allocator, branch: []const u8) !Plan {
        const res, const steps =
            try retrieveSteps(allocator, branch);

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

    // This should return an optional
    pub fn getLastStep(self: Plan) []const u8 {
        return self.steps[self.steps.len - 1].name;
    }

    pub fn update(self: *Plan, branch: []const u8) !void {
        const res, const steps =
            try retrieveSteps(self.allocator, branch);

        const oldSteps = self.steps;
        const oldRes = self.res;

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

pub const BranchWithPlan = struct {
    branch: Branch,
    plan: Plan,

    pub fn getLastStep(self: BranchWithPlan) []const u8 {
        return self.plan.getLastStep();
    }
};

pub const Branches = struct {
    allocator: std.mem.Allocator,
    branches: []BranchWithPlan,
    res: []const u8,

    pub fn init(allocator: std.mem.Allocator) !Branches {
        const res, const branches =
            try retrieveBranches(allocator);

        return .{ .allocator = allocator, .branches = branches, .res = res };
    }

    fn retrieveBranches(allocator: std.mem.Allocator) !struct { []const u8, []BranchWithPlan } {
        const res = try child_process.run(allocator, &.{ "git", "branch", "--sort=-committerdate" });

        // std.debug.print("{s}\n\n", .{res});

        const branches = try sqitch_parser.parseBranches(allocator, res);

        // std.debug.print("{any}\n\n", .{branches});

        // TODO: not sure about this, should I just use an array lsit as struct field?
        var branchesWithPlan: ArrayList(BranchWithPlan) = .empty;
        // defer branchesWithPlan.deinit(allocator);

        for (branches) |branch| {
            // std.debug.print("BRANCH: {s}\n\n", .{branch.name});
            const plan = try Plan.init(allocator, branch.name);
            const branchWithPlan =
                BranchWithPlan{ .branch = branch, .plan = plan };
            try branchesWithPlan.append(allocator, branchWithPlan);
        }

        return .{
            res,
            try branchesWithPlan.toOwnedSlice(allocator),
        };
    }

    pub fn update(self: *Branches) !void {
        const res, const branches =
            try retrieveBranches(self.allocator);

        const oldBranches = self.branches;
        const oldRes = self.res;

        self.branches = branches;
        self.res = res;

        self.allocator.free(oldBranches);
        self.allocator.free(oldRes);
    }

    // TODO: This leaks because Plan is not cleaning up properly.
    // I want to refactor all of this anyways
    pub fn deinit(self: *Branches) void {
        // self.steps.deinit(self.allocator);
        self.allocator.free(self.res);
        self.allocator.free(self.branches);
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
