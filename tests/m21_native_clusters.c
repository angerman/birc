/* SPDX-License-Identifier: Apache-2.0
 * Actual FFI tab admission and whole-cluster SpanOp painting, without a tty. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include "lint-ffi/ffi_stub.h"
#include "../src/ffi/timui_ffi.c"

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "m21_native_clusters:%d: %s\n", __LINE__, #x); return 1; } } while (0)

/* A small Data heap exercises the real list/SpanOp walker. Strings are copied
 * by io_cstr; fixture constructors borrow literals until the test returns. */
static Term fixture_heap[256];
static size_t fixture_used;
static Env fixture_env(void) {
  Env e = {fixture_heap, NULL};
  fixture_used = 0;
  return e;
}
static Term fixture_ctr(u32 cid, const Term *fields, size_t count) {
  size_t loc = fixture_used;
  assert(count <= 256 - fixture_used);
  memcpy(fixture_heap + loc, fields, count * sizeof *fields);
  fixture_used += count;
  return term_ctr(cid, loc);
}
static Term fixture_cons(Term head, Term tail) {
  Term fields[2] = {head, tail};
  return fixture_ctr(CID_CON, fields, 2);
}
u64 term_aux(Term t) { return t >> 48; }
Loc ctr_take(Env e, Term t, u32 count, Term *out) {
  Loc loc = t & UINT64_C(0x0000ffffffffffff);
  assert(e.mem && loc <= fixture_used && count <= fixture_used - loc);
  memcpy(out, e.mem + loc, count * sizeof *out);
  return loc;
}
void spare_free(Env e, Cls cls, Loc loc) { (void)e; (void)cls; (void)loc; }
void term_sink(Env e, Term t) { (void)e; (void)t; }
Cls cls_fit(u32 words) { return words; }
Loc heap_alloc(Env e, Cls cls) { (void)e; (void)cls; abort(); }
void *io_mem(void *p) { if (!p) abort(); return p; }
char *io_cstr(Env e, Term s, u64 *len) {
  const char *text = (const char *)(uintptr_t)s;
  char *copy;
  (void)e;
  *len = text ? strlen(text) : 0;
  copy = io_mem(malloc((size_t)*len + 1));
  memcpy(copy, text ? text : "", (size_t)*len + 1);
  return copy;
}
Term io_str(Env e, const char *p, u64 n) { (void)e; (void)n; return (Term)(uintptr_t)p; }
Term io_node(Env e, u64 cid, Term a, Term b) { (void)e; (void)cid; (void)a; return b; }
Term io_box(Env e, u64 cid, Term v) { (void)e; (void)cid; return v; }
Term io_tup(Env e, Term a, Term b) { (void)e; (void)a; return b; }
Term io_done(Env e, Term v) { (void)e; return v; }
Term io_fail(Env e, u32 code, const char *text) { (void)e; (void)text; return code; }
void io_eff(u32 cid, Effect run, u32 need) { (void)cid; (void)run; (void)need; }
u64 io_tick(void) { return 0; }
Term io_wait_on(IoWork *w, int fd, short events, uint64_t time, IoMore more) {
  (void)w; (void)fd; (void)events; (void)time; (void)more; return 0;
}

static int clipped(const char *text, size_t expected) {
  char store[1][64];
  const char *labels[1];
  Env e = fixture_env();
  Term list = fixture_cons((Term)(uintptr_t)text, term_pak(CID_NIL, 0));
  CHECK(birc_str_list(e, list, store, labels, 1) == 1);
  CHECK(labels[0] == store[0]);
  CHECK(strlen(labels[0]) == expected);
  CHECK(!memcmp(labels[0], text, expected));
  return 0;
}
static int clipping(void) {
  char text[128];
  const char *clusters[] = {"é", "👩‍💻", "👍🏽", "❤️", "🇺🇳"};
  size_t i;
  CHECK(birc_cluster_fit(NULL, 1, 63) == 0);
  CHECK(birc_cluster_fit("a", 1, 0) == 0);
  CHECK(birc_cluster_fit("é", strlen("é"), 63) == strlen("é"));
  memset(text, 'a', 80); text[80] = '\0';
  CHECK(clipped(text, 63) == 0); /* unchanged ASCII cap */
  for (i = 0; i < 40; i++) memcpy(text + 2 * i, "é", 2);
  text[80] = '\0';
  CHECK(clipped(text, 62) == 0); /* unchanged A7 code-point control */
  CHECK(clipped("", 0) == 0);
  for (i = 0; i < sizeof clusters / sizeof clusters[0]; i++) {
    size_t bytes = strlen(clusters[i]), exact = 63 - bytes;
    memset(text, 'a', exact);
    memcpy(text + exact, clusters[i], bytes);
    memcpy(text + 63, "X", 2);
    CHECK(clipped(text, 63) == 0); /* complete cluster exactly fits */
    memset(text, 'a', exact + 1);
    memcpy(text + exact + 1, clusters[i], bytes + 1);
    CHECK(clipped(text, exact + 1) == 0); /* no partial attachment at cap */
  }
  return 0;
}
static int discard_write(TimuiTransport *t, const void *p, size_t n) {
  (void)t; (void)p; return n > INT_MAX ? -1 : (int)n;
}
static int empty_read(TimuiTransport *t, void *p, size_t n) {
  (void)t; (void)p; (void)n; return 0;
}
static int cluster_is(TimuiCellBuffer *b, int x, int y, const char *text, int width) {
  const TimuiCell *c = &b->cells[y * b->w + x];
  TimuiStr glyph = timui_cell_grapheme(b, c);
  return c->width == width && glyph.ptr && glyph.len == strlen(text) && !memcmp(glyph.ptr, text, glyph.len);
}
static Term span(const char *text, u32 attrs) {
  Term fields[2] = {attrs, (Term)(uintptr_t)text};
  return fixture_ctr(CID_VIEW_SPN, fields, 2);
}
static int paint(void) {
  Timui *ui;
  TimuiFrame *f;
  TimuiCellBuffer *b;
  TimuiTransport transport = {discard_write, empty_read, NULL, NULL, NULL};
  TimuiAllocator allocator = timui_default_allocator();
  Env e = fixture_env();
  Term ordinary = fixture_cons(span("a", 0), fixture_cons(span("X", TIMUI_ATTR_BOLD), term_pak(CID_NIL, 0)));
  Term combining = fixture_cons(span("é", 0), fixture_cons(span("X", TIMUI_ATTR_BOLD), term_pak(CID_NIL, 0)));
  Term emoji = fixture_cons(span("👩‍💻", 0), fixture_cons(span("X", TIMUI_ATTR_BOLD), term_pak(CID_NIL, 0)));
  CHECK(timui_open_for_test(&ui, transport, 100, 4, &allocator) == TIMUI_OK);
  CHECK(timui_begin(ui, &f));
  b = timui_frame_buffer(f);
  CHECK(birc_draw_spans(e, f, 0, 0, 100, TIMUI_COLOR_DEFAULT, ordinary) == 2);
  CHECK(b->cells[0].codepoint == 'a' && b->cells[1].codepoint == 'X');
  CHECK(b->cells[1].attrs & TIMUI_ATTR_BOLD);
  CHECK(birc_draw_spans(e, f, 0, 1, 100, TIMUI_COLOR_DEFAULT, combining) == 2);
  CHECK(cluster_is(b, 0, 1, "é", 1) && b->cells[b->w + 1].codepoint == 'X');
  CHECK(birc_draw_spans(e, f, 0, 2, 100, TIMUI_COLOR_DEFAULT, emoji) == 3);
  CHECK(cluster_is(b, 0, 2, "👩‍💻", 2) && b->cells[2 * b->w + 2].codepoint == 'X');
  timui_end(f); timui_close(ui);
  return 0;
}
static int tabs(void) {
  char text[80], store[3][64];
  const char *labels[3];
  TimuiTabSpan spans[3];
  Timui *ui;
  TimuiFrame *f;
  TimuiTransport transport = {discard_write, empty_read, NULL, NULL, NULL};
  TimuiAllocator allocator = timui_default_allocator();
  Env e = fixture_env();
  int selected = 1;
  Term names;
  memset(text, 'a', 52);
  memcpy(text + 52, "👩‍💻", strlen("👩‍💻"));
  memcpy(text + 63, "X", 2);
  names = fixture_cons((Term)(uintptr_t)"#first", fixture_cons((Term)(uintptr_t)text,
            fixture_cons((Term)(uintptr_t)"#last", term_pak(CID_NIL, 0))));
  CHECK(birc_str_list(e, names, store, labels, 3) == 3);
  CHECK(!strcmp(labels[0], "#first") && !strcmp(labels[2], "#last"));
  CHECK(strlen(labels[1]) == 63 && !memcmp(labels[1] + 52, "👩‍💻", strlen("👩‍💻")));
  CHECK(timui_tabs_layout(labels, 3, 1, spans, 3) == 73);
  CHECK(spans[0].x == 0 && spans[1].x == 9 && spans[2].x == 66);
  CHECK(timui_open_for_test(&ui, transport, 100, 2, &allocator) == TIMUI_OK);
  CHECK(timui_begin(ui, &f));
  CHECK(timui_tabs(f, TIMUI_ID("m21-tabs"), TIMUI_RECT(0, 0, 100, 1), labels, 3, &selected) == 1);
  CHECK(cluster_is(timui_frame_buffer(f), 62, 0, "👩‍💻", 2));
  timui_interact_set_mouse(&ui->ia, 67, 0, 1); timui_interact_begin(&ui->ia);
  (void)timui_tabs(f, TIMUI_ID("m21-tabs"), TIMUI_RECT(0, 0, 100, 1), labels, 3, &selected);
  timui_interact_set_mouse(&ui->ia, 67, 0, 0); timui_interact_begin(&ui->ia);
  CHECK(timui_tabs(f, TIMUI_ID("m21-tabs"), TIMUI_RECT(0, 0, 100, 1), labels, 3, &selected) == 2);
  CHECK(selected == 2);
  timui_end(f); timui_close(ui);
  return 0;
}
int main(int argc, char **argv) {
  if (argc == 1 || !strcmp(argv[1], "paint")) CHECK(paint() == 0);
  if (argc == 1 || !strcmp(argv[1], "clipping")) CHECK(clipping() == 0);
  if (argc == 1 || !strcmp(argv[1], "tabs")) CHECK(tabs() == 0);
  puts("m21_native_clusters=ok");
  return 0;
}
