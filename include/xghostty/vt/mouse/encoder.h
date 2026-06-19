/**
 * @file encoder.h
 *
 * Mouse event encoding to terminal escape sequences.
 */

#ifndef XGHOSTTY_VT_MOUSE_ENCODER_H
#define XGHOSTTY_VT_MOUSE_ENCODER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <xghostty/vt/allocator.h>
#include <xghostty/vt/mouse/event.h>
#include <xghostty/vt/terminal.h>
#include <xghostty/vt/types.h>

/**
 * Opaque handle to a mouse encoder instance.
 *
 * This handle represents a mouse encoder that converts normalized
 * mouse events into terminal escape sequences.
 *
 * @ingroup mouse
 */
typedef struct GhosttyMouseEncoderImpl *GhosttyMouseEncoder;

/**
 * Mouse tracking mode.
 *
 * @ingroup mouse
 */
typedef enum XGHOSTTY_ENUM_TYPED {
  /** Mouse reporting disabled. */
  XGHOSTTY_MOUSE_TRACKING_NONE = 0,

  /** X10 mouse mode. */
  XGHOSTTY_MOUSE_TRACKING_X10 = 1,

  /** Normal mouse mode (button press/release only). */
  XGHOSTTY_MOUSE_TRACKING_NORMAL = 2,

  /** Button-event tracking mode. */
  XGHOSTTY_MOUSE_TRACKING_BUTTON = 3,

  /** Any-event tracking mode. */
  XGHOSTTY_MOUSE_TRACKING_ANY = 4,
  XGHOSTTY_MOUSE_TRACKING_MAX_VALUE = XGHOSTTY_ENUM_MAX_VALUE,
} GhosttyMouseTrackingMode;

/**
 * Mouse output format.
 *
 * @ingroup mouse
 */
typedef enum XGHOSTTY_ENUM_TYPED {
  XGHOSTTY_MOUSE_FORMAT_X10 = 0,
  XGHOSTTY_MOUSE_FORMAT_UTF8 = 1,
  XGHOSTTY_MOUSE_FORMAT_SGR = 2,
  XGHOSTTY_MOUSE_FORMAT_URXVT = 3,
  XGHOSTTY_MOUSE_FORMAT_SGR_PIXELS = 4,
  XGHOSTTY_MOUSE_FORMAT_MAX_VALUE = XGHOSTTY_ENUM_MAX_VALUE,
} GhosttyMouseFormat;

/**
 * Mouse encoder size and geometry context.
 *
 * This describes the rendered terminal geometry used to convert
 * surface-space positions into encoded coordinates.
 *
 * @ingroup mouse
 */
typedef struct {
  /** Size of this struct in bytes. Must be set to sizeof(GhosttyMouseEncoderSize). */
  size_t size;

  /** Full screen width in pixels. */
  uint32_t screen_width;

  /** Full screen height in pixels. */
  uint32_t screen_height;

  /** Cell width in pixels. Must be non-zero. */
  uint32_t cell_width;

  /** Cell height in pixels. Must be non-zero. */
  uint32_t cell_height;

  /** Top padding in pixels. */
  uint32_t padding_top;

  /** Bottom padding in pixels. */
  uint32_t padding_bottom;

  /** Right padding in pixels. */
  uint32_t padding_right;

  /** Left padding in pixels. */
  uint32_t padding_left;
} GhosttyMouseEncoderSize;

/**
 * Mouse encoder option identifiers.
 *
 * These values are used with xghostty_mouse_encoder_setopt() to configure
 * the behavior of the mouse encoder.
 *
 * @ingroup mouse
 */
typedef enum XGHOSTTY_ENUM_TYPED {
  /** Mouse tracking mode (value: GhosttyMouseTrackingMode). */
  XGHOSTTY_MOUSE_ENCODER_OPT_EVENT = 0,

  /** Mouse output format (value: GhosttyMouseFormat). */
  XGHOSTTY_MOUSE_ENCODER_OPT_FORMAT = 1,

  /** Renderer size context (value: GhosttyMouseEncoderSize). */
  XGHOSTTY_MOUSE_ENCODER_OPT_SIZE = 2,

  /** Whether any mouse button is currently pressed (value: bool). */
  XGHOSTTY_MOUSE_ENCODER_OPT_ANY_BUTTON_PRESSED = 3,

  /** Whether to enable motion deduplication by last cell (value: bool). */
  XGHOSTTY_MOUSE_ENCODER_OPT_TRACK_LAST_CELL = 4,
  XGHOSTTY_MOUSE_ENCODER_OPT_MAX_VALUE = XGHOSTTY_ENUM_MAX_VALUE,
} GhosttyMouseEncoderOption;

/**
 * Create a new mouse encoder instance.
 *
 * @param allocator Pointer to allocator, or NULL to use the default allocator
 * @param encoder Pointer to store the created encoder handle
 * @return XGHOSTTY_SUCCESS on success, or an error code on failure
 *
 * @ingroup mouse
 */
XGHOSTTY_API GhosttyResult xghostty_mouse_encoder_new(const GhosttyAllocator *allocator,
                                        GhosttyMouseEncoder *encoder);

/**
 * Free a mouse encoder instance.
 *
 * @param encoder The encoder handle to free (may be NULL)
 *
 * @ingroup mouse
 */
XGHOSTTY_API void xghostty_mouse_encoder_free(GhosttyMouseEncoder encoder);

/**
 * Set an option on the mouse encoder.
 *
 * A null pointer value does nothing. It does not reset to defaults.
 *
 * @param encoder The encoder handle, must not be NULL
 * @param option The option to set
 * @param value Pointer to option value (type depends on option)
 *
 * @ingroup mouse
 */
XGHOSTTY_API void xghostty_mouse_encoder_setopt(GhosttyMouseEncoder encoder,
                                  GhosttyMouseEncoderOption option,
                                  const void *value);

/**
 * Set encoder options from a terminal's current state.
 *
 * This sets tracking mode and output format from terminal state.
 * It does not modify size or any-button state.
 *
 * @param encoder The encoder handle, must not be NULL
 * @param terminal The terminal handle, must not be NULL
 *
 * @ingroup mouse
 */
XGHOSTTY_API void xghostty_mouse_encoder_setopt_from_terminal(GhosttyMouseEncoder encoder,
                                                GhosttyTerminal terminal);

/**
 * Reset internal encoder state.
 *
 * This clears motion deduplication state (last tracked cell).
 *
 * @param encoder The encoder handle (may be NULL)
 *
 * @ingroup mouse
 */
XGHOSTTY_API void xghostty_mouse_encoder_reset(GhosttyMouseEncoder encoder);

/**
 * Encode a mouse event into a terminal escape sequence.
 *
 * Not all mouse events produce output. In such cases this returns
 * XGHOSTTY_SUCCESS with out_len set to 0.
 *
 * If the output buffer is too small, this returns XGHOSTTY_OUT_OF_SPACE
 * and out_len contains the required size.
 *
 * @param encoder The encoder handle, must not be NULL
 * @param event The mouse event to encode, must not be NULL
 * @param out_buf Buffer to write encoded bytes to, or NULL to query required size
 * @param out_buf_size Size of out_buf in bytes
 * @param out_len Pointer to store bytes written (or required bytes on failure)
 * @return XGHOSTTY_SUCCESS on success, XGHOSTTY_OUT_OF_SPACE if buffer is too small,
 *         or another error code
 *
 * @ingroup mouse
 */
XGHOSTTY_API GhosttyResult xghostty_mouse_encoder_encode(GhosttyMouseEncoder encoder,
                                           GhosttyMouseEvent event,
                                           char *out_buf,
                                           size_t out_buf_size,
                                           size_t *out_len);

#endif /* XGHOSTTY_VT_MOUSE_ENCODER_H */
