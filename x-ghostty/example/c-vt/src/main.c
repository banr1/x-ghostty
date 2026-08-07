#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <xghostty/vt.h>

int main() {
  XGhosttyOscParser parser;
  if (xghostty_osc_new(NULL, &parser) != XGHOSTTY_SUCCESS) {
    return 1;
  }
  
  // Setup change window title command to change the title to "hello"
  xghostty_osc_next(parser, '0');
  xghostty_osc_next(parser, ';');
  const char *title = "hello";
  for (size_t i = 0; i < strlen(title); i++) {
    xghostty_osc_next(parser, title[i]);
  }
  
  // End parsing and get command
  XGhosttyOscCommand command = xghostty_osc_end(parser, 0);
  
  // Get and print command type
  XGhosttyOscCommandType type = xghostty_osc_command_type(command);
  printf("Command type: %d\n", type);
  
  // Extract and print the title
  if (xghostty_osc_command_data(command, XGHOSTTY_OSC_DATA_CHANGE_WINDOW_TITLE_STR, &title)) {
    printf("Extracted title: %s\n", title);
  } else {
    printf("Failed to extract title\n");
  }
  
  xghostty_osc_free(parser);
  return 0;
}
