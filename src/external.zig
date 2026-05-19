const std = @import("std");
const parser = @import("parser.zig");
const child_process = @import("./child_process.zig");
const ArrayList = std.ArrayList;
const SqitchChange = parser.SqitchChange;
const SqitchStatus = parser.SqitchStatus;
const BranchName = parser.BranchName;

fn sqitchPlanCommand(arg: []const u8) [3][]const u8 {
    return .{ "git", "show", arg };
}
const sqitchSqitchStatusCommand: [2][]const u8 =
    .{ "sqitch", "status" };

pub fn sqitchRevertCommand(migration: []const u8) [6][]const u8 {
    return .{ "sqitch", "revert", "-y", "--log-only", "--to", migration };
}

pub fn sqitchDeployCommand(migration: []const u8) [5][]const u8 {
    return .{ "sqitch", "deploy", "--log-only", "--to", migration };
}

const planLocation = "migrations/sqitch.plan";

// TODO all these structs share functionalities, maybe I can abstract this somehow?

pub const CurrentMigration = struct {
    allocator: std.mem.Allocator,
    status: *SqitchStatus,
    res: []const u8,

    pub fn init(allocator: std.mem.Allocator) !CurrentMigration {
        const res, const status =
            try retrieveSqitchStatus(allocator);

        const statusPointer = try allocator.create(SqitchStatus);

        statusPointer.* = status;
        return .{
            .allocator = allocator,
            .status = statusPointer,
            .res = res,
        };
    }

    fn retrieveSqitchStatus(allocator: std.mem.Allocator) !struct { []const u8, SqitchStatus } {
        const res = try child_process.run(allocator, &sqitchSqitchStatusCommand);

        const status = try parser.parseSqitchStatus(allocator, res);

        return .{ res, status };
    }

    pub fn update(self: *CurrentMigration) !void {
        const res, const status =
            try retrieveSqitchStatus(self.allocator);

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
    step: SqitchChange,
    branches: []BranchNameMigration,
    index: usize,
    is_current_migration: bool,
    is_verified: ?bool,

    fn init(allocator: std.mem.Allocator, step: SqitchChange, branches: []BranchNameMigration, index: usize, is_current_migration: bool, is_verified: ?bool) PlanMigration {
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

pub const BranchNameMigration = struct {
    allocator: std.mem.Allocator,
    branch: BranchName,
    migration: SqitchChange,
    res: []const u8,
    steps: []SqitchChange,

    fn init(allocator: std.mem.Allocator, branch: BranchName, steps: []SqitchChange, res: []const u8) BranchNameMigration {
        return BranchNameMigration{
            .allocator = allocator,
            .branch = branch,
            .migration = steps[0],
            .res = res,
            .steps = steps,
        };
    }

    fn deinit(self: BranchNameMigration) void {
        self.allocator.free(self.res);
        self.allocator.free(self.steps);
    }
};

pub const Plan = struct {
    allocator: std.mem.Allocator,
    branches: BranchNames,
    steps: []SqitchChange, // TODO might want to remove this?
    migrations: []PlanMigration,
    current_migration: CurrentMigration,
    res: []const u8,

    fn retrieveData(allocator: std.mem.Allocator) !struct {
        []const u8,
        []SqitchChange,
        BranchNames,
        []PlanMigration,
        CurrentMigration,
    } {
        const res, const steps =
            try retrieveSteps(allocator, "HEAD");

        const branches = try BranchNames.init(allocator);

        const current_migration = try getCurrentMigration(allocator);

        const migrations = try buildMigrations(allocator, steps, branches, current_migration);

        return .{ res, steps, branches, migrations, current_migration };
    }

    // TODO: this can fail with an empty list
    pub fn getCurrentPlanMigration(self: *Plan) ?PlanMigration {
        var i: usize = 0;
        while (i < self.migrations.len) : (i += 1) {
            if (self.migrations[i].is_current_migration) {
                return self.migrations[i];
            }
        }

        return null;
    }

    pub fn init(allocator: std.mem.Allocator) !Plan {
        const res, const steps, const branches, const migrations, const current_migration =
            try retrieveData(allocator);

        return .{
            .allocator = allocator,
            .steps = steps,
            .res = res,
            .branches = branches,
            .migrations = migrations,
            .current_migration = current_migration,
        };
    }

    pub fn update(self: *Plan) !void {
        const res, const steps, const branches, const migrations, const current_migration =
            try retrieveData(self.allocator);

        // TODO: I need to figure out how to clear the old values memory

        self.allocator.free(self.res);
        self.res = res;
        self.allocator.free(self.steps);
        self.steps = steps;
        self.branches.deinit();
        self.branches = branches;
        for (self.migrations) |migration| {
            migration.deinit();
        }
        self.allocator.free(self.migrations);
        self.migrations = migrations;
        self.current_migration.deinit();
        self.current_migration = current_migration;
    }

    fn getCurrentMigration(allocator: std.mem.Allocator) !CurrentMigration {
        return try CurrentMigration.init(allocator);
    }

    fn buildMigrations(allocator: std.mem.Allocator, steps: []SqitchChange, branches: BranchNames, current_migration: CurrentMigration) ![]PlanMigration {
        var migrations: std.ArrayList(PlanMigration) = .empty;
        for (steps, 0..) |step, ix| {
            const is_current_migration =
                std.mem.eql(u8, current_migration.status.name, step.name);

            var stepBranchNames: std.ArrayList(BranchNameMigration) = .empty;

            for (branches.branches) |branch| {
                if (std.mem.eql(u8, step.name, branch.migration.name)) {
                    try stepBranchNames.append(allocator, branch);
                }
            }

            const migration = PlanMigration.init(
                allocator,
                step,
                try stepBranchNames.toOwnedSlice(allocator),
                ix,
                is_current_migration,
                false,
            );
            try migrations.append(allocator, migration);
        }

        return migrations.toOwnedSlice(allocator);
    }

    fn getStepBranchNames(step: SqitchChange, allocator: std.mem.Allocator, branches: []BranchNames) []BranchNames {
        var stepBranchNames: std.ArrayList(BranchName) = .empty;
        for (branches.branches) |branch| {
            if (step.name)
                try stepBranchNames.append(allocator, branch);
        }

        return try stepBranchNames.toOwnedSlice(allocator);
    }

    fn retrieveBranchNames(allocator: std.mem.Allocator) !BranchNames {
        return try BranchNames.init(allocator);
    }

    // This should return an optional
    pub fn getLastStep(self: Plan) SqitchChange {
        return self.steps[self.steps.len - 1];
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

pub const BranchNames = struct {
    allocator: std.mem.Allocator,
    branchNames: []BranchName,
    branches: []BranchNameMigration,
    res: []const u8,

    pub fn init(allocator: std.mem.Allocator) !BranchNames {
        const res, const branchNames =
            try retrieveBranchNames(allocator);

        const branches = try buildBranchNames(allocator, branchNames);

        return .{
            .allocator = allocator,
            .branchNames = branchNames,
            .branches = branches,
            .res = res,
        };
    }

    fn retrieveBranchNames(allocator: std.mem.Allocator) !struct { []const u8, []BranchName } {
        const res = try child_process.run(allocator, &.{ "git", "branch", "--sort=-committerdate" });

        const branchNames = try parser.parseBranchNames(allocator, res);

        return .{
            res,
            branchNames,
        };
    }

    fn buildBranchNames(allocator: std.mem.Allocator, branchNames: []BranchName) ![]BranchNameMigration {
        // var total_res: std.ArrayList([]const u8) = .empty;
        var branches: std.ArrayList(BranchNameMigration) = .empty;
        // TODO I also need to accumulate all steps, I think this is poorly implemented
        for (branchNames) |branch| {
            const res, const steps =
                try retrieveSteps(allocator, branch.name);
            const branch_migration = BranchNameMigration.init(allocator, branch, steps, res);
            // const last_step = steps[0];
            // const branch_migration = BranchNameMigration{
            //     .branch = branch,
            //     .migration = last_step,
            // };
            try branches.append(allocator, branch_migration);
        }

        return branches.toOwnedSlice(allocator);
    }

    pub fn update(self: *BranchNames) !void {
        const res, const branchNames =
            try retrieveBranchNames(self.allocator);

        const oldBranchNameNames = self.branchNames;
        const oldRes = self.res;

        self.branchNames = branchNames;
        self.res = res;

        self.allocator.free(oldBranchNameNames);
        self.allocator.free(oldRes);
    }

    pub fn deinit(self: *BranchNames) void {
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
fn retrieveSteps(allocator: std.mem.Allocator, branch: []const u8) !struct { []const u8, []SqitchChange } {
    var command: ArrayList(u8) = .empty;
    defer command.deinit(allocator);

    try command.appendSlice(allocator, branch);
    try command.appendSlice(allocator, ":");
    try command.appendSlice(allocator, planLocation);

    const res = try child_process.run(allocator, &.{ "git", "show", command.items });

    const steps = try parser.parseSqitchChanges(allocator, res);

    var finalSteps: ArrayList(SqitchChange) = .empty;
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
