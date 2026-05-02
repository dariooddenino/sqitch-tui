const std = @import("std");
const mecha = @import("mecha");

pub const Plan = struct { steps: []const PlanStep };

pub const PlanStep = struct {
    deploy: []const u8,
    name: []const u8,
    planner: []const u8,
    date: []const u8,
};

const string = mecha.ascii.range('a', 'Z').many(.{ .collect = false }).asStr();

const colon = mecha.ascii.char(':').discard();

const comment = mecha.combine(.{
    mecha.string("#"),
    mecha.many(mecha.ascii.not(mecha.string("\n")), .{ .collect = false }),
    mecha.string("\n"),
});

const newLine = mecha.string("\n");

const header = mecha.combine(.{
    mecha.many(comment, .{ .collect = false }),
    mecha.many(newLine, .{ .collect = false }),
});

fn fieldValue(label: []const u8) mecha.Parser([]const u8) {
    return mecha.combine(.{
        mecha.string(label).discard(),
        mecha.many(mecha.string(" "), .{ .collect = false }).discard(),
        mecha.many(mecha.ascii.not(mecha.string("\n")), .{ .collect = false }),
        mecha.string("\n").discard(),
    });
}

const description =
    mecha.combine(.{
        mecha.many(mecha.ascii.not(mecha.string("\n")), .{ .collect = false }),
        mecha.string("\n"),
    });

const planStep = mecha.combine(.{
    fieldValue("Deploy"),
    fieldValue("Name:"),
    fieldValue("Planner:"),
    fieldValue("Date:"),
    mecha.many(newLine, .{ .collect = false }).discard(),
    // NOTE: for some reason this fails with `many`. I hope sqitch doesn't allow multiline descriptions...
    description.discard(),
    mecha.many(newLine, .{ .collect = false }).discard(),
}).map(mecha.toStruct(PlanStep));

const plan = mecha.combine(.{
    header.discard(),
    mecha.many(planStep, .{ .collect = true }),
}).map(mecha.toStruct(Plan));

test {
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
