#include <stdio.h>
#include <xghostty/vt.h>

//! [focus-encode]
int main() {
  char buf[8];
  size_t written = 0;

  XGhosttyResult result = xghostty_focus_encode(
      XGHOSTTY_FOCUS_GAINED, buf, sizeof(buf), &written);

  if (result == XGHOSTTY_SUCCESS) {
    printf("Encoded %zu bytes: ", written);
    fwrite(buf, 1, written, stdout);
    printf("\n");
  }

  return 0;
}
//! [focus-encode]
