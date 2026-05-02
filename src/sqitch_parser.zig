const std = @import("std");
const mecha = @import("mecha");

pub const Plan = struct {
    steps: []const PlanStep,
};

// TODO it'd be nice to have something different than strings
pub const PlanStep = struct {
    deploy: []const u8,
    name: []const u8,
    planner: []const u8,
    date: []const u8,
};

pub const Status = struct {
    change: []const u8,
    name: []const u8,
    deployed: []const u8,
    by: []const u8,
};

const newLine = mecha.string("\n");

const space = mecha.string(" ");

const text =
    mecha.many(mecha.ascii.not(mecha.string("\n")), .{ .collect = false });

const line =
    mecha.combine(.{
        text,
        newLine,
    });

const comment = mecha.combine(.{
    mecha.string("#"),
    line,
});

const header = mecha.combine(.{
    mecha.many(comment, .{ .collect = false }),
    mecha.many(newLine, .{ .collect = false }),
});

fn fieldValue(label: []const u8) mecha.Parser([]const u8) {
    return mecha.combine(.{
        mecha.string(label).discard(),
        mecha.many(space, .{ .collect = false }).discard(),
        mecha.many(mecha.ascii.not(mecha.string("\n")), .{ .collect = false }),
        newLine.discard(),
    });
}

const planStep = mecha.combine(.{
    fieldValue("Deploy"),
    fieldValue("Name:"),
    fieldValue("Planner:"),
    fieldValue("Date:"),
    mecha.many(newLine, .{ .collect = false }).discard(),
    // NOTE: for some reason this fails with `many`. I hope sqitch doesn't allow multiline descriptions...
    line.discard(),
    mecha.many(newLine, .{ .collect = false }).discard(),
}).map(mecha.toStruct(PlanStep));

const plan = mecha.combine(.{
    header.discard(),
    mecha.many(planStep, .{ .collect = true }),
}).map(mecha.toStruct(Plan));

// NOTE: the status has a horrible format, I can only hope that the amount of rows is always the same.
const status = mecha.combine(.{
    line.discard(),
    line.discard(),
    fieldValue("# Change:"),
    fieldValue("# Name:"),
    fieldValue("# Deployed:"),
    fieldValue("# By:"),
}).map(mecha.toStruct(Status));

test "plan" {
    const testing = std.testing;
    const allocator = std.heap.page_allocator;

    // The new arena allocator takes an existing allocator and manages it.
    // Note also this syntax, that's equivalent to `const arena = std.heap.ArenaAllocator.init(allocator);`
    const arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();

    const content =
        \\# Project: sqitch
        \\# File:    migrations/sqitch.plan
        \\
        \\Deploy 6c8b039e8d145420aa1a7dd34beffe5bb1aa6191
        \\Name:      name0
        \\Planner:   foo <foo@foo>
        \\Date:      2024-09-11 11:17:10 +0200
        \\
        \\ Test description 1
        \\
        \\Deploy 7febaee36a19b28e529aa1aa9952978e87fc0271
        \\Name:      name1
        \\Planner:   bar <bar@bar>
        \\Date:      2024-09-25 16:31:06 +0200
        \\
        \\ Test description2
        \\
    ;

    const actual = (try plan.parse(allocator, content)).value.ok;

    try testing.expectEqualStrings("name0", actual.steps[0].name);
    try testing.expectEqualStrings("foo <foo@foo>", actual.steps[0].planner);
    try testing.expectEqualStrings("name1", actual.steps[1].name);
}

test "status" {
    const testing = std.testing;
    const allocator = std.heap.page_allocator;

    // The new arena allocator takes an existing allocator and manages it.
    // Note also this syntax, that's equivalent to `const arena = std.heap.ArenaAllocator.init(allocator);`
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
