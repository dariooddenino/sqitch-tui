const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const flex = @import("flex.zig");
// const flex = vxfw;

pub const ConfirmModal = struct {
    show: bool = false,
    focused: bool = false,
    message: []const u8 = "",
    on_confirm: *const fn (?*anyopaque, *vxfw.EventContext) anyerror!void,
    on_cancel: *const fn (?*anyopaque, *vxfw.EventContext) anyerror!void,

    pub fn widget(self: *ConfirmModal) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = ConfirmModal.typeErasedEventHandler,
            .drawFn = ConfirmModal.typeErasedDrawFn,
        };
    }

    pub fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        const self: *ConfirmModal = @ptrCast(@alignCast(ptr));
        switch (event) {
            .focus_in => {
                self.focused = true;
                ctx.redraw = true;
            },
            else => {},
        }
    }

    pub fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *ConfirmModal = @ptrCast(@alignCast(ptr));

        // if (!self.show) return;

        const msg: vxfw.Text = .{ .text = self.message };

        var yes_btn: vxfw.Button = .{
            .label = "Yes (Y)",
            .userdata = self,
            .onClick = self.on_confirm,
        };

        var no_btn: vxfw.Button = .{
            .label = "No (N)",
            .userdata = self,
            .onClick = self.on_cancel,
        };

        var yes: vxfw.Padding = .{
            .child = yes_btn.widget(),
            .padding = .{
                .left = 5,
                .right = 10,
            },
        };

        var no: vxfw.Padding = .{
            .child = no_btn.widget(),
            .padding = .{
                .left = 10,
                .right = 5,
            },
        };

        // TODO this way the buttons take all the possible available space, how can I improve this?
        const buttons: flex.FlexRow = .{
            .children = &.{
                .{
                    .widget = no.widget(),
                    // .flex_shrink = 0,
                },
                .{
                    .widget = yes.widget(),
                    // .flex_shrink = 0,
                },
            },
        };

        const content: flex.FlexColumn = .{
            .children = &.{
                .{ .widget = msg.widget() },
                .{ .widget = buttons.widget(), .flex_shrink = 1 },
            },
        };

        const bordered: vxfw.Border = .{ .child = content.widget() };

        const centered: vxfw.Center = .{ .child = bordered.widget() };

        const centered_surface = try centered.widget().draw(ctx);

        const centered_child: vxfw.SubSurface = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = centered_surface,
        };

        const children = try ctx.arena.alloc(vxfw.SubSurface, 1);
        children[0] = centered_child;

        return vxfw.Surface.initWithChildren(ctx.arena, self.widget(), ctx.max.size(), children);
    }
};

// test ConfirmModal {
//     var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
//     defer arena.deinit();
//     vxfw.DrawContext.init(.unicode);

//     const ctx: vxfw.DrawContext = .{
//         .arena = arena.allocator(),
//         .min = .{},
//         .max = .{ .width = 16, .height = 16 },
//         .cell_size = .{ .width = 10, .height = 20 },
//     };

//     const callback = struct {
//         fn callback(ptr_: ?*anyopaque, ctx_: *vxfw.EventContext) anyerror!void {
//             _ = ptr_;
//             _ = ctx_;
//         }
//     }.callback;

//     var modal: ConfirmModal = .{
//         .message = "Test",
//         .on_confirm = callback,
//         .on_cancel = callback,
//     };

//     const surface = try modal.widget().draw(ctx);
//     try std.testing.expectEqual(16, surface.size.width);
// }
// test "refAllDecls" {
//     std.testing.refAllDecls(@This());
// }
