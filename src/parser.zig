const std = @import("std");
const mecha = @import("mecha");

// TODO it'd be nice to have something different than strings
pub const SqitchChange = struct {
    name: []const u8,
    date: []const u8,
    planner: []const u8,

    pub fn deinit(self: SqitchChange, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.date);
        allocator.free(self.planner);
    }
};

pub const SqitchStatus = struct {
    change: []const u8,
    name: []const u8,
    deployed: []const u8,
    by: []const u8,

    pub fn deinit(self: SqitchStatus, allocator: std.mem.Allocator) void {
        allocator.free(self.change);
        allocator.free(self.name);
        allocator.free(self.deployed);
        allocator.free(self.by);
    }
};

pub const BranchName = struct {
    name: []const u8,

    pub fn deinit(self: BranchName, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

// Parses the output of `sqitch status`
pub fn parseSqitchStatus(allocator: std.mem.Allocator, content: []const u8) !SqitchStatus {
    return (try status.parse(allocator, content)).value.ok;
}

// Parses the sqitch plan file
pub fn parseSqitchChanges(allocator: std.mem.Allocator, content: []const u8) ![]SqitchChange {
    return (try changes.parse(allocator, content)).value.ok;
}

// Parses the current git branches
pub fn parseBranchNames(allocator: std.mem.Allocator, content: []const u8) ![]BranchName {
    return (try branches.parse(allocator, content)).value.ok;
}

const newLine = mecha.string("\n");

const word =
    mecha.many(mecha.oneOf(.{
        mecha.ascii.alphanumeric,
        mecha.ascii.not(mecha.ascii.whitespace),
    }), .{ .collect = true });

const text =
    mecha.many(mecha.ascii.not(mecha.string("\n")), .{ .collect = false });

const comment = mecha.combine(.{
    mecha.string("%"),
    text,
});

const header = mecha.combine(.{
    mecha.many(mecha.combine(.{
        comment,
        newLine.discard(),
    }), .{ .collect = false }),
    mecha.many(newLine, .{ .collect = false }),
});

fn fieldValue(label: []const u8) mecha.Parser([]u8) {
    return mecha.combine(.{
        mecha.string(label).discard(),
        mecha.many(mecha.ascii.whitespace, .{ .collect = false }).discard(),
        mecha.many(mecha.ascii.not(mecha.string("\n")), .{ .collect = true }),
        newLine.discard(),
    });
}

const change = mecha.combine(.{
    word,
    mecha.ascii.whitespace.discard(),
    word,
    mecha.ascii.whitespace.discard(),
    word,
    mecha.ascii.whitespace.discard(),
    text.discard(),
}).map(mecha.toStruct(SqitchChange));

const changes = mecha.combine(.{
    header.discard(),
    mecha.many(mecha.combine(.{
        change,
        newLine.opt().discard(),
    }), .{ .collect = true }),
});

// NOTE: the status has a horrible format, I can only hope that the amount of rows is always the same.
const status = mecha.combine(.{
    text.discard(),
    newLine.discard(),
    text.discard(),
    newLine.discard(),
    fieldValue("# Change:"),
    fieldValue("# Name:"),
    fieldValue("# Deployed:"),
    fieldValue("# By:"),
}).map(mecha.toStruct(SqitchStatus));

// Could be improved!
const current_branch_indicator = mecha.combine(.{
    mecha.ascii.whitespace.opt(),
    mecha.string("*").opt(),
    mecha.ascii.whitespace.opt(),
});

const no_branch = mecha.combine(.{
    current_branch_indicator.opt(),
    mecha.string("(no branch)"),
    newLine,
});

const branch = mecha.combine(.{
    current_branch_indicator.opt().discard(),
    word,
}).map(mecha.toStruct(BranchName));

const branches = mecha.combine(.{
    // no_branch.opt().discard(),
    text.opt().discard(),
    newLine.opt().discard(),
    mecha.many(mecha.combine(.{
        branch,
        newLine.discard(), // TODO optional new line is not working for reasons
    }), .{ .collect = true }),
});

test "word" {
    const testing = std.testing;
    const allocator = std.heap.page_allocator;

    const arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();

    const content = "migration1_123 2024";
    const content2 = "2024-09-11T09:17:10Z";
    const content3 = "<foo@foo>";

    const actual = (try word.parse(allocator, content)).value;
    const actual2 = (try word.parse(allocator, content2)).value;
    const actual3 = (try word.parse(allocator, content3)).value;

    try testing.expectEqualStrings("migration1_123", actual.ok);
    try testing.expectEqualStrings(content2, actual2.ok);
    try testing.expectEqualStrings(content3, actual3.ok);
}

test "change" {
    const testing = std.testing;
    const allocator = std.heap.page_allocator;

    const arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();

    const content = "migration1 2024-09-11T09:17:10Z foo <foo@foo> # Comment";

    const actual = (try change.parse(allocator, content)).value;

    try testing.expectEqualStrings("migration1", actual.ok.name);
    try testing.expectEqualStrings("foo", actual.ok.planner);
}

test "branches" {
    const testing = std.testing;
    const allocator = std.heap.page_allocator;

    const arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();

    const content =
        \\* (no branch)
        \\foo123
        \\123-bar
        \\
    ;

    const actual = (try branches.parse(allocator, content)).value.ok;

    try testing.expectEqual(2, actual.len);
}

test "status" {
    const testing = std.testing;
    const allocator = std.heap.page_allocator;

    const arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();

    const content =
        \\# On database sqitch
        \\# Project:  sqitch
        \\# Change:   66884058aaa662582f9795f90191c5b9909975b0
        \\# Name:     bar
        \\# Deployed: 2026-04-29 14:11:03 +0200
        \\# By:       foo <foo@foo>
        \\#
        \\Nothing to deploy (up-to-date)
    ;

    const actual = (try status.parse(allocator, content)).value.ok;

    try testing.expectEqualStrings("bar", actual.name);
    try testing.expectEqualStrings("foo <foo@foo>", actual.by);
}
