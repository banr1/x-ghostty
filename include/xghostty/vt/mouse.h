/**
 * @file mouse.h
 *
 * Mouse encoding module - encode mouse events into terminal escape sequences.
 */

#ifndef XGHOSTTY_VT_MOUSE_H
#define XGHOSTTY_VT_MOUSE_H

/** @defgroup mouse Mouse Encoding
 *
 * Utilities for encoding mouse events into terminal escape sequences,
 * supporting X10, UTF-8, SGR, URxvt, and SGR-Pixels mouse protocols.
 *
 * ## Basic Usage
 *
 * 1. Create an encoder instance with xghostty_mouse_encoder_new().
 * 2. Configure encoder options with xghostty_mouse_encoder_setopt() or
 *    xghostty_mouse_encoder_setopt_from_terminal().
 * 3. For each mouse event:
 *    - Create a mouse event with xghostty_mouse_event_new().
 *    - Set event properties (action, button, modifiers, position).
 *    - Encode with xghostty_mouse_encoder_encode().
 *    - Free the event with xghostty_mouse_event_free() or reuse it.
 * 4. Free the encoder with xghostty_mouse_encoder_free() when done.
 *
 * For a complete working example, see example/c-vt-encode-mouse in the
 * repository.
 *
 * ## Example
 *
 * @snippet c-vt-encode-mouse/src/main.c mouse-encode
 *
 * ## Example: Encoding with Terminal State
 *
 * When you have a GhosttyTerminal, you can sync its tracking mode and
 * output format into the encoder automatically:
 *
 * @code{.c}
 * // Create a terminal and feed it some VT data that enables mouse tracking
 * GhosttyTerminal terminal;
 * xghostty_terminal_new(NULL, &terminal,
 *     (GhosttyTerminalOptions){.cols = 80, .rows = 24, .max_scrollback = 0});
 *
 * // Application might write data that enables mouse reporting, etc.
 * xghostty_terminal_vt_write(terminal, vt_data, vt_len);
 *
 * // Create an encoder and sync its options from the terminal
 * GhosttyMouseEncoder encoder;
 * xghostty_mouse_encoder_new(NULL, &encoder);
 * xghostty_mouse_encoder_setopt_from_terminal(encoder, terminal);
 *
 * // Encode a mouse event using the terminal-derived options
 * char buf[128];
 * size_t written = 0;
 * xghostty_mouse_encoder_encode(encoder, event, buf, sizeof(buf), &written);
 *
 * xghostty_mouse_encoder_free(encoder);
 * xghostty_terminal_free(terminal);
 * @endcode
 *
 * @{
 */

#include <xghostty/vt/mouse/event.h>
#include <xghostty/vt/mouse/encoder.h>

/** @} */

#endif /* XGHOSTTY_VT_MOUSE_H */
