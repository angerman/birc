/* SPDX-License-Identifier: Apache-2.0 */
/* Actual FFI: a non-key paint must not strand a timed parser continuation.
 * The wait spy preserves the originally armed deadline; it does not invent
 * another input owner or turn normal idle into periodic input polling. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include "lint-ffi/ffi_stub.h"

static uint64_t now_ms = 1000;
static int controlled_clock(clockid_t clock_id, struct timespec *ts) {
  (void)clock_id;
  ts->tv_sec = (time_t)(now_ms / 1000);
  ts->tv_nsec = (long)(now_ms % 1000) * 1000000;
  return 0;
}
#define clock_gettime controlled_clock
#include "../src/ffi/timui_ffi.c"
#undef clock_gettime

static Term arena[128];
static Loc arena_next;
static struct {
  int calls, fd;
  short events;
  uint64_t deadline;
  IoMore more;
} parked;

/* Minimal values/arena for the real frame's UiKeys; no Bend evaluation. */
u64 term_aux(Term t) { return t >> 48; }
Loc ctr_take(Env e, Term t, u32 n, Term *out) {
  (void)e; (void)t; memset(out, 0, n * sizeof *out); return 0;
}
void spare_free(Env e, Cls cls, Loc loc) { (void)e; (void)cls; (void)loc; }
void term_sink(Env e, Term t) { (void)e; (void)t; }
Cls cls_fit(u32 words) { return words; }
Loc heap_alloc(Env e, Cls cls) {
  Loc at = arena_next;
  (void)e;
  if (cls > sizeof arena / sizeof arena[0] - arena_next)
    abort();
  arena_next += cls;
  return at;
}
void *io_mem(void *mem) { if (!mem) abort(); return mem; }
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
u64 io_tick(void) { return now_ms * 1000000; }
Term io_wait_on(IoWork *w, int fd, short events, uint64_t deadline, IoMore more) {
  (void)w;
  parked.calls++;
  parked.fd = fd;
  parked.events = events;
  parked.deadline = deadline;
  parked.more = more;
  return 0;
}

#define CHECK(x) do { if (!(x)) { \
  fprintf(stderr, "input_wake:%d: %s\n", __LINE__, #x); return 1; \
} } while (0)

typedef struct {
  Timui *ui;
  BircUi *state;
  int input[2], output[2];
  IoWork watcher;
} Fixture;

static int fixture_start(Fixture *f) {
  TimuiAllocator allocator = timui_default_allocator();
  TimuiTransport transport = {fd_write, fd_read, fd_flush, NULL, NULL};
  memset(f, 0, sizeof *f);
  memset(&parked, 0, sizeof parked);
  now_ms = 1000;
  CHECK(pipe(f->input) == 0 && pipe(f->output) == 0);
  CHECK(fcntl(f->input[0], F_SETFL, O_NONBLOCK) == 0);
  CHECK(fcntl(f->output[0], F_SETFL, O_NONBLOCK) == 0);
  CHECK(fcntl(f->output[1], F_SETFL, O_NONBLOCK) == 0);
  CHECK(timui_open_for_test(&f->ui, transport, 80, 24, &allocator) == TIMUI_OK);
  f->ui->fd.read_fd = f->input[0];
  f->ui->fd.write_fd = f->output[1];
  f->ui->transport.ctx = &f->ui->fd;
  f->ui->cfg.input_poll_ms = 0;
  f->state = calloc(1, sizeof *f->state);
  CHECK(f->state != NULL);
  f->state->st.text = f->state->composer;
  f->state->st.cap = sizeof f->state->composer;
  f->state->last_tab = -1;
  f->ui->cfg.userdata = f->state;
  birc_ui_live = f->ui;
  return 0;
}

static int fixture_stop(Fixture *f) {
  birc_ui_live = NULL;
  f->ui->cfg.userdata = NULL;
  birc_state_destroy(f->state);
  timui_close(f->ui);
  CHECK(close(f->input[0]) == 0 && close(f->input[1]) == 0);
  CHECK(close(f->output[0]) == 0 && close(f->output[1]) == 0);
  return 0;
}

static int arm(Fixture *f) {
  Env env = {arena, NULL};
  Term args[1] = {io_hand((u64)f->input[0])};
  (void)fd_ready_run(env, args, &f->watcher);
  CHECK(parked.fd == f->input[0] && parked.events == POLLIN);
  CHECK(parked.more == fd_ready_more);
  return 0;
}

static uint32_t maintenance_ready(Fixture *f) {
  Env env = {arena, NULL};
  Term args[1] = {io_hand((u64)(uintptr_t)f->ui)};
  /* With no typing expiry, this is on_typing_tick's actual paint decision. */
  return (uint32_t)timui_redraw_ready_run(env, args, NULL);
}

static int paint(Fixture *f, uint32_t *key, uint32_t *more) {
  Env env = {arena, NULL};
  Term args[4] = {io_hand((u64)(uintptr_t)f->ui), term_pak(CID_NIL, 0),
                  (Term)(uintptr_t)"", 0};
  Term result;
  Loc at;
  arena_next = 0;
  result = timui_frame_run(env, args, NULL);
  CHECK(term_aux(result) == CID_UIKEYS);
  at = result & UINT64_C(0x0000ffffffffffff);
  *key = (uint32_t)arena[at + 5];
  *more = (uint32_t)arena[at + 9];
  return 0;
}

static int feed(Fixture *f, const char *bytes, size_t size,
                uint32_t *key, uint32_t *more) {
  CHECK(write(f->input[1], bytes, size) == (ssize_t)size);
  return paint(f, key, more);
}

static int fill_output(Fixture *f) {
  char bytes[4096] = {0};
  int i;
  for (i = 0; i < 64; i++) {
    ssize_t n = write(f->output[1], bytes, sizeof bytes);
    if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return 0;
    CHECK(n > 0);
  }
  CHECK(0); /* refuse an unexpectedly large pipe rather than fill forever */
  return 1;
}

static int drain_output(Fixture *f) {
  char bytes[4096];
  int i;
  for (i = 0; i < 65; i++) {
    ssize_t n = read(f->output[0], bytes, sizeof bytes);
    if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return 0;
    CHECK(n > 0);
  }
  CHECK(0);
  return 1;
}

static int idle_and_output_controls(void) {
  Fixture f;
  uint32_t key, more;
  CHECK(fixture_start(&f) == 0);
  CHECK(arm(&f) == 0 && parked.deadline == 0);
  CHECK(maintenance_ready(&f) == 0); /* ordinary idle stays parked */
  f.state->output.repaint = 1;
  CHECK(maintenance_ready(&f) == 1); /* existing writable output repair */
  CHECK(fill_output(&f) == 0);
  CHECK(maintenance_ready(&f) == 0); /* full output does not spin */
  CHECK(drain_output(&f) == 0 && maintenance_ready(&f) == 1);
  f.state->output.repaint = 0;
  CHECK(feed(&f, "\xe2", 1, &key, &more) == 0);
  CHECK(f.ui->input.state == 4 && key == TIMUI_KEY_UNKNOWN && more == 0);
  CHECK(maintenance_ready(&f) == 0); /* partial UTF-8 has no idle expiry */
  CHECK(fixture_stop(&f) == 0);
  return 0;
}

static int timed_escape_control(void) {
  Fixture f;
  uint32_t key, more;
  Env env = {arena, NULL};
  CHECK(fixture_start(&f) == 0);
  CHECK(feed(&f, "\x1b", 1, &key, &more) == 0);
  CHECK(f.ui->input.state == 1 && key == TIMUI_KEY_UNKNOWN && more == 0);
  CHECK(arm(&f) == 0 && parked.deadline == UINT64_C(1050000000));
  now_ms = 1050;
  CHECK(parked.more(env, &f.watcher) == io_hand((u64)f.input[0]));
  CHECK(paint(&f, &key, &more) == 0);
  CHECK(key == TIMUI_KEY_ESCAPE && more == 0 && f.ui->input.state == 0);
  CHECK(timui_should_quit(f.ui));
  CHECK(fixture_stop(&f) == 0);
  return 0;
}

static int split_escape_control(void) {
  Fixture f;
  uint32_t key, more;
  CHECK(fixture_start(&f) == 0);
  CHECK(feed(&f, "\x1b", 1, &key, &more) == 0);
  CHECK(arm(&f) == 0 && parked.deadline == UINT64_C(1050000000));
  now_ms = 1010;
  CHECK(feed(&f, "[A", 2, &key, &more) == 0);
  CHECK(key == TIMUI_KEY_UP && more == 0 && f.ui->input.state == 0);
  CHECK(!timui_should_quit(f.ui) && maintenance_ready(&f) == 0);
  CHECK(arm(&f) == 0 && parked.deadline == 0);
  now_ms = 1100;
  CHECK(paint(&f, &key, &more) == 0 && key == TIMUI_KEY_UNKNOWN);
  CHECK(!timui_should_quit(f.ui));
  CHECK(fixture_stop(&f) == 0);
  return 0;
}

static int nonkey_escape_gap(void) {
  Fixture f;
  uint32_t key, more, ready;
  CHECK(fixture_start(&f) == 0);
  CHECK(arm(&f) == 0 && parked.deadline == 0 && parked.calls == 1);
  /* Resize/network paints use the same FFI. They can read before the armed
   * tty poll observes readability, and they do not ACK/rearm that watcher. */
  CHECK(feed(&f, "\x1b", 1, &key, &more) == 0);
  CHECK(f.ui->input.state == 1 && key == TIMUI_KEY_UNKNOWN && more == 0);
  CHECK(parked.deadline == 0 && parked.calls == 1);
  CHECK(!birc_output_pending(f.ui));
  now_ms = 2000;
  ready = maintenance_ready(&f);
  if (!ready)
    fprintf(stderr, "input_wake: stranded Esc: state=%d key=%u more=%u "
                    "watch_deadline=%llu output_pending=%d ready=%u\n",
            f.ui->input.state, key, more, (unsigned long long)parked.deadline,
            birc_output_pending(f.ui), ready);
  CHECK(ready == 1); /* RED: old predicate sees only output */
  CHECK(paint(&f, &key, &more) == 0);
  CHECK(key == TIMUI_KEY_ESCAPE && more == 0 && f.ui->input.state == 0);
  CHECK(timui_should_quit(f.ui) && maintenance_ready(&f) == 0);
  CHECK(fixture_stop(&f) == 0);
  return 0;
}

static int full_output_escape_control(void) {
  Fixture f;
  uint32_t key, more;
  CHECK(fixture_start(&f) == 0);
  CHECK(arm(&f) == 0 && parked.deadline == 0);
  CHECK(feed(&f, "\x1b", 1, &key, &more) == 0);
  CHECK(f.ui->input.state == 1 && key == TIMUI_KEY_UNKNOWN && more == 0);
  CHECK(fill_output(&f) == 0);
  f.state->output.repaint = 1; /* still-full repair has no output wait */
  CHECK(!birc_output_ready(f.ui) && maintenance_ready(&f) == 1);
  now_ms = 2000;
  CHECK(paint(&f, &key, &more) == 0);
  CHECK(key == TIMUI_KEY_ESCAPE && more == 0 && f.ui->input.state == 0);
  CHECK(timui_should_quit(f.ui));
  CHECK(!birc_output_ready(f.ui) && maintenance_ready(&f) == 0);
  CHECK(drain_output(&f) == 0);
  CHECK(fixture_stop(&f) == 0);
  return 0;
}

static int timed_parser_controls(void) {
  static const struct { const char *bytes; size_t size; int state, pasting; } cases[] = {
    {"\x1b[", 2, 2, 0}, {"\x1bO", 2, 3, 0},
    {"\x1b]x", 3, 5, 0}, {"\x1b]x\x1b", 4, 6, 0},
    {"\x1b[M", 3, 7, 0}, {"\x1b[200~", 6, 0, 1}
  };
  size_t i;
  for (i = 0; i < sizeof cases / sizeof cases[0]; i++) {
    Fixture f;
    uint32_t key, more;
    CHECK(fixture_start(&f) == 0);
    CHECK(feed(&f, cases[i].bytes, cases[i].size, &key, &more) == 0);
    CHECK(f.ui->input.state == cases[i].state && f.ui->input.pasting == cases[i].pasting);
    CHECK(key == TIMUI_KEY_UNKNOWN && more == 0 && maintenance_ready(&f) == 1);
    now_ms = 2000;
    CHECK(paint(&f, &key, &more) == 0);
    CHECK(f.ui->input.state == 0 && !f.ui->input.pasting);
    CHECK(key == TIMUI_KEY_UNKNOWN && more == 0 && maintenance_ready(&f) == 0);
    CHECK(fixture_stop(&f) == 0);
  }
  return 0;
}

int main(void) {
  CHECK(idle_and_output_controls() == 0);
  CHECK(timed_escape_control() == 0);
  CHECK(split_escape_control() == 0);
  CHECK(nonkey_escape_gap() == 0);
  CHECK(full_output_escape_control() == 0);
  CHECK(timed_parser_controls() == 0);
  puts("input_wake=ok");
  return 0;
}
