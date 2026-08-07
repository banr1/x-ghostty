#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <xghostty/vt.h>

//! [selection-gesture-main]
static void vt_write(XGhosttyTerminal terminal, const char *s) {
  xghostty_terminal_vt_write(terminal, (const uint8_t *)s, strlen(s));
}

static XGhosttyGridRef ref_at(XGhosttyTerminal terminal, uint16_t x, uint16_t y) {
  XGhosttyGridRef ref = XGHOSTTY_INIT_SIZED(XGhosttyGridRef);
  XGhosttyPoint point = {
    .tag = XGHOSTTY_POINT_TAG_ACTIVE,
    .value = { .coordinate = { .x = x, .y = y } },
  };

  XGhosttyResult result = xghostty_terminal_grid_ref(terminal, point, &ref);
  assert(result == XGHOSTTY_SUCCESS);
  return ref;
}

static void print_selection(
    XGhosttyTerminal terminal,
    const char *label,
    const XGhosttySelection *selection) {
  XGhosttyTerminalSelectionFormatOptions opts =
      XGHOSTTY_INIT_SIZED(XGhosttyTerminalSelectionFormatOptions);
  opts.emit = XGHOSTTY_FORMATTER_FORMAT_PLAIN;
  opts.trim = true;
  opts.selection = selection;

  uint8_t *buf = NULL;
  size_t len = 0;
  XGhosttyResult result = xghostty_terminal_selection_format_alloc(
      terminal, NULL, opts, &buf, &len);
  assert(result == XGHOSTTY_SUCCESS);

  printf("%s: ", label);
  fwrite(buf, 1, len, stdout);
  printf("\n");

  xghostty_free(NULL, buf, len);
}

static XGhosttySelectionGestureEvent new_event(
    XGhosttySelectionGestureEventType type) {
  XGhosttySelectionGestureEvent event = NULL;
  XGhosttyResult result = xghostty_selection_gesture_event_new(NULL, &event, type);
  assert(result == XGHOSTTY_SUCCESS);
  return event;
}

int main() {
  XGhosttyTerminal terminal;
  XGhosttyTerminalOptions opts = {
    .cols = 20,
    .rows = 4,
    .max_scrollback = 100,
  };
  XGhosttyResult result = xghostty_terminal_new(NULL, &terminal, opts);
  assert(result == XGHOSTTY_SUCCESS);

  vt_write(terminal, "hello world\r\nsecond line");

  XGhosttySelectionGesture gesture = NULL;
  result = xghostty_selection_gesture_new(NULL, &gesture);
  assert(result == XGHOSTTY_SUCCESS);

  XGhosttySelectionGestureEvent press =
      new_event(XGHOSTTY_SELECTION_GESTURE_EVENT_TYPE_PRESS);
  XGhosttySelectionGestureEvent drag =
      new_event(XGHOSTTY_SELECTION_GESTURE_EVENT_TYPE_DRAG);
  XGhosttySelectionGestureEvent release =
      new_event(XGHOSTTY_SELECTION_GESTURE_EVENT_TYPE_RELEASE);
  XGhosttySelectionGestureEvent deep_press =
      new_event(XGHOSTTY_SELECTION_GESTURE_EVENT_TYPE_DEEP_PRESS);

  XGhosttySelectionGestureGeometry geometry = {
    .columns = 20,
    .cell_width = 10,
    .padding_left = 0,
    .screen_height = 40,
  };

  // Press in the first cell. A normal single press records the click anchor but
  // doesn't produce a selection yet, so we discard the optional output.
  XGhosttyGridRef press_ref = ref_at(terminal, 0, 0);
  result = xghostty_selection_gesture_event_set(
      press, XGHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF, &press_ref);
  assert(result == XGHOSTTY_SUCCESS);

  XGhosttySurfacePosition press_pos = { .x = 2, .y = 8 };
  result = xghostty_selection_gesture_event_set(
      press, XGHOSTTY_SELECTION_GESTURE_EVENT_OPT_POSITION, &press_pos);
  assert(result == XGHOSTTY_SUCCESS);

  result = xghostty_selection_gesture_event(
      gesture, terminal, press, NULL);
  assert(result == XGHOSTTY_NO_VALUE);

  // Drag across "hello". The drag event returns a selection snapshot that the
  // embedder can apply to its UI, copy, or format immediately.
  XGhosttyGridRef drag_ref = ref_at(terminal, 4, 0);
  result = xghostty_selection_gesture_event_set(
      drag, XGHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF, &drag_ref);
  assert(result == XGHOSTTY_SUCCESS);

  XGhosttySurfacePosition drag_pos = { .x = 46, .y = 8 };
  result = xghostty_selection_gesture_event_set(
      drag, XGHOSTTY_SELECTION_GESTURE_EVENT_OPT_POSITION, &drag_pos);
  assert(result == XGHOSTTY_SUCCESS);

  result = xghostty_selection_gesture_event_set(
      drag, XGHOSTTY_SELECTION_GESTURE_EVENT_OPT_GEOMETRY, &geometry);
  assert(result == XGHOSTTY_SUCCESS);

  XGhosttySelection selection = XGHOSTTY_INIT_SIZED(XGhosttySelection);
  result = xghostty_selection_gesture_event(
      gesture, terminal, drag, &selection);
  assert(result == XGHOSTTY_SUCCESS);
  print_selection(terminal, "drag", &selection);

  // Release updates gesture state but never produces a selection.
  result = xghostty_selection_gesture_event_set(
      release, XGHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF, &drag_ref);
  assert(result == XGHOSTTY_SUCCESS);
  result = xghostty_selection_gesture_event(
      gesture, terminal, release, NULL);
  assert(result == XGHOSTTY_NO_VALUE);

  bool dragged = false;
  result = xghostty_selection_gesture_get(
      gesture, terminal, XGHOSTTY_SELECTION_GESTURE_DATA_DRAGGED, &dragged);
  assert(result == XGHOSTTY_SUCCESS);
  printf("dragged: %s\n", dragged ? "true" : "false");

  // Deep press uses the active click anchor to select the surrounding word.
  xghostty_selection_gesture_reset(gesture, terminal);
  XGhosttyGridRef world_ref = ref_at(terminal, 6, 0);
  result = xghostty_selection_gesture_event_set(
      press, XGHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF, &world_ref);
  assert(result == XGHOSTTY_SUCCESS);
  result = xghostty_selection_gesture_event(
      gesture, terminal, press, NULL);
  assert(result == XGHOSTTY_NO_VALUE);

  result = xghostty_selection_gesture_event(
      gesture, terminal, deep_press, &selection);
  assert(result == XGHOSTTY_SUCCESS);
  print_selection(terminal, "deep press", &selection);

  xghostty_selection_gesture_event_free(deep_press);
  xghostty_selection_gesture_event_free(release);
  xghostty_selection_gesture_event_free(drag);
  xghostty_selection_gesture_event_free(press);
  xghostty_selection_gesture_free(gesture, terminal);
  xghostty_terminal_free(terminal);
  return 0;
}
//! [selection-gesture-main]
