// XGhostty embedding API. The documentation for the embedding API is
// only within the Zig source files that define the implementations. This
// isn't meant to be a general purpose embedding API (yet) so there hasn't
// been documentation or example work beyond that.
//
// The only consumer of this API is the macOS app, but the API is built to
// be more general purpose.
#ifndef XGHOSTTY_H
#define XGHOSTTY_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef _MSC_VER
#include <BaseTsd.h>
typedef SSIZE_T ssize_t;
#else
#include <sys/types.h>
#endif

//-------------------------------------------------------------------
// Macros

#define XGHOSTTY_SUCCESS 0

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

//-------------------------------------------------------------------
// Types

// Opaque types
typedef void* xghostty_app_t;
typedef void* xghostty_config_t;
typedef void* xghostty_surface_t;
typedef void* xghostty_inspector_t;

// All the types below are fully defined and must be kept in sync with
// their Zig counterparts. Any changes to these types MUST have an associated
// Zig change.
typedef enum {
  XGHOSTTY_PLATFORM_INVALID,
  XGHOSTTY_PLATFORM_MACOS,
  XGHOSTTY_PLATFORM_IOS,
} xghostty_platform_e;

typedef enum {
  XGHOSTTY_CLIPBOARD_STANDARD,
  XGHOSTTY_CLIPBOARD_SELECTION,
} xghostty_clipboard_e;

typedef struct {
  const char *mime;
  const char *data;
} xghostty_clipboard_content_s;

typedef enum {
  XGHOSTTY_CLIPBOARD_REQUEST_PASTE,
  XGHOSTTY_CLIPBOARD_REQUEST_OSC_52_READ,
  XGHOSTTY_CLIPBOARD_REQUEST_OSC_52_WRITE,
} xghostty_clipboard_request_e;

typedef enum {
  XGHOSTTY_MOUSE_RELEASE,
  XGHOSTTY_MOUSE_PRESS,
} xghostty_input_mouse_state_e;

typedef enum {
  XGHOSTTY_MOUSE_UNKNOWN,
  XGHOSTTY_MOUSE_LEFT,
  XGHOSTTY_MOUSE_RIGHT,
  XGHOSTTY_MOUSE_MIDDLE,
  XGHOSTTY_MOUSE_FOUR,
  XGHOSTTY_MOUSE_FIVE,
  XGHOSTTY_MOUSE_SIX,
  XGHOSTTY_MOUSE_SEVEN,
  XGHOSTTY_MOUSE_EIGHT,
  XGHOSTTY_MOUSE_NINE,
  XGHOSTTY_MOUSE_TEN,
  XGHOSTTY_MOUSE_ELEVEN,
} xghostty_input_mouse_button_e;

typedef enum {
  XGHOSTTY_MOUSE_MOMENTUM_NONE,
  XGHOSTTY_MOUSE_MOMENTUM_BEGAN,
  XGHOSTTY_MOUSE_MOMENTUM_STATIONARY,
  XGHOSTTY_MOUSE_MOMENTUM_CHANGED,
  XGHOSTTY_MOUSE_MOMENTUM_ENDED,
  XGHOSTTY_MOUSE_MOMENTUM_CANCELLED,
  XGHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN,
} xghostty_input_mouse_momentum_e;

typedef enum {
  XGHOSTTY_COLOR_SCHEME_LIGHT = 0,
  XGHOSTTY_COLOR_SCHEME_DARK = 1,
} xghostty_color_scheme_e;

// This is a packed struct (see src/input/mouse.zig) but the C standard
// afaik doesn't let us reliably define packed structs so we build it up
// from scratch.
typedef int xghostty_input_scroll_mods_t;

typedef enum {
  XGHOSTTY_MODS_NONE = 0,
  XGHOSTTY_MODS_SHIFT = 1 << 0,
  XGHOSTTY_MODS_CTRL = 1 << 1,
  XGHOSTTY_MODS_ALT = 1 << 2,
  XGHOSTTY_MODS_SUPER = 1 << 3,
  XGHOSTTY_MODS_CAPS = 1 << 4,
  XGHOSTTY_MODS_NUM = 1 << 5,
  XGHOSTTY_MODS_SHIFT_RIGHT = 1 << 6,
  XGHOSTTY_MODS_CTRL_RIGHT = 1 << 7,
  XGHOSTTY_MODS_ALT_RIGHT = 1 << 8,
  XGHOSTTY_MODS_SUPER_RIGHT = 1 << 9,
} xghostty_input_mods_e;

typedef enum {
  XGHOSTTY_BINDING_FLAGS_CONSUMED = 1 << 0,
  XGHOSTTY_BINDING_FLAGS_ALL = 1 << 1,
  XGHOSTTY_BINDING_FLAGS_GLOBAL = 1 << 2,
  XGHOSTTY_BINDING_FLAGS_PERFORMABLE = 1 << 3,
} xghostty_binding_flags_e;

typedef enum {
  XGHOSTTY_ACTION_RELEASE,
  XGHOSTTY_ACTION_PRESS,
  XGHOSTTY_ACTION_REPEAT,
} xghostty_input_action_e;

// Based on: https://www.w3.org/TR/uievents-code/
typedef enum {
  XGHOSTTY_KEY_UNIDENTIFIED,

  // "Writing System Keys" § 3.1.1
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

  // "Functional Keys" § 3.1.2
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

  // "Control Pad Section" § 3.2
  XGHOSTTY_KEY_DELETE,
  XGHOSTTY_KEY_END,
  XGHOSTTY_KEY_HELP,
  XGHOSTTY_KEY_HOME,
  XGHOSTTY_KEY_INSERT,
  XGHOSTTY_KEY_PAGE_DOWN,
  XGHOSTTY_KEY_PAGE_UP,

  // "Arrow Pad Section" § 3.3
  XGHOSTTY_KEY_ARROW_DOWN,
  XGHOSTTY_KEY_ARROW_LEFT,
  XGHOSTTY_KEY_ARROW_RIGHT,
  XGHOSTTY_KEY_ARROW_UP,

  // "Numpad Section" § 3.4
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

  // "Function Section" § 3.5
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

  // "Media Keys" § 3.6
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

  // "Legacy, Non-standard, and Special Keys" § 3.7
  XGHOSTTY_KEY_COPY,
  XGHOSTTY_KEY_CUT,
  XGHOSTTY_KEY_PASTE,
} xghostty_input_key_e;

typedef struct {
  xghostty_input_action_e action;
  xghostty_input_mods_e mods;
  xghostty_input_mods_e consumed_mods;
  uint32_t keycode;
  const char* text;
  uint32_t unshifted_codepoint;
  bool composing;
} xghostty_input_key_s;

typedef enum {
  XGHOSTTY_TRIGGER_PHYSICAL,
  XGHOSTTY_TRIGGER_UNICODE,
  XGHOSTTY_TRIGGER_CATCH_ALL,
} xghostty_input_trigger_tag_e;

typedef union {
  xghostty_input_key_e physical;
  uint32_t unicode;
  // catch_all has no payload
} xghostty_input_trigger_key_u;

typedef struct {
  xghostty_input_trigger_tag_e tag;
  xghostty_input_trigger_key_u key;
  xghostty_input_mods_e mods;
} xghostty_input_trigger_s;

typedef struct {
  const char* action_key;
  const char* action;
  const char* title;
  const char* description;
} xghostty_command_s;

typedef enum {
  XGHOSTTY_BUILD_MODE_DEBUG,
  XGHOSTTY_BUILD_MODE_RELEASE_SAFE,
  XGHOSTTY_BUILD_MODE_RELEASE_FAST,
  XGHOSTTY_BUILD_MODE_RELEASE_SMALL,
} xghostty_build_mode_e;

typedef struct {
  xghostty_build_mode_e build_mode;
  const char* version;
  uintptr_t version_len;
} xghostty_info_s;

typedef struct {
  const char* message;
} xghostty_diagnostic_s;

typedef struct {
  const char* ptr;
  uintptr_t len;
  bool sentinel;
} xghostty_string_s;

typedef struct {
  double tl_px_x;
  double tl_px_y;
  uint32_t offset_start;
  uint32_t offset_len;
  const char* text;
  uintptr_t text_len;
} xghostty_text_s;

typedef enum {
  XGHOSTTY_POINT_ACTIVE,
  XGHOSTTY_POINT_VIEWPORT,
  XGHOSTTY_POINT_SCREEN,
  XGHOSTTY_POINT_SURFACE,
} xghostty_point_tag_e;

typedef enum {
  XGHOSTTY_POINT_COORD_EXACT,
  XGHOSTTY_POINT_COORD_TOP_LEFT,
  XGHOSTTY_POINT_COORD_BOTTOM_RIGHT,
} xghostty_point_coord_e;

typedef struct {
  xghostty_point_tag_e tag;
  xghostty_point_coord_e coord;
  uint32_t x;
  uint32_t y;
} xghostty_point_s;

typedef struct {
  xghostty_point_s top_left;
  xghostty_point_s bottom_right;
  bool rectangle;
} xghostty_selection_s;

typedef struct {
  const char* key;
  const char* value;
} xghostty_env_var_s;

typedef struct {
  void* nsview;
} xghostty_platform_macos_s;

typedef struct {
  void* uiview;
} xghostty_platform_ios_s;

typedef union {
  xghostty_platform_macos_s macos;
  xghostty_platform_ios_s ios;
} xghostty_platform_u;

typedef enum {
  XGHOSTTY_SURFACE_CONTEXT_WINDOW = 0,
  XGHOSTTY_SURFACE_CONTEXT_TAB = 1,
  XGHOSTTY_SURFACE_CONTEXT_SPLIT = 2,
} xghostty_surface_context_e;

typedef struct {
  xghostty_platform_e platform_tag;
  xghostty_platform_u platform;
  void* userdata;
  double scale_factor;
  float font_size;
  const char* working_directory;
  const char* command;
  xghostty_env_var_s* env_vars;
  size_t env_var_count;
  const char* initial_input;
  bool wait_after_command;
  xghostty_surface_context_e context;
} xghostty_surface_config_s;

typedef struct {
  uint16_t columns;
  uint16_t rows;
  uint32_t width_px;
  uint32_t height_px;
  uint32_t cell_width_px;
  uint32_t cell_height_px;
} xghostty_surface_size_s;

// Config types

// config.Path
typedef struct {
  const char* path;
  bool optional;
} xghostty_config_path_s;

// config.Color
typedef struct {
  uint8_t r;
  uint8_t g;
  uint8_t b;
} xghostty_config_color_s;

// config.ColorList
typedef struct {
  const xghostty_config_color_s* colors;
  size_t len;
} xghostty_config_color_list_s;

// config.RepeatableCommand
typedef struct {
  const xghostty_command_s* commands;
  size_t len;
} xghostty_config_command_list_s;

// config.Palette
typedef struct {
  xghostty_config_color_s colors[256];
} xghostty_config_palette_s;

// config.QuickTerminalSize
typedef enum {
  XGHOSTTY_QUICK_TERMINAL_SIZE_NONE,
  XGHOSTTY_QUICK_TERMINAL_SIZE_PERCENTAGE,
  XGHOSTTY_QUICK_TERMINAL_SIZE_PIXELS,
} xghostty_quick_terminal_size_tag_e;

typedef union {
  float percentage;
  uint32_t pixels;
} xghostty_quick_terminal_size_value_u;

typedef struct {
  xghostty_quick_terminal_size_tag_e tag;
  xghostty_quick_terminal_size_value_u value;
} xghostty_quick_terminal_size_s;

typedef struct {
  xghostty_quick_terminal_size_s primary;
  xghostty_quick_terminal_size_s secondary;
} xghostty_config_quick_terminal_size_s;

// config.Fullscreen
typedef enum {
  XGHOSTTY_CONFIG_FULLSCREEN_FALSE,
  XGHOSTTY_CONFIG_FULLSCREEN_TRUE,
  XGHOSTTY_CONFIG_FULLSCREEN_NON_NATIVE,
  XGHOSTTY_CONFIG_FULLSCREEN_NON_NATIVE_VISIBLE_MENU,
  XGHOSTTY_CONFIG_FULLSCREEN_NON_NATIVE_PADDED_NOTCH,
} xghostty_config_fullscreen_e;

// apprt.Target.Key
typedef enum {
  XGHOSTTY_TARGET_APP,
  XGHOSTTY_TARGET_SURFACE,
} xghostty_target_tag_e;

typedef union {
  xghostty_surface_t surface;
} xghostty_target_u;

typedef struct {
  xghostty_target_tag_e tag;
  xghostty_target_u target;
} xghostty_target_s;

// apprt.action.SplitDirection
typedef enum {
  XGHOSTTY_SPLIT_DIRECTION_RIGHT,
  XGHOSTTY_SPLIT_DIRECTION_DOWN,
  XGHOSTTY_SPLIT_DIRECTION_LEFT,
  XGHOSTTY_SPLIT_DIRECTION_UP,
} xghostty_action_split_direction_e;

// apprt.action.GotoSplit
typedef enum {
  XGHOSTTY_GOTO_SPLIT_PREVIOUS,
  XGHOSTTY_GOTO_SPLIT_NEXT,
  XGHOSTTY_GOTO_SPLIT_UP,
  XGHOSTTY_GOTO_SPLIT_LEFT,
  XGHOSTTY_GOTO_SPLIT_DOWN,
  XGHOSTTY_GOTO_SPLIT_RIGHT,
} xghostty_action_goto_split_e;

// apprt.action.GotoWindow
typedef enum {
  XGHOSTTY_GOTO_WINDOW_PREVIOUS,
  XGHOSTTY_GOTO_WINDOW_NEXT,
} xghostty_action_goto_window_e;

// apprt.action.ResizeSplit.Direction
typedef enum {
  XGHOSTTY_RESIZE_SPLIT_UP,
  XGHOSTTY_RESIZE_SPLIT_DOWN,
  XGHOSTTY_RESIZE_SPLIT_LEFT,
  XGHOSTTY_RESIZE_SPLIT_RIGHT,
} xghostty_action_resize_split_direction_e;

// apprt.action.ResizeSplit
typedef struct {
  uint16_t amount;
  xghostty_action_resize_split_direction_e direction;
} xghostty_action_resize_split_s;

// apprt.action.MoveTab
typedef struct {
  ssize_t amount;
} xghostty_action_move_tab_s;

// apprt.action.GotoTab
typedef enum {
  XGHOSTTY_GOTO_TAB_PREVIOUS = -1,
  XGHOSTTY_GOTO_TAB_NEXT = -2,
  XGHOSTTY_GOTO_TAB_LAST = -3,
} xghostty_action_goto_tab_e;

// apprt.action.Fullscreen
typedef enum {
  XGHOSTTY_FULLSCREEN_NATIVE,
  XGHOSTTY_FULLSCREEN_MACOS_NON_NATIVE,
  XGHOSTTY_FULLSCREEN_MACOS_NON_NATIVE_VISIBLE_MENU,
  XGHOSTTY_FULLSCREEN_MACOS_NON_NATIVE_PADDED_NOTCH,
} xghostty_action_fullscreen_e;

// apprt.action.FloatWindow
typedef enum {
  XGHOSTTY_FLOAT_WINDOW_ON,
  XGHOSTTY_FLOAT_WINDOW_OFF,
  XGHOSTTY_FLOAT_WINDOW_TOGGLE,
} xghostty_action_float_window_e;

// apprt.action.SecureInput
typedef enum {
  XGHOSTTY_SECURE_INPUT_ON,
  XGHOSTTY_SECURE_INPUT_OFF,
  XGHOSTTY_SECURE_INPUT_TOGGLE,
} xghostty_action_secure_input_e;

// apprt.action.Inspector
typedef enum {
  XGHOSTTY_INSPECTOR_TOGGLE,
  XGHOSTTY_INSPECTOR_SHOW,
  XGHOSTTY_INSPECTOR_HIDE,
} xghostty_action_inspector_e;

// apprt.action.QuitTimer
typedef enum {
  XGHOSTTY_QUIT_TIMER_START,
  XGHOSTTY_QUIT_TIMER_STOP,
} xghostty_action_quit_timer_e;

// apprt.action.Readonly
typedef enum {
  XGHOSTTY_READONLY_OFF,
  XGHOSTTY_READONLY_ON,
} xghostty_action_readonly_e;

// apprt.action.DesktopNotification.C
typedef struct {
  const char* title;
  const char* body;
} xghostty_action_desktop_notification_s;

// apprt.action.SetTitle.C
typedef struct {
  const char* title;
} xghostty_action_set_title_s;

// apprt.action.PromptTitle
typedef enum {
  XGHOSTTY_PROMPT_TITLE_SURFACE,
  XGHOSTTY_PROMPT_TITLE_TAB,
} xghostty_action_prompt_title_e;

// apprt.action.Pwd.C
typedef struct {
  const char* pwd;
} xghostty_action_pwd_s;

// terminal.MouseShape
typedef enum {
  XGHOSTTY_MOUSE_SHAPE_DEFAULT,
  XGHOSTTY_MOUSE_SHAPE_CONTEXT_MENU,
  XGHOSTTY_MOUSE_SHAPE_HELP,
  XGHOSTTY_MOUSE_SHAPE_POINTER,
  XGHOSTTY_MOUSE_SHAPE_PROGRESS,
  XGHOSTTY_MOUSE_SHAPE_WAIT,
  XGHOSTTY_MOUSE_SHAPE_CELL,
  XGHOSTTY_MOUSE_SHAPE_CROSSHAIR,
  XGHOSTTY_MOUSE_SHAPE_TEXT,
  XGHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT,
  XGHOSTTY_MOUSE_SHAPE_ALIAS,
  XGHOSTTY_MOUSE_SHAPE_COPY,
  XGHOSTTY_MOUSE_SHAPE_MOVE,
  XGHOSTTY_MOUSE_SHAPE_NO_DROP,
  XGHOSTTY_MOUSE_SHAPE_NOT_ALLOWED,
  XGHOSTTY_MOUSE_SHAPE_GRAB,
  XGHOSTTY_MOUSE_SHAPE_GRABBING,
  XGHOSTTY_MOUSE_SHAPE_ALL_SCROLL,
  XGHOSTTY_MOUSE_SHAPE_COL_RESIZE,
  XGHOSTTY_MOUSE_SHAPE_ROW_RESIZE,
  XGHOSTTY_MOUSE_SHAPE_N_RESIZE,
  XGHOSTTY_MOUSE_SHAPE_E_RESIZE,
  XGHOSTTY_MOUSE_SHAPE_S_RESIZE,
  XGHOSTTY_MOUSE_SHAPE_W_RESIZE,
  XGHOSTTY_MOUSE_SHAPE_NE_RESIZE,
  XGHOSTTY_MOUSE_SHAPE_NW_RESIZE,
  XGHOSTTY_MOUSE_SHAPE_SE_RESIZE,
  XGHOSTTY_MOUSE_SHAPE_SW_RESIZE,
  XGHOSTTY_MOUSE_SHAPE_EW_RESIZE,
  XGHOSTTY_MOUSE_SHAPE_NS_RESIZE,
  XGHOSTTY_MOUSE_SHAPE_NESW_RESIZE,
  XGHOSTTY_MOUSE_SHAPE_NWSE_RESIZE,
  XGHOSTTY_MOUSE_SHAPE_ZOOM_IN,
  XGHOSTTY_MOUSE_SHAPE_ZOOM_OUT,
} xghostty_action_mouse_shape_e;

// apprt.action.MouseVisibility
typedef enum {
  XGHOSTTY_MOUSE_VISIBLE,
  XGHOSTTY_MOUSE_HIDDEN,
} xghostty_action_mouse_visibility_e;

// apprt.action.MouseOverLink
typedef struct {
  const char* url;
  size_t len;
} xghostty_action_mouse_over_link_s;

// apprt.action.SizeLimit
typedef struct {
  uint32_t min_width;
  uint32_t min_height;
  uint32_t max_width;
  uint32_t max_height;
} xghostty_action_size_limit_s;

// apprt.action.InitialSize
typedef struct {
  uint32_t width;
  uint32_t height;
} xghostty_action_initial_size_s;

// apprt.action.CellSize
typedef struct {
  uint32_t width;
  uint32_t height;
} xghostty_action_cell_size_s;

// renderer.Health
typedef enum {
  XGHOSTTY_RENDERER_HEALTH_HEALTHY,
  XGHOSTTY_RENDERER_HEALTH_UNHEALTHY,
} xghostty_action_renderer_health_e;

// apprt.action.KeySequence
typedef struct {
  bool active;
  xghostty_input_trigger_s trigger;
} xghostty_action_key_sequence_s;

// apprt.action.KeyTable.Tag
typedef enum {
  XGHOSTTY_KEY_TABLE_ACTIVATE,
  XGHOSTTY_KEY_TABLE_DEACTIVATE,
  XGHOSTTY_KEY_TABLE_DEACTIVATE_ALL,
} xghostty_action_key_table_tag_e;

// apprt.action.KeyTable.CValue
typedef union {
  struct {
    const char *name;
    size_t len;
  } activate;
} xghostty_action_key_table_u;

// apprt.action.KeyTable.C
typedef struct {
  xghostty_action_key_table_tag_e tag;
  xghostty_action_key_table_u value;
} xghostty_action_key_table_s;

// apprt.action.ColorKind
typedef enum {
  XGHOSTTY_ACTION_COLOR_KIND_FOREGROUND = -1,
  XGHOSTTY_ACTION_COLOR_KIND_BACKGROUND = -2,
  XGHOSTTY_ACTION_COLOR_KIND_CURSOR = -3,
} xghostty_action_color_kind_e;

// apprt.action.ColorChange
typedef struct {
  xghostty_action_color_kind_e kind;
  uint8_t r;
  uint8_t g;
  uint8_t b;
} xghostty_action_color_change_s;

// apprt.action.ConfigChange
typedef struct {
  xghostty_config_t config;
} xghostty_action_config_change_s;

// apprt.action.ReloadConfig
typedef struct {
  bool soft;
} xghostty_action_reload_config_s;

// apprt.action.OpenUrlKind
typedef enum {
  XGHOSTTY_ACTION_OPEN_URL_KIND_UNKNOWN,
  XGHOSTTY_ACTION_OPEN_URL_KIND_TEXT,
  XGHOSTTY_ACTION_OPEN_URL_KIND_HTML,
} xghostty_action_open_url_kind_e;

// apprt.action.OpenUrl.C
typedef struct {
  xghostty_action_open_url_kind_e kind;
  const char* url;
  uintptr_t len;
} xghostty_action_open_url_s;

// apprt.action.CloseTabMode
typedef enum {
  XGHOSTTY_ACTION_CLOSE_TAB_MODE_THIS,
  XGHOSTTY_ACTION_CLOSE_TAB_MODE_OTHER,
  XGHOSTTY_ACTION_CLOSE_TAB_MODE_RIGHT,
} xghostty_action_close_tab_mode_e;

// apprt.surface.Message.ChildExited
typedef struct {
  uint32_t exit_code;
  uint64_t timetime_ms;
} xghostty_surface_message_childexited_s;

// terminal.osc.Command.ProgressReport.State
typedef enum {
  XGHOSTTY_PROGRESS_STATE_REMOVE,
  XGHOSTTY_PROGRESS_STATE_SET,
  XGHOSTTY_PROGRESS_STATE_ERROR,
  XGHOSTTY_PROGRESS_STATE_INDETERMINATE,
  XGHOSTTY_PROGRESS_STATE_PAUSE,
} xghostty_action_progress_report_state_e;

// terminal.osc.Command.ProgressReport.C
typedef struct {
  xghostty_action_progress_report_state_e state;
  // -1 if no progress was reported, otherwise 0-100 indicating percent
  // completeness.
  int8_t progress;
} xghostty_action_progress_report_s;

// apprt.action.CommandFinished.C
typedef struct {
  // -1 if no exit code was reported, otherwise 0-255
  int16_t exit_code;
  // number of nanoseconds that command was running for
  uint64_t duration;
} xghostty_action_command_finished_s;

// apprt.action.StartSearch.C
typedef struct {
  const char* needle;
} xghostty_action_start_search_s;

// apprt.action.SearchTotal
typedef struct {
  ssize_t total;
} xghostty_action_search_total_s;

// apprt.action.SearchSelected
typedef struct {
  ssize_t selected;
} xghostty_action_search_selected_s;

// terminal.Scrollbar
typedef struct {
  uint64_t total;
  uint64_t offset;
  uint64_t len;
} xghostty_action_scrollbar_s;

// apprt.Action.Key
typedef enum {
  XGHOSTTY_ACTION_QUIT,
  XGHOSTTY_ACTION_NEW_WINDOW,
  XGHOSTTY_ACTION_NEW_TAB,
  XGHOSTTY_ACTION_CLOSE_TAB,
  XGHOSTTY_ACTION_NEW_SPLIT,
  XGHOSTTY_ACTION_CLOSE_ALL_WINDOWS,
  XGHOSTTY_ACTION_TOGGLE_MAXIMIZE,
  XGHOSTTY_ACTION_TOGGLE_FULLSCREEN,
  XGHOSTTY_ACTION_TOGGLE_TAB_OVERVIEW,
  XGHOSTTY_ACTION_TOGGLE_WINDOW_DECORATIONS,
  XGHOSTTY_ACTION_TOGGLE_QUICK_TERMINAL,
  XGHOSTTY_ACTION_TOGGLE_COMMAND_PALETTE,
  XGHOSTTY_ACTION_TOGGLE_VISIBILITY,
  XGHOSTTY_ACTION_TOGGLE_BACKGROUND_OPACITY,
  XGHOSTTY_ACTION_MOVE_TAB,
  XGHOSTTY_ACTION_GOTO_TAB,
  XGHOSTTY_ACTION_GOTO_SPLIT,
  XGHOSTTY_ACTION_GOTO_WINDOW,
  XGHOSTTY_ACTION_RESIZE_SPLIT,
  XGHOSTTY_ACTION_EQUALIZE_SPLITS,
  XGHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM,
  XGHOSTTY_ACTION_PRESENT_TERMINAL,
  XGHOSTTY_ACTION_SIZE_LIMIT,
  XGHOSTTY_ACTION_RESET_WINDOW_SIZE,
  XGHOSTTY_ACTION_INITIAL_SIZE,
  XGHOSTTY_ACTION_CELL_SIZE,
  XGHOSTTY_ACTION_SCROLLBAR,
  XGHOSTTY_ACTION_RENDER,
  XGHOSTTY_ACTION_INSPECTOR,
  XGHOSTTY_ACTION_SHOW_GTK_INSPECTOR,
  XGHOSTTY_ACTION_RENDER_INSPECTOR,
  XGHOSTTY_ACTION_DESKTOP_NOTIFICATION,
  XGHOSTTY_ACTION_SET_TITLE,
  XGHOSTTY_ACTION_SET_TAB_TITLE,
  XGHOSTTY_ACTION_PROMPT_TITLE,
  XGHOSTTY_ACTION_PWD,
  XGHOSTTY_ACTION_MOUSE_SHAPE,
  XGHOSTTY_ACTION_MOUSE_VISIBILITY,
  XGHOSTTY_ACTION_MOUSE_OVER_LINK,
  XGHOSTTY_ACTION_RENDERER_HEALTH,
  XGHOSTTY_ACTION_OPEN_CONFIG,
  XGHOSTTY_ACTION_QUIT_TIMER,
  XGHOSTTY_ACTION_FLOAT_WINDOW,
  XGHOSTTY_ACTION_SECURE_INPUT,
  XGHOSTTY_ACTION_KEY_SEQUENCE,
  XGHOSTTY_ACTION_KEY_TABLE,
  XGHOSTTY_ACTION_COLOR_CHANGE,
  XGHOSTTY_ACTION_RELOAD_CONFIG,
  XGHOSTTY_ACTION_CONFIG_CHANGE,
  XGHOSTTY_ACTION_CLOSE_WINDOW,
  XGHOSTTY_ACTION_RING_BELL,
  XGHOSTTY_ACTION_SELECTION_CHANGED,
  XGHOSTTY_ACTION_UNDO,
  XGHOSTTY_ACTION_REDO,
  XGHOSTTY_ACTION_CHECK_FOR_UPDATES,
  XGHOSTTY_ACTION_OPEN_URL,
  XGHOSTTY_ACTION_SHOW_CHILD_EXITED,
  XGHOSTTY_ACTION_PROGRESS_REPORT,
  XGHOSTTY_ACTION_SHOW_ON_SCREEN_KEYBOARD,
  XGHOSTTY_ACTION_COMMAND_FINISHED,
  XGHOSTTY_ACTION_START_SEARCH,
  XGHOSTTY_ACTION_END_SEARCH,
  XGHOSTTY_ACTION_SEARCH_TOTAL,
  XGHOSTTY_ACTION_SEARCH_SELECTED,
  XGHOSTTY_ACTION_READONLY,
  XGHOSTTY_ACTION_COPY_TITLE_TO_CLIPBOARD,
  XGHOSTTY_ACTION_NEW_GROUP_SPLIT,
  XGHOSTTY_ACTION_GOTO_GROUP,
  XGHOSTTY_ACTION_RESIZE_GROUP,
  XGHOSTTY_ACTION_EQUALIZE_GROUPS,
  XGHOSTTY_ACTION_TOGGLE_GROUP_ZOOM,
  XGHOSTTY_ACTION_HIDE_GROUP,
  XGHOSTTY_ACTION_SHOW_GROUP,
  XGHOSTTY_ACTION_RENAME_GROUP,
  XGHOSTTY_ACTION_SET_GROUP_TITLE,
  XGHOSTTY_ACTION_CLOSE_GROUP,
} xghostty_action_tag_e;

typedef union {
  xghostty_action_split_direction_e new_split;
  xghostty_action_fullscreen_e toggle_fullscreen;
  xghostty_action_move_tab_s move_tab;
  xghostty_action_goto_tab_e goto_tab;
  xghostty_action_goto_split_e goto_split;
  xghostty_action_goto_window_e goto_window;
  xghostty_action_resize_split_s resize_split;
  xghostty_action_size_limit_s size_limit;
  xghostty_action_initial_size_s initial_size;
  xghostty_action_cell_size_s cell_size;
  xghostty_action_scrollbar_s scrollbar;
  xghostty_action_inspector_e inspector;
  xghostty_action_desktop_notification_s desktop_notification;
  xghostty_action_set_title_s set_title;
  xghostty_action_set_title_s set_tab_title;
  xghostty_action_prompt_title_e prompt_title;
  xghostty_action_pwd_s pwd;
  xghostty_action_mouse_shape_e mouse_shape;
  xghostty_action_mouse_visibility_e mouse_visibility;
  xghostty_action_mouse_over_link_s mouse_over_link;
  xghostty_action_renderer_health_e renderer_health;
  xghostty_action_quit_timer_e quit_timer;
  xghostty_action_float_window_e float_window;
  xghostty_action_secure_input_e secure_input;
  xghostty_action_key_sequence_s key_sequence;
  xghostty_action_key_table_s key_table;
  xghostty_action_color_change_s color_change;
  xghostty_action_reload_config_s reload_config;
  xghostty_action_config_change_s config_change;
  xghostty_action_open_url_s open_url;
  xghostty_action_close_tab_mode_e close_tab_mode;
  xghostty_surface_message_childexited_s child_exited;
  xghostty_action_progress_report_s progress_report;
  xghostty_action_command_finished_s command_finished;
  xghostty_action_start_search_s start_search;
  xghostty_action_search_total_s search_total;
  xghostty_action_search_selected_s search_selected;
  xghostty_action_readonly_e readonly;
  xghostty_action_split_direction_e new_group_split;
  xghostty_action_goto_split_e goto_group;
  xghostty_action_resize_split_s resize_group;
  xghostty_action_set_title_s show_group;
  xghostty_action_set_title_s set_group_title;
} xghostty_action_u;

typedef struct {
  xghostty_action_tag_e tag;
  xghostty_action_u action;
} xghostty_action_s;

typedef void (*xghostty_runtime_wakeup_cb)(void*);
typedef bool (*xghostty_runtime_read_clipboard_cb)(void*,
                                                  xghostty_clipboard_e,
                                                  void*);
typedef void (*xghostty_runtime_confirm_read_clipboard_cb)(
    void*,
    const char*,
    void*,
    xghostty_clipboard_request_e);
typedef void (*xghostty_runtime_write_clipboard_cb)(void*,
                                                   xghostty_clipboard_e,
                                                   const xghostty_clipboard_content_s*,
                                                   size_t,
                                                   bool);
typedef void (*xghostty_runtime_close_surface_cb)(void*, bool);
typedef bool (*xghostty_runtime_action_cb)(xghostty_app_t,
                                          xghostty_target_s,
                                          xghostty_action_s);

typedef struct {
  void* userdata;
  bool supports_selection_clipboard;
  xghostty_runtime_wakeup_cb wakeup_cb;
  xghostty_runtime_action_cb action_cb;
  xghostty_runtime_read_clipboard_cb read_clipboard_cb;
  xghostty_runtime_confirm_read_clipboard_cb confirm_read_clipboard_cb;
  xghostty_runtime_write_clipboard_cb write_clipboard_cb;
  xghostty_runtime_close_surface_cb close_surface_cb;
} xghostty_runtime_config_s;

// apprt.ipc.Target.Key
typedef enum {
  XGHOSTTY_IPC_TARGET_CLASS,
  XGHOSTTY_IPC_TARGET_DETECT,
} xghostty_ipc_target_tag_e;

typedef union {
  char *klass;
} xghostty_ipc_target_u;

typedef struct {
  xghostty_ipc_target_tag_e tag;
  xghostty_ipc_target_u target;
} chostty_ipc_target_s;

// apprt.ipc.Action.NewWindow
typedef struct {
  // This should be a null terminated list of strings.
  const char **arguments;
} xghostty_ipc_action_new_window_s;

typedef union {
  xghostty_ipc_action_new_window_s new_window;
} xghostty_ipc_action_u;

// apprt.ipc.Action.Key
typedef enum {
  XGHOSTTY_IPC_ACTION_NEW_WINDOW,
  XGHOSTTY_IPC_ACTION_TOGGLE_QUICK_TERMINAL,
} xghostty_ipc_action_tag_e;

//-------------------------------------------------------------------
// Published API

XGHOSTTY_API int xghostty_init(uintptr_t, char**);
XGHOSTTY_API void xghostty_cli_try_action(void);
XGHOSTTY_API xghostty_info_s xghostty_info(void);
XGHOSTTY_API const char* xghostty_translate(const char*);
XGHOSTTY_API void xghostty_string_free(xghostty_string_s);

XGHOSTTY_API xghostty_config_t xghostty_config_new();
XGHOSTTY_API void xghostty_config_free(xghostty_config_t);
XGHOSTTY_API xghostty_config_t xghostty_config_clone(xghostty_config_t);
XGHOSTTY_API void xghostty_config_load_cli_args(xghostty_config_t);
XGHOSTTY_API void xghostty_config_load_file(xghostty_config_t, const char*);
XGHOSTTY_API void xghostty_config_load_default_files(xghostty_config_t);
XGHOSTTY_API void xghostty_config_load_recursive_files(xghostty_config_t);
XGHOSTTY_API void xghostty_config_finalize(xghostty_config_t);
XGHOSTTY_API bool xghostty_config_get(xghostty_config_t, void*, const char*, uintptr_t);
XGHOSTTY_API xghostty_input_trigger_s xghostty_config_trigger(xghostty_config_t,
                                                              const char*,
                                                              uintptr_t);
XGHOSTTY_API bool xghostty_config_key_is_binding(xghostty_config_t, xghostty_input_key_s);
XGHOSTTY_API uint32_t xghostty_config_diagnostics_count(xghostty_config_t);
XGHOSTTY_API xghostty_diagnostic_s xghostty_config_get_diagnostic(xghostty_config_t, uint32_t);
XGHOSTTY_API xghostty_string_s xghostty_config_open_path(void);

XGHOSTTY_API xghostty_app_t xghostty_app_new(const xghostty_runtime_config_s*,
                                             xghostty_config_t);
XGHOSTTY_API void xghostty_app_free(xghostty_app_t);
XGHOSTTY_API void xghostty_app_tick(xghostty_app_t);
XGHOSTTY_API void* xghostty_app_userdata(xghostty_app_t);
XGHOSTTY_API void xghostty_app_set_focus(xghostty_app_t, bool);
XGHOSTTY_API bool xghostty_app_key(xghostty_app_t, xghostty_input_key_s);
XGHOSTTY_API void xghostty_app_keyboard_changed(xghostty_app_t);
XGHOSTTY_API void xghostty_app_open_config(xghostty_app_t);
XGHOSTTY_API void xghostty_app_update_config(xghostty_app_t, xghostty_config_t);
XGHOSTTY_API bool xghostty_app_needs_confirm_quit(xghostty_app_t);
XGHOSTTY_API bool xghostty_app_has_global_keybinds(xghostty_app_t);
XGHOSTTY_API void xghostty_app_set_color_scheme(xghostty_app_t, xghostty_color_scheme_e);

XGHOSTTY_API xghostty_surface_config_s xghostty_surface_config_new();

XGHOSTTY_API xghostty_surface_t xghostty_surface_new(xghostty_app_t,
                                                     const xghostty_surface_config_s*);
XGHOSTTY_API void xghostty_surface_free(xghostty_surface_t);
XGHOSTTY_API void* xghostty_surface_userdata(xghostty_surface_t);
XGHOSTTY_API xghostty_app_t xghostty_surface_app(xghostty_surface_t);
XGHOSTTY_API xghostty_surface_config_s xghostty_surface_inherited_config(xghostty_surface_t, xghostty_surface_context_e);
XGHOSTTY_API void xghostty_surface_update_config(xghostty_surface_t, xghostty_config_t);
XGHOSTTY_API bool xghostty_surface_needs_confirm_quit(xghostty_surface_t);
XGHOSTTY_API bool xghostty_surface_process_exited(xghostty_surface_t);
XGHOSTTY_API void xghostty_surface_refresh(xghostty_surface_t);
XGHOSTTY_API void xghostty_surface_draw(xghostty_surface_t);
XGHOSTTY_API void xghostty_surface_set_content_scale(xghostty_surface_t, double, double);
XGHOSTTY_API void xghostty_surface_set_focus(xghostty_surface_t, bool);
XGHOSTTY_API void xghostty_surface_set_occlusion(xghostty_surface_t, bool);
XGHOSTTY_API void xghostty_surface_set_size(xghostty_surface_t, uint32_t, uint32_t);
XGHOSTTY_API xghostty_surface_size_s xghostty_surface_size(xghostty_surface_t);
XGHOSTTY_API uint64_t xghostty_surface_foreground_pid(xghostty_surface_t);
XGHOSTTY_API xghostty_string_s xghostty_surface_tty_name(xghostty_surface_t);
XGHOSTTY_API void xghostty_surface_set_color_scheme(xghostty_surface_t,
                                                     xghostty_color_scheme_e);
XGHOSTTY_API xghostty_input_mods_e xghostty_surface_key_translation_mods(xghostty_surface_t,
                                                                         xghostty_input_mods_e);
XGHOSTTY_API bool xghostty_surface_key(xghostty_surface_t, xghostty_input_key_s);
XGHOSTTY_API bool xghostty_surface_key_is_binding(xghostty_surface_t,
                                                   xghostty_input_key_s,
                                                   xghostty_binding_flags_e*);
XGHOSTTY_API void xghostty_surface_text(xghostty_surface_t, const char*, uintptr_t);
XGHOSTTY_API void xghostty_surface_preedit(xghostty_surface_t, const char*, uintptr_t);
XGHOSTTY_API bool xghostty_surface_mouse_captured(xghostty_surface_t);
XGHOSTTY_API bool xghostty_surface_mouse_button(xghostty_surface_t,
                                                 xghostty_input_mouse_state_e,
                                                 xghostty_input_mouse_button_e,
                                                 xghostty_input_mods_e);
XGHOSTTY_API void xghostty_surface_mouse_pos(xghostty_surface_t,
                                              double,
                                              double,
                                              xghostty_input_mods_e);
XGHOSTTY_API void xghostty_surface_mouse_scroll(xghostty_surface_t,
                                                 double,
                                                 double,
                                                 xghostty_input_scroll_mods_t);
XGHOSTTY_API void xghostty_surface_mouse_pressure(xghostty_surface_t, uint32_t, double);
XGHOSTTY_API void xghostty_surface_ime_point(xghostty_surface_t, double*, double*, double*, double*);
XGHOSTTY_API void xghostty_surface_request_close(xghostty_surface_t);
XGHOSTTY_API void xghostty_surface_split(xghostty_surface_t, xghostty_action_split_direction_e);
XGHOSTTY_API void xghostty_surface_split_focus(xghostty_surface_t,
                                                xghostty_action_goto_split_e);
XGHOSTTY_API void xghostty_surface_split_resize(xghostty_surface_t,
                                                 xghostty_action_resize_split_direction_e,
                                                 uint16_t);
XGHOSTTY_API void xghostty_surface_split_equalize(xghostty_surface_t);
XGHOSTTY_API bool xghostty_surface_binding_action(xghostty_surface_t, const char*, uintptr_t);
XGHOSTTY_API void xghostty_surface_complete_clipboard_request(xghostty_surface_t,
                                                               const char*,
                                                               void*,
                                                               bool);
XGHOSTTY_API bool xghostty_surface_has_selection(xghostty_surface_t);
XGHOSTTY_API bool xghostty_surface_read_selection(xghostty_surface_t, xghostty_text_s*);
XGHOSTTY_API bool xghostty_surface_read_text(xghostty_surface_t,
                                              xghostty_selection_s,
                                              xghostty_text_s*);
XGHOSTTY_API void xghostty_surface_free_text(xghostty_surface_t, xghostty_text_s*);

#ifdef __APPLE__
XGHOSTTY_API void xghostty_surface_set_display_id(xghostty_surface_t, uint32_t);
XGHOSTTY_API void* xghostty_surface_quicklook_font(xghostty_surface_t);
XGHOSTTY_API bool xghostty_surface_quicklook_word(xghostty_surface_t, xghostty_text_s*);
#endif

XGHOSTTY_API xghostty_inspector_t xghostty_surface_inspector(xghostty_surface_t);
XGHOSTTY_API void xghostty_inspector_free(xghostty_surface_t);
XGHOSTTY_API void xghostty_inspector_set_focus(xghostty_inspector_t, bool);
XGHOSTTY_API void xghostty_inspector_set_content_scale(xghostty_inspector_t, double, double);
XGHOSTTY_API void xghostty_inspector_set_size(xghostty_inspector_t, uint32_t, uint32_t);
XGHOSTTY_API void xghostty_inspector_mouse_button(xghostty_inspector_t,
                                                   xghostty_input_mouse_state_e,
                                                   xghostty_input_mouse_button_e,
                                                   xghostty_input_mods_e);
XGHOSTTY_API void xghostty_inspector_mouse_pos(xghostty_inspector_t, double, double);
XGHOSTTY_API void xghostty_inspector_mouse_scroll(xghostty_inspector_t,
                                                   double,
                                                   double,
                                                   xghostty_input_scroll_mods_t);
XGHOSTTY_API void xghostty_inspector_key(xghostty_inspector_t,
                                          xghostty_input_action_e,
                                          xghostty_input_key_e,
                                          xghostty_input_mods_e);
XGHOSTTY_API void xghostty_inspector_text(xghostty_inspector_t, const char*);

#ifdef __APPLE__
XGHOSTTY_API bool xghostty_inspector_metal_init(xghostty_inspector_t, void*);
XGHOSTTY_API void xghostty_inspector_metal_render(xghostty_inspector_t, void*, void*);
XGHOSTTY_API bool xghostty_inspector_metal_shutdown(xghostty_inspector_t);
#endif

// APIs I'd like to get rid of eventually but are still needed for now.
// Don't use these unless you know what you're doing.
XGHOSTTY_API void xghostty_set_window_background_blur(xghostty_app_t, void*);

// Benchmark API, if available.
XGHOSTTY_API bool xghostty_benchmark_cli(const char*, const char*);

#ifdef __cplusplus
}
#endif

#endif /* XGHOSTTY_H */
