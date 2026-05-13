const std = @import("std");
const parser = @import("parser.zig");
const child_process = @import("./child_process.zig");
const ArrayList = std.ArrayList;
const PlanStep = parser.PlanStep;
const Status = parser.Status;
const Branch = parser.Branch;

fn sqitchPlanCommand(arg: []const u8) [3][]const u8 {
    return .{ "git", "show", arg };
}

const sqitchStatusCommand: [2][]const u8 =
    .{ "sqitch", "status" };

const planLocation = "migrations/sqitch.plan";

// TODO all these structs share functionalities, maybe I can abstract this somehow?

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
        const res = try child_process.run(allocator, &sqitchStatusCommand);

        const status = try parser.parseStatus(allocator, res);

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

pub const PlanMigration = struct {
    allocator: std.mem.Allocator,
    step: PlanStep,
    branches: []BranchMigration,
    index: usize,
    is_current_migration: bool,
    is_verified: ?bool,

    fn init(allocator: std.mem.Allocator, step: PlanStep, branches: []BranchMigration, index: usize, is_current_migration: bool, is_verified: ?bool) PlanMigration {
        return PlanMigration{
            .allocator = allocator,
            .step = step,
            .branches = branches,
            .index = index,
            .is_current_migration = is_current_migration,
            .is_verified = is_verified,
        };
    }

    fn deinit(self: PlanMigration) void {
        self.allocator.free(self.branches);
    }
};

pub const BranchMigration = struct {
    allocator: std.mem.Allocator,
    branch: Branch,
    migration: PlanStep,
    res: []const u8,
    steps: []PlanStep,

    fn init(allocator: std.mem.Allocator, branch: Branch, steps: []PlanStep, res: []const u8) BranchMigration {
        return BranchMigration{
            .allocator = allocator,
            .branch = branch,
            .migration = steps[0],
            .res = res,
            .steps = steps,
        };
    }

    fn deinit(self: BranchMigration) void {
        self.allocator.free(self.res);
        self.allocator.free(self.steps);
    }
};

pub const Plan = struct {
    allocator: std.mem.Allocator,
    branches: Branches,
    steps: []PlanStep, // TODO might want to remove this?
    migrations: []PlanMigration,
    current_migration: CurrentMigration,
    res: []const u8,

    pub fn init(allocator: std.mem.Allocator, branch: []const u8) !Plan {
        const res, const steps =
            try retrieveSteps(allocator, branch);

        const branches = try Branches.init(allocator);

        const current_migration = try getCurrentMigration(allocator);

        const migrations = try buildMigrations(allocator, steps, branches, current_migration);

        return .{
            .allocator = allocator,
            .steps = steps,
            .res = res,
            .branches = branches,
            .migrations = migrations,
            .current_migration = current_migration,
        };
    }

    fn getCurrentMigration(allocator: std.mem.Allocator) !CurrentMigration {
        return try CurrentMigration.init(allocator);
    }

    fn buildMigrations(allocator: std.mem.Allocator, steps: []PlanStep, branches: Branches, current_migration: CurrentMigration) ![]PlanMigration {
        var migrations: std.ArrayList(PlanMigration) = .empty;
        for (steps, 0..) |step, ix| {
            const is_current_migration =
                std.mem.eql(u8, current_migration.status.name, step.name);

            var stepBranches: std.ArrayList(BranchMigration) = .empty;

            for (branches.branches) |branch| {
                if (std.mem.eql(u8, step.name, branch.migration.name)) {
                    try stepBranches.append(allocator, branch);
                }
            }

            const migration = PlanMigration.init(
                allocator,
                step,
                try stepBranches.toOwnedSlice(allocator),
                ix,
                is_current_migration,
                false,
            );
            try migrations.append(allocator, migration);
        }

        return migrations.toOwnedSlice(allocator);
    }

    fn getStepBranches(step: PlanStep, allocator: std.mem.Allocator, branches: []Branches) []Branches {
        var stepBranches: std.ArrayList(Branch) = .empty;
        for (branches.branches) |branch| {
            if (step.name)
                try stepBranches.append(allocator, branch);
        }

        return try stepBranches.toOwnedSlice(allocator);
    }

    fn retrieveBranches(allocator: std.mem.Allocator) !Branches {
        return try Branches.init(allocator);
    }

    // This should return an optional
    pub fn getLastStep(self: Plan) PlanStep {
        return self.steps[self.steps.len - 1];
    }

    pub fn update(self: *Plan) !void {
        _ = self;
        // const res, const steps =
        //     try retrieveSteps(self.allocator, self.branch);

        // const oldSteps = self.steps;
        // const oldRes = self.res;

        // self.steps = steps;
        // self.res = res;

        // self.allocator.free(oldSteps);
        // self.allocator.free(oldRes);
    }

    pub fn deinit(self: *Plan) void {
        self.allocator.free(self.res);
        self.allocator.free(self.steps);
        self.branches.deinit();
        for (self.migrations) |plan_migration| {
            plan_migration.deinit();
        }
        self.allocator.free(self.migrations);
        self.current_migration.deinit();
    }
};

pub const Branches = struct {
    allocator: std.mem.Allocator,
    branchNames: []Branch,
    branches: []BranchMigration,
    res: []const u8,

    pub fn init(allocator: std.mem.Allocator) !Branches {
        const res, const branchNames =
            try retrieveBranches(allocator);

        const branches = try buildBranches(allocator, branchNames);

        return .{
            .allocator = allocator,
            .branchNames = branchNames,
            .branches = branches,
            .res = res,
        };
    }

    fn retrieveBranches(allocator: std.mem.Allocator) !struct { []const u8, []Branch } {
        const res = try child_process.run(allocator, &.{ "git", "branch", "--sort=-committerdate" });

        const branchNames = try parser.parseBranches(allocator, res);

        return .{
            res,
            branchNames,
        };
    }

    fn buildBranches(allocator: std.mem.Allocator, branchNames: []Branch) ![]BranchMigration {
        // var total_res: std.ArrayList([]const u8) = .empty;
        var branches: std.ArrayList(BranchMigration) = .empty;
        // TODO I also need to accumulate all steps, I think this is poorly implemented
        for (branchNames) |branch| {
            const res, const steps =
                try retrieveSteps(allocator, branch.name);
            const branch_migration = BranchMigration.init(allocator, branch, steps, res);
            // const last_step = steps[0];
            // const branch_migration = BranchMigration{
            //     .branch = branch,
            //     .migration = last_step,
            // };
            try branches.append(allocator, branch_migration);
        }

        return branches.toOwnedSlice(allocator);
    }

    pub fn update(self: *Branches) !void {
        const res, const branchNames =
            try retrieveBranches(self.allocator);

        const oldBranchNames = self.branchNames;
        const oldRes = self.res;

        self.branchNames = branchNames;
        self.res = res;

        self.allocator.free(oldBranchNames);
        self.allocator.free(oldRes);
    }

    pub fn deinit(self: *Branches) void {
        self.allocator.free(self.res);
        self.allocator.free(self.branchNames);
        for (self.branches) |branch| {
            branch.deinit();
        }
        self.allocator.free(self.branches);
        // self.branches.deinit(self.allocator);
    }
};

// pub fn sqitchPlan(allocator: std.mem.Allocator, branch: []const u8) !Plan {
//     var arg: ArrayList(u8) = .empty;
//     defer arg.deinit(allocator);

//     try arg.appendSlice(allocator, branch);
//     try arg.appendSlice(allocator, ":");
//     try arg.appendSlice(allocator, planLocation);

//     const command = sqitchPlanCommand(arg.items);

//     const res = try child_process.run(allocator, &command);

//     return try parser.parsePlan(allocator, res);
// }
//
fn retrieveSteps(allocator: std.mem.Allocator, branch: []const u8) !struct { []const u8, []PlanStep } {
    var command: ArrayList(u8) = .empty;
    defer command.deinit(allocator);

    try command.appendSlice(allocator, branch);
    try command.appendSlice(allocator, ":");
    try command.appendSlice(allocator, planLocation);

    const res = try child_process.run(allocator, &.{ "git", "show", command.items });

    const steps = try parser.parseSteps(allocator, res);

    var finalSteps: ArrayList(PlanStep) = .empty;
    var i = steps.len;
    while (i > 0) {
        i -= 1;
        try finalSteps.append(allocator, steps[i]);
    }

    allocator.free(steps);

    return .{ res, try finalSteps.toOwnedSlice(allocator) };
}

test {
    _ = parser;
}
