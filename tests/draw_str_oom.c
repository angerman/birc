/* SPDX-License-Identifier: Apache-2.0 */
/* birc_draw_str io_cstr OOM: *out_n must be 0 so ignored-return callers stay safe. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "lint-ffi/ffi_stub.h"
#include "../src/ffi/timui_ffi.c"

#define CHECK(x) do { if (!(x)) { \
  fprintf(stderr, "draw_str_oom:%d: %s\n", __LINE__, #x); return 1; \
} } while (0)

static Term fixture_heap[256];
static size_t fixture_used;
static int fail_cstr;
static u64 fail_cstr_len;

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
  if (fail_cstr) {
    *len = fail_cstr_len;
    return NULL;
  }
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

static int oom_paint_skips_span(void) {
  Timui *ui;
  TimuiFrame *fr;
  TimuiCellBuffer *buf;
  TimuiTransport transport = {discard_write, empty_read, NULL, NULL, NULL};
  TimuiAllocator allocator = timui_default_allocator();
  BircUi bu;
  BircLay ly;
  Env e = fixture_env();
  Term op;
  memset(&bu, 0, sizeof bu);
  CHECK(timui_open_for_test(&ui, transport, 40, 4, &allocator) == TIMUI_OK);
  ui->cfg.userdata = &bu;
  CHECK(timui_begin(ui, &fr));
  buf = timui_frame_buffer(fr);
  ly.buf = buf;
  ly.border = timui_style_make(TIMUI_COLOR_DEFAULT, TIMUI_COLOR_DEFAULT, 0);
  ly.root = TIMUI_RECT(0, 0, 40, 4);
  ly.click = NULL;
  ly.bu = &bu;
  ly.ui = ui;
  fail_cstr = 1;
  fail_cstr_len = 5; /* nonzero length with NULL heap must not overread "" */
  op = op_text(3, 1, 5, TIMUI_COLOR_DEFAULT, 0, "hello");
  birc_draw_op(e, fr, op, &ly);
  fail_cstr = 0;
  CHECK(buf->cells[1 * buf->w + 3].codepoint != 'h');
  CHECK(!bu.ghost_on);
  timui_end(fr);
  timui_close(ui);
  return 0;
}

static int oom_empty_ok(void) {
  Timui *ui;
  TimuiFrame *fr;
  TimuiTransport transport = {discard_write, empty_read, NULL, NULL, NULL};
  TimuiAllocator allocator = timui_default_allocator();
  BircUi bu;
  BircLay ly;
  Env e = fixture_env();
  Term op;
  memset(&bu, 0, sizeof bu);
  CHECK(timui_open_for_test(&ui, transport, 40, 4, &allocator) == TIMUI_OK);
  ui->cfg.userdata = &bu;
  CHECK(timui_begin(ui, &fr));
  ly.buf = timui_frame_buffer(fr);
  ly.border = timui_style_make(TIMUI_COLOR_DEFAULT, TIMUI_COLOR_DEFAULT, 0);
  ly.root = TIMUI_RECT(0, 0, 40, 4);
  ly.click = NULL;
  ly.bu = &bu;
  ly.ui = ui;
  fail_cstr = 1;
  fail_cstr_len = 0; /* empty source may return NULL with len 0 */
  op = op_text(0, 0, 1, TIMUI_COLOR_DEFAULT, 0, "");
  birc_draw_op(e, fr, op, &ly);
  fail_cstr = 0;
  timui_end(fr);
  timui_close(ui);
  return 0;
}

int main(void) {
  CHECK(oom_paint_skips_span() == 0);
  CHECK(oom_empty_ok() == 0);
  puts("draw_str_oom=ok");
  return 0;
}
