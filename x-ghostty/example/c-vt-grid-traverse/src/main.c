#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <xghostty/vt.h>

//! [grid-ref-traverse]
int main() {
  // Create a small terminal
  XGhosttyTerminal terminal;
  XGhosttyTerminalOptions opts = {
    .cols = 10,
    .rows = 3,
    .max_scrollback = 0,
  };
  XGhosttyResult result = xghostty_terminal_new(NULL, &terminal, opts);
  assert(result == XGHOSTTY_SUCCESS);

  // Write some content so the grid has interesting data
  const char *text = "Hello!\r\n"    // Row 0: H e l l o !
                     "World\r\n"     // Row 1: W o r l d
                     "\033[1mBold";   // Row 2: B o l d (bold style)
  xghostty_terminal_vt_write(
      terminal, (const uint8_t *)text, strlen(text));

  // Get terminal dimensions
  uint16_t cols, rows;
  xghostty_terminal_get(terminal, XGHOSTTY_TERMINAL_DATA_COLS, &cols);
  xghostty_terminal_get(terminal, XGHOSTTY_TERMINAL_DATA_ROWS, &rows);

  // Traverse the entire grid using grid refs
  for (uint16_t row = 0; row < rows; row++) {
    printf("Row %u: ", row);
    for (uint16_t col = 0; col < cols; col++) {
      // Resolve the point to a grid reference
      XGhosttyGridRef ref = XGHOSTTY_INIT_SIZED(XGhosttyGridRef);
      XGhosttyPoint pt = {
        .tag = XGHOSTTY_POINT_TAG_ACTIVE,
        .value = { .coordinate = { .x = col, .y = row } },
      };
      result = xghostty_terminal_grid_ref(terminal, pt, &ref);
      assert(result == XGHOSTTY_SUCCESS);

      // Read the cell from the grid ref
      XGhosttyCell cell;
      result = xghostty_grid_ref_cell(&ref, &cell);
      assert(result == XGHOSTTY_SUCCESS);

      // Check if the cell has text
      bool has_text = false;
      xghostty_cell_get(cell, XGHOSTTY_CELL_DATA_HAS_TEXT, &has_text);

      if (has_text) {
        uint32_t codepoint = 0;
        xghostty_cell_get(cell, XGHOSTTY_CELL_DATA_CODEPOINT, &codepoint);
        printf("%c", (char)codepoint);
      } else {
        printf(".");
      }
    }

    // Also inspect the row for wrap state
    XGhosttyGridRef ref = XGHOSTTY_INIT_SIZED(XGhosttyGridRef);
    XGhosttyPoint pt = {
      .tag = XGHOSTTY_POINT_TAG_ACTIVE,
      .value = { .coordinate = { .x = 0, .y = row } },
    };
    xghostty_terminal_grid_ref(terminal, pt, &ref);

    XGhosttyRow grid_row;
    xghostty_grid_ref_row(&ref, &grid_row);

    bool wrap = false;
    xghostty_row_get(grid_row, XGHOSTTY_ROW_DATA_WRAP, &wrap);
    printf(" (wrap=%s", wrap ? "true" : "false");

    // Check the style of the first cell with text
    XGhosttyStyle style = XGHOSTTY_INIT_SIZED(XGhosttyStyle);
    xghostty_grid_ref_style(&ref, &style);
    printf(", bold=%s)\n", style.bold ? "true" : "false");
  }

  xghostty_terminal_free(terminal);
  return 0;
}
//! [grid-ref-traverse]
