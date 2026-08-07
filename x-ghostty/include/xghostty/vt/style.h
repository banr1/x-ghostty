/**
 * @file style.h
 *
 * Terminal cell style types.
 */

#ifndef XGHOSTTY_VT_STYLE_H
#define XGHOSTTY_VT_STYLE_H

#include <xghostty/vt/color.h>
#include <xghostty/vt/types.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** @defgroup style Style
 *
 * Terminal cell style attributes.
 *
 * A style describes the visual attributes of a terminal cell, including
 * foreground, background, and underline colors, as well as flags for
 * bold, italic, underline, and other text decorations.
 *
 * @{
 */

/**
 * Style identifier type.
 *
 * Used to look up the full style from a grid reference.
 * Obtain this from a cell via XGHOSTTY_CELL_DATA_STYLE_ID.
 *
 * @ingroup style
 */
typedef uint16_t XGhosttyStyleId;

/**
 * Style color tags.
 *
 * These values identify the type of color in a style color.
 * Use the tag to determine which field in the color value union to access.
 *
 * @ingroup style
 */
typedef enum XGHOSTTY_ENUM_TYPED {
  XGHOSTTY_STYLE_COLOR_NONE = 0,
  XGHOSTTY_STYLE_COLOR_PALETTE = 1,
  XGHOSTTY_STYLE_COLOR_RGB = 2,
  XGHOSTTY_STYLE_COLOR_TAG_MAX_VALUE = XGHOSTTY_ENUM_MAX_VALUE,
  } XGhosttyStyleColorTag;

/**
 * Style color value union.
 *
 * Use the tag to determine which field is active.
 *
 * @ingroup style
 */
typedef union {
  XGhosttyColorPaletteIndex palette;
  XGhosttyColorRgb rgb;
  uint64_t _padding;
} XGhosttyStyleColorValue;

/**
 * Style color (tagged union).
 *
 * A color used in a style attribute. Can be unset (none), a palette
 * index, or a direct RGB value.
 *
 * @ingroup style
 */
typedef struct {
  XGhosttyStyleColorTag tag;
  XGhosttyStyleColorValue value;
} XGhosttyStyleColor;

/**
 * Terminal cell style.
 *
 * Describes the complete visual style for a terminal cell, including
 * foreground, background, and underline colors, as well as text
 * decoration flags. The underline field uses the same values as
 * XGhosttySgrUnderline.
 *
 * This is a sized struct. Use XGHOSTTY_INIT_SIZED() to initialize it.
 *
 * @ingroup style
 */
typedef struct {
  size_t size;
  XGhosttyStyleColor fg_color;
  XGhosttyStyleColor bg_color;
  XGhosttyStyleColor underline_color;
  bool bold;
  bool italic;
  bool faint;
  bool blink;
  bool inverse;
  bool invisible;
  bool strikethrough;
  bool overline;
  int underline; /**< One of XGHOSTTY_SGR_UNDERLINE_* values */
} XGhosttyStyle;

/**
 * Get the default style.
 *
 * Initializes the style to the default values (no colors, no flags).
 *
 * @param style Pointer to the style to initialize
 *
 * @ingroup style
 */
XGHOSTTY_API void xghostty_style_default(XGhosttyStyle* style);

/**
 * Check if a style is the default style.
 *
 * Returns true if all colors are unset and all flags are off.
 *
 * @param style Pointer to the style to check
 * @return true if the style is the default style
 *
 * @ingroup style
 */
XGHOSTTY_API bool xghostty_style_is_default(const XGhosttyStyle* style);

#ifdef __cplusplus
}
#endif

/** @} */

#endif /* XGHOSTTY_VT_STYLE_H */
