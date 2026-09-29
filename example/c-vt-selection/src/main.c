#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <xghostty/vt.h>

//! [selection-main]
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
  XGhosttyFormatterTerminalOptions opts = XGHOSTTY_INIT_SIZED(XGhosttyFormatterTerminalOptions);
  opts.emit = XGHOSTTY_FORMATTER_FORMAT_PLAIN;
  opts.trim = true;
  opts.selection = selection;

  XGhosttyFormatter formatter;
  XGhosttyResult result = xghostty_formatter_terminal_new(
      NULL, &formatter, terminal, opts);
  assert(result == XGHOSTTY_SUCCESS);

  uint8_t *buf = NULL;
  size_t len = 0;
  result = xghostty_formatter_format_alloc(formatter, NULL, &buf, &len);
  assert(result == XGHOSTTY_SUCCESS);

  printf("%s: ", label);
  fwrite(buf, 1, len, stdout);
  printf("\n");

  xghostty_free(NULL, buf, len);
  xghostty_formatter_free(formatter);
}

int main() {
  XGhosttyTerminal terminal;
  XGhosttyTerminalOptions opts = {
    .cols = 80,
    .rows = 8,
    .max_scrollback = 0,
  };
  XGhosttyResult result = xghostty_terminal_new(NULL, &terminal, opts);
  assert(result == XGHOSTTY_SUCCESS);

  // A realistic shell transcript with OSC 133 semantic prompt markers.
  // XGhostty uses these markers to distinguish prompt/input from command
  // output for semantic line and output selections.
  vt_write(terminal,
      "\033]133;A\007$ "           // Prompt starts: "$ "
      "\033]133;B\007git status"  // Input starts: "git status"
      "\033]133;C\007\r\n"        // Output starts after Enter
      "On branch main\r\n"
      "nothing to commit, working tree clean");

  XGhosttySelection selection = XGHOSTTY_INIT_SIZED(XGhosttySelection);

  // Double-click style word selection under the cursor.
  XGhosttyTerminalSelectWordOptions word = XGHOSTTY_INIT_SIZED(XGhosttyTerminalSelectWordOptions);
  word.ref = ref_at(terminal, 6, 0); // the "status" in "git status"
  result = xghostty_terminal_select_word(terminal, &word, &selection);
  assert(result == XGHOSTTY_SUCCESS);
  print_selection(terminal, "word", &selection);

  //! [selection-word-between]
  // Double-click-and-drag style selection. Suppose the user double-clicks
  // "git" and drags to "status". The pointer may pass over whitespace, so
  // select the nearest word between the original click and current drag point
  // in both directions, then combine the outer word bounds.
  XGhosttyGridRef click_ref = ref_at(terminal, 2, 0); // the "git" in "git status"
  XGhosttyGridRef drag_ref = ref_at(terminal, 6, 0);  // the "status" in "git status"

  XGhosttyTerminalSelectWordBetweenOptions start_word_opts =
      XGHOSTTY_INIT_SIZED(XGhosttyTerminalSelectWordBetweenOptions);
  start_word_opts.start = click_ref;
  start_word_opts.end = drag_ref;

  XGhosttySelection start_word = XGHOSTTY_INIT_SIZED(XGhosttySelection);
  result = xghostty_terminal_select_word_between(
      terminal, &start_word_opts, &start_word);
  assert(result == XGHOSTTY_SUCCESS);

  XGhosttyTerminalSelectWordBetweenOptions end_word_opts =
      XGHOSTTY_INIT_SIZED(XGhosttyTerminalSelectWordBetweenOptions);
  end_word_opts.start = drag_ref;
  end_word_opts.end = click_ref;

  XGhosttySelection end_word = XGHOSTTY_INIT_SIZED(XGhosttySelection);
  result = xghostty_terminal_select_word_between(
      terminal, &end_word_opts, &end_word);
  assert(result == XGHOSTTY_SUCCESS);

  XGhosttySelection drag_selection = XGHOSTTY_INIT_SIZED(XGhosttySelection);
  drag_selection.start = start_word.start;
  drag_selection.end = end_word.end;
  print_selection(terminal, "double-click drag", &drag_selection);
  //! [selection-word-between]

  // Triple-click style line selection. With semantic prompt boundaries enabled,
  // this selects only the input area rather than the leading "$ " prompt.
  XGhosttyTerminalSelectLineOptions line = XGHOSTTY_INIT_SIZED(XGhosttyTerminalSelectLineOptions);
  line.ref = ref_at(terminal, 2, 0); // the "git status" input area
  line.semantic_prompt_boundary = true;
  result = xghostty_terminal_select_line(terminal, &line, &selection);
  assert(result == XGHOSTTY_SUCCESS);
  print_selection(terminal, "line", &selection);

  // Select exactly the command output for the command under the cursor.
  result = xghostty_terminal_select_output(
      terminal, ref_at(terminal, 0, 1), &selection);
  assert(result == XGHOSTTY_SUCCESS);
  print_selection(terminal, "output", &selection);

  // Select all visible content.
  result = xghostty_terminal_select_all(terminal, &selection);
  assert(result == XGHOSTTY_SUCCESS);
  print_selection(terminal, "all", &selection);

  xghostty_terminal_free(terminal);
  return 0;
}
//! [selection-main]
