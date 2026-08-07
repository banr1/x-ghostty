//! This is the public API of the ghostty-vt Zig module.
//!
//! WARNING: The API is not guaranteed to be stable.
//!
//! The functionality is extremely stable, since it is extracted
//! directly from XGhostty which has been used in real world scenarios
//! by thousands of users for years. However, the API itself (functions,
//! types, etc.) may change without warning. We're working on stabilizing
//! this in the future.
const lib = @This();

const std = @import("std");
const builtin = @import("builtin");

// The public API below reproduces a lot of terminal/main.zig but
// is separate because (1) we need our root file to be in `src/`
// so we can access other directories and (2) we may want to withhold
// parts of `terminal` that are not ready for public consumption
// or are too XGhostty-internal.
const terminal = @import("terminal/main.zig");

/// System interface for the terminal package.
///
/// This module provides runtime-swappable function pointers for operations
/// that depend on external implementations. Embedders can use this to
/// provide or override default behaviors. These must be set at startup
/// before any terminal functionality is used.
///
/// This lets libghostty-vt have no runtime dependencies on external
/// libraries, while still allowing rich functionality that may require
/// external libraries (e.g. image decoding or regular expresssions).
///
/// Setting these will enable various features of the terminal package.
/// For example, setting a PNG decoder will enable support for PNG images in
/// the Kitty Graphics Protocol.
///
/// Additional functionality will be added here over time as needed.
pub const sys = terminal.sys;

pub const apc = terminal.apc;
pub const dcs = terminal.dcs;
pub const osc = terminal.osc;
pub const point = terminal.point;
pub const color = terminal.color;
pub const device_status = terminal.device_status;
pub const formatter = terminal.formatter;
pub const highlight = terminal.highlight;
pub const kitty = terminal.kitty;
pub const modes = terminal.modes;
pub const page = terminal.page;
pub const parse_table = terminal.parse_table;
pub const search = terminal.search;
pub const sgr = terminal.sgr;
pub const size = terminal.size;
pub const x11_color = terminal.x11_color;

pub const Charset = terminal.Charset;
pub const CharsetSlot = terminal.CharsetSlot;
pub const CharsetActiveSlot = terminal.CharsetActiveSlot;
pub const Cell = page.Cell;
pub const Coordinate = point.Coordinate;
pub const CSI = Parser.Action.CSI;
pub const DCS = Parser.Action.DCS;
pub const MouseShape = terminal.MouseShape;
pub const Page = page.Page;
pub const PageList = terminal.PageList;
pub const Parser = terminal.Parser;
pub const Pin = PageList.Pin;
pub const Point = point.Point;
pub const RenderState = terminal.RenderState;
pub const Screen = terminal.Screen;
pub const ScreenSet = terminal.ScreenSet;
pub const Selection = terminal.Selection;
pub const size_report = terminal.size_report;
pub const SizeReportStyle = terminal.SizeReportStyle;
pub const StringMap = terminal.StringMap;
pub const Style = terminal.Style;
pub const Terminal = terminal.Terminal;
pub const TerminalStream = terminal.TerminalStream;
pub const Stream = terminal.Stream;
pub const StreamAction = terminal.StreamAction;
pub const Cursor = Screen.Cursor;
pub const CursorStyle = Screen.CursorStyle;
pub const CursorStyleReq = terminal.CursorStyle;
pub const DeviceAttributeReq = terminal.DeviceAttributeReq;
pub const Mode = modes.Mode;
pub const ModePacked = modes.ModePacked;
pub const ModifyKeyFormat = terminal.ModifyKeyFormat;
pub const ProtectedMode = terminal.ProtectedMode;
pub const StatusLineType = terminal.StatusLineType;
pub const StatusDisplay = terminal.StatusDisplay;
pub const EraseDisplay = terminal.EraseDisplay;
pub const EraseLine = terminal.EraseLine;
pub const TabClear = terminal.TabClear;
pub const Attribute = terminal.Attribute;

/// Terminal-specific input encoding is also part of libghostty-vt.
pub const input = struct {
    // We have to be careful to only import targeted files within
    // the input package because the full package brings in too many
    // other dependencies.
    const focus = terminal.focus;
    const paste = @import("input/paste.zig");
    const key = @import("input/key.zig");
    const key_encode = @import("input/key_encode.zig");
    const mouse_encode = @import("input/mouse_encode.zig");

    // Focus-related APIs
    pub const max_focus_encode_size = focus.max_encode_size;
    pub const FocusEvent = focus.Event;
    pub const encodeFocus = focus.encode;

    // Paste-related APIs
    pub const PasteError = paste.Error;
    pub const PasteOptions = paste.Options;
    pub const isSafePaste = paste.isSafe;
    pub const encodePaste = paste.encode;

    // Key encoding
    pub const Key = key.Key;
    pub const KeyAction = key.Action;
    pub const KeyEvent = key.KeyEvent;
    pub const KeyMods = key.Mods;
    pub const KeyEncodeOptions = key_encode.Options;
    pub const encodeKey = key_encode.encode;

    // Mouse encoding
    pub const MouseAction = @import("input/mouse.zig").Action;
    pub const MouseButton = @import("input/mouse.zig").Button;
    pub const MouseEncodeOptions = mouse_encode.Options;
    pub const MouseEncodeEvent = mouse_encode.Event;
    pub const encodeMouse = mouse_encode.encode;
};

comptime {
    // If we're building the C library (vs. the Zig module) then
    // we want to reference the C API so that it gets exported.
    if (@import("root") == lib) {
        const c = terminal.c_api;
        @export(&c.key_event_new, .{ .name = "xghostty_key_event_new" });
        @export(&c.key_event_free, .{ .name = "xghostty_key_event_free" });
        @export(&c.key_event_set_action, .{ .name = "xghostty_key_event_set_action" });
        @export(&c.key_event_get_action, .{ .name = "xghostty_key_event_get_action" });
        @export(&c.key_event_set_key, .{ .name = "xghostty_key_event_set_key" });
        @export(&c.key_event_get_key, .{ .name = "xghostty_key_event_get_key" });
        @export(&c.key_event_set_mods, .{ .name = "xghostty_key_event_set_mods" });
        @export(&c.key_event_get_mods, .{ .name = "xghostty_key_event_get_mods" });
        @export(&c.key_event_set_consumed_mods, .{ .name = "xghostty_key_event_set_consumed_mods" });
        @export(&c.key_event_get_consumed_mods, .{ .name = "xghostty_key_event_get_consumed_mods" });
        @export(&c.key_event_set_composing, .{ .name = "xghostty_key_event_set_composing" });
        @export(&c.key_event_get_composing, .{ .name = "xghostty_key_event_get_composing" });
        @export(&c.key_event_set_utf8, .{ .name = "xghostty_key_event_set_utf8" });
        @export(&c.key_event_get_utf8, .{ .name = "xghostty_key_event_get_utf8" });
        @export(&c.key_event_set_unshifted_codepoint, .{ .name = "xghostty_key_event_set_unshifted_codepoint" });
        @export(&c.key_event_get_unshifted_codepoint, .{ .name = "xghostty_key_event_get_unshifted_codepoint" });
        @export(&c.key_encoder_new, .{ .name = "xghostty_key_encoder_new" });
        @export(&c.key_encoder_free, .{ .name = "xghostty_key_encoder_free" });
        @export(&c.key_encoder_setopt, .{ .name = "xghostty_key_encoder_setopt" });
        @export(&c.key_encoder_setopt_from_terminal, .{ .name = "xghostty_key_encoder_setopt_from_terminal" });
        @export(&c.key_encoder_encode, .{ .name = "xghostty_key_encoder_encode" });
        @export(&c.mouse_event_new, .{ .name = "xghostty_mouse_event_new" });
        @export(&c.mouse_event_free, .{ .name = "xghostty_mouse_event_free" });
        @export(&c.mouse_event_set_action, .{ .name = "xghostty_mouse_event_set_action" });
        @export(&c.mouse_event_get_action, .{ .name = "xghostty_mouse_event_get_action" });
        @export(&c.mouse_event_set_button, .{ .name = "xghostty_mouse_event_set_button" });
        @export(&c.mouse_event_clear_button, .{ .name = "xghostty_mouse_event_clear_button" });
        @export(&c.mouse_event_get_button, .{ .name = "xghostty_mouse_event_get_button" });
        @export(&c.mouse_event_set_mods, .{ .name = "xghostty_mouse_event_set_mods" });
        @export(&c.mouse_event_get_mods, .{ .name = "xghostty_mouse_event_get_mods" });
        @export(&c.mouse_event_set_position, .{ .name = "xghostty_mouse_event_set_position" });
        @export(&c.mouse_event_get_position, .{ .name = "xghostty_mouse_event_get_position" });
        @export(&c.mouse_encoder_new, .{ .name = "xghostty_mouse_encoder_new" });
        @export(&c.mouse_encoder_free, .{ .name = "xghostty_mouse_encoder_free" });
        @export(&c.mouse_encoder_setopt, .{ .name = "xghostty_mouse_encoder_setopt" });
        @export(&c.mouse_encoder_setopt_from_terminal, .{ .name = "xghostty_mouse_encoder_setopt_from_terminal" });
        @export(&c.mouse_encoder_reset, .{ .name = "xghostty_mouse_encoder_reset" });
        @export(&c.mouse_encoder_encode, .{ .name = "xghostty_mouse_encoder_encode" });
        @export(&c.osc_new, .{ .name = "xghostty_osc_new" });
        @export(&c.osc_free, .{ .name = "xghostty_osc_free" });
        @export(&c.osc_next, .{ .name = "xghostty_osc_next" });
        @export(&c.osc_reset, .{ .name = "xghostty_osc_reset" });
        @export(&c.osc_end, .{ .name = "xghostty_osc_end" });
        @export(&c.osc_command_type, .{ .name = "xghostty_osc_command_type" });
        @export(&c.osc_command_data, .{ .name = "xghostty_osc_command_data" });
        @export(&c.focus_encode, .{ .name = "xghostty_focus_encode" });
        @export(&c.mode_report_encode, .{ .name = "xghostty_mode_report_encode" });
        @export(&c.paste_is_safe, .{ .name = "xghostty_paste_is_safe" });
        @export(&c.paste_encode, .{ .name = "xghostty_paste_encode" });
        @export(&c.size_report_encode, .{ .name = "xghostty_size_report_encode" });
        @export(&c.style_default, .{ .name = "xghostty_style_default" });
        @export(&c.style_is_default, .{ .name = "xghostty_style_is_default" });
        @export(&c.sys_log_stderr, .{ .name = "xghostty_sys_log_stderr" });
        @export(&c.sys_set, .{ .name = "xghostty_sys_set" });
        @export(&c.cell_get, .{ .name = "xghostty_cell_get" });
        @export(&c.cell_get_multi, .{ .name = "xghostty_cell_get_multi" });
        @export(&c.row_get, .{ .name = "xghostty_row_get" });
        @export(&c.row_get_multi, .{ .name = "xghostty_row_get_multi" });
        @export(&c.color_rgb_get, .{ .name = "xghostty_color_rgb_get" });
        @export(&c.sgr_new, .{ .name = "xghostty_sgr_new" });
        @export(&c.sgr_free, .{ .name = "xghostty_sgr_free" });
        @export(&c.sgr_reset, .{ .name = "xghostty_sgr_reset" });
        @export(&c.sgr_set_params, .{ .name = "xghostty_sgr_set_params" });
        @export(&c.sgr_next, .{ .name = "xghostty_sgr_next" });
        @export(&c.sgr_unknown_full, .{ .name = "xghostty_sgr_unknown_full" });
        @export(&c.sgr_unknown_partial, .{ .name = "xghostty_sgr_unknown_partial" });
        @export(&c.sgr_attribute_tag, .{ .name = "xghostty_sgr_attribute_tag" });
        @export(&c.sgr_attribute_value, .{ .name = "xghostty_sgr_attribute_value" });
        @export(&c.formatter_terminal_new, .{ .name = "xghostty_formatter_terminal_new" });
        @export(&c.formatter_format_buf, .{ .name = "xghostty_formatter_format_buf" });
        @export(&c.formatter_format_alloc, .{ .name = "xghostty_formatter_format_alloc" });
        @export(&c.formatter_free, .{ .name = "xghostty_formatter_free" });
        @export(&c.terminal_selection_format_buf, .{ .name = "xghostty_terminal_selection_format_buf" });
        @export(&c.terminal_selection_format_alloc, .{ .name = "xghostty_terminal_selection_format_alloc" });
        @export(&c.render_state_new, .{ .name = "xghostty_render_state_new" });
        @export(&c.render_state_update, .{ .name = "xghostty_render_state_update" });
        @export(&c.render_state_get, .{ .name = "xghostty_render_state_get" });
        @export(&c.render_state_get_multi, .{ .name = "xghostty_render_state_get_multi" });
        @export(&c.render_state_set, .{ .name = "xghostty_render_state_set" });
        @export(&c.render_state_colors_get, .{ .name = "xghostty_render_state_colors_get" });
        @export(&c.render_state_row_iterator_new, .{ .name = "xghostty_render_state_row_iterator_new" });
        @export(&c.render_state_row_iterator_next, .{ .name = "xghostty_render_state_row_iterator_next" });
        @export(&c.render_state_row_get, .{ .name = "xghostty_render_state_row_get" });
        @export(&c.render_state_row_get_multi, .{ .name = "xghostty_render_state_row_get_multi" });
        @export(&c.render_state_row_set, .{ .name = "xghostty_render_state_row_set" });
        @export(&c.render_state_row_iterator_free, .{ .name = "xghostty_render_state_row_iterator_free" });
        @export(&c.render_state_row_cells_new, .{ .name = "xghostty_render_state_row_cells_new" });
        @export(&c.render_state_row_cells_next, .{ .name = "xghostty_render_state_row_cells_next" });
        @export(&c.render_state_row_cells_select, .{ .name = "xghostty_render_state_row_cells_select" });
        @export(&c.render_state_row_cells_get, .{ .name = "xghostty_render_state_row_cells_get" });
        @export(&c.render_state_row_cells_get_multi, .{ .name = "xghostty_render_state_row_cells_get_multi" });
        @export(&c.render_state_row_cells_free, .{ .name = "xghostty_render_state_row_cells_free" });
        @export(&c.render_state_free, .{ .name = "xghostty_render_state_free" });
        @export(&c.terminal_new, .{ .name = "xghostty_terminal_new" });
        @export(&c.terminal_free, .{ .name = "xghostty_terminal_free" });
        @export(&c.terminal_reset, .{ .name = "xghostty_terminal_reset" });
        @export(&c.terminal_resize, .{ .name = "xghostty_terminal_resize" });
        @export(&c.terminal_set, .{ .name = "xghostty_terminal_set" });
        @export(&c.terminal_vt_write, .{ .name = "xghostty_terminal_vt_write" });
        @export(&c.terminal_scroll_viewport, .{ .name = "xghostty_terminal_scroll_viewport" });
        @export(&c.terminal_mode_get, .{ .name = "xghostty_terminal_mode_get" });
        @export(&c.terminal_mode_set, .{ .name = "xghostty_terminal_mode_set" });
        @export(&c.terminal_get, .{ .name = "xghostty_terminal_get" });
        @export(&c.terminal_get_multi, .{ .name = "xghostty_terminal_get_multi" });
        @export(&c.terminal_select_word, .{ .name = "xghostty_terminal_select_word" });
        @export(&c.terminal_select_word_between, .{ .name = "xghostty_terminal_select_word_between" });
        @export(&c.terminal_select_line, .{ .name = "xghostty_terminal_select_line" });
        @export(&c.terminal_select_all, .{ .name = "xghostty_terminal_select_all" });
        @export(&c.terminal_select_output, .{ .name = "xghostty_terminal_select_output" });
        @export(&c.terminal_selection_adjust, .{ .name = "xghostty_terminal_selection_adjust" });
        @export(&c.terminal_selection_order, .{ .name = "xghostty_terminal_selection_order" });
        @export(&c.terminal_selection_ordered, .{ .name = "xghostty_terminal_selection_ordered" });
        @export(&c.terminal_selection_contains, .{ .name = "xghostty_terminal_selection_contains" });
        @export(&c.terminal_selection_equal, .{ .name = "xghostty_terminal_selection_equal" });
        @export(&c.selection_gesture_new, .{ .name = "xghostty_selection_gesture_new" });
        @export(&c.selection_gesture_free, .{ .name = "xghostty_selection_gesture_free" });
        @export(&c.selection_gesture_reset, .{ .name = "xghostty_selection_gesture_reset" });
        @export(&c.selection_gesture_event, .{ .name = "xghostty_selection_gesture_event" });
        @export(&c.selection_gesture_get, .{ .name = "xghostty_selection_gesture_get" });
        @export(&c.selection_gesture_get_multi, .{ .name = "xghostty_selection_gesture_get_multi" });
        @export(&c.selection_gesture_event_new, .{ .name = "xghostty_selection_gesture_event_new" });
        @export(&c.selection_gesture_event_free, .{ .name = "xghostty_selection_gesture_event_free" });
        @export(&c.selection_gesture_event_set, .{ .name = "xghostty_selection_gesture_event_set" });
        @export(&c.terminal_grid_ref, .{ .name = "xghostty_terminal_grid_ref" });
        @export(&c.terminal_grid_ref_track, .{ .name = "xghostty_terminal_grid_ref_track" });
        @export(&c.terminal_point_from_grid_ref, .{ .name = "xghostty_terminal_point_from_grid_ref" });
        @export(&c.kitty_graphics_get, .{ .name = "xghostty_kitty_graphics_get" });
        @export(&c.kitty_graphics_image, .{ .name = "xghostty_kitty_graphics_image" });
        @export(&c.kitty_graphics_image_get, .{ .name = "xghostty_kitty_graphics_image_get" });
        @export(&c.kitty_graphics_image_get_multi, .{ .name = "xghostty_kitty_graphics_image_get_multi" });
        @export(&c.kitty_graphics_placement_iterator_new, .{ .name = "xghostty_kitty_graphics_placement_iterator_new" });
        @export(&c.kitty_graphics_placement_iterator_free, .{ .name = "xghostty_kitty_graphics_placement_iterator_free" });
        @export(&c.kitty_graphics_placement_iterator_set, .{ .name = "xghostty_kitty_graphics_placement_iterator_set" });
        @export(&c.kitty_graphics_placement_next, .{ .name = "xghostty_kitty_graphics_placement_next" });
        @export(&c.kitty_graphics_placement_get, .{ .name = "xghostty_kitty_graphics_placement_get" });
        @export(&c.kitty_graphics_placement_get_multi, .{ .name = "xghostty_kitty_graphics_placement_get_multi" });
        @export(&c.kitty_graphics_placement_rect, .{ .name = "xghostty_kitty_graphics_placement_rect" });
        @export(&c.kitty_graphics_placement_pixel_size, .{ .name = "xghostty_kitty_graphics_placement_pixel_size" });
        @export(&c.kitty_graphics_placement_grid_size, .{ .name = "xghostty_kitty_graphics_placement_grid_size" });
        @export(&c.kitty_graphics_placement_viewport_pos, .{ .name = "xghostty_kitty_graphics_placement_viewport_pos" });
        @export(&c.kitty_graphics_placement_source_rect, .{ .name = "xghostty_kitty_graphics_placement_source_rect" });
        @export(&c.kitty_graphics_placement_render_info, .{ .name = "xghostty_kitty_graphics_placement_render_info" });
        @export(&c.grid_ref_cell, .{ .name = "xghostty_grid_ref_cell" });
        @export(&c.grid_ref_row, .{ .name = "xghostty_grid_ref_row" });
        @export(&c.grid_ref_graphemes, .{ .name = "xghostty_grid_ref_graphemes" });
        @export(&c.grid_ref_hyperlink_uri, .{ .name = "xghostty_grid_ref_hyperlink_uri" });
        @export(&c.grid_ref_style, .{ .name = "xghostty_grid_ref_style" });
        @export(&c.tracked_grid_ref_free, .{ .name = "xghostty_tracked_grid_ref_free" });
        @export(&c.tracked_grid_ref_has_value, .{ .name = "xghostty_tracked_grid_ref_has_value" });
        @export(&c.tracked_grid_ref_point, .{ .name = "xghostty_tracked_grid_ref_point" });
        @export(&c.tracked_grid_ref_set, .{ .name = "xghostty_tracked_grid_ref_set" });
        @export(&c.tracked_grid_ref_snapshot, .{ .name = "xghostty_tracked_grid_ref_snapshot" });
        @export(&c.build_info, .{ .name = "xghostty_build_info" });
        @export(&c.type_json, .{ .name = "xghostty_type_json" });
        @export(&c.alloc_alloc, .{ .name = "xghostty_alloc" });
        @export(&c.alloc_free, .{ .name = "xghostty_free" });

        // On Wasm we need to export our allocator convenience functions.
        if (builtin.target.cpu.arch.isWasm()) {
            const alloc = @import("lib/allocator/convenience.zig");
            @export(&alloc.allocOpaque, .{ .name = "xghostty_wasm_alloc_opaque" });
            @export(&alloc.freeOpaque, .{ .name = "xghostty_wasm_free_opaque" });
            @export(&alloc.allocU8Array, .{ .name = "xghostty_wasm_alloc_u8_array" });
            @export(&alloc.freeU8Array, .{ .name = "xghostty_wasm_free_u8_array" });
            @export(&alloc.allocU16Array, .{ .name = "xghostty_wasm_alloc_u16_array" });
            @export(&alloc.freeU16Array, .{ .name = "xghostty_wasm_free_u16_array" });
            @export(&alloc.allocU8, .{ .name = "xghostty_wasm_alloc_u8" });
            @export(&alloc.freeU8, .{ .name = "xghostty_wasm_free_u8" });
            @export(&alloc.allocUsize, .{ .name = "xghostty_wasm_alloc_usize" });
            @export(&alloc.freeUsize, .{ .name = "xghostty_wasm_free_usize" });
            @export(&c.wasm_alloc_sgr_attribute, .{ .name = "xghostty_wasm_alloc_sgr_attribute" });
            @export(&c.wasm_free_sgr_attribute, .{ .name = "xghostty_wasm_free_sgr_attribute" });
        }
    }
}

pub const std_options: std.Options = options: {
    if (builtin.target.cpu.arch.isWasm()) break :options .{
        // Wasm builds we specifically want to optimize for space with small
        // releases so we bump up to warn. Everything else acts pretty normal.
        .log_level = switch (builtin.mode) {
            .Debug => .debug,
            .ReleaseSmall => .warn,
            else => .info,
        },

        // Wasm doesn't have access to stdio so we have a custom log function.
        .logFn = @import("os/wasm/log.zig").log,
    };

    // For C ABI builds, use a custom log function that dispatches to an
    // embedder-provided callback (or silently discards when none is set).
    if (terminal.options.c_abi) break :options .{
        .logFn = @import("terminal/c/sys.zig").logFn,
    };

    break :options .{};
};

test {
    _ = terminal;
    _ = @import("lib/main.zig");
    @import("std").testing.refAllDecls(input);
    if (comptime terminal.options.c_abi) {
        _ = terminal.c_api;
    }
}
