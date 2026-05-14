//! Virtual list component for efficiently rendering large datasets.
//! Only renders items visible in the viewport.

// NOTE: I started this just to add some parameters to the existing component,
// but at a certain point I figured out that it was easier to just customize this by bypassing the render_fn
const std = @import("std");
const Writer = std.Io.Writer;
const zz = @import("zigzag");
const style_mod = zz.style;
const Color = zz.Color;
const keys = zz.input.keys;
const measure = zz.measure;
const external = @import("./external.zig");
const PlanMigration = external.PlanMigration;

pub fn VirtualList(comptime T: type) type {
    return struct {
        /// All items (not copied — references the original slice).
        items: []const T = &.{},
        /// Number of visible rows.
        viewport_height: u16 = 20,
        /// Current cursor position (absolute index).
        cursor: usize = 0,
        /// Scroll offset (first visible item index).
        offset: usize = 0,
        /// Selection set.
        selected: ?std.AutoHashMap(usize, void) = null,
        /// Multi-select mode.
        multi_select: bool = false,
        /// Focused state.
        focused: bool = true,
        /// Wrap cursor around list ends.
        wrap_around: bool = false,
        /// Text shown when list is empty.
        empty_text: []const u8 = "(empty)",
        /// Width for each row (0 = no padding).
        row_width: u16 = 0,
        theme_manager: *zz.ThemeManager,

        // Styling
        // cursor_style: style_mod.Style = blk: {
        //     var s = style_mod.Style{};
        //     s = s.bg(.blue);
        //     s = s.fg(.white);
        //     s = s.inline_style(true);
        //     break :blk s;
        // },
        // item_style: style_mod.Style = blk: {
        //     var s = style_mod.Style{};
        //     s = s.inline_style(true);
        //     break :blk s;
        // },
        // selected_style: style_mod.Style = blk: {
        //     var s = style_mod.Style{};
        //     s = s.fg(.green);
        //     s = s.inline_style(true);
        //     break :blk s;
        // },
        // scrollbar_style: style_mod.Style = blk: {
        //     var s = style_mod.Style{};
        //     s = s.fg(.gray(8));
        //     s = s.inline_style(true);
        //     break :blk s;
        // },
        /// Cursor prefix.
        cursor_symbol: []const u8 = "> ",
        /// Normal prefix.
        normal_symbol: []const u8 = "  ",
        /// Show scrollbar.
        show_scrollbar: bool = true,
        /// Show item count.
        show_count: bool = true,

        const Self = @This();

        pub fn setItems(self: *Self, items: []const T) void {
            self.items = items;
            if (self.cursor >= items.len and items.len > 0) {
                self.cursor = items.len - 1;
            }
            self.ensureVisible();
        }

        pub fn update(self: *Self, key: keys.KeyEvent) void {
            const total = self.items.len;
            if (total == 0) return;

            switch (key.key) {
                .up => {
                    if (self.cursor > 0) {
                        self.cursor -= 1;
                    } else if (self.wrap_around and total > 0) {
                        self.cursor = total - 1;
                    }
                    self.ensureVisible();
                },
                .down => {
                    if (self.cursor + 1 < total) {
                        self.cursor += 1;
                    } else if (self.wrap_around) {
                        self.cursor = 0;
                    }
                    self.ensureVisible();
                },
                .page_up => {
                    if (self.cursor >= self.viewport_height) {
                        self.cursor -= self.viewport_height;
                    } else {
                        self.cursor = 0;
                    }
                    self.ensureVisible();
                },
                .page_down => {
                    self.cursor += self.viewport_height;
                    if (self.cursor >= total) self.cursor = total - 1;
                    self.ensureVisible();
                },
                .home => {
                    self.cursor = 0;
                    self.ensureVisible();
                },
                .end => {
                    if (total > 0) self.cursor = total - 1;
                    self.ensureVisible();
                },
                .char => |c| {
                    if (c == ' ' and self.multi_select) {
                        self.toggleSelection(self.cursor);
                    }
                },
                .enter => {
                    self.toggleSelection(self.cursor);
                },
                else => {},
            }
        }

        fn toggleSelection(self: *Self, index: usize) void {
            _ = self;
            _ = index;
            // Selection is managed externally; this is a placeholder for signaling
        }

        fn ensureVisible(self: *Self) void {
            if (self.cursor < self.offset) {
                self.offset = self.cursor;
            }
            if (self.cursor >= self.offset + self.viewport_height) {
                self.offset = self.cursor - self.viewport_height + 1;
            }
        }

        pub fn view(self: *const Self, allocator: std.mem.Allocator, width: u16, _: u16) []const u8 {
            var result: Writer.Allocating = .init(allocator);
            const writer = &result.writer;
            const total = self.items.len;
            const vh: usize = self.viewport_height;

            if (total == 0) {
                writer.writeAll(self.empty_text) catch {};
                return result.toArrayList().items;
            }

            const theme = &self.theme_manager.current;
            const palette = &theme.palette;

            var scrollbar_style = zz.Style{};
            scrollbar_style = scrollbar_style.fg(palette.secondary);
            scrollbar_style = scrollbar_style.inline_style(true);

            const end = @min(self.offset + vh, total);

            var ellipse_style = zz.Style{};
            ellipse_style = ellipse_style.overflow(.ellipsis);
            ellipse_style = ellipse_style.width(width - 10);

            for (self.offset..end) |i| {
                if (i > self.offset) writer.writeByte('\n') catch {};

                // Scrollbar
                if (self.show_scrollbar and total > vh) {
                    const row = i - self.offset;
                    const thumb_start = (self.offset * vh) / total;
                    const thumb_size = @max(1, (vh * vh) / total);
                    const is_thumb = row >= thumb_start and row < thumb_start + thumb_size;
                    const sb_char: []const u8 = if (is_thumb) "\xe2\x96\x88" else "\xe2\x96\x91";
                    writer.writeByte(' ') catch {};
                    writer.writeAll(scrollbar_style.render(allocator, sb_char) catch sb_char) catch {};
                }

                // Get item text
                const item_text = self.renderItem(self.items[i], i, allocator);

                writer.writeAll(ellipse_style.render(allocator, item_text) catch item_text) catch {};
            }

            // Item count
            if (self.show_count) {
                writer.writeByte('\n') catch {};
                const count_str = std.fmt.allocPrint(allocator, " {d}/{d}", .{ self.cursor + 1, total }) catch "";
                var cs = style_mod.Style{};
                cs = cs.fg(palette.subtle);
                cs = cs.inline_style(true);
                writer.writeAll(cs.render(allocator, count_str) catch count_str) catch {};
            }

            return result.toArrayList().items;
        }

        fn renderItem(self: *const Self, item: PlanMigration, i: usize, allocator: std.mem.Allocator) []const u8 {
            const theme = &self.theme_manager.current;
            const palette = &theme.palette;

            var list_content: Writer.Allocating = .init(allocator);
            const writer = &list_content.writer;

            const is_cursor = (i == self.cursor and self.focused);
            const is_selected = false; // Could check selection map

            var cursor_style = zz.Style{};
            cursor_style = cursor_style.bg(palette.overlay);
            cursor_style = cursor_style.fg(palette.secondary);
            cursor_style = cursor_style.inline_style(true);

            var selected_style = zz.Style{};
            selected_style = selected_style.fg(palette.highlight);
            selected_style = selected_style.inline_style(true);

            var plain_style = zz.Style{};
            plain_style = plain_style.inline_style(true);

            const prefix = if (is_cursor) self.cursor_symbol else self.normal_symbol;
            const item_style = if (is_cursor) cursor_style else if (is_selected) selected_style else plain_style;

            const styled_cursor = item_style.render(allocator, prefix) catch prefix;
            writer.writeAll(styled_cursor) catch {};

            // const line = std.fmt.allocPrint(self.allocator, "{s}{s}", .{ prefix, item_text }) catch item_text;
            var current_style = item_style.bold(true);
            current_style = current_style.fg(palette.primary);

            if (item.is_current_migration) {
                const styled = current_style.render(allocator, "* ") catch "* ";
                writer.writeAll(styled) catch {};
            } else {
                const styled = item_style.render(allocator, "  ") catch "  ";
                writer.writeAll(styled) catch {};
            }

            // TODO this has to be updated to deal with the selection
            if (item.is_current_migration) {
                const styled = current_style.render(allocator, item.step.name) catch item.step.name;
                writer.writeAll(styled) catch {};
                // } else if (i == self.steps.cursor) {
                //     var selected_style = zz.Style{};
                //     selected_style = selected_style.bold(true);
                //     selected_style = selected_style.fg(zz.Color.magenta);
                //     selected_style = selected_style.inline_style(true);
                //     const styled = selected_style.render(allocator, item.title) catch item.title;
                //     writer.writeAll(styled) catch {};
            } else {
                const styled = item_style.render(allocator, item.step.name) catch item.step.name;
                writer.writeAll(styled) catch {};
            }

            var help_style = zz.Style{};
            help_style = help_style.fg(palette.subtle);
            // TODO: I really need to check this
            help_style = help_style.inline_style(true);
            var ix: usize = 0;
            for (item.branches) |branchMigration| {
                const branchName = branchMigration.branch.name;
                // if (ix < 4 and std.mem.eql(u8, branchLastStep.name, item.name)) {
                if (ix < 40) {
                    ix += 1;
                    writer.writeAll(" ") catch {};
                    const styled = help_style.render(allocator, branchName) catch branchName;
                    writer.writeAll(styled) catch {};
                }
            }

            return list_content.toOwnedSlice() catch "";
        }
    };
}
