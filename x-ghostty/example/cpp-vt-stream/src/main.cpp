#include <cassert>
#include <cstdio>
#include <cstring>
#include <xghostty/vt.h>

int main() {
  // Create a terminal
  XGhosttyTerminal terminal;
  XGhosttyTerminalOptions opts = {
    .cols = 80,
    .rows = 24,
    .max_scrollback = 0,
  };
  XGhosttyResult result = xghostty_terminal_new(nullptr, &terminal, opts);
  assert(result == XGHOSTTY_SUCCESS);

  // Feed VT data into the terminal
  const char *text = "Hello from C++!\r\n";
  xghostty_terminal_vt_write(terminal, reinterpret_cast<const uint8_t *>(text), std::strlen(text));

  text = "\x1b[1;32mGreen Text\x1b[0m\r\n";
  xghostty_terminal_vt_write(terminal, reinterpret_cast<const uint8_t *>(text), std::strlen(text));

  text = "\x1b[1;1HTop-left corner\r\n";
  xghostty_terminal_vt_write(terminal, reinterpret_cast<const uint8_t *>(text), std::strlen(text));

  // Get the final terminal state as a plain string
  XGhosttyFormatterTerminalOptions fmt_opts =
      XGHOSTTY_INIT_SIZED(XGhosttyFormatterTerminalOptions);
  fmt_opts.emit = XGHOSTTY_FORMATTER_FORMAT_PLAIN;
  fmt_opts.trim = true;

  XGhosttyFormatter formatter;
  result = xghostty_formatter_terminal_new(nullptr, &formatter, terminal, fmt_opts);
  assert(result == XGHOSTTY_SUCCESS);

  uint8_t *buf = nullptr;
  size_t len = 0;
  result = xghostty_formatter_format_alloc(formatter, nullptr, &buf, &len);
  assert(result == XGHOSTTY_SUCCESS);

  std::fwrite(buf, 1, len, stdout);
  std::printf("\n");

  xghostty_free(nullptr, buf, len);
  xghostty_formatter_free(formatter);
  xghostty_terminal_free(terminal);
  return 0;
}
