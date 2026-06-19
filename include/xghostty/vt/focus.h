/**
 * @file focus.h
 *
 * Focus encoding - encode focus in/out events into terminal escape sequences.
 */

#ifndef XGHOSTTY_VT_FOCUS_H
#define XGHOSTTY_VT_FOCUS_H

/** @defgroup focus Focus Encoding
 *
 * Utilities for encoding focus gained/lost events into terminal escape
 * sequences (CSI I / CSI O) for focus reporting mode (mode 1004).
 *
 * ## Basic Usage
 *
 * Use xghostty_focus_encode() to encode a focus event into a caller-provided
 * buffer. If the buffer is too small, the function returns
 * XGHOSTTY_OUT_OF_SPACE and sets the required size in the output parameter.
 *
 * ## Example
 *
 * @snippet c-vt-encode-focus/src/main.c focus-encode
 *
 * @{
 */

#include <stddef.h>
#include <xghostty/vt/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Focus event types for focus reporting mode (mode 1004).
 */
typedef enum XGHOSTTY_ENUM_TYPED {
    /** Terminal window gained focus */
    XGHOSTTY_FOCUS_GAINED = 0,
    /** Terminal window lost focus */
    XGHOSTTY_FOCUS_LOST = 1,
    XGHOSTTY_FOCUS_MAX_VALUE = XGHOSTTY_ENUM_MAX_VALUE,
} GhosttyFocusEvent;

/**
 * Encode a focus event into a terminal escape sequence.
 *
 * Encodes a focus gained (CSI I) or focus lost (CSI O) report into the
 * provided buffer.
 *
 * If the buffer is too small, the function returns XGHOSTTY_OUT_OF_SPACE
 * and writes the required buffer size to @p out_written. The caller can
 * then retry with a sufficiently sized buffer.
 *
 * @param event The focus event to encode
 * @param buf Output buffer to write the encoded sequence into (may be NULL)
 * @param buf_len Size of the output buffer in bytes
 * @param[out] out_written On success, the number of bytes written. On
 *             XGHOSTTY_OUT_OF_SPACE, the required buffer size.
 * @return XGHOSTTY_SUCCESS on success, XGHOSTTY_OUT_OF_SPACE if the buffer
 *         is too small
 */
XGHOSTTY_API GhosttyResult xghostty_focus_encode(
    GhosttyFocusEvent event,
    char* buf,
    size_t buf_len,
    size_t* out_written);

#ifdef __cplusplus
}
#endif

/** @} */

#endif /* XGHOSTTY_VT_FOCUS_H */
