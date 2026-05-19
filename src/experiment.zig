const std = @import("std");
const parser = @import("parser.zig");
const child_process = @import("./child_process.zig");
const ArrayList = std.ArrayList;
const SqitchStatus = parser.SqitchStatus;
const BranchName = parser.BranchName;
const SqitchChange = parser.SqitchChange;

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

fn retrieveSqitchStatus(allocator: std.mem.Allocator) !SqitchStatus {
    const res = try child_process.run(allocator, &sqitchSqitchStatusCommand);

    defer allocator.free(res);

    const status = try parser.parseSqitchStatus(allocator, res);

    return status;
}

fn retrieveChanges(allocator: std.mem.Allocator, branch: []const u8) ![]SqitchChange {
    var command: ArrayList(u8) = .empty;
    defer command.deinit(allocator);

    try command.appendSlice(allocator, branch);
    try command.appendSlice(allocator, ":");
    try command.appendSlice(allocator, planLocation);

    const res = try child_process.run(allocator, &.{ "git", "show", command.items });
    defer allocator.free(res);

    const steps = try parser.parseSqitchChanges(allocator, res);

    var finalSteps: ArrayList(SqitchChange) = .empty;
    var i = steps.len;
    while (i > 0) {
        i -= 1;
        try finalSteps.append(allocator, steps[i]);
    }

    allocator.free(steps);

    return try finalSteps.toOwnedSlice(allocator);
}

fn retrieveBranchNames(allocator: std.mem.Allocator) ![]BranchName {
    const res = try child_process.run(allocator, &.{ "git", "branch", "--sort=-committerdate" });
    defer allocator.free(res);

    const branchNames = try parser.parseBranchNames(allocator, res);

    return branchNames;
}

pub const Status = struct {
    allocator: std.mem.Allocator,
    status: SqitchStatus,

    pub fn init(allocator: std.mem.Allocator) !Status {
        const status =
            try retrieveSqitchStatus(allocator);

        // TODO this fails
        std.debug.print("status in: {s}\n\n", .{status.name});

        return .{
            .allocator = allocator,
            .status = status,
        };
    }

    pub fn deinit(self: Status) void {
        // self.status.deinit(self.allocator);
        _ = self;
    }
};

pub const Branch = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    changes: []SqitchChange,

    pub fn init(allocator: std.mem.Allocator, branch_name: BranchName) !Branch {
        const changes = try retrieveChanges(allocator, branch_name.name);
        var name: ArrayList(u8) = .empty;
        try name.appendSlice(allocator, branch_name.name);
        return .{
            .allocator = allocator,
            .name = try name.toOwnedSlice(allocator),
            .changes = changes,
        };
    }

    pub fn deinit(self: Branch) void {
        for (self.changes) |change| {
            change.deinit(self.allocator);
        }
        self.allocator.free(self.changes);
        self.allocator.free(self.name);
    }
};

pub const TUIData = struct {
    allocator: std.mem.Allocator,
    status: Status,
    head: Branch,
    branches: []Branch,

    pub fn init(allocator: std.mem.Allocator) !TUIData {
        const status = try Status.init(allocator);
        const head = try Branch.init(allocator, .{ .name = "HEAD" });

        var branches: ArrayList(Branch) = .empty;
        // const branch_names = try retrieveBranchNames(allocator);

        // defer for (branch_names) |branch_name| {
        //     branch_name.deinit(allocator);
        // };
        // defer allocator.free(branch_names);
        // _ = branch_names;
        // const branch_names: [1]BranchName = .{.{ .name = "HEAD" }};

        // for (branch_names) |branch_name| {
        //     const branch = try Branch.init(allocator, branch_name);
        //     try branches.append(allocator, branch);
        //     branch_name.deinit(allocator);
        // }

        // std.debug.print("{s}\n", .{status.status.name});

        return .{
            .allocator = allocator,
            .status = status,
            .head = head,
            .branches = try branches.toOwnedSlice(allocator),
        };
    }

    pub fn update(self: *TUIData) !void {
        const status = try Status.init(self.allocator);
        const head = try Branch.init(self.allocator, .{ .name = "HEAD" });

        self.head.deinit();
        self.status = status;
        self.head = head;
    }

    pub fn deinit(self: TUIData) void {
        _ = self;
        // self.head.deinit();
        // self.status.deinit();
        // for (self.branches) |branch| {
        //     branch.deinit();
        // }
        // self.allocator.free(self.branches);
    }
};
