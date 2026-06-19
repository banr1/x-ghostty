//! Comptime-generated metadata describing the layout of all C API
//! extern structs for the current target.
//!
//! This is embedded in the binary as a const string and exposed via
//! `xghostty_type_json` so that WASM (and other FFI) consumers can
//! build structs without hardcoding byte offsets.
const std = @import("std");
const lib = @import("../lib.zig");
const color = @import("../color.zig");
const mouse_event = @import("mouse_event.zig");
const point = @import("../point.zig");
const size_report = @import("size_report.zig");

const terminal = @import("terminal.zig");
const formatter = @import("formatter.zig");
const selection = @import("selection.zig");
const selection_gesture = @import("selection_gesture.zig");
const render = @import("render.zig");
const style_c = @import("style.zig");
const mouse_encode = @import("mouse_encode.zig");
const grid_ref = @import("grid_ref.zig");

/// C: GhosttySurfacePosition
pub const SurfacePosition = extern struct {
    x: f64,
    y: f64,
};

/// C: GhosttyCodepoints
pub const Codepoints = extern struct {
    ptr: ?[*]const u32 = null,
    len: usize = 0,
};

/// All C API structs and their XGhostty C names.
pub const structs: std.StaticStringMap(StructInfo) = structs: {
    @setEvalBranchQuota(10_000);
    break :structs .initComptime(.{
        .{ "XGhosttyBuffer", StructInfo.init(lib.Buffer) },
        .{ "XGhosttyCodepoints", StructInfo.init(Codepoints) },
        .{ "XGhosttyColorRgb", StructInfo.init(color.RGB.C) },
        .{ "XGhosttyDeviceAttributes", StructInfo.init(terminal.DeviceAttributes) },
        .{ "XGhosttyDeviceAttributesPrimary", StructInfo.init(terminal.DeviceAttributes.Primary) },
        .{ "XGhosttyDeviceAttributesSecondary", StructInfo.init(terminal.DeviceAttributes.Secondary) },
        .{ "XGhosttyDeviceAttributesTertiary", StructInfo.init(terminal.DeviceAttributes.Tertiary) },
        .{ "XGhosttyFormatterTerminalOptions", StructInfo.init(formatter.TerminalOptions) },
        .{ "XGhosttySelection", StructInfo.init(selection.CSelection) },
        .{ "XGhosttyTerminalSelectWordOptions", StructInfo.init(selection.SelectWordOptions) },
        .{ "XGhosttyTerminalSelectWordBetweenOptions", StructInfo.init(selection.SelectWordBetweenOptions) },
        .{ "XGhosttyTerminalSelectLineOptions", StructInfo.init(selection.SelectLineOptions) },
        .{ "XGhosttyFormatterTerminalExtra", StructInfo.init(formatter.TerminalOptions.Extra) },
        .{ "XGhosttyFormatterScreenExtra", StructInfo.init(formatter.ScreenOptions.Extra) },
        .{ "XGhosttyGridRef", StructInfo.init(grid_ref.CGridRef) },
        .{ "XGhosttyMouseEncoderSize", StructInfo.init(mouse_encode.Size) },
        .{ "XGhosttyMousePosition", StructInfo.init(mouse_event.Position) },
        .{ "XGhosttyPoint", StructInfo.init(point.Point.C) },
        .{ "XGhosttyPointCoordinate", StructInfo.init(point.Coordinate) },
        .{ "XGhosttyRenderStateColors", StructInfo.init(render.Colors) },
        .{ "XGhosttySelectionGestureBehaviors", StructInfo.init(selection_gesture.Behaviors) },
        .{ "XGhosttySelectionGestureGeometry", StructInfo.init(selection_gesture.Geometry) },
        .{ "XGhosttySizeReportSize", StructInfo.init(size_report.Size) },
        .{ "XGhosttyString", StructInfo.init(lib.String) },
        .{ "XGhosttySurfacePosition", StructInfo.init(SurfacePosition) },
        .{ "XGhosttyStyle", StructInfo.init(style_c.Style) },
        .{ "XGhosttyStyleColor", StructInfo.init(style_c.Color) },
        .{ "XGhosttyTerminalOptions", StructInfo.init(terminal.Options) },
        .{ "XGhosttyTerminalScrollbar", StructInfo.init(terminal.TerminalScrollbar) },
        .{ "XGhosttyTerminalScrollViewport", StructInfo.init(terminal.ScrollViewport) },
    });
};

/// The comptime-generated JSON string of all structs.
pub const json: [:0]const u8 = json: {
    @setEvalBranchQuota(100000);
    var counter: std.Io.Writer.Discarding = .init(&.{});
    jsonWriteAll(&counter.writer) catch unreachable;

    var buf: [counter.count:0]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    jsonWriteAll(&writer) catch unreachable;
    const final = buf;
    break :json final[0..writer.end :0];
};

/// Returns a pointer to the comptime-generated JSON string describing
/// the layout of all C API extern structs, and writes its length to `len`.
/// Exported as `xghostty_type_json` for FFI consumers.
pub fn get_json() callconv(lib.calling_conv) [*:0]const u8 {
    return json.ptr;
}

/// Meta information about a struct that we expose to ease writing
/// bindings in some languages, particularly WASM where we can't
/// easily share struct definitions and need to hardcode byte offsets.
pub const StructInfo = struct {
    name: []const u8,
    size: usize,
    @"align": usize,
    fields: []const FieldInfo,

    pub const FieldInfo = struct {
        name: []const u8,
        offset: usize,
        size: usize,
        type: []const u8,
    };

    pub fn init(comptime T: type) StructInfo {
        comptime {
            const fields = @typeInfo(T).@"struct".fields;
            const field_infos: [fields.len]FieldInfo = blk: {
                var infos: [fields.len]FieldInfo = undefined;
                for (fields, 0..) |field, i| infos[i] = .{
                    .name = field.name,
                    .offset = @offsetOf(T, field.name),
                    .size = @sizeOf(field.type),
                    .type = typeName(field.type),
                };
                break :blk infos;
            };

            return .{
                .name = @typeName(T),
                .size = @sizeOf(T),
                .@"align" = @alignOf(T),
                .fields = &field_infos,
            };
        }
    }

    pub fn jsonStringify(
        self: *const StructInfo,
        jws: anytype,
    ) std.Io.Writer.Error!void {
        try jws.beginObject();
        try jws.objectField("size");
        try jws.write(self.size);
        try jws.objectField("align");
        try jws.write(self.@"align");
        try jws.objectField("fields");
        try jws.beginObject();
        for (self.fields) |field| {
            try jws.objectField(field.name);
            try jws.beginObject();
            try jws.objectField("offset");
            try jws.write(field.offset);
            try jws.objectField("size");
            try jws.write(field.size);
            try jws.objectField("type");
            try jws.write(field.type);
            try jws.endObject();
        }
        try jws.endObject();
        try jws.endObject();
    }
};

fn jsonWriteAll(writer: *std.Io.Writer) std.Io.Writer.Error!void {
    var jws: std.json.Stringify = .{ .writer = writer };
    try jws.beginObject();
    for (structs.keys(), structs.values()) |name, *info| {
        try jws.objectField(name);
        try info.jsonStringify(&jws);
    }
    try jws.endObject();
}

fn typeName(comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .bool => "bool",
        .float => |info| switch (info.bits) {
            32 => "f32",
            64 => "f64",
            else => @compileError("unsupported float size"),
        },
        .int => |info| switch (info.signedness) {
            .signed => switch (info.bits) {
                8 => "i8",
                16 => "i16",
                32 => "i32",
                64 => "i64",
                else => @compileError("unsupported signed int size"),
            },
            .unsigned => switch (info.bits) {
                8 => "u8",
                16 => "u16",
                32 => "u32",
                64 => "u64",
                else => @compileError("unsupported unsigned int size"),
            },
        },
        .@"enum" => "enum",
        .@"struct" => "struct",
        .pointer => "pointer",
        .array => "array",
        else => "opaque",
    };
}

test "json parses" {
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        json,
        .{},
    );
    defer parsed.deinit();

    const root = parsed.value.object;

    // Verify we have all expected structs
    try std.testing.expect(root.contains("XGhosttyTerminalOptions"));
    try std.testing.expect(root.contains("XGhosttyFormatterTerminalOptions"));

    // Verify GhosttyTerminalOptions fields
    const term_opts = root.get("XGhosttyTerminalOptions").?.object;
    try std.testing.expect(term_opts.contains("size"));
    try std.testing.expect(term_opts.contains("align"));
    try std.testing.expect(term_opts.contains("fields"));

    const fields = term_opts.get("fields").?.object;
    try std.testing.expect(fields.contains("cols"));
    try std.testing.expect(fields.contains("rows"));
    try std.testing.expect(fields.contains("max_scrollback"));

    // Verify field offsets make sense (cols should be at 0)
    const cols = fields.get("cols").?.object;
    try std.testing.expectEqual(0, cols.get("offset").?.integer);
}

test "struct sizes are non-zero" {
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        json,
        .{},
    );
    defer parsed.deinit();

    var it = parsed.value.object.iterator();
    while (it.next()) |entry| {
        const struct_info = entry.value_ptr.object;
        const size = struct_info.get("size").?.integer;
        try std.testing.expect(size > 0);
    }
}
