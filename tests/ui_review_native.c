/* SPDX-License-Identifier: Apache-2.0 */
/* Actual painter and selection FFI; no network or clipboard process. */
#define main ui_review_transport_controls
#include "output_shutdown.c"
#undef main
#undef CHECK
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "ui_review_native:%d: %s\n", __LINE__, #x); return 1; } } while (0)

typedef struct {
  unsigned char bytes[32768];
  size_t size;
  int live, refuse;
} Review;

static int review_write(TimuiTransport *t, const void *p, size_t n) {
  Review *r = t->ctx;
  if (n > sizeof r->bytes - r->size) return -1;
  memcpy(r->bytes + r->size, p, n); r->size += n;
  return (int)n;
}
static int review_read(TimuiTransport *t, void *p, size_t n) {
  (void)t; (void)p; (void)n; return 0;
}
static void *review_alloc(void *ctx, size_t n) {
  Review *r = ctx;
  void *p = r->refuse ? NULL : malloc(n);
  if (p) r->live++;
  return p;
}
static void *review_resize(void *ctx, void *p, size_t old, size_t n) {
  Review *r = ctx;
  (void)old;
  if (r->refuse) return NULL;
  if (!p) return review_alloc(ctx, n);
  return realloc(p, n);
}
static void review_free(void *ctx, void *p, size_t n) {
  Review *r = ctx;
  (void)n;
  if (p) { r->live--; free(p); }
}
static int review_contains(const Review *r, const char *text) {
  size_t i, n = strlen(text);
  for (i = 0; i + n <= r->size; i++)
    if (!memcmp(r->bytes + i, text, n)) return 1;
  return 0;
}
static void review_render(Review *r, TimuiCellBuffer *a, TimuiCellBuffer *b) {
  TimuiRenderer renderer;
  TimuiTransport transport = {review_write, NULL, NULL, NULL, r};
  r->size = 0;
  timui_renderer_reset(&renderer);
  timui_render_diff(&transport, a, b, &renderer);
}

static int fidelity(void) {
  static const char text[] = "ASCII é é 👍🏽 👩‍💻 ❤︎";
  Review r = {0};
  TimuiAllocator allocator = {&r, review_alloc, review_resize, review_free};
  TimuiCellBuffer a, b;
  Timui ui;
  BircUi state;
  CHECK(timui_cells_init(&a, 40, 1, &allocator) == TIMUI_OK);
  CHECK(timui_cells_init(&b, 40, 1, &allocator) == TIMUI_OK);
  timui_draw_text(&b, 0, 0, (TimuiStr){text, sizeof text - 1}, timui_style_make(TIMUI_COLOR_DEFAULT, TIMUI_COLOR_DEFAULT, 0));
  review_render(&r, &a, &b);
  CHECK(review_contains(&r, text));
  CHECK(b.cells[13].width == 2 && (b.cells[14].flags & TIMUI_CELL_CONTINUATION));
  memset(&ui, 0, sizeof ui); memset(&state, 0, sizeof state);
  ui.transport = (TimuiTransport){review_write, NULL, NULL, NULL, &r};
  state.sel.active = 1; state.sel.pane = (TimuiRect){0,0,40,1};
  state.sel.cur_x = 39;
  birc_copy_selection(&ui, &b, &state);
  CHECK(state.clipboard && !strcmp(state.clipboard, text));
  free(state.clipboard);
  timui_cells_destroy(&a); timui_cells_destroy(&b);
  CHECK(r.live == 0);
  return 0;
}

static int exact_links(void) {
  Review r = {0};
  TimuiAllocator allocator = {&r, review_alloc, review_resize, review_free};
  TimuiCellBuffer a, b;
  char url[1026], open[1040];
  uint32_t id;
  CHECK(timui_cells_init(&a, 4, 1, &allocator) == TIMUI_OK);
  CHECK(timui_cells_init(&b, 4, 1, &allocator) == TIMUI_OK);
  memcpy(url, "https://example.test/", 21);
  memset(url + 21, 'a', 1003); url[1024] = '\0';
  id = timui_hyperlink_set(&b, url); CHECK(id != 0);
  timui_draw_text_linked(&b, 0, 0, (TimuiStr){"link", 4}, timui_style_make(TIMUI_COLOR_DEFAULT, TIMUI_COLOR_DEFAULT, 0), id);
  review_render(&r, &a, &b);
  CHECK(snprintf(open, sizeof open, "\x1b]8;;%s\x1b\\", url) > 0);
  CHECK(review_contains(&r, open));
  url[1024] = 'b'; url[1025] = '\0';
  CHECK(timui_hyperlink_set(&b, url) == 0); /* decline, never a prefix */
  timui_cells_destroy(&a); timui_cells_destroy(&b);
  CHECK(r.live == 0);
  return 0;
}

static int ownership(void) {
  Review r = {0};
  TimuiAllocator allocator = {&r, review_alloc, review_resize, review_free};
  TimuiCellBuffer a, b, temporary;
  TimuiStyle style = timui_style_make(TIMUI_COLOR_DEFAULT, TIMUI_COLOR_DEFAULT, 0);
  TimuiStr glyph;
  TimuiCell foreign;
  char source[] = "é", snapshot[2048], many[603];
  size_t i, old_size;
  CHECK(timui_cells_init(&a, 8, 2, &allocator) == TIMUI_OK);
  CHECK(timui_cells_init(&b, 8, 2, &allocator) == TIMUI_OK);
  timui_draw_text(&a, 0, 0, (TimuiStr){source, sizeof source - 1}, style);
  memset(source, 'x', sizeof source - 1); /* no borrowed caller bytes */
  glyph = timui_cell_grapheme(&a, &a.cells[0]);
  CHECK(glyph.len == strlen("é") && !memcmp(glyph.ptr, "é", glyph.len));
  timui_draw_text(&b, 0, 0, (TimuiStr){"è", strlen("è")}, style);
  CHECK(!timui_grid_eq(&a, &b, snapshot, sizeof snapshot));
  CHECK(strstr(snapshot, "65CC81") && strstr(snapshot, "65CC80"));
  review_render(&r, &a, &b); CHECK(review_contains(&r, "è"));
  /* Same base cp and foreign offset cannot borrow unrelated local bytes. */
  foreign = a.cells[0]; CHECK(timui_cells_put(&b, 0, 0, &foreign));
  CHECK(!timui_cell_grapheme(&b, &b.cells[0]).len);
  timui_draw_text(&b, 0, 1, (TimuiStr){"👍🏽", strlen("👍🏽")}, style);
  timui_draw_fill(&a, (TimuiRect){0,1,8,1}, style);
  timui_draw_fill(&b, (TimuiRect){0,1,8,1}, style);
  timui_draw_text(&b, 0, 0, (TimuiStr){"é", strlen("é")}, style);
  CHECK(a.cells[0].grapheme_offset != b.cells[0].grapheme_offset);
  CHECK(timui_grid_eq(&a, &b, NULL, 0));
  review_render(&r, &a, &b); CHECK(r.size == 0); /* compare bytes, not offsets */
  CHECK(timui_snapshot_grid(&a, snapshot, sizeof snapshot) > 0);
  CHECK(strstr(snapshot, "e{65CC81}"));
  temporary = a; a = b; b = temporary; /* ownership follows buffer swaps */
  CHECK(timui_grid_eq(&a, &b, NULL, 0));
  timui_draw_text(&a, 2, 0, (TimuiStr){"👩‍💻", strlen("👩‍💻")}, style);
  CHECK(a.cells[2].width == 2 && (a.cells[3].flags & TIMUI_CELL_CONTINUATION));
  timui_draw_text(&a, 3, 0, (TimuiStr){"x", 1}, style);
  CHECK(!a.cells[2].codepoint && !a.cells[2].grapheme_len);
  CHECK(a.cells[3].codepoint == 'x' && !a.cells[3].grapheme_len);
  old_size = a.grapheme_size;
  a.has_clip = 1; a.clip = (TimuiRect){0,0,1,1};
  timui_draw_text(&a, 0, 0, (TimuiStr){"👩‍💻", strlen("👩‍💻")}, style);
  CHECK(a.grapheme_size == old_size); /* clipped clusters allocate nothing */
  a.has_clip = 0;
  a.cells[0].codepoint = 'x';
  CHECK(!timui_cell_grapheme(&a, &a.cells[0]).len);
  timui_draw_text(&a, 0, 0, (TimuiStr){"⠁́", strlen("⠁́")}, style);
  timui_chart_put_dot_(&a, (TimuiRect){0,0,1,1}, 0, 0, 0);
  CHECK(a.cells[0].codepoint == 0x2801 && !a.cells[0].grapheme_len);
  /* Force growth, then paint a borrowed cluster back into its owning arena. */
  many[0] = 'e';
  for (i = 1; i < sizeof many - 2; i += 2) { many[i] = (char)0xCC; many[i + 1] = (char)0x81; }
  timui_draw_text(&a, 0, 0, (TimuiStr){many, 601}, style);
  glyph = timui_cell_grapheme(&a, &a.cells[0]);
  CHECK(glyph.len == 601);
  timui_draw_text(&a, 1, 0, glyph, style);
  glyph = timui_cell_grapheme(&a, &a.cells[1]);
  CHECK(glyph.len == 601 && !memcmp(glyph.ptr, many, 601));
  r.refuse = 1; old_size = a.grapheme_size;
  CHECK(timui_cells_resize(&a, 40, 2, &allocator) == TIMUI_ERR_OUT_OF_MEMORY);
  CHECK(a.w == 8 && a.grapheme_size == old_size);
  r.refuse = 0;
  CHECK(timui_cells_resize(&a, 40, 2, &allocator) == TIMUI_OK);
  CHECK(a.grapheme_size == 0 && !a.cells[0].grapheme_len);
  timui_cells_destroy(&a); timui_cells_destroy(&b);
  CHECK(r.live == 0);
  CHECK(timui_cells_init(&a, 4, 1, &allocator) == TIMUI_OK);
  CHECK(timui_cells_init(&b, 4, 1, &allocator) == TIMUI_OK);
  r.refuse = 1;
  timui_draw_text(&a, 0, 0, (TimuiStr){"é", strlen("é")}, style);
  CHECK(a.cells[0].codepoint == 0xFFFD && !a.cells[0].grapheme_len);
  timui_draw_text(&a, 0, 0, (TimuiStr){"👩‍💻", strlen("👩‍💻")}, style);
  timui_draw_text(&a, 2, 0, (TimuiStr){"x", 1}, style);
  CHECK(a.cells[0].width == 1 && !(a.cells[1].flags & TIMUI_CELL_CONTINUATION));
  review_render(&r, &b, &a); CHECK(review_contains(&r, "�\x1b[1;3Hx"));
  r.refuse = 0;
  timui_draw_text(&a, 1, 0, (TimuiStr){"\xff", 1}, style);
  CHECK(a.cells[1].codepoint == 0xFFFD && a.cells[1].width == 1);
  timui_draw_text(&a, 0, 0, (TimuiStr){"e‍\x1b", strlen("e‍\x1b")}, style);
  glyph = timui_cell_grapheme(&a, &a.cells[0]);
  CHECK(glyph.len == strlen("e‍ ") && !memcmp(glyph.ptr, "e‍ ", glyph.len));
  timui_cells_clear(&a); CHECK(a.grapheme_size == 0);
  timui_cells_destroy(&a); timui_cells_destroy(&a); timui_cells_destroy(&b); CHECK(r.live == 0);
  return 0;
}

static int span_clipping(void) {
  Review r = {0};
  TimuiAllocator allocator = {&r, review_alloc, review_resize, review_free};
  TimuiTransport transport = {review_write, review_read, NULL, NULL, &r};
  Timui *ui;
  TimuiFrame *frame;
  TimuiCellBuffer *cells;
  TimuiStr glyph;
  int x, width;
  CHECK(birc_clip_cols("👩‍💻", strlen("👩‍💻"), 0, 2, &width) == strlen("👩‍💻"));
  CHECK(width == 2);
  CHECK(birc_clip_cols("👩‍💻", strlen("👩‍💻"), 0, 1, &width) == 0 && width == 0);
  CHECK(timui_open_for_test(&ui, transport, 8, 1, &allocator) == TIMUI_OK);
  CHECK(timui_begin(ui, &frame));
  x = birc_put_span(frame, 0, 0, 2, "👩‍💻", strlen("👩‍💻"), TIMUI_COLOR_DEFAULT, 0, NULL);
  CHECK(x == 2);
  cells = timui_frame_buffer(frame);
  glyph = timui_cell_grapheme(cells, &cells->cells[0]);
  CHECK(glyph.len == strlen("👩‍💻") && !memcmp(glyph.ptr, "👩‍💻", glyph.len));
  x = birc_put_span(frame, x, 0, 8, "X", 1, TIMUI_COLOR_DEFAULT, TIMUI_ATTR_BOLD, NULL);
  CHECK(x == 3 && cells->cells[2].codepoint == 'X');
  timui_end(frame); timui_close(ui); CHECK(r.live == 0);
  return 0;
}

int main(void) {
  CHECK(fidelity() == 0);
  CHECK(exact_links() == 0);
  CHECK(ownership() == 0);
  CHECK(span_clipping() == 0);
  puts("ui_review_native=ok");
  return 0;
}
