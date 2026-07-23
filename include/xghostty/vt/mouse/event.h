/**
 * @file event.h
 *
 * Mouse event representation and manipulation.
 */

#ifndef XGHOSTTY_VT_MOUSE_EVENT_H
#define XGHOSTTY_VT_MOUSE_EVENT_H

#include <stdbool.h>
#include <xghostty/vt/allocator.h>
#include <xghostty/vt/key/event.h>
#include <xghostty/vt/types.h>

/**
 * Opaque handle to a mouse event.
 *
 * This handle represents a normalized mouse input event containing
 * action, button, modifiers, and surface-space position.
 *
 * @ingroup mouse
 */
typedef struct XGhosttyMouseEventImpl *XGhosttyMouseEvent;

/**
 * Mouse event action type.
 *
 * @ingroup mouse
 */
typedef enum XGHOSTTY_ENUM_TYPED {
  /** Mouse button was pressed. */
  XGHOSTTY_MOUSE_ACTION_PRESS = 0,

  /** Mouse button was released. */
  XGHOSTTY_MOUSE_ACTION_RELEASE = 1,

  /** Mouse moved. */
  XGHOSTTY_MOUSE_ACTION_MOTION = 2,
  XGHOSTTY_MOUSE_ACTION_MAX_VALUE = XGHOSTTY_ENUM_MAX_VALUE,
} XGhosttyMouseAction;

/**
 * Mouse button identity.
 *
 * @ingroup mouse
 */
typedef enum XGHOSTTY_ENUM_TYPED {
  XGHOSTTY_MOUSE_BUTTON_UNKNOWN = 0,
  XGHOSTTY_MOUSE_BUTTON_LEFT = 1,
  XGHOSTTY_MOUSE_BUTTON_RIGHT = 2,
  XGHOSTTY_MOUSE_BUTTON_MIDDLE = 3,
  XGHOSTTY_MOUSE_BUTTON_FOUR = 4,
  XGHOSTTY_MOUSE_BUTTON_FIVE = 5,
  XGHOSTTY_MOUSE_BUTTON_SIX = 6,
  XGHOSTTY_MOUSE_BUTTON_SEVEN = 7,
  XGHOSTTY_MOUSE_BUTTON_EIGHT = 8,
  XGHOSTTY_MOUSE_BUTTON_NINE = 9,
  XGHOSTTY_MOUSE_BUTTON_TEN = 10,
  XGHOSTTY_MOUSE_BUTTON_ELEVEN = 11,
  XGHOSTTY_MOUSE_BUTTON_MAX_VALUE = XGHOSTTY_ENUM_MAX_VALUE,
} XGhosttyMouseButton;

/**
 * Mouse position in surface-space pixels.
 *
 * @ingroup mouse
 */
typedef struct {
  float x;
  float y;
} XGhosttyMousePosition;

/**
 * Create a new mouse event instance.
 *
 * @param allocator Pointer to allocator, or NULL to use the default allocator
 * @param event Pointer to store the created event handle
 * @return XGHOSTTY_SUCCESS on success, or an error code on failure
 *
 * @ingroup mouse
 */
XGHOSTTY_API XGhosttyResult xghostty_mouse_event_new(const XGhosttyAllocator *allocator,
                                      XGhosttyMouseEvent *event);

/**
 * Free a mouse event instance.
 *
 * @param event The mouse event handle to free (may be NULL)
 *
 * @ingroup mouse
 */
XGHOSTTY_API void xghostty_mouse_event_free(XGhosttyMouseEvent event);

/**
 * Set the event action.
 *
 * @param event The event handle, must not be NULL
 * @param action The action to set
 *
 * @ingroup mouse
 */
XGHOSTTY_API void xghostty_mouse_event_set_action(XGhosttyMouseEvent event,
                                    XGhosttyMouseAction action);

/**
 * Get the event action.
 *
 * @param event The event handle, must not be NULL
 * @return The event action
 *
 * @ingroup mouse
 */
XGHOSTTY_API XGhosttyMouseAction xghostty_mouse_event_get_action(XGhosttyMouseEvent event);

/**
 * Set the event button.
 *
 * This sets a concrete button identity for the event.
 * To represent "no button" (for motion events), use
 * xghostty_mouse_event_clear_button().
 *
 * @param event The event handle, must not be NULL
 * @param button The button to set
 *
 * @ingroup mouse
 */
XGHOSTTY_API void xghostty_mouse_event_set_button(XGhosttyMouseEvent event,
                                    XGhosttyMouseButton button);

/**
 * Clear the event button.
 *
 * This sets the event button to "none".
 *
 * @param event The event handle, must not be NULL
 *
 * @ingroup mouse
 */
XGHOSTTY_API void xghostty_mouse_event_clear_button(XGhosttyMouseEvent event);

/**
 * Get the event button.
 *
 * @param event The event handle, must not be NULL
 * @param out_button Output pointer for the button value (may be NULL)
 * @return true if a button is set, false if no button is set
 *
 * @ingroup mouse
 */
XGHOSTTY_API bool xghostty_mouse_event_get_button(XGhosttyMouseEvent event,
                                    XGhosttyMouseButton *out_button);

/**
 * Set keyboard modifiers held during the event.
 *
 * @param event The event handle, must not be NULL
 * @param mods Modifier bitmask
 *
 * @ingroup mouse
 */
XGHOSTTY_API void xghostty_mouse_event_set_mods(XGhosttyMouseEvent event,
                                  XGhosttyMods mods);

/**
 * Get keyboard modifiers held during the event.
 *
 * @param event The event handle, must not be NULL
 * @return Modifier bitmask
 *
 * @ingroup mouse
 */
XGHOSTTY_API XGhosttyMods xghostty_mouse_event_get_mods(XGhosttyMouseEvent event);

/**
 * Set the event position in surface-space pixels.
 *
 * @param event The event handle, must not be NULL
 * @param position The position to set
 *
 * @ingroup mouse
 */
XGHOSTTY_API void xghostty_mouse_event_set_position(XGhosttyMouseEvent event,
                                      XGhosttyMousePosition position);

/**
 * Get the event position in surface-space pixels.
 *
 * @param event The event handle, must not be NULL
 * @return The current event position
 *
 * @ingroup mouse
 */
XGHOSTTY_API XGhosttyMousePosition xghostty_mouse_event_get_position(XGhosttyMouseEvent event);

#endif /* XGHOSTTY_VT_MOUSE_EVENT_H */
