/* SPDX-License-Identifier: Apache-2.0 */
/* OpGhost must keep Bend's w for post-composer ghost paint maxx.
 * Underlined OpText (attrs == TIMUI_ATTR_UNDERLINE) must paint normally. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "lint-ffi/ffi_stub.h"
#include "../src/ffi/timui_ffi.c"

#define CHECK(x) do { if (!(x)) { \
  fprintf(stderr, "ghost_width:%d: %s\n", __LINE__, #x); return 1; \
} } while (0)

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
void io_eff(u32 cid, Effect run) { (void)cid; (void)run; }
u64 io_tick(void) { return 0; }
Term io_wait_on(IoWork *w, int fd, short events, uint64_t time, IoMore more) {
  (void)w; (void)fd; (void)events; (void)time; (void)more; return 0;
}

static int discard_write(TimuiTransport *t, const void *p, size_t n) {
  (void)t; (void)p; return n > INT_MAX ? -1 : (int)n;
}
static int empty_read(TimuiTransport *t, void *p, size_t n) {
  (void)t; (void)p; (void)n; return 0;
}

static Term op_text(int x, int y, int w, uint32_t fg, uint32_t attrs,
                    const char *s) {
  Term fields[6] = {
    (Term)(uint32_t)x, (Term)(uint32_t)y, (Term)(uint32_t)w,
    (Term)fg, (Term)attrs, (Term)(uintptr_t)s
  };
  return fixture_ctr(CID_VIEW_OPTEXT, fields, 6);
}

static Term op_ghost(int x, int y, int w, uint32_t fg, const char *s) {
  Term fields[5] = {
    (Term)(uint32_t)x, (Term)(uint32_t)y, (Term)(uint32_t)w,
    (Term)fg, (Term)(uintptr_t)s
  };
  return fixture_ctr(CID_VIEW_OPGHOST, fields, 5);
}

static int open_lay(Timui **ui_out, TimuiFrame **fr_out, BircUi *bu, BircLay *ly) {
  TimuiTransport transport = {discard_write, empty_read, NULL, NULL, NULL};
  TimuiAllocator allocator = timui_default_allocator();
  TimuiCellBuffer *buf;
  memset(bu, 0, sizeof *bu);
  CHECK(timui_open_for_test(ui_out, transport, 40, 4, &allocator) == TIMUI_OK);
  (*ui_out)->cfg.userdata = bu;
  CHECK(timui_begin(*ui_out, fr_out));
  buf = timui_frame_buffer(*fr_out);
  ly->buf = buf;
  ly->border = timui_style_make(TIMUI_COLOR_DEFAULT, TIMUI_COLOR_DEFAULT, 0);
  ly->root = TIMUI_RECT(0, 0, 40, 4);
  ly->click = NULL;
  ly->bu = bu;
  ly->ui = *ui_out;
  return 0;
}

static int ghost_honors_opghost_w(void) {
  Timui *ui;
  TimuiFrame *fr;
  TimuiCellBuffer *buf;
  BircUi bu;
  BircLay ly;
  Env e = fixture_env();
  Term op;
  int end;
  CHECK(open_lay(&ui, &fr, &bu, &ly) == 0);
  buf = ly.buf;
  /* w=2 columns, six ASCII bytes: stash keeps text; paint clips to w. */
  op = op_ghost(3, 1, 2, TIMUI_COLOR_DEFAULT, "abcdef");
  birc_draw_op(e, fr, op, &ly);
  CHECK(bu.ghost_on);
  CHECK(bu.ghost_w == 2);
  CHECK(bu.ghost_x == 3 && bu.ghost_y == 1);
  CHECK(!strcmp(bu.ghost, "abcdef"));
  end = birc_put_span(fr, bu.ghost_x, bu.ghost_y, bu.ghost_x + bu.ghost_w,
                      bu.ghost, strlen(bu.ghost), bu.ghost_fg, 0, NULL);
  CHECK(end == bu.ghost_x + 2);
  CHECK(buf->cells[1 * buf->w + 3].codepoint == 'a');
  CHECK(buf->cells[1 * buf->w + 4].codepoint == 'b');
  CHECK(buf->cells[1 * buf->w + 5].codepoint != 'c');
  timui_end(fr);
  timui_close(ui);
  return 0;
}

static int underline_optext_paints(void) {
  Timui *ui;
  TimuiFrame *fr;
  TimuiCellBuffer *buf;
  BircUi bu;
  BircLay ly;
  Env e = fixture_env();
  Term op;
  CHECK(open_lay(&ui, &fr, &bu, &ly) == 0);
  buf = ly.buf;
  /* attrs == 8 is TIMUI_ATTR_UNDERLINE, not a ghost diversion. */
  op = op_text(2, 1, 4, TIMUI_COLOR_DEFAULT, TIMUI_ATTR_UNDERLINE, "abcd");
  birc_draw_op(e, fr, op, &ly);
  CHECK(!bu.ghost_on);
  CHECK(bu.ghost_w == 0);
  CHECK(buf->cells[1 * buf->w + 2].codepoint == 'a');
  CHECK(buf->cells[1 * buf->w + 3].codepoint == 'b');
  CHECK((buf->cells[1 * buf->w + 2].attrs & TIMUI_ATTR_UNDERLINE) != 0);
  timui_end(fr);
  timui_close(ui);
  return 0;
}

int main(void) {
  CHECK(ghost_honors_opghost_w() == 0);
  CHECK(underline_optext_paints() == 0);
  puts("ghost_width=ok");
  return 0;
}
