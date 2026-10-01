/* SPDX-License-Identifier: Apache-2.0
 * Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
 * Actual native cluster measurement, tab layout, and code-widget storage. */
#define _POSIX_C_SOURCE 200809L
#define TIMUI_IMPLEMENTATION
#include "timui.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "ui_review_widgets:%d: %s\n", __LINE__, #x); return 1; } } while (0)

static int discard_write(TimuiTransport *t, const void *p, size_t n) {
  (void)t; (void)p;
  return n > INT_MAX ? -1 : (int)n;
}
static int empty_read(TimuiTransport *t, void *p, size_t n) {
  (void)t; (void)p; (void)n;
  return 0;
}
static int cluster_is(TimuiCellBuffer *b, int x, int y, const char *s, int width) {
  const TimuiCell *cell = &b->cells[y * b->w + x];
  TimuiStr glyph = timui_cell_grapheme(b, cell);
  return cell->width == width && glyph.len == strlen(s) &&
         glyph.ptr && !memcmp(glyph.ptr, s, glyph.len);
}
static int click_tab(Timui *ui, TimuiFrame *f, const char *const *labels, int x) {
  int selected = 0;
  timui_interact_set_mouse(&ui->ia, x, 0, 1);
  timui_interact_begin(&ui->ia);
  (void)timui_tabs(f, TIMUI_ID("click"), TIMUI_RECT(0, 0, 13, 1), labels, 3, &selected);
  timui_interact_set_mouse(&ui->ia, x, 0, 0);
  timui_interact_begin(&ui->ia);
  return timui_tabs(f, TIMUI_ID("click"), TIMUI_RECT(0, 0, 13, 1), labels, 3, &selected);
}
static int tabs(void) {
  const char *labels[] = {"👩‍💻", "❤️", "x"};
  const char *controls[] = {"abc", "é", "👍🏽"};
  TimuiTabSpan spans[3];
  Timui *ui;
  TimuiFrame *f;
  TimuiCellBuffer *b;
  TimuiTransport transport = {discard_write, empty_read, NULL, NULL, NULL};
  TimuiAllocator allocator = timui_default_allocator();
  int selected = 0;
  CHECK(timui_tabs_layout(controls, 3, 1, spans, 3) == 14);
  CHECK(spans[0].w == 5 && spans[1].w == 3 && spans[2].w == 4);
  CHECK(timui_tabs_layout(labels, 3, 1, spans, 3) == 13);
  CHECK(spans[0].x == 0 && spans[0].w == 4);
  CHECK(spans[1].x == 5 && spans[1].w == 4);
  CHECK(spans[2].x == 10 && spans[2].w == 3);
  CHECK(timui_tabs_scroll(spans, 3, 1, 4, 0) == 5);
  CHECK(!timui_tab_visible(spans[0], 5, 4));
  CHECK(timui_tab_visible(spans[1], 5, 4));
  CHECK(timui_open_for_test(&ui, transport, 13, 2, &allocator) == TIMUI_OK);
  CHECK(timui_begin(ui, &f));
  CHECK(timui_tabs(f, TIMUI_ID("clusters"), TIMUI_RECT(0, 0, 13, 1), labels, 3, &selected) == 0);
  b = timui_frame_buffer(f);
  CHECK(cluster_is(b, 1, 0, labels[0], 2));
  CHECK(cluster_is(b, 6, 0, labels[1], 2));
  CHECK(b->cells[11].codepoint == 'x');
  CHECK(click_tab(ui, f, labels, 4) == 0); /* separator is not either label */
  CHECK(click_tab(ui, f, labels, 5) == 1); /* second tab starts here, not at 7 */
  CHECK(click_tab(ui, f, labels, 11) == 2); /* ordinary label remains clickable */
  selected = 1;
  CHECK(timui_tabs(f, TIMUI_ID("tight"), TIMUI_RECT(0, 1, 4, 1), labels, 3, &selected) == 1);
  CHECK(cluster_is(b, 1, 1, labels[1], 2));
  CHECK(b->cells[b->w].codepoint == ' ' && b->cells[b->w + 3].codepoint == ' ');
  timui_end(f);
  timui_close(ui);
  return 0;
}
static int code(void) {
  static const char source[] = "é 👍🏽 👩‍💻 ❤️\n// é👩‍💻\n+́x";
  Timui *ui;
  TimuiFrame *f;
  TimuiCellBuffer *b;
  TimuiTransport transport = {discard_write, empty_read, NULL, NULL, NULL};
  TimuiAllocator allocator = timui_default_allocator();
  int scroll = 0;
  CHECK(timui_open_for_test(&ui, transport, 24, 4, &allocator) == TIMUI_OK);
  CHECK(timui_begin(ui, &f));
  timui_code(f, TIMUI_RECT(0, 0, 24, 3), source, (int)sizeof source - 1, "c", &scroll);
  b = timui_frame_buffer(f);
  CHECK(b->cells[0].codepoint == '1'); /* ordinary gutter */
  CHECK(cluster_is(b, 2, 0, "é", 1));
  CHECK(cluster_is(b, 4, 0, "👍🏽", 2));
  CHECK(cluster_is(b, 7, 0, "👩‍💻", 2));
  CHECK(cluster_is(b, 10, 0, "❤️", 2));
  CHECK(cluster_is(b, 5, 1, "é", 1));
  CHECK(b->cells[b->w + 5].fg == timui_hl_color(TIMUI_HL_COMMENT));
  CHECK(cluster_is(b, 6, 1, "👩‍💻", 2));
  CHECK(cluster_is(b, 2, 2, "+́", 1));
  CHECK(b->cells[2 * b->w + 2].fg == timui_hl_color(TIMUI_HL_PUNCT));
  CHECK(b->cells[2 * b->w + 3].codepoint == 'x');
  timui_hl_draw_line(f, 0, 3, 2, "👩‍💻x", (int)strlen("👩‍💻x"), "c");
  CHECK(cluster_is(b, 0, 3, "👩‍💻", 2));
  CHECK(!b->cells[3 * b->w + 2].codepoint);
  timui_hl_draw_line(f, 3, 3, 5, "\xffx", 2, "c");
  CHECK(b->cells[3 * b->w + 3].codepoint == 0xfffd);
  CHECK(b->cells[3 * b->w + 4].codepoint == 'x');
  timui_end(f);
  timui_close(ui);
  return 0;
}
static void widths(int argc, char **argv) {
  int j;
  for (j = 2; j < argc; j++) {
    const char *s = argv[j];
    size_t len = strlen(s), end = timui_grapheme_next(s, len, 0), i = 0, count = 0;
    while (i < end) {
      int n = timui_utf8_decode(s + i, end - i, NULL);
      i += n > 0 ? (size_t)n : 1;
      count++;
    }
    printf("%d %d %zu\n", timui_display_width(s), timui_grapheme_width(s, len), count);
  }
}
int main(int argc, char **argv) {
  if (argc > 1 && !strcmp(argv[1], "--columns")) { widths(argc, argv); return 0; }
  if (argc == 1 || !strcmp(argv[1], "tabs")) CHECK(tabs() == 0);
  if (argc == 1 || !strcmp(argv[1], "code")) CHECK(code() == 0);
  puts("ui_review_widgets=ok");
  return 0;
}
