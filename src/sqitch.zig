const std = @import("std");
const sqitch_parser = @import("sqitch_parser.zig");
const ArrayList = std.ArrayList;

// TODO I need two functions to get back the Plan and the Status
pub fn runSqitch() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const argv: [2][]const u8 = .{ "sqitch", "plan" };

    var child = std.process.Child.init(&argv, alloc);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();

    var output: ArrayList(u8) = .empty;
    defer output.deinit(alloc);

    try read_child_stdout(child.stdout.?, alloc, &output);

    const res = try sqitch_parser.parsePlan(alloc, output.items);

    std.debug.print("{any}\n\n", .{res});

    _ = try child.wait();
}

// TODO: I think I will need to collect things in an ArrayList
fn read_child_stdout(child_stdout_f: std.fs.File, alloc: std.mem.Allocator, output: *std.array_list.Aligned(u8, null)) !void {
    var reader_buf: [1024]u8 = undefined;
    var f_reader = child_stdout_f.reader(&reader_buf);
    var reader = &f_reader.interface;
    var chunk: [1024]u8 = undefined;
    while (true) {
        const len = try reader.readSliceShort(&chunk);
        if (len == 0) break;
        try output.appendSlice(alloc, chunk[0..len]);
    }
}

test {
    _ = sqitch_parser;
}
