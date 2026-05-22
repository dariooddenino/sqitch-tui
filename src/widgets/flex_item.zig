const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

pub const FlexItem = struct {
    widget: vxfw.Widget,
    flex_grow: u8 = 1,
    flex_shrink: u8 = 0,
};
