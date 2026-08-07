#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <xghostty/vt.h>

//! [grid-ref-tracked]
static uint32_t codepoint_at_tracked_ref(XGhosttyTrackedGridRef tracked) {
  XGhosttyGridRef snapshot = XGHOSTTY_INIT_SIZED(XGhosttyGridRef);
  XGhosttyResult result = xghostty_tracked_grid_ref_snapshot(tracked, &snapshot);
  assert(result == XGHOSTTY_SUCCESS);

  XGhosttyCell cell;
  result = xghostty_grid_ref_cell(&snapshot, &cell);
  assert(result == XGHOSTTY_SUCCESS);

  bool has_text = false;
  xghostty_cell_get(cell, XGHOSTTY_CELL_DATA_HAS_TEXT, &has_text);
  assert(has_text);

  uint32_t codepoint = 0;
  xghostty_cell_get(cell, XGHOSTTY_CELL_DATA_CODEPOINT, &codepoint);
  return codepoint;
}

int main() {
  XGhosttyTerminal terminal;
  XGhosttyTerminalOptions opts = {
    .cols = 8,
    .rows = 3,
    .max_scrollback = 100,
  };
  XGhosttyResult result = xghostty_terminal_new(NULL, &terminal, opts);
  assert(result == XGHOSTTY_SUCCESS);

  const char *text = "alpha\r\n"
                     "bravo\r\n"
                     "charlie";
  xghostty_terminal_vt_write(
      terminal, (const uint8_t *)text, strlen(text));

  XGhosttyTrackedGridRef tracked = NULL;
  XGhosttyPoint alpha = {
    .tag = XGHOSTTY_POINT_TAG_ACTIVE,
    .value = { .coordinate = { .x = 0, .y = 0 } },
  };
  result = xghostty_terminal_grid_ref_track(terminal, alpha, &tracked);
  assert(result == XGHOSTTY_SUCCESS);

  // Writing another line scrolls the original "alpha" row into scrollback.
  // The tracked ref still follows the same cell.
  const char *more = "\r\ndelta";
  xghostty_terminal_vt_write(
      terminal, (const uint8_t *)more, strlen(more));

  assert(xghostty_tracked_grid_ref_has_value(tracked));
  printf("tracked codepoint after scroll: %c\n",
      (char)codepoint_at_tracked_ref(tracked));

  XGhosttyPointCoordinate screen = {0};
  result = xghostty_tracked_grid_ref_point(
      tracked, XGHOSTTY_POINT_TAG_SCREEN, &screen);
  assert(result == XGHOSTTY_SUCCESS);
  printf("tracked screen point: %u,%u\n", screen.x, screen.y);

  // Resetting the terminal discards the old grid contents. The tracked
  // handle remains valid, but no longer has a meaningful location.
  xghostty_terminal_reset(terminal);
  assert(!xghostty_tracked_grid_ref_has_value(tracked));

  XGhosttyGridRef discarded = XGHOSTTY_INIT_SIZED(XGhosttyGridRef);
  result = xghostty_tracked_grid_ref_snapshot(tracked, &discarded);
  assert(result == XGHOSTTY_NO_VALUE);

  // The same handle can be moved to a new point after it loses its value.
  const char *replacement = "echo";
  xghostty_terminal_vt_write(
      terminal, (const uint8_t *)replacement, strlen(replacement));

  XGhosttyPoint echo = {
    .tag = XGHOSTTY_POINT_TAG_ACTIVE,
    .value = { .coordinate = { .x = 0, .y = 0 } },
  };
  result = xghostty_tracked_grid_ref_set(tracked, terminal, echo);
  assert(result == XGHOSTTY_SUCCESS);
  assert(xghostty_tracked_grid_ref_has_value(tracked));
  printf("tracked codepoint after reset/set: %c\n",
      (char)codepoint_at_tracked_ref(tracked));

  xghostty_tracked_grid_ref_free(tracked);
  xghostty_terminal_free(terminal);
  return 0;
}
//! [grid-ref-tracked]
