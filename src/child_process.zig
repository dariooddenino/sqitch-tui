const std = @import("std");
const ArrayList = std.ArrayList;

// TODO: Can I make the length of argv not fixed?
// git and sqitch use different numbers of commands, so I can't put 2 or 3 here :/
// TODO: I forgot everything about slices...
pub fn run(allocator: std.mem.Allocator, argv: []const []const u8) ![]const u8 {
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();

    var output: ArrayList(u8) = .empty;
    defer output.deinit(allocator);

    try read_child_stdout(child.stdout.?, allocator, &output);

    _ = try child.wait();

    return output.toOwnedSlice(allocator);
}
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
