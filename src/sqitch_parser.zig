const std = @import("std");
const mecha = @import("mecha");

pub const Plan = struct {
    steps: []const PlanStep,
};

// TODO it'd be nice to have something different than strings
pub const PlanStep = struct {
    name: []const u8,
    date: []const u8,
    planner: []const u8,
};

pub const Status = struct {
    change: []const u8,
    name: []const u8,
    deployed: []const u8,
    by: []const u8,
};

const newLine = mecha.string("\n");

const word =
    mecha.many(mecha.oneOf(.{
        mecha.ascii.alphanumeric,
        mecha.ascii.not(mecha.ascii.whitespace),
    }), .{ .collect = false });

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

fn fieldValue(label: []const u8) mecha.Parser([]const u8) {
    return mecha.combine(.{
        mecha.string(label).discard(),
        mecha.many(mecha.ascii.whitespace, .{ .collect = false }).discard(),
        mecha.many(mecha.ascii.not(mecha.string("\n")), .{ .collect = false }),
        newLine.discard(),
    });
}

const planStep = mecha.combine(.{
    word,
    mecha.ascii.whitespace.discard(),
    word,
    mecha.ascii.whitespace.discard(),
    word,
    mecha.ascii.whitespace.discard(),
    word.discard(),
    text.discard(),
}).map(mecha.toStruct(PlanStep));

const plan = mecha.combine(.{
    header.discard(),
    mecha.many(mecha.combine(.{
        planStep,
        newLine.opt().discard(),
    }), .{ .collect = true }),
}).map(mecha.toStruct(Plan));

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
}).map(mecha.toStruct(Status));

// Parses the sqitch.plan file
pub fn parsePlan(allocator: std.mem.Allocator, content: []const u8) !Plan {
    return (try plan.parse(allocator, content)).value.ok;
}

// Parses the output of `sqitch status`
pub fn parseStatus(allocator: std.mem.Allocator, content: []const u8) !Status {
    return (try status.parse(allocator, content)).value.ok;
}

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

test "planStep" {
    const testing = std.testing;
    const allocator = std.heap.page_allocator;

    const arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();

    const content = "migration1 2024-09-11T09:17:10Z foo <foo@foo> # Comment";

    const actual = (try planStep.parse(allocator, content)).value;

    try testing.expectEqualStrings("migration1", actual.ok.name);
    try testing.expectEqualStrings("foo", actual.ok.planner);
}

test "plan" {
    const testing = std.testing;
    const allocator = std.heap.page_allocator;

    // The new arena allocator takes an existing allocator and manages it.
    // Note also this syntax, that's equivalent to `const arena = std.heap.ArenaAllocator.init(allocator);`
    const arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();

    const content =
        \\%syntax-version=1.0.0
        \\%project=bluemoon
        \\%uri=https://github.com/livtours/bm-backend/
        \\
        \\migration1 2024-09-11T09:17:10Z foo <foo@foo> # Comment
        \\migration2 2024-09-25T14:31:06Z foo <foo@foo> # Comment 2
        \\migration3 2024-09-12T09:29:23Z foo <foo@foo> # Comment 3
        \\migration4 2024-10-08T14:28:55Z bar <bar@bar> # Comment 4
    ;

    const actual = (try plan.parse(allocator, content)).value.ok;

    try testing.expectEqualStrings("migration1", actual.steps[0].name);
    try testing.expectEqualStrings("2024-09-25T14:31:06Z", actual.steps[1].date);
    try testing.expectEqualStrings("foo", actual.steps[2].planner);
    try testing.expectEqualStrings("migration4", actual.steps[3].name);
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
