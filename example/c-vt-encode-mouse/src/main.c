#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <xghostty/vt.h>

//! [mouse-encode]
int main() {
  // Create encoder
  XGhosttyMouseEncoder encoder;
  XGhosttyResult result = xghostty_mouse_encoder_new(NULL, &encoder);
  assert(result == XGHOSTTY_SUCCESS);

  // Configure SGR format with normal tracking
  xghostty_mouse_encoder_setopt(encoder, XGHOSTTY_MOUSE_ENCODER_OPT_EVENT,
      &(XGhosttyMouseTrackingMode){XGHOSTTY_MOUSE_TRACKING_NORMAL});
  xghostty_mouse_encoder_setopt(encoder, XGHOSTTY_MOUSE_ENCODER_OPT_FORMAT,
      &(XGhosttyMouseFormat){XGHOSTTY_MOUSE_FORMAT_SGR});

  // Set terminal geometry for coordinate mapping
  xghostty_mouse_encoder_setopt(encoder, XGHOSTTY_MOUSE_ENCODER_OPT_SIZE,
      &(XGhosttyMouseEncoderSize){
          .size = sizeof(XGhosttyMouseEncoderSize),
          .screen_width = 800, .screen_height = 600,
          .cell_width = 10, .cell_height = 20,
      });

  // Create and configure a left button press event
  XGhosttyMouseEvent event;
  result = xghostty_mouse_event_new(NULL, &event);
  assert(result == XGHOSTTY_SUCCESS);
  xghostty_mouse_event_set_action(event, XGHOSTTY_MOUSE_ACTION_PRESS);
  xghostty_mouse_event_set_button(event, XGHOSTTY_MOUSE_BUTTON_LEFT);
  xghostty_mouse_event_set_position(event,
      (XGhosttyMousePosition){.x = 50.0f, .y = 40.0f});

  // Encode the mouse event
  char buf[128];
  size_t written = 0;
  result = xghostty_mouse_encoder_encode(encoder, event,
      buf, sizeof(buf), &written);
  assert(result == XGHOSTTY_SUCCESS);

  // Use the encoded sequence (e.g., write to terminal)
  fwrite(buf, 1, written, stdout);

  // Cleanup
  xghostty_mouse_event_free(event);
  xghostty_mouse_encoder_free(encoder);
  return 0;
}
//! [mouse-encode]
