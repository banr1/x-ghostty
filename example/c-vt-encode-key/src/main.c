#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <xghostty/vt.h>

//! [key-encode]
int main() {
  // Create encoder
  XGhosttyKeyEncoder encoder;
  XGhosttyResult result = xghostty_key_encoder_new(NULL, &encoder);
  assert(result == XGHOSTTY_SUCCESS);

  // Enable Kitty keyboard protocol with all features
  xghostty_key_encoder_setopt(encoder, XGHOSTTY_KEY_ENCODER_OPT_KITTY_FLAGS,
                             &(uint8_t){XGHOSTTY_KITTY_KEY_ALL});

  // Create and configure key event for Ctrl+C press
  XGhosttyKeyEvent event;
  result = xghostty_key_event_new(NULL, &event);
  assert(result == XGHOSTTY_SUCCESS);
  xghostty_key_event_set_action(event, XGHOSTTY_KEY_ACTION_PRESS);
  xghostty_key_event_set_key(event, XGHOSTTY_KEY_C);
  xghostty_key_event_set_mods(event, XGHOSTTY_MODS_CTRL);

  // Encode the key event
  char buf[128];
  size_t written = 0;
  result = xghostty_key_encoder_encode(encoder, event, buf, sizeof(buf), &written);
  assert(result == XGHOSTTY_SUCCESS);

  // Use the encoded sequence (e.g., write to terminal)
  fwrite(buf, 1, written, stdout);

  // Cleanup
  xghostty_key_event_free(event);
  xghostty_key_encoder_free(encoder);
  return 0;
}
//! [key-encode]
