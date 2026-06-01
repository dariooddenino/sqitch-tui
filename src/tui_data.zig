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

fn retrieveSqitchStatus(io: std.Io, allocator: std.mem.Allocator) !SqitchStatus {
    const res = try child_process.run(io, allocator, &sqitchSqitchStatusCommand);

    defer allocator.free(res);

    const status = try parser.parseSqitchStatus(allocator, res);

    return status;
}

fn retrieveChanges(io: std.Io, allocator: std.mem.Allocator, branch: []const u8) ![]SqitchChange {
    var command: ArrayList(u8) = .empty;
    defer command.deinit(allocator);

    try command.appendSlice(allocator, branch);
    try command.appendSlice(allocator, ":");
    try command.appendSlice(allocator, planLocation);

    const res = try child_process.run(io, allocator, &.{ "git", "show", command.items });
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

fn retrieveBranchNames(io: std.Io, allocator: std.mem.Allocator) ![]BranchName {
    const res = try child_process.run(io, allocator, &.{ "git", "branch", "--sort=-committerdate" });
    defer allocator.free(res);

    const branchNames = try parser.parseBranchNames(allocator, res);

    return branchNames;
}

pub const Status = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    status: SqitchStatus,

    pub fn init(io: std.Io, allocator: std.mem.Allocator) !Status {
        const status =
            try retrieveSqitchStatus(io, allocator);

        return .{
            .io = io,
            .allocator = allocator,
            .status = status,
        };
    }

    pub fn deinit(self: Status) void {
        self.status.deinit(self.allocator);
    }
};

pub const Branch = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    name: []const u8,
    changes: []SqitchChange,

    pub fn init(io: std.Io, allocator: std.mem.Allocator, branch_name: BranchName) !Branch {
        const changes = try retrieveChanges(io, allocator, branch_name.name);
        var name: ArrayList(u8) = .empty;
        try name.appendSlice(allocator, branch_name.name);
        return .{
            .io = io,
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
    io: std.Io,
    allocator: std.mem.Allocator,
    status: Status,
    head: Branch,
    branches: []Branch,

    pub fn init(io: std.Io, allocator: std.mem.Allocator) !TUIData {
        const status, const head, const branches = try retrieveData(io, allocator);

        return .{
            .io = io,
            .allocator = allocator,
            .status = status,
            .head = head,
            .branches = branches,
        };
    }

    fn getCurrentMigrationIndex(self: TUIData) usize {
        const current_migration_name = self.status.status.name;

        for (self.head.changes, 0..) |change, i| {
            if (std.mem.eql(u8, change.name, current_migration_name)) {
                return i;
            }
        }

        // TODO: again, questionable. I should handle error cases
        return 0;
    }

    pub fn logOnlyMigrate(self: TUIData, cursor: usize) !void {
        const current_index = self.getCurrentMigrationIndex();
        const target_migration = self.head.changes[cursor].name;

        // TODO: definitely cleanup here
        if (cursor > current_index) {
            // revert
            const command = sqitchRevertCommand(target_migration);
            const res = try child_process.run(self.io, self.allocator, &command);
            self.allocator.free(res);
        }

        if (cursor < current_index) {
            // deploy
            const command = sqitchDeployCommand(target_migration);

            const res = try child_process.run(self.io, self.allocator, &command);
            self.allocator.free(res);
        }

        // else noop
    }

    pub fn update(self: *TUIData) !void {
        self.head.deinit();
        self.status.deinit();
        for (self.branches) |branch| {
            branch.deinit();
        }
        self.allocator.free(self.branches);

        const status, const head, const branches = try retrieveData(self.allocator);

        self.status = status;
        self.head = head;
        self.branches = branches;
    }

    pub fn retrieveData(io: std.Io, allocator: std.mem.Allocator) !struct { Status, Branch, []Branch } {
        const status = try Status.init(io, allocator);
        const head = try Branch.init(io, allocator, .{ .name = "HEAD" });

        var branches: ArrayList(Branch) = .empty;
        const branch_names = try retrieveBranchNames(io, allocator);

        defer allocator.free(branch_names);

        for (branch_names) |branch_name| {
            const branch = try Branch.init(io, allocator, branch_name);
            try branches.append(allocator, branch);
            branch_name.deinit(allocator);
        }

        return .{ status, head, try branches.toOwnedSlice(allocator) };
    }

    pub fn deinit(self: TUIData) void {
        self.head.deinit();
        self.status.deinit();
        for (self.branches) |branch| {
            branch.deinit();
        }
        self.allocator.free(self.branches);
    }
};
