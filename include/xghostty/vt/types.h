/**
 * @file types.h
 *
 * Common types, macros, and utilities for libghostty-vt.
 */

#ifndef XGHOSTTY_VT_TYPES_H
#define XGHOSTTY_VT_TYPES_H

#include <limits.h>
#include <stddef.h>
#include <stdint.h>

// Symbol visibility for shared library builds. On Windows, functions
// are exported from the DLL when building and imported when consuming.
// On other platforms with GCC/Clang, functions are marked with default
// visibility so they remain accessible when the library is built with
// -fvisibility=hidden. For static library builds, define XGHOSTTY_STATIC
// before including this header to make this a no-op.
#ifndef XGHOSTTY_API
#if defined(XGHOSTTY_STATIC)
  #define XGHOSTTY_API
#elif defined(_WIN32) || defined(_WIN64)
  #ifdef XGHOSTTY_BUILD_SHARED
    #define XGHOSTTY_API __declspec(dllexport)
  #else
    #define XGHOSTTY_API __declspec(dllimport)
  #endif
#elif defined(__GNUC__) && __GNUC__ >= 4
  #define XGHOSTTY_API __attribute__((visibility("default")))
#else
  #define XGHOSTTY_API
#endif
#endif

/**
 * Enum int-sizing helpers.
 *
 * The Zig side backs all C enums with c_int, so the C declarations
 * must use int as their underlying type to maintain ABI compatibility.
 *
 * C23 (detected via __STDC_VERSION__ >= 202311L) supports explicit
 * enum underlying types with `enum : int { ... }`. For pre-C23
 * compilers, which are free to choose any type that can represent
 * all values (C11 §6.7.2.2), we add an INT_MAX sentinel as the last
 * entry to force the compiler to use int.
 *
 * INT_MAX is used rather than a fixed constant like 0xFFFFFFFF
 * because enum constants must have type int (which is signed).
 * Values above INT_MAX overflow signed int and are a constraint
 * violation in standard C; compilers that accept them interpret them
 * as negative values via two's complement, which can collide with
 * legitimate negative enum values.
 *
 * Usage:
 * @code
 * typedef enum XGHOSTTY_ENUM_TYPED {
 *     FOO_A = 0,
 *     FOO_B = 1,
 *     FOO_MAX_VALUE = XGHOSTTY_ENUM_MAX_VALUE,
 * } Foo;
 * @endcode
 */
#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 202311L
#define XGHOSTTY_ENUM_TYPED : int
#else
#define XGHOSTTY_ENUM_TYPED
#endif
#define XGHOSTTY_ENUM_MAX_VALUE INT_MAX

/**
 * Result codes for libghostty-vt operations.
 */
typedef enum XGHOSTTY_ENUM_TYPED {
    /** Operation completed successfully */
    XGHOSTTY_SUCCESS = 0,
    /** Operation failed due to failed allocation */
    XGHOSTTY_OUT_OF_MEMORY = -1,
    /** Operation failed due to invalid value */
    XGHOSTTY_INVALID_VALUE = -2,
    /** Operation failed because the provided buffer was too small */
    XGHOSTTY_OUT_OF_SPACE = -3,
    /** The requested value has no value */
    XGHOSTTY_NO_VALUE = -4,
    XGHOSTTY_RESULT_MAX_VALUE = XGHOSTTY_ENUM_MAX_VALUE,
} GhosttyResult;

/* ---- Opaque handles ---- */

/**
 * Opaque handle to a terminal instance.
 *
 * @ingroup terminal
 */
typedef struct GhosttyTerminalImpl* GhosttyTerminal;

/**
 * Opaque handle to a tracked grid reference.
 *
 * A tracked grid reference is owned by the caller and must be freed with
 * xghostty_tracked_grid_ref_free(). If the terminal that created it is freed
 * first, the handle remains valid only for tracked-grid-ref APIs: it reports no
 * value and can still be freed.
 *
 * @ingroup grid_ref
 */
typedef struct GhosttyTrackedGridRefImpl* GhosttyTrackedGridRef;

/**
 * Opaque handle to a Kitty graphics image storage.
 *
 * Obtained via xghostty_terminal_get() with
 * XGHOSTTY_TERMINAL_DATA_KITTY_GRAPHICS. The pointer is borrowed from
 * the terminal and remains valid until the next mutating terminal call
 * (e.g. xghostty_terminal_vt_write() or xghostty_terminal_reset()).
 *
 * @ingroup kitty_graphics
 */
typedef struct XGhosttyKittyGraphicsImpl* XGhosttyKittyGraphics;

/**
 * Opaque handle to a Kitty graphics image.
 *
 * Obtained via xghostty_kitty_graphics_image() with an image ID. The
 * pointer is borrowed from the storage and remains valid until the next
 * mutating terminal call.
 *
 * @ingroup kitty_graphics
 */
typedef const struct XGhosttyKittyGraphicsImageImpl* XGhosttyKittyGraphicsImage;

/**
 * Opaque handle to a Kitty graphics placement iterator.
 *
 * @ingroup kitty_graphics
 */
typedef struct XGhosttyKittyGraphicsPlacementIteratorImpl* XGhosttyKittyGraphicsPlacementIterator;

/**
 * Opaque handle to a render state instance.
 *
 * @ingroup render
 */
typedef struct GhosttyRenderStateImpl* GhosttyRenderState;

/**
 * Opaque handle to a render-state row iterator.
 *
 * @ingroup render
 */
typedef struct GhosttyRenderStateRowIteratorImpl* GhosttyRenderStateRowIterator;

/**
 * Opaque handle to render-state row cells.
 *
 * @ingroup render
 */
typedef struct GhosttyRenderStateRowCellsImpl* GhosttyRenderStateRowCells;

/**
 * Opaque handle to an SGR parser instance.
 *
 * This handle represents an SGR (Select Graphic Rendition) parser that can
 * be used to parse SGR sequences and extract individual text attributes.
 *
 * @ingroup sgr
 */
typedef struct GhosttySgrParserImpl* GhosttySgrParser;

/**
 * Opaque handle to a formatter instance.
 *
 * @ingroup formatter
 */
typedef struct GhosttyFormatterImpl* GhosttyFormatter;

/**
 * Opaque handle to an OSC parser instance.
 *
 * This handle represents an OSC (Operating System Command) parser that can
 * be used to parse the contents of OSC sequences.
 *
 * @ingroup osc
 */
typedef struct GhosttyOscParserImpl* GhosttyOscParser;

/**
 * Opaque handle to a single OSC command.
 *
 * This handle represents a parsed OSC (Operating System Command) command.
 * The command can be queried for its type and associated data.
 *
 * @ingroup osc
 */
typedef struct GhosttyOscCommandImpl* GhosttyOscCommand;

/* ---- Common value types ---- */

/**
 * Terminal content output format.
 *
 * @ingroup formatter
 */
typedef enum XGHOSTTY_ENUM_TYPED {
  /** Plain text (no escape sequences). */
  XGHOSTTY_FORMATTER_FORMAT_PLAIN,

  /** VT sequences preserving colors, styles, URLs, etc. */
  XGHOSTTY_FORMATTER_FORMAT_VT,

  /** HTML with inline styles. */
  XGHOSTTY_FORMATTER_FORMAT_HTML,
  XGHOSTTY_FORMATTER_FORMAT_MAX_VALUE = XGHOSTTY_ENUM_MAX_VALUE,
} GhosttyFormatterFormat;

/**
 * A borrowed byte string (pointer + length).
 *
 * The memory is not owned by this struct. The pointer is only valid
 * for the lifetime documented by the API that produces or consumes it.
 */
typedef struct {
  /** Pointer to the string bytes. */
  const uint8_t* ptr;

  /** Length of the string in bytes. */
  size_t len;
} GhosttyString;

/**
 * A caller-provided byte buffer.
 *
 * APIs that write to this type use `len` for the number of bytes written on
 * XGHOSTTY_SUCCESS and the required byte capacity on XGHOSTTY_OUT_OF_SPACE.
 */
typedef struct {
  /** Destination buffer for bytes. May be NULL when cap is 0 to query required size. */
  uint8_t* ptr;

  /** Capacity of ptr in bytes. */
  size_t cap;

  /** Bytes written on success, or required byte capacity on XGHOSTTY_OUT_OF_SPACE. */
  size_t len;
} GhosttyBuffer;

/**
 * A surface-space position in pixels.
 *
 * This is not a terminal grid coordinate. It represents an x/y position in the
 * rendered surface coordinate space, with (0, 0) at the top-left of the
 * surface.
 */
typedef struct {
  /** X position in surface pixels. */
  double x;

  /** Y position in surface pixels. */
  double y;
} GhosttySurfacePosition;

/**
 * A borrowed list of Unicode scalar values.
 *
 * Values are encoded as uint32_t scalar values. The memory is not owned by this
 * struct. The pointer is only valid for the lifetime documented by the API that
 * consumes or produces it.
 *
 * APIs may document special handling for NULL + len 0, such as “use defaults”.
 */
typedef struct {
  /** Pointer to Unicode scalar values. */
  const uint32_t* ptr;

  /** Number of entries in ptr. */
  size_t len;
} GhosttyCodepoints;

/**
 * Initialize a sized struct to zero and set its size field.
 *
 * Sized structs use a `size` field as the first member for ABI
 * compatibility. This macro zero-initializes the struct and sets the
 * size field to `sizeof(type)`, which allows the library to detect
 * which version of the struct the caller was compiled against.
 *
 * @param type The struct type to initialize
 * @return A zero-initialized struct with the size field set
 *
 * Example:
 * @code
 * GhosttyFormatterTerminalOptions opts = XGHOSTTY_INIT_SIZED(GhosttyFormatterTerminalOptions);
 * opts.emit = XGHOSTTY_FORMATTER_FORMAT_PLAIN;
 * opts.trim = true;
 * @endcode
 */
#define XGHOSTTY_INIT_SIZED(type) \
  ((type){ .size = sizeof(type) })

/**
 * Return a pointer to a null-terminated JSON string describing the
 * layout of every C API struct for the current target.
 *
 * This is primarily useful for language bindings that can't easily
 * set C struct fields and need to do so via byte offsets. For example,
 * WebAssembly modules can't share struct definitions with the host.
 *
 * Example (abbreviated):
 * @code{.json}
 * {
 *   "GhosttyMouseEncoderSize": {
 *     "size": 40,
 *     "align": 8,
 *     "fields": {
 *       "size":           { "offset": 0,  "size": 8, "type": "u64" },
 *       "screen_width":   { "offset": 8,  "size": 4, "type": "u32" },
 *       "screen_height":  { "offset": 12, "size": 4, "type": "u32" },
 *       "cell_width":     { "offset": 16, "size": 4, "type": "u32" },
 *       "cell_height":    { "offset": 20, "size": 4, "type": "u32" },
 *       "padding_top":    { "offset": 24, "size": 4, "type": "u32" },
 *       "padding_bottom": { "offset": 28, "size": 4, "type": "u32" },
 *       "padding_right":  { "offset": 32, "size": 4, "type": "u32" },
 *       "padding_left":   { "offset": 36, "size": 4, "type": "u32" }
 *     }
 *   }
 * }
 * @endcode
 *
 * The returned pointer is valid for the lifetime of the process.
 *
 * @return Pointer to the null-terminated JSON string.
 */
XGHOSTTY_API const char *xghostty_type_json(void);

#endif /* XGHOSTTY_VT_TYPES_H */
