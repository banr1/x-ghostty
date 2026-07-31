#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <xghostty/vt.h>

int main(void) {
  //! [vt-stream-init]
  // Create a terminal
  XGhosttyTerminal terminal;
  XGhosttyTerminalOptions opts = {
    .cols = 80,
    .rows = 24,
    .max_scrollback = 0,
  };
  XGhosttyResult result = xghostty_terminal_new(NULL, &terminal, opts);
  assert(result == XGHOSTTY_SUCCESS);
  //! [vt-stream-init]

  //! [vt-stream-write]
  // Feed VT data into the terminal
  const char *text = "Hello, World!\r\n";
  xghostty_terminal_vt_write(terminal, (const uint8_t *)text, strlen(text));

  // ANSI color codes: ESC[1;32m = bold green, ESC[0m = reset
  text = "\x1b[1;32mGreen Text\x1b[0m\r\n";
  xghostty_terminal_vt_write(terminal, (const uint8_t *)text, strlen(text));

  // Cursor positioning: ESC[1;1H = move to row 1, column 1
  text = "\x1b[1;1HTop-left corner\r\n";
  xghostty_terminal_vt_write(terminal, (const uint8_t *)text, strlen(text));

  // Cursor movement: ESC[5B = move down 5 lines
  text = "\x1b[5B";
  xghostty_terminal_vt_write(terminal, (const uint8_t *)text, strlen(text));
  text = "Moved down!\r\n";
  xghostty_terminal_vt_write(terminal, (const uint8_t *)text, strlen(text));

  // Erase line: ESC[2K = clear entire line
  text = "\x1b[2K";
  xghostty_terminal_vt_write(terminal, (const uint8_t *)text, strlen(text));
  text = "New content\r\n";
  xghostty_terminal_vt_write(terminal, (const uint8_t *)text, strlen(text));

  // Multiple lines
  text = "Line A\r\nLine B\r\nLine C\r\n";
  xghostty_terminal_vt_write(terminal, (const uint8_t *)text, strlen(text));
  //! [vt-stream-write]

  //! [vt-stream-read]
  // Get the final terminal state as a plain string using the formatter
  XGhosttyFormatterTerminalOptions fmt_opts =
      XGHOSTTY_INIT_SIZED(XGhosttyFormatterTerminalOptions);
  fmt_opts.emit = XGHOSTTY_FORMATTER_FORMAT_PLAIN;
  fmt_opts.trim = true;

  XGhosttyFormatter formatter;
  result = xghostty_formatter_terminal_new(NULL, &formatter, terminal, fmt_opts);
  assert(result == XGHOSTTY_SUCCESS);

  uint8_t *buf = NULL;
  size_t len = 0;
  result = xghostty_formatter_format_alloc(formatter, NULL, &buf, &len);
  assert(result == XGHOSTTY_SUCCESS);

  fwrite(buf, 1, len, stdout);
  printf("\n");

  xghostty_free(NULL, buf, len);
  xghostty_formatter_free(formatter);
  //! [vt-stream-read]

  xghostty_terminal_free(terminal);
  return 0;
}
