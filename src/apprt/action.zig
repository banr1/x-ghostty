const std = @import("std");
const assert = @import("../quirks.zig").inlineAssert;
const apprt = @import("../apprt.zig");
const configpkg = @import("../config.zig");
const input = @import("../input.zig");
const renderer = @import("../renderer.zig");
const terminal = @import("../terminal/main.zig");
const CoreSurface = @import("../Surface.zig");
const lib = @import("../lib/main.zig");

/// The target for an action. This is generally the thing that had focus
/// while the action was made but the concept of "focus" is not guaranteed
/// since actions can also be triggered by timers, scripts, etc.
pub const Target = union(Key) {
    app,
    surface: *CoreSurface,

    // Sync with: xghostty_target_tag_e
    pub const Key = enum(c_int) {
        app,
        surface,

        test "xghostty.h Target.Key" {
            try lib.checkXGhosttyHEnum(Key, "XGHOSTTY_TARGET_");
        }
    };

    // Sync with: xghostty_target_u
    pub const CValue = extern union {
        app: void,
        surface: *apprt.Surface,
    };

    // Sync with: xghostty_target_s
    pub const C = extern struct {
        key: Key,
        value: CValue,
    };

    /// Convert to xghostty_target_s.
    pub fn cval(self: Target) C {
        return .{
            .key = @as(Key, self),
            .value = switch (self) {
                .app => .{ .app = {} },
                .surface => |v| .{ .surface = v.rt_surface },
            },
        };
    }
};

/// The possible actions an apprt has to react to. Actions are one-way
/// messages that are sent to the app runtime to trigger some behavior.
///
/// Actions are very often key binding actions but can also be triggered
/// by lifecycle events. For example, the `quit_timer` action is not bindable.
///
/// Importantly, actions are generally OPTIONAL to implement by an apprt.
/// Required functionality is called directly on the runtime structure so
/// there is a compiler error if an action is not implemented.
pub const Action = union(Key) {
    // A GUIDE TO ADDING NEW ACTIONS:
    //
    // 1. Add the action to the `Key` enum. The order of the enum matters
    //    because it maps directly to the libxghostty C enum. For ABI
    //    compatibility, new actions should be added to the end of the enum.
    //
    // 2. Add the action and optional value to the Action union.
    //
    // 3. If the value type is not void, ensure the value is C ABI
    //    compatible (extern). If it is not, add a `C` decl to the value
    //    and a `cval` function to convert to the C ABI compatible value.
    //
    // 4. Update `include/xghostty.h`: add the new key, value, and union
    //    entry. If the value type is void then only the key needs to be
    //    added. Ensure the order matches exactly with the Zig code.

    /// Quit the application.
    quit,

    /// Create a new split. The value determines the location of the split
    /// relative to the target.
    new_split: SplitDirection,

    /// Toggle maximized window state.
    toggle_maximize,

    /// Toggle fullscreen mode.
    toggle_fullscreen: Fullscreen,

    /// Toggle the command palette.
    toggle_command_palette,

    /// Toggle the window background opacity. This only has an effect
    /// if the window started as transparent (non-opaque), and toggles
    /// it between fully opaque and the configured background opacity.
    toggle_background_opacity,

    /// Jump to a specific split.
    goto_split: GotoSplit,

    /// Resize the split in the given direction.
    resize_split: ResizeSplit,

    /// Equalize all the splits in the target window.
    equalize_splits,

    /// Toggle whether a split is zoomed or not. A zoomed split is resized
    /// to take up the entire window.
    toggle_split_zoom,

    /// Present the target terminal whether its a project or a split.
    present_terminal,

    /// Sets a size limit (in pixels) for the target terminal.
    size_limit: SizeLimit,

    /// Resets the window size to the default size. See the
    /// `reset_window_size` keybinding for more information.
    reset_window_size,

    /// Specifies the initial size of the target terminal.
    ///
    /// This may be sent once during the initialization of a surface
    /// (as part of the init call) to indicate the initial size requested
    /// for the window if it is not maximized or fullscreen.
    ///
    /// This may also be sent at any time after the surface is initialized
    /// to note the new "default size" of the window. This should in general
    /// be ignored, but may be useful if the apprt wants to support
    /// a "return to default size" action.
    initial_size: InitialSize,

    /// The cell size has changed to the given dimensions in pixels.
    cell_size: CellSize,

    /// The scrollbar is updating.
    scrollbar: terminal.Scrollbar,

    /// The target should be re-rendered. This usually has a specific
    /// surface target but if the app is targeted then all active
    /// surfaces should be redrawn.
    render,

    /// Control whether the inspector is shown or hidden.
    inspector: Inspector,

    /// The inspector for the given target has changes and should be
    /// rendered at the next opportunity.
    render_inspector,

    /// Show a desktop notification.
    desktop_notification: DesktopNotification,

    /// Set the title of the target to the requested value.
    set_title: SetTitle,

    /// Set the title of the target to a prompted value. It is up to
    /// the apprt to prompt.
    prompt_title,

    /// The current working directory has changed for the target terminal.
    pwd: Pwd,

    /// Set the mouse cursor shape.
    mouse_shape: terminal.MouseShape,

    /// Set whether the mouse cursor is visible or not.
    mouse_visibility: MouseVisibility,

    /// Called when the mouse is over or recently left a link.
    mouse_over_link: MouseOverLink,

    /// The health of the renderer has changed.
    renderer_health: renderer.Health,

    /// Open the XGhostty configuration. This is platform-specific about
    /// what it means; it can mean opening a dedicated UI or just opening
    /// a file in a text editor.
    open_config,

    /// Called when there are no more surfaces and the app should quit
    /// after the configured delay.
    ///
    /// Despite the name, this is the notification that libxghostty sends
    /// when there are no more surfaces regardless of if the configuration
    /// wants to quit after close, has any delay set, etc. It's up to the
    /// apprt to implement the proper logic based on the config.
    ///
    /// This can be cancelled by sending another quit_timer action with "stop".
    /// Multiple "starts" shouldn't happen and can be ignored or cause a
    /// restart it isn't that important.
    quit_timer: QuitTimer,

    /// Set the window floating state. A floating window is one that is
    /// always on top of other windows even when not focused.
    float_window: FloatWindow,

    /// Set the secure input functionality on or off. "Secure input" means
    /// that the user is currently at some sort of prompt where they may be
    /// entering a password or other sensitive information. This can be used
    /// by the app runtime to change the appearance of the cursor, setup
    /// system APIs to not log the input, etc.
    secure_input: SecureInput,

    /// A sequenced key binding has started, continued, or stopped.
    /// The UI should show some indication that the user is in a sequenced
    /// key mode because other input may be ignored.
    key_sequence: KeySequence,

    /// A key table has been activated or deactivated.
    key_table: KeyTable,

    /// A terminal color was changed programmatically through things
    /// such as OSC 10/11.
    color_change: ColorChange,

    /// A request to reload the configuration. The reload request can be
    /// from a user or for some internal reason. The reload request may
    /// request it is a soft reload or a full reload. See the struct for
    /// more documentation.
    ///
    /// The configuration should be passed to updateConfig either at the
    /// app or surface level depending on the target.
    reload_config: ReloadConfig,

    /// The configuration has changed. The value is a pointer to the new
    /// configuration. The pointer is only valid for the duration of the
    /// action and should not be stored.
    ///
    /// This should be used by apprts to update any internal state that
    /// depends on configuration for the given target (i.e. headerbar colors).
    /// The apprt should copy any data it needs since the memory lifetime
    /// is only valid for the duration of the action.
    ///
    /// This allows an apprt to have config-dependent state reactively
    /// change without having to store the entire configuration or poll
    /// for changes.
    config_change: ConfigChange,

    /// Called when the bell character is seen. The apprt should do whatever
    /// it needs to ring the bell. This is usually a sound or visual effect.
    ring_bell,

    /// Called when the active selection changes. The apprt should read the
    /// current selection itself; this carries no payload.
    selection_changed,

    /// Undo the last action. See the "undo" keybinding for more
    /// details on what can and cannot be undone.
    undo,

    /// Redo the last undone action.
    redo,

    check_for_updates,

    /// Open a URL using the native OS mechanisms. On macOS this might be `open`
    /// or on Linux this might be `xdg-open`. The exact mechanism is up to the
    /// apprt.
    open_url: OpenUrl,

    /// Show a native GUI notification that the child process has exited.
    show_child_exited: apprt.surface.Message.ChildExited,

    /// Show a native GUI notification about the progress of some TUI operation.
    progress_report: terminal.osc.Command.ProgressReport,

    /// A command has finished,
    command_finished: CommandFinished,

    /// Start the search overlay with an optional initial needle. If the
    /// search is already active and the needle is non-empty, update the
    /// current search needle and focus the search input.
    start_search: StartSearch,

    /// End the search overlay, clearing the search state and hiding it.
    end_search,

    /// The total number of matches found by the search.
    search_total: SearchTotal,

    /// The currently selected search match index (1-based).
    search_selected: SearchSelected,

    /// The readonly state of the surface has changed.
    readonly: Readonly,

    /// Copy the effective title of the surface to the clipboard.
    /// The effective title is the user-overridden title if set,
    /// otherwise the terminal-set title.
    copy_title_to_clipboard,

    // Project-layer actions. A project is the upper layer of the two-level split
    // model; these operate on the window's project tree rather than a single
    // project's pane tree. The argument types are shared with the corresponding
    // split actions. New actions must be appended (here and in the Key enum
    // below) to preserve C ABI compatibility.

    /// Create a new project through the project list (the list opens if
    /// needed and the new row lands below the cursor row, ready for title
    /// entry).
    new_project,

    /// Focus a project in the given direction or creation order.
    goto_project: GotoSplit,

    /// Toggle whether the current project is zoomed. A zoomed project is resized
    /// to take up the entire window.
    toggle_project_zoom,

    /// Hide the current project without terminating its processes.
    hide_project,

    /// Show a previously hidden project, identified by its id or name.
    show_project: SetTitle,

    /// Prompt to rename the current project. It is up to the apprt to prompt.
    rename_project,

    /// Set the name of the current project to the requested value.
    set_project_title: SetTitle,

    /// Close the current project, terminating the processes of all its panes.
    close_project,

    /// Swap the current project with an adjacent project. Mirrors `goto_project`
    /// but exchanges the two projects' contents instead of moving focus.
    /// Appended last (rather than next to `goto_project`) to preserve C ABI
    /// compatibility; see the note above.
    move_project: GotoSplit,

    /// Focus the Nth visible project (1-indexed) in tree traversal order.
    /// Uses `GotoProject` (only its non-negative index values are used here).
    /// Appended last (rather than next to `goto_project`) to preserve C ABI
    /// compatibility; see the note above.
    goto_project_index: GotoProject,

    /// Open the note editor overlay for the current project. It is up to the
    /// apprt to present the editor. Appended last (rather than next to
    /// `rename_project`) to preserve C ABI compatibility; see the note above.
    edit_project_note,

    /// Toggle the read-only note overview over all visible projects. It is up
    /// to the apprt to present the overlays. Appended last to preserve C ABI
    /// compatibility; see the note above.
    toggle_note_overview,

    /// Make the focused pane the primary pane of its project (the pane the
    /// overall view renders). It is up to the apprt to apply it — only
    /// effective while zoomed into the project. Appended last to preserve
    /// C ABI compatibility; see the note above.
    set_primary,

    /// Open the layout-selection overlay listing the built-in registered
    /// layouts. It is up to the apprt to show it. Appended last to preserve
    /// C ABI compatibility; see the note above.
    choose_project_layout,

    /// Open the project-list overlay listing every project including hidden
    /// ones. It is up to the apprt to show it. Appended last to preserve
    /// C ABI compatibility; see the note above.
    list_projects,

    /// Toggle the read-only shortcut-list overlay enumerating the effective
    /// shortcuts grouped by scene. It is up to the apprt to show it.
    /// Appended last to preserve C ABI compatibility; see the note above.
    toggle_shortcut_list,

    /// Sync with: xghostty_action_tag_e
    pub const Key = enum(c_int) {
        quit,
        new_split,
        toggle_maximize,
        toggle_fullscreen,
        toggle_command_palette,
        toggle_background_opacity,
        goto_split,
        resize_split,
        equalize_splits,
        toggle_split_zoom,
        present_terminal,
        size_limit,
        reset_window_size,
        initial_size,
        cell_size,
        scrollbar,
        render,
        inspector,
        render_inspector,
        desktop_notification,
        set_title,
        prompt_title,
        pwd,
        mouse_shape,
        mouse_visibility,
        mouse_over_link,
        renderer_health,
        open_config,
        quit_timer,
        float_window,
        secure_input,
        key_sequence,
        key_table,
        color_change,
        reload_config,
        config_change,
        ring_bell,
        selection_changed,
        undo,
        redo,
        check_for_updates,
        open_url,
        show_child_exited,
        progress_report,
        command_finished,
        start_search,
        end_search,
        search_total,
        search_selected,
        readonly,
        copy_title_to_clipboard,

        // Project-layer actions, appended for C ABI compatibility. Keep this
        // order in sync with the union above and with `xghostty_action_tag_e`
        // in include/xghostty.h. (`new_project` replaced `new_project_split`
        // in place, keeping every later tag value stable; the retired sort
        // actions were removed outright — the sort is a persisted state now,
        // not an action — shifting the two tags after them, with the header
        // updated in lockstep.)
        new_project,
        goto_project,
        toggle_project_zoom,
        hide_project,
        show_project,
        rename_project,
        set_project_title,
        close_project,
        move_project,
        goto_project_index,
        edit_project_note,
        toggle_note_overview,
        set_primary,
        choose_project_layout,
        list_projects,
        toggle_shortcut_list,

        test "xghostty.h Action.Key" {
            try lib.checkXGhosttyHEnum(Key, "XGHOSTTY_ACTION_");
        }
    };

    /// Sync with: xghostty_action_u
    pub const CValue = cvalue: {
        const key_fields = @typeInfo(Key).@"enum".fields;
        var union_fields: [key_fields.len]std.builtin.Type.UnionField = undefined;
        for (key_fields, 0..) |field, i| {
            const action = @unionInit(Action, field.name, undefined);
            const Type = t: {
                const Type = @TypeOf(@field(action, field.name));
                // Types can provide custom types for their CValue.
                if (Type != void and @hasDecl(Type, "C")) break :t Type.C;
                break :t Type;
            };

            union_fields[i] = .{
                .name = field.name,
                .type = Type,
                .alignment = @alignOf(Type),
            };
        }

        break :cvalue @Type(.{ .@"union" = .{
            .layout = .@"extern",
            .tag_type = null,
            .fields = &union_fields,
            .decls = &.{},
        } });
    };

    /// Sync with: xghostty_action_s
    pub const C = extern struct {
        key: Key,
        value: CValue,
    };

    comptime {
        // For ABI compatibility, we expect that this is our union size.
        // At the time of writing, we don't promise ABI compatibility
        // so we can change this but I want to be aware of it.
        assert(@sizeOf(CValue) == switch (@sizeOf(usize)) {
            4 => 16,
            8 => 24,
            else => unreachable,
        });
    }

    /// Returns the value type for the given key.
    pub fn Value(comptime key: Key) type {
        inline for (@typeInfo(Action).@"union".fields) |field| {
            const field_key = @field(Key, field.name);
            if (field_key == key) return field.type;
        }

        unreachable;
    }

    /// Convert to xghostty_action_s.
    pub fn cval(self: Action) C {
        const value: CValue = switch (self) {
            inline else => |v, tag| @unionInit(
                CValue,
                @tagName(tag),
                if (@TypeOf(v) != void and @hasDecl(@TypeOf(v), "cval")) v.cval() else v,
            ),
        };

        return .{
            .key = @as(Key, self),
            .value = value,
        };
    }
};

// This is made extern (c_int) to make interop easier with our embedded
// runtime. The small size cost doesn't make a difference in our union.
pub const SplitDirection = enum(c_int) {
    right,
    down,
    left,
    up,

    test "xghostty.h SplitDirection" {
        try lib.checkXGhosttyHEnum(SplitDirection, "XGHOSTTY_SPLIT_DIRECTION_");
    }
};

// This is made extern (c_int) to make interop easier with our embedded
// runtime. The small size cost doesn't make a difference in our union.
pub const GotoSplit = enum(c_int) {
    previous,
    next,

    up,
    left,
    down,
    right,

    test "xghostty.h GotoSplit" {
        try lib.checkXGhosttyHEnum(GotoSplit, "XGHOSTTY_GOTO_SPLIT_");
    }
};

/// The amount to resize the split by and the direction to resize it in.
pub const ResizeSplit = extern struct {
    amount: u16,
    direction: Direction,

    pub const Direction = enum(c_int) {
        up,
        down,
        left,
        right,

        test "xghostty.h ResizeSplit.Direction" {
            try lib.checkXGhosttyHEnum(Direction, "XGHOSTTY_RESIZE_SPLIT_");
        }
    };
};

/// The project to jump to. This is non-exhaustive so that integer values
/// represent the index (zero-based) of the project to jump to. Negative values
/// are special values.
pub const GotoProject = enum(c_int) {
    previous = -1,
    next = -2,
    last = -3,
    _,

    // TODO: check non-exhaustive enums
    // test "xghostty.h GotoProject" {
    //     try lib.checkXGhosttyHEnum(GotoProject, "XGHOSTTY_GOTO_PROJECT_");
    // }
};

/// The fullscreen mode to toggle to if we're moving to fullscreen.
pub const Fullscreen = enum(c_int) {
    native,

    /// macOS has a non-native fullscreen mode that is more like a maximized
    /// window. This is much faster to enter and exit than the native mode.
    macos_non_native,
    macos_non_native_visible_menu,
    macos_non_native_padded_notch,

    test "xghostty.h Fullscreen" {
        try lib.checkXGhosttyHEnum(Fullscreen, "XGHOSTTY_FULLSCREEN_");
    }
};

pub const FloatWindow = enum(c_int) {
    on,
    off,
    toggle,

    test "xghostty.h FloatWindow" {
        try lib.checkXGhosttyHEnum(FloatWindow, "XGHOSTTY_FLOAT_WINDOW_");
    }
};

pub const SecureInput = enum(c_int) {
    on,
    off,
    toggle,

    test "xghostty.h SecureInput" {
        try lib.checkXGhosttyHEnum(SecureInput, "XGHOSTTY_SECURE_INPUT_");
    }
};

/// The inspector mode to toggle to if we're toggling the inspector.
pub const Inspector = enum(c_int) {
    toggle,
    show,
    hide,

    test "xghostty.h Inspector" {
        try lib.checkXGhosttyHEnum(Inspector, "XGHOSTTY_INSPECTOR_");
    }
};

pub const QuitTimer = enum(c_int) {
    start,
    stop,

    test "xghostty.h QuitTimer" {
        try lib.checkXGhosttyHEnum(QuitTimer, "XGHOSTTY_QUIT_TIMER_");
    }
};

pub const Readonly = enum(c_int) {
    off,
    on,

    test "xghostty.h Readonly" {
        try lib.checkXGhosttyHEnum(Readonly, "XGHOSTTY_READONLY_");
    }
};

pub const MouseVisibility = enum(c_int) {
    visible,
    hidden,

    test "xghostty.h MouseVisibility" {
        try lib.checkXGhosttyHEnum(MouseVisibility, "XGHOSTTY_MOUSE_");
    }
};

pub const MouseOverLink = struct {
    url: [:0]const u8,

    // Sync with: xghostty_action_mouse_over_link_s
    pub const C = extern struct {
        url: [*]const u8,
        len: usize,
    };

    pub fn cval(self: MouseOverLink) C {
        return .{
            .url = self.url.ptr,
            .len = self.url.len,
        };
    }
};

pub const SizeLimit = extern struct {
    min_width: u32,
    min_height: u32,
    max_width: u32,
    max_height: u32,
};

pub const InitialSize = extern struct {
    width: u32,
    height: u32,
};

pub const CellSize = extern struct {
    width: u32,
    height: u32,
};

pub const SetTitle = struct {
    title: [:0]const u8,

    // Sync with: xghostty_action_set_title_s
    pub const C = extern struct {
        title: [*:0]const u8,
    };

    pub fn cval(self: SetTitle) C {
        return .{
            .title = self.title.ptr,
        };
    }

    pub fn format(
        value: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: *std.Io.Writer,
    ) !void {
        try writer.print("{s}{{ {s} }}", .{ @typeName(@This()), value.title });
    }
};

pub const Pwd = struct {
    pwd: [:0]const u8,

    /// The host the pwd was reported from, empty when it is this machine.
    /// A non-empty host means the shell that reported it runs elsewhere, so
    /// the path is not a path in our own filesystem.
    host: [:0]const u8 = "",

    // Sync with: xghostty_action_set_pwd_s
    pub const C = extern struct {
        pwd: [*:0]const u8,
        host: [*:0]const u8,
    };

    pub fn cval(self: Pwd) C {
        return .{
            .pwd = self.pwd.ptr,
            .host = self.host.ptr,
        };
    }

    pub fn format(
        value: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: *std.Io.Writer,
    ) !void {
        try writer.print("{s}{{ {s}:{s} }}", .{
            @typeName(@This()),
            value.host,
            value.pwd,
        });
    }
};

/// The desktop notification to show.
pub const DesktopNotification = struct {
    title: [:0]const u8,
    body: [:0]const u8,

    // Sync with: xghostty_action_desktop_notification_s
    pub const C = extern struct {
        title: [*:0]const u8,
        body: [*:0]const u8,
    };

    pub fn cval(self: DesktopNotification) C {
        return .{
            .title = self.title.ptr,
            .body = self.body.ptr,
        };
    }

    pub fn format(
        value: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: *std.Io.Writer,
    ) !void {
        try writer.print("{s}{{ title: {s}, body: {s} }}", .{
            @typeName(@This()),
            value.title,
            value.body,
        });
    }
};

pub const KeySequence = union(enum) {
    trigger: input.Trigger,
    end,

    // Sync with: xghostty_action_key_sequence_s
    pub const C = extern struct {
        active: bool,
        trigger: input.Trigger.C,
    };

    pub fn cval(self: KeySequence) C {
        return switch (self) {
            .trigger => |t| .{ .active = true, .trigger = t.cval() },
            .end => .{ .active = false, .trigger = .{} },
        };
    }
};

pub const KeyTable = union(enum) {
    activate: []const u8,
    deactivate,
    deactivate_all,

    // Sync with: xghostty_action_key_table_tag_e
    pub const Tag = enum(c_int) {
        activate,
        deactivate,
        deactivate_all,
    };

    // Sync with: xghostty_action_key_table_u
    pub const CValue = extern union {
        activate: extern struct {
            name: [*]const u8,
            len: usize,
        },
    };

    // Sync with: xghostty_action_key_table_s
    pub const C = extern struct {
        tag: Tag,
        value: CValue,
    };

    pub fn cval(self: KeyTable) C {
        return switch (self) {
            .activate => |name| .{
                .tag = .activate,
                .value = .{ .activate = .{ .name = name.ptr, .len = name.len } },
            },
            .deactivate => .{
                .tag = .deactivate,
                .value = undefined,
            },
            .deactivate_all => .{
                .tag = .deactivate_all,
                .value = undefined,
            },
        };
    }
};

pub const ColorChange = extern struct {
    kind: ColorKind,
    r: u8,
    g: u8,
    b: u8,
};

pub const ColorKind = enum(c_int) {
    // Negative numbers indicate some named kind
    foreground = -1,
    background = -2,
    cursor = -3,

    // 0+ values indicate a palette index
    _,

    // TODO: check non-non-exhaustive enums
    // test "xghostty.h ColorKind" {
    //     try lib.checkXGhosttyHEnum(ColorKind, "XGHOSTTY_COLOR_KIND_");
    // }
};

pub const ReloadConfig = extern struct {
    /// A soft reload means that the configuration doesn't need to be
    /// read off disk, but libxghostty needs the full config again so call
    /// updateConfig with it.
    soft: bool = false,
};

pub const ConfigChange = struct {
    config: *const configpkg.Config,

    // Sync with: xghostty_action_config_change_s
    pub const C = extern struct {
        config: *const configpkg.Config,
    };

    pub fn cval(self: ConfigChange) C {
        return .{
            .config = self.config,
        };
    }
};

/// Open a URL
pub const OpenUrl = struct {
    /// The type of data that the URL refers to.
    kind: Kind,

    /// The URL.
    url: []const u8,

    /// The type of the data at the URL to open. This is used as a hint to
    /// potentially open the URL in a different way.
    ///
    /// Sync with: xghostty_action_open_url_kind_e
    pub const Kind = enum(c_int) {
        /// The type is unknown. This is the default and apprts should
        /// open the URL in the most generic way possible. For example,
        /// on macOS this would be the equivalent of `open` or on Linux
        /// this would be `xdg-open`.
        unknown,

        /// The URL is known to be a text file. In this case, the apprt
        /// should try to open the URL in a text editor or viewer or
        /// some equivalent, if possible.
        text,

        /// The URL is known to contain HTML content.
        html,

        test "xghostty.h OpenUrl.Kind" {
            try lib.checkXGhosttyHEnum(Kind, "XGHOSTTY_ACTION_OPEN_URL_KIND_");
        }
    };

    // Sync with: xghostty_action_open_url_s
    pub const C = extern struct {
        kind: Kind,
        url: [*]const u8,
        len: usize,
    };

    pub fn cval(self: OpenUrl) C {
        return .{
            .kind = self.kind,
            .url = self.url.ptr,
            .len = self.url.len,
        };
    }
};

pub const CommandFinished = struct {
    exit_code: ?u8,
    duration: configpkg.Config.Duration,

    /// sync with xghostty_action_command_finished_s in ghostty.h
    pub const C = extern struct {
        exit_code: i16,
        duration: u64,
    };

    pub fn cval(self: CommandFinished) C {
        return .{
            .exit_code = self.exit_code orelse -1,
            .duration = self.duration.duration,
        };
    }
};

pub const StartSearch = struct {
    needle: [:0]const u8,

    // Sync with: xghostty_action_start_search_s
    pub const C = extern struct {
        needle: [*:0]const u8,
    };

    pub fn cval(self: StartSearch) C {
        return .{
            .needle = self.needle.ptr,
        };
    }
};

pub const SearchTotal = struct {
    total: ?usize,

    // Sync with: xghostty_action_search_total_s
    pub const C = extern struct {
        total: isize,
    };

    pub fn cval(self: SearchTotal) C {
        return .{
            .total = if (self.total) |t| @intCast(t) else -1,
        };
    }
};

pub const SearchSelected = struct {
    selected: ?usize,

    // Sync with: xghostty_action_search_selected_s
    pub const C = extern struct {
        selected: isize,
    };

    pub fn cval(self: SearchSelected) C {
        return .{
            .selected = if (self.selected) |s| @intCast(s) else -1,
        };
    }
};

test {
    _ = std.testing.refAllDeclsRecursive(@This());
}
