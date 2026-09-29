#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <xghostty/vt.h>

//! [colors-set-defaults]
/// Set up a dark color theme with custom palette entries.
void set_color_theme(XGhosttyTerminal terminal) {
  // Set default foreground (light gray) and background (dark)
  XGhosttyColorRgb fg = { .r = 0xDD, .g = 0xDD, .b = 0xDD };
  XGhosttyColorRgb bg = { .r = 0x1E, .g = 0x1E, .b = 0x2E };
  XGhosttyColorRgb cursor = { .r = 0xF5, .g = 0xE0, .b = 0xDC };

  xghostty_terminal_set(terminal, XGHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND, &fg);
  xghostty_terminal_set(terminal, XGHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND, &bg);
  xghostty_terminal_set(terminal, XGHOSTTY_TERMINAL_OPT_COLOR_CURSOR, &cursor);

  // Set a custom palette — start from the built-in default and override
  // the first 8 entries with a custom dark theme.
  XGhosttyColorRgb palette[256];
  xghostty_terminal_get(terminal, XGHOSTTY_TERMINAL_DATA_COLOR_PALETTE, palette);

  palette[XGHOSTTY_COLOR_NAMED_BLACK]   = (XGhosttyColorRgb){ 0x45, 0x47, 0x5A };
  palette[XGHOSTTY_COLOR_NAMED_RED]     = (XGhosttyColorRgb){ 0xF3, 0x8B, 0xA8 };
  palette[XGHOSTTY_COLOR_NAMED_GREEN]   = (XGhosttyColorRgb){ 0xA6, 0xE3, 0xA1 };
  palette[XGHOSTTY_COLOR_NAMED_YELLOW]  = (XGhosttyColorRgb){ 0xF9, 0xE2, 0xAF };
  palette[XGHOSTTY_COLOR_NAMED_BLUE]    = (XGhosttyColorRgb){ 0x89, 0xB4, 0xFA };
  palette[XGHOSTTY_COLOR_NAMED_MAGENTA] = (XGhosttyColorRgb){ 0xF5, 0xC2, 0xE7 };
  palette[XGHOSTTY_COLOR_NAMED_CYAN]    = (XGhosttyColorRgb){ 0x94, 0xE2, 0xD5 };
  palette[XGHOSTTY_COLOR_NAMED_WHITE]   = (XGhosttyColorRgb){ 0xBA, 0xC2, 0xDE };

  xghostty_terminal_set(terminal, XGHOSTTY_TERMINAL_OPT_COLOR_PALETTE, palette);
}
//! [colors-set-defaults]

//! [colors-read]
/// Print the effective and default values for a color, showing how
/// OSC overrides layer on top of defaults.
void print_color(XGhosttyTerminal terminal,
                 const char* name,
                 XGhosttyTerminalData effective_data,
                 XGhosttyTerminalData default_data) {
  XGhosttyColorRgb color;

  XGhosttyResult res = xghostty_terminal_get(terminal, effective_data, &color);
  if (res == XGHOSTTY_SUCCESS) {
    printf("  %-12s effective: #%02X%02X%02X", name, color.r, color.g, color.b);
  } else {
    printf("  %-12s effective: (not set)", name);
  }

  res = xghostty_terminal_get(terminal, default_data, &color);
  if (res == XGHOSTTY_SUCCESS) {
    printf("  default: #%02X%02X%02X\n", color.r, color.g, color.b);
  } else {
    printf("  default: (not set)\n");
  }
}

void print_all_colors(XGhosttyTerminal terminal, const char* label) {
  printf("%s:\n", label);
  print_color(terminal, "foreground",
      XGHOSTTY_TERMINAL_DATA_COLOR_FOREGROUND,
      XGHOSTTY_TERMINAL_DATA_COLOR_FOREGROUND_DEFAULT);
  print_color(terminal, "background",
      XGHOSTTY_TERMINAL_DATA_COLOR_BACKGROUND,
      XGHOSTTY_TERMINAL_DATA_COLOR_BACKGROUND_DEFAULT);
  print_color(terminal, "cursor",
      XGHOSTTY_TERMINAL_DATA_COLOR_CURSOR,
      XGHOSTTY_TERMINAL_DATA_COLOR_CURSOR_DEFAULT);

  // Show palette index 0 (black) as an example
  XGhosttyColorRgb palette[256];
  xghostty_terminal_get(terminal, XGHOSTTY_TERMINAL_DATA_COLOR_PALETTE, palette);
  printf("  %-12s effective: #%02X%02X%02X", "palette[0]",
      palette[0].r, palette[0].g, palette[0].b);

  xghostty_terminal_get(terminal, XGHOSTTY_TERMINAL_DATA_COLOR_PALETTE_DEFAULT,
      palette);
  printf("  default: #%02X%02X%02X\n", palette[0].r, palette[0].g, palette[0].b);
}
//! [colors-read]

//! [colors-main]
int main() {
  // Create a terminal
  XGhosttyTerminal terminal = NULL;
  XGhosttyTerminalOptions opts = {
    .cols = 80,
    .rows = 24,
    .max_scrollback = 0,
  };
  if (xghostty_terminal_new(NULL, &terminal, opts) != XGHOSTTY_SUCCESS) {
    fprintf(stderr, "Failed to create terminal\n");
    return 1;
  }

  // Before setting any colors, everything is unset
  print_all_colors(terminal, "Before setting defaults");

  // Set our color theme defaults
  set_color_theme(terminal);
  print_all_colors(terminal, "\nAfter setting defaults");

  // Simulate an OSC override (e.g. a program running inside the
  // terminal changes the foreground via OSC 10)
  const char* osc_fg = "\x1B]10;rgb:FF/00/00\x1B\\";
  xghostty_terminal_vt_write(terminal, (const uint8_t*)osc_fg,
                            strlen(osc_fg));
  print_all_colors(terminal, "\nAfter OSC foreground override");

  // Clear the foreground default — the OSC override is still active
  xghostty_terminal_set(terminal, XGHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND, NULL);
  print_all_colors(terminal, "\nAfter clearing foreground default");

  xghostty_terminal_free(terminal);
  return 0;
}
//! [colors-main]
