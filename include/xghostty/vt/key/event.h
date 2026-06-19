/**
 * @file event.h
 *
 * Key event representation and manipulation.
 */

#ifndef XGHOSTTY_VT_KEY_EVENT_H
#define XGHOSTTY_VT_KEY_EVENT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <xghostty/vt/types.h>
#include <xghostty/vt/allocator.h>

/**
 * Opaque handle to a key event.
 * 
 * This handle represents a keyboard input event containing information about
 * the physical key pressed, modifiers, and generated text.
 *
 * @ingroup key
 */
typedef struct GhosttyKeyEventImpl *GhosttyKeyEvent;

/**
 * Keyboard input event types.
 *
 * @ingroup key
 */
typedef enum XGHOSTTY_ENUM_TYPED {
    /** Key was released */
    XGHOSTTY_KEY_ACTION_RELEASE = 0,
    /** Key was pressed */
    XGHOSTTY_KEY_ACTION_PRESS = 1,
    /** Key is being repeated (held down) */
    XGHOSTTY_KEY_ACTION_REPEAT = 2,
    XGHOSTTY_KEY_ACTION_MAX_VALUE = XGHOSTTY_ENUM_MAX_VALUE,
} GhosttyKeyAction;

/**
 * Keyboard modifier keys bitmask.
 *
 * A bitmask representing all keyboard modifiers. This tracks which modifier keys 
 * are pressed and, where supported by the platform, which side (left or right) 
 * of each modifier is active.
 *
 * Use the XGHOSTTY_MODS_* constants to test and set individual modifiers.
 *
 * Modifier side bits are only meaningful when the corresponding modifier bit is set.
 * Not all platforms support distinguishing between left and right modifier 
 * keys and XGhostty is built to expect that some platforms may not provide this
 * information.
 *
 * @ingroup key
 */
typedef uint16_t GhosttyMods;

/** Shift key is pressed */
#define XGHOSTTY_MODS_SHIFT (1 << 0)
/** Control key is pressed */
#define XGHOSTTY_MODS_CTRL (1 << 1)
/** Alt/Option key is pressed */
#define XGHOSTTY_MODS_ALT (1 << 2)
/** Super/Command/Windows key is pressed */
#define XGHOSTTY_MODS_SUPER (1 << 3)
/** Caps Lock is active */
#define XGHOSTTY_MODS_CAPS_LOCK (1 << 4)
/** Num Lock is active */
#define XGHOSTTY_MODS_NUM_LOCK (1 << 5)

/**
 * Right shift is pressed (0 = left, 1 = right).
 * Only meaningful when XGHOSTTY_MODS_SHIFT is set.
 */
#define XGHOSTTY_MODS_SHIFT_SIDE (1 << 6)
/**
 * Right ctrl is pressed (0 = left, 1 = right).
 * Only meaningful when XGHOSTTY_MODS_CTRL is set.
 */
#define XGHOSTTY_MODS_CTRL_SIDE (1 << 7)
/**
 * Right alt is pressed (0 = left, 1 = right).
 * Only meaningful when XGHOSTTY_MODS_ALT is set.
 */
#define XGHOSTTY_MODS_ALT_SIDE (1 << 8)
/**
 * Right super is pressed (0 = left, 1 = right).
 * Only meaningful when XGHOSTTY_MODS_SUPER is set.
 */
#define XGHOSTTY_MODS_SUPER_SIDE (1 << 9)

/**
 * Physical key codes.
 *
 * The set of key codes that XGhostty is aware of. These represent physical keys 
 * on the keyboard and are layout-independent. For example, the "a" key on a US 
 * keyboard is the same as the "ф" key on a Russian keyboard, but both will 
 * report the same key_a value.
 *
 * Layout-dependent strings are provided separately as UTF-8 text and are produced 
 * by the platform. These values are based on the W3C UI Events KeyboardEvent code 
 * standard. See: https://www.w3.org/TR/uievents-code
 *
 * @ingroup key
 */
typedef enum XGHOSTTY_ENUM_TYPED {
    XGHOSTTY_KEY_UNIDENTIFIED = 0,

    // Writing System Keys (W3C § 3.1.1)
    XGHOSTTY_KEY_BACKQUOTE,
    XGHOSTTY_KEY_BACKSLASH,
    XGHOSTTY_KEY_BRACKET_LEFT,
    XGHOSTTY_KEY_BRACKET_RIGHT,
    XGHOSTTY_KEY_COMMA,
    XGHOSTTY_KEY_DIGIT_0,
    XGHOSTTY_KEY_DIGIT_1,
    XGHOSTTY_KEY_DIGIT_2,
    XGHOSTTY_KEY_DIGIT_3,
    XGHOSTTY_KEY_DIGIT_4,
    XGHOSTTY_KEY_DIGIT_5,
    XGHOSTTY_KEY_DIGIT_6,
    XGHOSTTY_KEY_DIGIT_7,
    XGHOSTTY_KEY_DIGIT_8,
    XGHOSTTY_KEY_DIGIT_9,
    XGHOSTTY_KEY_EQUAL,
    XGHOSTTY_KEY_INTL_BACKSLASH,
    XGHOSTTY_KEY_INTL_RO,
    XGHOSTTY_KEY_INTL_YEN,
    XGHOSTTY_KEY_A,
    XGHOSTTY_KEY_B,
    XGHOSTTY_KEY_C,
    XGHOSTTY_KEY_D,
    XGHOSTTY_KEY_E,
    XGHOSTTY_KEY_F,
    XGHOSTTY_KEY_G,
    XGHOSTTY_KEY_H,
    XGHOSTTY_KEY_I,
    XGHOSTTY_KEY_J,
    XGHOSTTY_KEY_K,
    XGHOSTTY_KEY_L,
    XGHOSTTY_KEY_M,
    XGHOSTTY_KEY_N,
    XGHOSTTY_KEY_O,
    XGHOSTTY_KEY_P,
    XGHOSTTY_KEY_Q,
    XGHOSTTY_KEY_R,
    XGHOSTTY_KEY_S,
    XGHOSTTY_KEY_T,
    XGHOSTTY_KEY_U,
    XGHOSTTY_KEY_V,
    XGHOSTTY_KEY_W,
    XGHOSTTY_KEY_X,
    XGHOSTTY_KEY_Y,
    XGHOSTTY_KEY_Z,
    XGHOSTTY_KEY_MINUS,
    XGHOSTTY_KEY_PERIOD,
    XGHOSTTY_KEY_QUOTE,
    XGHOSTTY_KEY_SEMICOLON,
    XGHOSTTY_KEY_SLASH,

    // Functional Keys (W3C § 3.1.2)
    XGHOSTTY_KEY_ALT_LEFT,
    XGHOSTTY_KEY_ALT_RIGHT,
    XGHOSTTY_KEY_BACKSPACE,
    XGHOSTTY_KEY_CAPS_LOCK,
    XGHOSTTY_KEY_CONTEXT_MENU,
    XGHOSTTY_KEY_CONTROL_LEFT,
    XGHOSTTY_KEY_CONTROL_RIGHT,
    XGHOSTTY_KEY_ENTER,
    XGHOSTTY_KEY_META_LEFT,
    XGHOSTTY_KEY_META_RIGHT,
    XGHOSTTY_KEY_SHIFT_LEFT,
    XGHOSTTY_KEY_SHIFT_RIGHT,
    XGHOSTTY_KEY_SPACE,
    XGHOSTTY_KEY_TAB,
    XGHOSTTY_KEY_CONVERT,
    XGHOSTTY_KEY_KANA_MODE,
    XGHOSTTY_KEY_NON_CONVERT,

    // Control Pad Section (W3C § 3.2)
    XGHOSTTY_KEY_DELETE,
    XGHOSTTY_KEY_END,
    XGHOSTTY_KEY_HELP,
    XGHOSTTY_KEY_HOME,
    XGHOSTTY_KEY_INSERT,
    XGHOSTTY_KEY_PAGE_DOWN,
    XGHOSTTY_KEY_PAGE_UP,

    // Arrow Pad Section (W3C § 3.3)
    XGHOSTTY_KEY_ARROW_DOWN,
    XGHOSTTY_KEY_ARROW_LEFT,
    XGHOSTTY_KEY_ARROW_RIGHT,
    XGHOSTTY_KEY_ARROW_UP,

    // Numpad Section (W3C § 3.4)
    XGHOSTTY_KEY_NUM_LOCK,
    XGHOSTTY_KEY_NUMPAD_0,
    XGHOSTTY_KEY_NUMPAD_1,
    XGHOSTTY_KEY_NUMPAD_2,
    XGHOSTTY_KEY_NUMPAD_3,
    XGHOSTTY_KEY_NUMPAD_4,
    XGHOSTTY_KEY_NUMPAD_5,
    XGHOSTTY_KEY_NUMPAD_6,
    XGHOSTTY_KEY_NUMPAD_7,
    XGHOSTTY_KEY_NUMPAD_8,
    XGHOSTTY_KEY_NUMPAD_9,
    XGHOSTTY_KEY_NUMPAD_ADD,
    XGHOSTTY_KEY_NUMPAD_BACKSPACE,
    XGHOSTTY_KEY_NUMPAD_CLEAR,
    XGHOSTTY_KEY_NUMPAD_CLEAR_ENTRY,
    XGHOSTTY_KEY_NUMPAD_COMMA,
    XGHOSTTY_KEY_NUMPAD_DECIMAL,
    XGHOSTTY_KEY_NUMPAD_DIVIDE,
    XGHOSTTY_KEY_NUMPAD_ENTER,
    XGHOSTTY_KEY_NUMPAD_EQUAL,
    XGHOSTTY_KEY_NUMPAD_MEMORY_ADD,
    XGHOSTTY_KEY_NUMPAD_MEMORY_CLEAR,
    XGHOSTTY_KEY_NUMPAD_MEMORY_RECALL,
    XGHOSTTY_KEY_NUMPAD_MEMORY_STORE,
    XGHOSTTY_KEY_NUMPAD_MEMORY_SUBTRACT,
    XGHOSTTY_KEY_NUMPAD_MULTIPLY,
    XGHOSTTY_KEY_NUMPAD_PAREN_LEFT,
    XGHOSTTY_KEY_NUMPAD_PAREN_RIGHT,
    XGHOSTTY_KEY_NUMPAD_SUBTRACT,
    XGHOSTTY_KEY_NUMPAD_SEPARATOR,
    XGHOSTTY_KEY_NUMPAD_UP,
    XGHOSTTY_KEY_NUMPAD_DOWN,
    XGHOSTTY_KEY_NUMPAD_RIGHT,
    XGHOSTTY_KEY_NUMPAD_LEFT,
    XGHOSTTY_KEY_NUMPAD_BEGIN,
    XGHOSTTY_KEY_NUMPAD_HOME,
    XGHOSTTY_KEY_NUMPAD_END,
    XGHOSTTY_KEY_NUMPAD_INSERT,
    XGHOSTTY_KEY_NUMPAD_DELETE,
    XGHOSTTY_KEY_NUMPAD_PAGE_UP,
    XGHOSTTY_KEY_NUMPAD_PAGE_DOWN,

    // Function Section (W3C § 3.5)
    XGHOSTTY_KEY_ESCAPE,
    XGHOSTTY_KEY_F1,
    XGHOSTTY_KEY_F2,
    XGHOSTTY_KEY_F3,
    XGHOSTTY_KEY_F4,
    XGHOSTTY_KEY_F5,
    XGHOSTTY_KEY_F6,
    XGHOSTTY_KEY_F7,
    XGHOSTTY_KEY_F8,
    XGHOSTTY_KEY_F9,
    XGHOSTTY_KEY_F10,
    XGHOSTTY_KEY_F11,
    XGHOSTTY_KEY_F12,
    XGHOSTTY_KEY_F13,
    XGHOSTTY_KEY_F14,
    XGHOSTTY_KEY_F15,
    XGHOSTTY_KEY_F16,
    XGHOSTTY_KEY_F17,
    XGHOSTTY_KEY_F18,
    XGHOSTTY_KEY_F19,
    XGHOSTTY_KEY_F20,
    XGHOSTTY_KEY_F21,
    XGHOSTTY_KEY_F22,
    XGHOSTTY_KEY_F23,
    XGHOSTTY_KEY_F24,
    XGHOSTTY_KEY_F25,
    XGHOSTTY_KEY_FN,
    XGHOSTTY_KEY_FN_LOCK,
    XGHOSTTY_KEY_PRINT_SCREEN,
    XGHOSTTY_KEY_SCROLL_LOCK,
    XGHOSTTY_KEY_PAUSE,

    // Media Keys (W3C § 3.6)
    XGHOSTTY_KEY_BROWSER_BACK,
    XGHOSTTY_KEY_BROWSER_FAVORITES,
    XGHOSTTY_KEY_BROWSER_FORWARD,
    XGHOSTTY_KEY_BROWSER_HOME,
    XGHOSTTY_KEY_BROWSER_REFRESH,
    XGHOSTTY_KEY_BROWSER_SEARCH,
    XGHOSTTY_KEY_BROWSER_STOP,
    XGHOSTTY_KEY_EJECT,
    XGHOSTTY_KEY_LAUNCH_APP_1,
    XGHOSTTY_KEY_LAUNCH_APP_2,
    XGHOSTTY_KEY_LAUNCH_MAIL,
    XGHOSTTY_KEY_MEDIA_PLAY_PAUSE,
    XGHOSTTY_KEY_MEDIA_SELECT,
    XGHOSTTY_KEY_MEDIA_STOP,
    XGHOSTTY_KEY_MEDIA_TRACK_NEXT,
    XGHOSTTY_KEY_MEDIA_TRACK_PREVIOUS,
    XGHOSTTY_KEY_POWER,
    XGHOSTTY_KEY_SLEEP,
    XGHOSTTY_KEY_AUDIO_VOLUME_DOWN,
    XGHOSTTY_KEY_AUDIO_VOLUME_MUTE,
    XGHOSTTY_KEY_AUDIO_VOLUME_UP,
    XGHOSTTY_KEY_WAKE_UP,

    // Legacy, Non-standard, and Special Keys (W3C § 3.7)
    XGHOSTTY_KEY_COPY,
    XGHOSTTY_KEY_CUT,
    XGHOSTTY_KEY_PASTE,
    XGHOSTTY_KEY_MAX_VALUE = XGHOSTTY_ENUM_MAX_VALUE,
} GhosttyKey;

/**
 * Create a new key event instance.
 * 
 * Creates a new key event with default values. The event must be freed using
 * xghostty_key_event_free() when no longer needed.
 * 
 * @param allocator Pointer to the allocator to use for memory management, or NULL to use the default allocator
 * @param event Pointer to store the created key event handle
 * @return XGHOSTTY_SUCCESS on success, or an error code on failure
 * 
 * @ingroup key
 */
XGHOSTTY_API GhosttyResult xghostty_key_event_new(const GhosttyAllocator *allocator, GhosttyKeyEvent *event);

/**
 * Free a key event instance.
 * 
 * Releases all resources associated with the key event. After this call,
 * the event handle becomes invalid and must not be used.
 * 
 * @param event The key event handle to free (may be NULL)
 * 
 * @ingroup key
 */
XGHOSTTY_API void xghostty_key_event_free(GhosttyKeyEvent event);

/**
 * Set the key action (press, release, repeat).
 *
 * @param event The key event handle, must not be NULL
 * @param action The action to set
 *
 * @ingroup key
 */
XGHOSTTY_API void xghostty_key_event_set_action(GhosttyKeyEvent event, GhosttyKeyAction action);

/**
 * Get the key action (press, release, repeat).
 *
 * @param event The key event handle, must not be NULL
 * @return The key action
 *
 * @ingroup key
 */
XGHOSTTY_API GhosttyKeyAction xghostty_key_event_get_action(GhosttyKeyEvent event);

/**
 * Set the physical key code.
 *
 * @param event The key event handle, must not be NULL
 * @param key The physical key code to set
 *
 * @ingroup key
 */
XGHOSTTY_API void xghostty_key_event_set_key(GhosttyKeyEvent event, GhosttyKey key);

/**
 * Get the physical key code.
 *
 * @param event The key event handle, must not be NULL
 * @return The physical key code
 *
 * @ingroup key
 */
XGHOSTTY_API GhosttyKey xghostty_key_event_get_key(GhosttyKeyEvent event);

/**
 * Set the modifier keys bitmask.
 *
 * @param event The key event handle, must not be NULL
 * @param mods The modifier keys bitmask to set
 *
 * @ingroup key
 */
XGHOSTTY_API void xghostty_key_event_set_mods(GhosttyKeyEvent event, GhosttyMods mods);

/**
 * Get the modifier keys bitmask.
 *
 * @param event The key event handle, must not be NULL
 * @return The modifier keys bitmask
 *
 * @ingroup key
 */
XGHOSTTY_API GhosttyMods xghostty_key_event_get_mods(GhosttyKeyEvent event);

/**
 * Set the consumed modifiers bitmask.
 *
 * @param event The key event handle, must not be NULL
 * @param consumed_mods The consumed modifiers bitmask to set
 *
 * @ingroup key
 */
XGHOSTTY_API void xghostty_key_event_set_consumed_mods(GhosttyKeyEvent event, GhosttyMods consumed_mods);

/**
 * Get the consumed modifiers bitmask.
 *
 * @param event The key event handle, must not be NULL
 * @return The consumed modifiers bitmask
 *
 * @ingroup key
 */
XGHOSTTY_API GhosttyMods xghostty_key_event_get_consumed_mods(GhosttyKeyEvent event);

/**
 * Set whether the key event is part of a composition sequence.
 *
 * @param event The key event handle, must not be NULL
 * @param composing Whether the key event is part of a composition sequence
 *
 * @ingroup key
 */
XGHOSTTY_API void xghostty_key_event_set_composing(GhosttyKeyEvent event, bool composing);

/**
 * Get whether the key event is part of a composition sequence.
 *
 * @param event The key event handle, must not be NULL
 * @return Whether the key event is part of a composition sequence
 *
 * @ingroup key
 */
XGHOSTTY_API bool xghostty_key_event_get_composing(GhosttyKeyEvent event);

/**
 * Set the UTF-8 text generated by the key for the current keyboard layout.
 *
 * Must contain the unmodified character before any Ctrl/Meta transformations.
 * The encoder derives modifier sequences from the logical key and mods
 * bitmask, not from this text. Do not pass C0 control characters
 * (U+0000-U+001F, U+007F) or platform function key codes (e.g. macOS PUA
 * U+F700-U+F8FF); pass NULL instead and let the encoder use the logical key.
 *
 * The key event does NOT take ownership of the text pointer. The caller
 * must ensure the string remains valid for the lifetime needed by the event.
 *
 * @param event The key event handle, must not be NULL
 * @param utf8 The UTF-8 text to set (or NULL for empty)
 * @param len Length of the UTF-8 text in bytes
 *
 * @ingroup key
 */
XGHOSTTY_API void xghostty_key_event_set_utf8(GhosttyKeyEvent event, const char *utf8, size_t len);

/**
 * Get the UTF-8 text generated by the key event.
 *
 * The returned pointer is valid until the event is freed or the UTF-8 text is modified.
 *
 * @param event The key event handle, must not be NULL
 * @param len Pointer to store the length of the UTF-8 text in bytes (may be NULL)
 * @return The UTF-8 text (or NULL for empty)
 *
 * @ingroup key
 */
XGHOSTTY_API const char *xghostty_key_event_get_utf8(GhosttyKeyEvent event, size_t *len);

/**
 * Set the unshifted Unicode codepoint.
 *
 * @param event The key event handle, must not be NULL
 * @param codepoint The unshifted Unicode codepoint to set
 *
 * @ingroup key
 */
XGHOSTTY_API void xghostty_key_event_set_unshifted_codepoint(GhosttyKeyEvent event, uint32_t codepoint);

/**
 * Get the unshifted Unicode codepoint.
 *
 * @param event The key event handle, must not be NULL
 * @return The unshifted Unicode codepoint
 *
 * @ingroup key
 */
XGHOSTTY_API uint32_t xghostty_key_event_get_unshifted_codepoint(GhosttyKeyEvent event);

#endif /* XGHOSTTY_VT_KEY_EVENT_H */
