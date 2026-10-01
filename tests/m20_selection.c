/* SPDX-License-Identifier: Apache-2.0 */
/* Actual selection FFI, with local allocation failures and no desktop helper. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <stdlib.h>
static int selection_fail_alloc, selection_fail_resize;
static void *selection_malloc(size_t n) {
  return selection_fail_alloc ? NULL : malloc(n);
}
static void *selection_realloc(void *p, size_t n) {
  return selection_fail_resize ? NULL : realloc(p, n);
}
#define malloc selection_malloc
#define realloc selection_realloc
#define main existing_shutdown_controls
#include "output_shutdown.c"
#undef main
#undef malloc
#undef realloc
#undef CHECK
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "m20_selection:%d: %s\n", __LINE__, #x); return 1; } } while (0)

static size_t selection_written;
static int selection_write(TimuiTransport *t, const void *p, size_t n) {
  (void)t; (void)p;
  selection_written += n;
  return n <= INT_MAX ? (int)n : -1;
}
static void *cell_alloc(void *ctx, size_t n) { (void)ctx; return malloc(n); }
static void *cell_resize(void *ctx, void *p, size_t old, size_t n) {
  (void)ctx; (void)old; return realloc(p, n);
}
static void cell_free(void *ctx, void *p, size_t n) { (void)ctx; (void)n; free(p); }

static int copy_case(size_t cluster_size, int rows, int fail) {
  char text[8194], expected[8200];
  TimuiAllocator allocator = {NULL, cell_alloc, cell_resize, cell_free};
  TimuiCellBuffer cells;
  Timui ui;
  BircUi state;
  size_t i = 0, expected_size;
  CHECK(cluster_size >= 1 && cluster_size <= 8191);
  if (cluster_size % 2 == 0) { text[i++] = (char)0xc3; text[i++] = (char)0xa9; }
  else text[i++] = 'e';
  while (i < cluster_size) { text[i++] = (char)0xcc; text[i++] = (char)0x81; }
  text[i++] = 'X'; text[i++] = ' '; text[i] = '\0';
  memcpy(expected, text, cluster_size + 1);
  expected_size = cluster_size + 1;
  if (rows == 2) { memcpy(expected + expected_size, "\néY", strlen("\néY")); expected_size += strlen("\néY"); }
  expected[expected_size] = '\0';
  CHECK(timui_cells_init(&cells, 3, rows, &allocator) == TIMUI_OK);
  timui_draw_text(&cells, 0, 0, (TimuiStr){text, i}, timui_style_make(TIMUI_COLOR_DEFAULT, TIMUI_COLOR_DEFAULT, 0));
  if (rows == 2) timui_draw_text(&cells, 0, 1, (TimuiStr){"éY ", strlen("éY ")}, timui_style_make(TIMUI_COLOR_DEFAULT, TIMUI_COLOR_DEFAULT, 0));
  memset(&ui, 0, sizeof ui); memset(&state, 0, sizeof state);
  ui.transport = (TimuiTransport){selection_write, NULL, NULL, NULL, NULL};
  state.sel.active = 1; state.sel.pane = (TimuiRect){0, 0, 3, rows};
  state.sel.cur_x = 2; state.sel.cur_y = rows - 1;
  state.clipboard = malloc(4); CHECK(state.clipboard); memcpy(state.clipboard, "old", 4);
  selection_written = 0;
  selection_fail_alloc = fail == 1; selection_fail_resize = fail == 2;
  birc_copy_selection(&ui, &cells, &state);
  selection_fail_alloc = 0; selection_fail_resize = 0;
  if (fail) { CHECK(!strcmp(state.clipboard, "old")); CHECK(selection_written == 0); }
  else { CHECK(strlen(state.clipboard) == expected_size); CHECK(!memcmp(state.clipboard, expected, expected_size)); CHECK(selection_written > 0); }
  free(state.clipboard); timui_cells_destroy(&cells);
  return 0;
}

static int attached_space(void) {
  static const char text[] = "e‍ ";
  TimuiAllocator allocator = {NULL, cell_alloc, cell_resize, cell_free};
  TimuiCellBuffer cells;
  Timui ui;
  BircUi state;
  CHECK(timui_cells_init(&cells, 2, 1, &allocator) == TIMUI_OK);
  timui_draw_text(&cells, 0, 0, (TimuiStr){text, sizeof text - 1}, timui_style_make(TIMUI_COLOR_DEFAULT, TIMUI_COLOR_DEFAULT, 0));
  memset(&ui, 0, sizeof ui); memset(&state, 0, sizeof state);
  ui.transport = (TimuiTransport){selection_write, NULL, NULL, NULL, NULL};
  state.sel.active = 1; state.sel.pane = (TimuiRect){0, 0, 2, 1}; state.sel.cur_x = 1;
  birc_copy_selection(&ui, &cells, &state);
  CHECK(state.clipboard && !strcmp(state.clipboard, text));
  free(state.clipboard); timui_cells_destroy(&cells);
  return 0;
}

int main(void) {
  CHECK(copy_case(3, 1, 0) == 0);
  CHECK(copy_case(2047, 1, 0) == 0);
  CHECK(copy_case(2048, 1, 0) == 0);
  CHECK(copy_case(2401, 1, 0) == 0);
  CHECK(copy_case(8191, 2, 0) == 0);
  CHECK(copy_case(3, 1, 1) == 0);
  CHECK(copy_case(8191, 2, 2) == 0);
  CHECK(attached_space() == 0);
  puts("m20_selection=ok");
  return 0;
}
