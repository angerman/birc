/* Exercise the actual FFI close/final effects without a Bend runtime. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include "lint-ffi/ffi_stub.h"

static unsigned char captured[2][512];
static size_t captured_len[2], allowance[2], attempts[2];
static struct stat sinks[2];
static jmp_buf final_exit;
static int final_status;
static time_t clock_seconds;
static int clock_paused;
static int replenish_after_full;
static int signal_on_write;
static int signal_nonblock;
static volatile sig_atomic_t signal_count;
static int real_sink, blocking_attempt, short_success;
static int pause_handler, pause_enter[2], pause_resume[2];
static volatile sig_atomic_t pause_phase, ui_retired;
static int watch_retire, signal_retire_phase, image_freed, image_detached;

static void pause_signal_writer(void) {
  char byte = 1;
  pause_handler = 0;
  __atomic_store_n(&pause_phase, 1, __ATOMIC_RELEASE);
  if (write(pause_enter[1], &byte, 1) != 1 ||
      read(pause_resume[0], &byte, 1) != 1 ||
      __atomic_load_n(&pause_phase, __ATOMIC_ACQUIRE) != 2)
    abort();
}

static ssize_t real_write(int fd, const void *data, size_t size) {
  return write(fd, data, size);
}

static int sink_index(int fd) {
  struct stat st;
  int i;
  if (fstat(fd, &st) != 0)
    return -1;
  for (i = 0; i < 2; i++)
    if (st.st_dev == sinks[i].st_dev && st.st_ino == sinks[i].st_ino)
      return i;
  return -1;
}

static ssize_t captured_write(int fd, const void *data, size_t size) {
  if (pause_handler)
    pause_signal_writer();
  if (real_sink) {
    ssize_t result;
    /* Fail the guard safely instead of letting the known bad bounded writer
     * block this test in a >PIPE_BUF write to the almost-full real pipe. */
    if (size > 4096 && !(fcntl(fd, F_GETFL, 0) & O_NONBLOCK)) {
      blocking_attempt = 1;
      errno = EDEADLK;
      return -1;
    }
    result = real_write(fd, data, size);
    if (result > 0 && signal_on_write) {
      signal_on_write = 0;
      if (raise(SIGTERM) != 0)
        abort();
      signal_nonblock = (fcntl(fd, F_GETFL, 0) & O_NONBLOCK) != 0;
    }
    return result;
  }
  int sink = sink_index(fd);
  if (sink < 0) {
    errno = EBADF;
    return -1;
  }
  attempts[sink]++;
  if (!allowance[sink]) {
    if (replenish_after_full) {
      allowance[sink] = 2;
      replenish_after_full = 0;
    }
    errno = EAGAIN;
    return -1;
  }
  if (size > allowance[sink])
    size = allowance[sink];
  if (short_success && size > 1)
    size = 1;
  if (size > sizeof captured[sink] - captured_len[sink])
    abort();
  memcpy(captured[sink] + captured_len[sink], data, size);
  captured_len[sink] += size;
  allowance[sink] -= size;
  if (signal_on_write) {
    signal_on_write = 0;
    if (raise(SIGTERM) != 0)
      abort();
    signal_nonblock = (fcntl(fd, F_GETFL, 0) & O_NONBLOCK) != 0;
  }
  return (ssize_t)size;
}

/* Advance beyond each budget without busy-polling a writable fake pipe. */
static int advancing_clock(clockid_t clock_id, struct timespec *ts) {
  (void)clock_id;
  ts->tv_sec = clock_paused ? clock_seconds : ++clock_seconds;
  ts->tv_nsec = 0;
  return 0;
}

static _Noreturn void captured_exit(int status) {
  final_status = status;
  longjmp(final_exit, 1);
}

#define write captured_write
#define clock_gettime advancing_clock
#define _Exit captured_exit
#include "../src/ffi/timui_ffi.c"
static void install_writer(Timui *ui) {
  ui->transport.write = fd_write;
  ui->transport.ctx = &ui->fd;
}
#undef _Exit
#undef clock_gettime
#undef write

/* The effects above need only handles and a copied error string here. */
u64 term_aux(Term t) { return t; }
Loc ctr_take(Env e, Term t, u32 n, Term *out) {
  (void)e; (void)t; (void)n; (void)out; return 0;
}
void spare_free(Env e, Cls cls, Loc loc) { (void)e; (void)cls; (void)loc; }
void term_sink(Env e, Term t) { (void)e; (void)t; }
Cls cls_fit(u32 words) { return words; }
Loc heap_alloc(Env e, Cls cls) { (void)e; (void)cls; return 0; }
void *io_mem(void *mem) { return mem; }
char *io_cstr(Env e, Term s, u64 *len) {
  const char *text = (const char *)(uintptr_t)s;
  char *copy;
  (void)e;
  *len = text ? strlen(text) : 0;
  copy = malloc((size_t)*len + 1);
  if (copy)
    memcpy(copy, text ? text : "", (size_t)*len + 1);
  return copy;
}
Term io_str(Env e, const char *p, u64 n) { (void)e; (void)n; return (Term)(uintptr_t)p; }
Term io_node(Env e, u64 cid, Term a, Term b) {
  (void)e; (void)cid; (void)a; return b;
}
Term io_box(Env e, u64 cid, Term v) { (void)e; (void)cid; return v; }
Term io_tup(Env e, Term a, Term b) { (void)e; (void)a; return b; }
Term io_done(Env e, Term v) { (void)e; return v; }
Term io_fail(Env e, u32 code, const char *text) { (void)e; (void)text; return code; }
void io_eff(u32 cid, Effect run, u32 need) { (void)cid; (void)run; (void)need; }
u64 io_tick(void) { return 0; }
Term io_wait_on(IoWork *w, int fd, short evts, uint64_t time, IoMore more) {
  (void)w; (void)fd; (void)evts; (void)time; (void)more; return 0;
}

#define CHECK(test) do { if (!(test)) { \
  fprintf(stderr, "output_shutdown: line %d: %s\n", __LINE__, #test); return 1; \
} } while (0)

typedef struct {
  int fds[2][2];
  int saved_out, saved_err;
} SinkFixture;

static int fixture_start(SinkFixture *fixture) {
  CHECK(pipe(fixture->fds[0]) == 0 && pipe(fixture->fds[1]) == 0);
  CHECK(fstat(fixture->fds[0][1], &sinks[0]) == 0 &&
        fstat(fixture->fds[1][1], &sinks[1]) == 0);
  fixture->saved_out = dup(STDOUT_FILENO);
  fixture->saved_err = dup(STDERR_FILENO);
  CHECK(fixture->saved_out >= 0 && fixture->saved_err >= 0);
  CHECK(dup2(fixture->fds[0][1], STDOUT_FILENO) == STDOUT_FILENO);
  CHECK(dup2(fixture->fds[0][1], STDERR_FILENO) == STDERR_FILENO);
  memset(captured_len, 0, sizeof captured_len);
  memset(attempts, 0, sizeof attempts);
  allowance[0] = 0;
  allowance[1] = sizeof captured[1];
  return 0;
}

static int fixture_stop(SinkFixture *fixture) {
  CHECK(dup2(fixture->saved_out, STDOUT_FILENO) == STDOUT_FILENO);
  CHECK(dup2(fixture->saved_err, STDERR_FILENO) == STDERR_FILENO);
  CHECK(close(fixture->saved_out) == 0 && close(fixture->saved_err) == 0);
  CHECK(close(fixture->fds[0][0]) == 0 && close(fixture->fds[0][1]) == 0);
  CHECK(close(fixture->fds[1][0]) == 0 && close(fixture->fds[1][1]) == 0);
  return 0;
}

static Timui *fixture_ui(int fd) {
  Timui *ui = calloc(1, sizeof *ui);
  if (!ui)
    return NULL;
  ui->alloc = timui_default_allocator();
  ui->trace_fd = -1;
  ui->fd.read_fd = -1;
  ui->fd.write_fd = fd;
  ui->fd.teardown_bounded = 1;
  ui->fd.teardown_deadline_ms = 0;
  ui->have_transport = 1;
  ui->screen_active = 1;
  ui->screen.flags = TIMUI_FLAG_ALT_SCREEN;
  install_writer(ui);
  return ui;
}

static int run_final_debt(size_t cut, size_t repair, int failure, int redirected,
                          int reuse, int debt) {
  static const unsigned char scalar[] = {0xf0, 0x9f, 0x98, 0x80};
  static const char ok[] = "birc=ok\n", error[] = "error\n";
  const char *status = failure ? error : ok;
  size_t status_len = failure ? sizeof error - 1 : sizeof ok - 1;
  unsigned char expected[64];
  size_t prefix_len = 0, expected_len, owed;
  Env env = {0};
  Timui *ui;
  Term args[1];
  SinkFixture fixture;
  int sink = redirected ? 1 : 0;
  size_t before;
  CHECK(fixture_start(&fixture) == 0);
  allowance[1] = sizeof captured[1];
  ui = fixture_ui(fixture.fds[0][1]);
  CHECK(ui != NULL);
  if (debt & 2) {
    memcpy(expected + prefix_len, "\x1b[?2026h", 8);
    prefix_len += 8;
    ui->sync_open = 1;
  }
  if (debt & 1) {
    memcpy(expected + prefix_len, "\x1b]52;;x", 7);
    prefix_len += 7;
    ui->framing_debt = 1;
  }
  allowance[0] = prefix_len;
  CHECK(fd_write(&ui->transport, expected, prefix_len) == (int)prefix_len);
  memcpy(expected + prefix_len, scalar, sizeof scalar);
  expected_len = prefix_len + sizeof scalar;
  if (debt & 1) {
    memcpy(expected + expected_len, "\\\x1b\\", 3);
    expected_len += 3;
  }
  if (debt & 2) {
    memcpy(expected + expected_len, "\x1b[?2026l", 8);
    expected_len += 8;
  }
  owed = expected_len - prefix_len - cut;
  memcpy(expected + expected_len, status, status_len);
  expected_len += status_len;
  allowance[0] = cut;
  CHECK(fd_write(&ui->transport, scalar, sizeof scalar) == 4);
  CHECK(ui->fd.write_utf8_tail_len == 4 - cut && captured_len[0] == prefix_len + cut);
  args[0] = io_hand((u64)(uintptr_t)ui);
  timui_close_run(env, args, NULL);
  CHECK(captured_len[0] == prefix_len + cut);
  before = attempts[0];
  if (redirected)
    CHECK(dup2(fixture.fds[1][1], failure ? STDERR_FILENO : STDOUT_FILENO) >= 0);
  if (reuse) {
    /* The retained owner must keep the original stream alive, not trust a
     * borrowed descriptor number that now names another pipe. */
    CHECK(close(fixture.fds[0][1]) == 0);
    CHECK(dup2(fixture.fds[1][1], fixture.fds[0][1]) == fixture.fds[0][1]);
  }
  allowance[0] = repair;
  if (!setjmp(final_exit)) {
    if (failure) {
      args[0] = (Term)(uintptr_t)"error";
      sys_exit_fail_run(env, args, NULL);
    } else {
      sys_exit_done_run(env, NULL, NULL);
    }
  }
  CHECK(fixture_stop(&fixture) == 0);
  CHECK(final_status == (failure ? EXIT_FAILURE : EXIT_SUCCESS));
  if (redirected) {
    CHECK(attempts[0] == before && captured_len[0] == prefix_len + cut);
    CHECK(captured_len[1] == status_len && memcmp(captured[1], status, status_len) == 0);
  } else if (repair < owed) {
    CHECK(captured_len[0] == prefix_len + cut + repair);
    CHECK(memcmp(captured[0], expected, captured_len[0]) == 0);
    CHECK(captured_len[1] == 0);
  } else {
    CHECK(captured_len[sink] == expected_len);
    CHECK(memcmp(captured[sink], expected, expected_len) == 0);
    CHECK(captured_len[1] == 0);
  }
  return 0;
}

static int run_final(size_t cut, size_t repair, int failure, int redirected,
                     int reuse) {
  return run_final_debt(cut, repair, failure, redirected, reuse, 0);
}

static int unicode_failure(void) {
  SinkFixture fixture;
  Env env = {0};
  Term args[1] = {(Term)(uintptr_t)"\xe2\x94\x80"};
  static const char expected[] = "\xe2\x94\x80\n";
  CHECK(fixture_start(&fixture) == 0);
  allowance[0] = 2;
  replenish_after_full = 1;
  /* This positive repair happens within one final-output budget. Other
   * fixtures advance time to exercise refusal after the deadline. */
  clock_paused = 1;
  if (!setjmp(final_exit))
    sys_exit_fail_run(env, args, NULL);
  clock_paused = 0;
  CHECK(fixture_stop(&fixture) == 0);
  CHECK(final_status == EXIT_FAILURE && !replenish_after_full);
  CHECK(captured_len[0] == sizeof expected - 1);
  CHECK(memcmp(captured[0], expected, captured_len[0]) == 0);
  return 0;
}

static int profile_alias(int redirected) {
  SinkFixture fixture;
  Env env = {0};
  Timui *ui;
  BircUi *state;
  Term args[1];
  static const char scalar[] = "\xf0\x9f\x98\x80";
  CHECK(fixture_start(&fixture) == 0);
  if (redirected)
    CHECK(dup2(fixture.fds[1][1], STDERR_FILENO) == STDERR_FILENO);
  ui = fixture_ui(fixture.fds[0][1]);
  state = calloc(1, sizeof *state);
  CHECK(ui != NULL && state != NULL);
  state->profile_enabled = 1;
  ui->cfg.userdata = state;
  allowance[0] = 1;
  CHECK(fd_write(&ui->transport, scalar, 4) == 4);
  allowance[0] = redirected ? 0 : sizeof captured[0] - 1;
  args[0] = io_hand((u64)(uintptr_t)ui);
  timui_close_run(env, args, NULL);
  birc_final_disown();
  CHECK(fixture_stop(&fixture) == 0);
  if (redirected) {
    CHECK(captured_len[0] == 1 && captured[0][0] == 0xf0);
    CHECK(captured_len[1] > 12 && memcmp(captured[1], "birc_profile", 12) == 0);
  } else {
    CHECK(captured_len[0] > 16 && memcmp(captured[0], scalar, 4) == 0);
    CHECK(memcmp(captured[0] + 4, "birc_profile", 12) == 0);
  }
  return 0;
}

static void returning_signal(int sig) {
  (void)sig;
  signal_count++;
  if (watch_retire)
    signal_retire_phase = __atomic_load_n(&ui_retired, __ATOMIC_ACQUIRE);
}

static int signal_borrow(int shared, int frame) {
  SinkFixture fixture;
  Env env = {0};
  Timui *ui;
  Term args[1];
  struct sigaction action, saved;
  TimuiTransportWrite saved_write;
  int input, input_flags, output_flags, saved_flags = -1;
  CHECK(fixture_start(&fixture) == 0);
  ui = fixture_ui(fixture.fds[0][1]);
  CHECK(ui != NULL);
  ui->cfg.userdata = calloc(1, sizeof(BircUi));
  CHECK(ui->cfg.userdata != NULL);
  birc_ui_live = ui;
  input = shared ? fixture.fds[0][1] : fixture.fds[1][1];
  input_flags = fcntl(input, F_GETFL, 0);
  output_flags = fcntl(fixture.fds[0][1], F_GETFL, 0);
  CHECK(input_flags >= 0 && output_flags >= 0);
  ui->fd.read_fd = input;
  ui->input_flags = input_flags;
  ui->input_flags_saved = 1;
  CHECK(fcntl(input, F_SETFL, input_flags | O_NONBLOCK) == 0);
  ui->cfg.flags = TIMUI_FLAG_RESTORE_ON_EXIT;
  memset(&action, 0, sizeof action);
  action.sa_handler = returning_signal;
  sigemptyset(&action.sa_mask);
  CHECK(sigaction(SIGTERM, &action, &saved) == 0);
  timui_install_sig_handlers(ui);
  signal_count = signal_nonblock = 0;
  signal_on_write = 1;
  allowance[0] = 1;
  if (frame) {
    saved_write = birc_output_begin(ui, &saved_flags);
    CHECK(birc_frame_write(&ui->transport, "\xf0\x9f\x98\x80", 4) == 4);
    birc_output_end(ui, saved_write, saved_flags);
  } else {
    birc_write_bounded(&ui->fd, ui->fd.write_fd, "\xf0\x9f\x98\x80", 4, 0);
  }
  timui_remove_sig_handlers(ui);
  CHECK(sigaction(SIGTERM, &saved, NULL) == 0);
  CHECK(signal_count == 1 && signal_nonblock && !ui->input_flags_saved);
  /* The borrow's old snapshot must not undo a returning handler's restore.
   * An independent output description must still lose the borrow's own bit. */
  int flags_ok = fcntl(input, F_GETFL, 0) == input_flags &&
                 fcntl(ui->fd.write_fd, F_GETFL, 0) == output_flags;
  allowance[0] = sizeof captured[0] - captured_len[0];
  args[0] = io_hand((u64)(uintptr_t)ui);
  timui_close_run(env, args, NULL);
  CHECK(fixture_stop(&fixture) == 0);
  CHECK(flags_ok);
  CHECK(captured_len[0] >= 4 && memcmp(captured[0], "\xf0\x9f\x98\x80", 4) == 0);
  return 0;
}

static int output_failure_status(void) {
  SinkFixture fixture;
  Env env = {0};
  static const char expected[] = "birc=failed\n";
  CHECK(fixture_start(&fixture) == 0);
  allowance[0] = sizeof captured[0];
  birc_output_failure = 1;
  if (!setjmp(final_exit))
    sys_exit_done_run(env, NULL, NULL);
  birc_output_failure = 0;
  CHECK(fixture_stop(&fixture) == 0);
  CHECK(final_status == EXIT_FAILURE);
  CHECK(captured_len[0] == sizeof expected - 1 &&
        memcmp(captured[0], expected, sizeof expected - 1) == 0);
  return 0;
}

static int signal_next_payload(int shared, int capture) {
  SinkFixture fixture;
  Timui *ui;
  Env env = {0};
  Term args[1];
  struct sigaction action, saved;
  struct timespec before, after;
  TimuiTransportWrite saved_write;
  unsigned char payload[65536], drained[4096];
  int input, input_flags, output_flags, saved_flags = -1, result;
  CHECK(fixture_start(&fixture) == 0);
  /* Grow/fill the real pipe before taking its original flag snapshot. Darwin
   * exposes its internal large-pipe bit through F_GETFL after the first large
   * write; that is not a flag the bounded writer owns. */
  output_flags = fcntl(fixture.fds[0][1], F_GETFL, 0);
  CHECK(output_flags >= 0);
  CHECK(fcntl(fixture.fds[0][1], F_SETFL, output_flags | O_NONBLOCK) == 0);
  memset(payload, 'x', sizeof payload);
  while (real_write(fixture.fds[0][1], payload, sizeof payload) > 0) {}
  CHECK(errno == EAGAIN || errno == EWOULDBLOCK);
  CHECK(read(fixture.fds[0][0], drained, sizeof drained) == sizeof drained);
  CHECK(fcntl(fixture.fds[0][1], F_SETFL, output_flags) == 0);
  ui = fixture_ui(fixture.fds[0][1]);
  CHECK(ui != NULL);
  ui->cfg.userdata = calloc(1, sizeof(BircUi));
  CHECK(ui->cfg.userdata != NULL);
  birc_ui_live = ui;
  input = shared ? ui->fd.write_fd : fixture.fds[1][1];
  input_flags = fcntl(input, F_GETFL, 0);
  output_flags = fcntl(ui->fd.write_fd, F_GETFL, 0);
  CHECK(input_flags >= 0 && output_flags >= 0);
  ui->fd.read_fd = input;
  ui->input_flags = input_flags;
  ui->input_flags_saved = 1;
  CHECK(fcntl(input, F_SETFL, input_flags | O_NONBLOCK) == 0);
  ui->cfg.flags = TIMUI_FLAG_RESTORE_ON_EXIT;
  memset(&action, 0, sizeof action);
  action.sa_handler = returning_signal;
  sigemptyset(&action.sa_mask);
  CHECK(sigaction(SIGTERM, &action, &saved) == 0);
  timui_install_sig_handlers(ui);
  saved_write = birc_output_begin(ui, &saved_flags);
  signal_count = signal_nonblock = blocking_attempt = 0;
  real_sink = 1;
  if (capture) {
    /* The frame transport is installed, but no fd writer owns the flags. */
    CHECK(raise(SIGTERM) == 0);
  } else {
    signal_on_write = 1;
    CHECK(timui_fd_write_(&ui->fd, "x", 1, 1, 0) == 1);
    CHECK(signal_nonblock);
  }
  CHECK(signal_count == 1 && !ui->input_flags_saved);
  CHECK(clock_gettime(CLOCK_MONOTONIC, &before) == 0);
  result = timui_fd_write_(&ui->fd, payload, sizeof payload, 1, 0);
  CHECK(clock_gettime(CLOCK_MONOTONIC, &after) == 0);
  real_sink = 0;
  birc_output_end(ui, saved_write, saved_flags);
  timui_remove_sig_handlers(ui);
  CHECK(sigaction(SIGTERM, &saved, NULL) == 0);
  int flags_ok = fcntl(input, F_GETFL, 0) == input_flags &&
                 fcntl(ui->fd.write_fd, F_GETFL, 0) == output_flags;
  allowance[0] = sizeof captured[0];
  args[0] = io_hand((u64)(uintptr_t)ui);
  timui_close_run(env, args, NULL);
  CHECK(fixture_stop(&fixture) == 0);
  CHECK(!blocking_attempt);
  CHECK(result >= -1 && result < (int)sizeof payload);
  CHECK((after.tv_sec - before.tv_sec) * 1000 +
        (after.tv_nsec - before.tv_nsec) / 1000000 < 500);
  CHECK(flags_ok);
  return 0;
}

static int successful_short_budget(int expired) {
  SinkFixture fixture;
  TimuiFdCtx output = {0};
  static const char payload[] = "0123456789abcdef";
  uint64_t deadline = expired ? 0 : (uint64_t)(clock_seconds + 1000) * 1000;
  int written;
  CHECK(fixture_start(&fixture) == 0);
  output.write_fd = fixture.fds[0][1];
  allowance[0] = sizeof captured[0];
  short_success = 1;
  written = timui_fd_write_(&output, payload, sizeof payload - 1, 1, deadline);
  short_success = 0;
  CHECK(fixture_stop(&fixture) == 0);
  CHECK(written == (expired ? 1 : (int)sizeof payload - 1));
  CHECK(captured_len[0] == (size_t)written && attempts[0] == (size_t)written);
  CHECK(memcmp(captured[0], payload, captured_len[0]) == 0);
  return 0;
}

#ifdef BIRC_OUTPUT_H
static int capture_failure_preserves_debt(int failure) {
  SinkFixture fixture;
  Env env = {0};
  Timui *ui;
  BircUi *state;
  TimuiTransportWrite saved;
  int flags;
  static const char prefix[] = "\x1b[?2026h\x1b]52;;x";
  CHECK(fixture_start(&fixture) == 0);
  ui = fixture_ui(fixture.fds[0][1]);
  state = calloc(1, sizeof *state);
  CHECK(ui && state);
  ui->cfg.userdata = state;
  birc_ui_live = ui;
  allowance[0] = sizeof captured[0];
  CHECK(fd_write(&ui->transport, prefix, sizeof prefix - 1) == (int)sizeof prefix - 1);
  ui->framing_debt = ui->sync_open = 1;
  clock_paused = 1;
  saved = birc_output_begin(ui, &flags);
  CHECK(!ui->framing_debt && ui->sync_open); /* resync captured, not physical */
  CHECK(timui_sync_end_accepted_(&ui->transport));
  ui->sync_open = 0; /* native frame accepted its closing marker in memory */
  if (failure)
    CHECK(birc_frame_write(&ui->transport, "", BIRC_OUTPUT_LIMIT) < 0);
  else
    CHECK(birc_frame_write(&ui->transport, "done", 4) == 4);
  birc_output_end(ui, saved, flags);
  CHECK(captured_len[0] == sizeof prefix - 1 + (failure ? 0u : 15u));
  int correct_debt = failure ? ui->framing_debt && ui->sync_open
                            : !ui->framing_debt && !ui->sync_open;
  Term args[1] = {io_hand((u64)(uintptr_t)ui)};
  timui_close_run(env, args, NULL);
  clock_paused = 0;
  birc_output_failure = 0;
  CHECK(fixture_stop(&fixture) == 0);
  CHECK(correct_debt);
  CHECK(captured_len[0] > sizeof prefix - 1 + 11);
  CHECK(memcmp(captured[0] + sizeof prefix - 1, "\\\x1b\\\x1b[?2026l", 11) == 0);
  return 0;
}

/* A transient writer owner can refuse the begin drain before its deadline.
 * If end drains that old frame, the refused latest model still needs paint. */
static int latest_frame_pending(void) {
  SinkFixture fixture;
  Env env = {0};
  Timui *ui;
  BircUi *state;
  TimuiTransportWrite saved;
  int flags;
  CHECK(fixture_start(&fixture) == 0);
  ui = fixture_ui(fixture.fds[0][1]);
  state = calloc(1, sizeof *state);
  CHECK(ui && state);
  ui->cfg.userdata = state;
  birc_ui_live = ui;
  CHECK(birc_output_start(&state->output));
  CHECK(birc_output_capture(&state->output, "OLD", 3) == 3);
  CHECK(birc_output_finish(&state->output));
  clock_paused = 1;
  ui->fd.write_owner = 3;
  saved = birc_output_begin(ui, &flags);
  CHECK(!state->output.capturing);
  CHECK(birc_frame_write(&ui->transport, "LATEST", 6) < 0);
  ui->fd.write_owner = 0;
  allowance[0] = sizeof captured[0];
  birc_output_end(ui, saved, flags);
  CHECK(state->output.size == 0 && birc_output_pending(ui));
  saved = birc_output_begin(ui, &flags);
  CHECK(state->output.capturing);
  CHECK(birc_frame_write(&ui->transport, "LATEST", 6) == 6);
  birc_output_end(ui, saved, flags);
  CHECK(!birc_output_pending(ui));
  CHECK(captured_len[0] == 9 && memcmp(captured[0], "OLDLATEST", 9) == 0);
  Term args[1] = {io_hand((u64)(uintptr_t)ui)};
  timui_close_run(env, args, NULL);
  clock_paused = 0;
  CHECK(fixture_stop(&fixture) == 0);
  return 0;
}

/* Each native call permits a first attempt. A serialized frame must not use
 * repeated calls, including its end drain, to bypass that one deadline. */
static int serialized_frame_budget(int expired) {
  SinkFixture fixture;
  Env env = {0};
  Timui *ui;
  BircUi *state;
  TimuiTransportWrite saved;
  static const char payload[] = "0123456789abcdef";
  int flags;
  CHECK(fixture_start(&fixture) == 0);
  ui = fixture_ui(fixture.fds[0][1]);
  state = calloc(1, sizeof *state);
  CHECK(ui && state);
  ui->cfg.userdata = state;
  birc_ui_live = ui;
  CHECK(birc_output_start(&state->output));
  CHECK(birc_output_capture(&state->output, payload, sizeof payload - 1) == (int)sizeof payload - 1);
  CHECK(birc_output_finish(&state->output));
  allowance[0] = sizeof captured[0];
  short_success = 1;
  clock_paused = !expired;
  saved = birc_output_begin(ui, &flags);
  birc_output_end(ui, saved, flags);
  CHECK(captured_len[0] == (expired ? 1u : sizeof payload - 1));
  CHECK(attempts[0] == captured_len[0]);
  short_success = 0;
  clock_paused = 1;
  Term args[1] = {io_hand((u64)(uintptr_t)ui)};
  timui_close_run(env, args, NULL);
  clock_paused = 0;
  CHECK(fixture_stop(&fixture) == 0);
  return 0;
}
#endif
/* Reuse released storage but keep it mapped. This observes stale access to a
 * retired allocator object without dereferencing an actual freed allocation. */
static void retire_ui(void *arg, void *pointer, size_t bytes) {
  Timui *ui = pointer;
  (void)arg;
  memset(pointer, 0, bytes);
  ui->fd.write_fd = 999;
  __atomic_store_n(&ui_retired, 1, __ATOMIC_RELEASE);
}

static void retire_image(void *arg, void *pointer, size_t bytes) {
  TimuiImage *image = pointer;
  (void)arg;
  image_detached += image->id_owner == NULL;
  image_freed++;
  memset(pointer, 0, bytes);
}

static void *deliver_paused_signal(void *arg) {
  (void)arg;
  if (raise(SIGTERM) != 0)
    abort();
  return NULL;
}

static int same_termios(const struct termios *a, const struct termios *b) {
  return a->c_iflag == b->c_iflag && a->c_oflag == b->c_oflag &&
         a->c_cflag == b->c_cflag && a->c_lflag == b->c_lflag &&
         memcmp(a->c_cc, b->c_cc, sizeof a->c_cc) == 0 &&
         cfgetispeed(a) == cfgetispeed(b) && cfgetospeed(a) == cfgetospeed(b);
}

static int handler_close_lifetime(int unresolved) {
  SinkFixture fixture;
  Env env = {0};
  Term args[1];
  Timui *ui;
  BircUi *state;
  TimuiImage *image, *retiring;
  struct sigaction action, saved, current, previous;
  struct termios original, restored;
  pthread_t handler;
  char byte = 1;
  int master, slave, input_probe, output_probe, input_flags, output_flags, other_flags;
  int held, previews_held, unresolved_quiet = 1, host_restored = 1;
  CHECK(fixture_start(&fixture) == 0);
  CHECK(pipe(pause_enter) == 0 && pipe(pause_resume) == 0);
  master = posix_openpt(O_RDWR | O_NOCTTY);
  CHECK(master >= 0 && grantpt(master) == 0 && unlockpt(master) == 0);
  slave = open(ptsname(master), O_RDWR | O_NOCTTY);
  CHECK(slave >= 0 && tcgetattr(slave, &original) == 0);
  input_probe = dup(slave);
  CHECK(input_probe >= 0);
  ui = fixture_ui(fixture.fds[0][1]);
  state = calloc(1, sizeof *state);
  image = calloc(1, sizeof *image);
  retiring = calloc(1, sizeof *retiring);
  CHECK(ui && state && image && retiring);
  ui->cfg.userdata = state;
  ui->alloc.free = retire_ui;
  image->alloc = timui_default_allocator();
  image->alloc.free = retire_image;
  retiring->alloc = image->alloc;
  state->previews[0].image = image;
  state->previews[1].retiring = retiring;
  timui_set_image_id_for_test(ui, image, 7);
  timui_set_image_id_for_test(ui, retiring, 8);
  CHECK(birc_output_start(&state->output));
  CHECK(birc_output_capture(&state->output, "owned", 5) == 5);
  CHECK(birc_output_finish(&state->output));
  unsigned char *owned_payload = state->output.bytes;
  birc_ui_live = ui;
  ui->fd.read_fd = slave;
  input_flags = fcntl(slave, F_GETFL, 0);
  output_flags = fcntl(ui->fd.write_fd, F_GETFL, 0);
  output_probe = dup(ui->fd.write_fd);
  other_flags = fcntl(fixture.fds[1][1], F_GETFL, 0);
  CHECK(input_flags >= 0 && output_flags >= 0 && other_flags >= 0 && output_probe >= 0);
  ui->input_flags = input_flags;
  ui->input_flags_saved = 1;
  CHECK(fcntl(slave, F_SETFL, input_flags | O_NONBLOCK) == 0);
  CHECK(timui_termios_enter(&ui->termios, slave) == TIMUI_OK);
  ui->termios_active = 1;
  ui->cfg.flags = TIMUI_FLAG_RESTORE_ON_EXIT;
  memset(&action, 0, sizeof action);
  action.sa_handler = returning_signal;
  sigemptyset(&action.sa_mask);
  sigaddset(&action.sa_mask, SIGUSR1);
  action.sa_flags = SA_RESTART;
  CHECK(sigaction(SIGTERM, &action, &saved) == 0);
  CHECK(sigaction(SIGTERM, NULL, &previous) == 0);
  timui_install_sig_handlers(ui);
  CHECK(sigaction(SIGTERM, NULL, &current) == 0 && current.sa_handler == timui_sig_restore);
  /* A frame borrow can precede the signal. A returning handler must not
   * reinstate that borrowed flag after final host restoration. */
  if (unresolved == 3)
    CHECK(fcntl(ui->fd.write_fd, F_SETFL, output_flags | O_NONBLOCK) == 0);
  __atomic_store_n(&ui_retired, 0, __ATOMIC_RELEASE);
  signal_count = image_freed = image_detached = 0;
  allowance[0] = sizeof captured[0];
  pause_handler = 1;
  CHECK(pthread_create(&handler, NULL, deliver_paused_signal, NULL) == 0);
  CHECK(read(pause_enter[0], &byte, 1) == 1 &&
        __atomic_load_n(&pause_phase, __ATOMIC_ACQUIRE) == 1);
  args[0] = io_hand((u64)(uintptr_t)ui);
  timui_close_run(env, args, NULL);
  held = !__atomic_load_n(&ui_retired, __ATOMIC_ACQUIRE);
  previews_held = held && image_freed == 0 && image->id_owner == ui &&
      retiring->id_owner == ui && state->output.bytes == owned_payload;
  /* Caller may reuse both borrowed descriptor numbers after close returns.
   * The handler must keep writing/restoring the original streams. */
  CHECK(close(slave) == 0 && dup2(fixture.fds[1][1], slave) == slave);
  CHECK(close(fixture.fds[0][1]) == 0 &&
        dup2(fixture.fds[1][1], fixture.fds[0][1]) == fixture.fds[0][1]);
  if (unresolved) {
    struct timespec before_time, after_time;
    size_t before = captured_len[0];
    if (unresolved == 2)
      CHECK(dup2(fixture.fds[1][1], STDOUT_FILENO) == STDOUT_FILENO);
    CHECK(clock_gettime(CLOCK_MONOTONIC, &before_time) == 0);
    if (!setjmp(final_exit))
      sys_exit_done_run(env, NULL, NULL);
    CHECK(clock_gettime(CLOCK_MONOTONIC, &after_time) == 0);
    unresolved_quiet = captured_len[0] == before &&
        captured_len[1] == (unresolved == 2 ? 8u : 0u) &&
        (after_time.tv_sec - before_time.tv_sec) * 1000 +
            (after_time.tv_nsec - before_time.tv_nsec) / 1000000 < 500;
    host_restored = tcgetattr(input_probe, &restored) == 0 &&
        same_termios(&original, &restored) &&
        fcntl(input_probe, F_GETFL, 0) == input_flags &&
        fcntl(output_probe, F_GETFL, 0) == output_flags &&
        !__atomic_load_n(&ui_retired, __ATOMIC_ACQUIRE) && image_freed == 0;
  }
  CHECK(dup2(output_probe, STDOUT_FILENO) == STDOUT_FILENO);
  __atomic_store_n(&pause_phase, 2, __ATOMIC_RELEASE);
  CHECK(write(pause_resume[1], &byte, 1) == 1 && pthread_join(handler, NULL) == 0);
  CHECK(sigaction(SIGTERM, NULL, &current) == 0);
  int disposition_ok = current.sa_handler == action.sa_handler &&
      current.sa_flags == previous.sa_flags && sigismember(&current.sa_mask, SIGUSR1) == 1;
  if (!setjmp(final_exit))
    sys_exit_done_run(env, NULL, NULL);
  int restored_ok = tcgetattr(input_probe, &restored) == 0 &&
      same_termios(&original, &restored) &&
      fcntl(input_probe, F_GETFL, 0) == input_flags &&
      fcntl(STDOUT_FILENO, F_GETFL, 0) == output_flags &&
      fcntl(fixture.fds[1][1], F_GETFL, 0) == other_flags;
  CHECK(sigaction(SIGTERM, &saved, NULL) == 0);
  CHECK(close(master) == 0 && close(slave) == 0 && close(input_probe) == 0 && close(output_probe) == 0);
  CHECK(close(pause_enter[0]) == 0 && close(pause_enter[1]) == 0);
  CHECK(close(pause_resume[0]) == 0 && close(pause_resume[1]) == 0);
  CHECK(fixture_stop(&fixture) == 0);
  CHECK(held && previews_held && unresolved_quiet && host_restored);
  CHECK(disposition_ok && signal_count == 1 && restored_ok);
  CHECK(__atomic_load_n(&ui_retired, __ATOMIC_ACQUIRE) &&
        image_freed == 2 && image_detached == 2);
  CHECK(captured_len[1] == (unresolved == 2 ? 8u : 0u) && captured_len[0] >= 8 &&
        memcmp(captured[0] + captured_len[0] - 8, "birc=ok\n", 8) == 0);
  free(image);
  free(retiring);
  free(ui);
  return 0;
}

static int signal_during_close(void) {
  SinkFixture fixture;
  Env env = {0};
  Term args[1];
  Timui *ui;
  struct sigaction action, saved, current, previous;
  CHECK(fixture_start(&fixture) == 0);
  ui = fixture_ui(fixture.fds[0][1]);
  CHECK(ui != NULL);
  ui->alloc.free = retire_ui;
  ui->cfg.flags = TIMUI_FLAG_RESTORE_ON_EXIT;
  memset(&action, 0, sizeof action);
  action.sa_handler = returning_signal;
  sigemptyset(&action.sa_mask);
  sigaddset(&action.sa_mask, SIGUSR1);
  action.sa_flags = SA_RESTART;
  CHECK(sigaction(SIGTERM, &action, &saved) == 0);
  CHECK(sigaction(SIGTERM, NULL, &previous) == 0);
  timui_install_sig_handlers(ui);
  CHECK(sigaction(SIGTERM, NULL, &current) == 0 && current.sa_handler == timui_sig_restore);
  __atomic_store_n(&ui_retired, 0, __ATOMIC_RELEASE);
  signal_count = signal_retire_phase = 0;
  watch_retire = signal_on_write = 1;
  allowance[0] = sizeof captured[0];
  args[0] = io_hand((u64)(uintptr_t)ui);
  timui_close_run(env, args, NULL);
  watch_retire = 0;
  CHECK(sigaction(SIGTERM, NULL, &current) == 0);
  int disposition_ok = current.sa_handler == action.sa_handler &&
      current.sa_flags == previous.sa_flags && sigismember(&current.sa_mask, SIGUSR1) == 1;
  CHECK(sigaction(SIGTERM, &saved, NULL) == 0);
  CHECK(fixture_stop(&fixture) == 0);
  CHECK(signal_count == 1 && signal_retire_phase == 1 && disposition_ok);
  free(ui);
  return 0;
}

static int late_signal_entry(void) {
  struct sigaction action, saved, current;
  memset(&action, 0, sizeof action);
  action.sa_handler = returning_signal;
  sigemptyset(&action.sa_mask);
  CHECK(sigaction(SIGTERM, &action, &saved) == 0);
  signal_count = 0;
  /* Simulate an already-dispatched handler entering after the close handoff.
   * It must preserve the caller's current disposition, not install SIG_DFL. */
  timui_sig_restore(SIGTERM);
  CHECK(sigaction(SIGTERM, NULL, &current) == 0);
  CHECK(current.sa_handler == action.sa_handler && signal_count == 1);
  CHECK(sigaction(SIGTERM, &saved, NULL) == 0);
  return 0;
}

static int short_signal_debt(int sync, int recover) {
  SinkFixture fixture;
  Env env = {0};
  Term args[1];
  Timui *ui;
  struct sigaction action, saved;
  const char *repair = sync ? "\x1b[?2026l" : "\\\x1b\\";
  size_t repair_len = sync ? 8u : 3u;
  int debt_held;
  CHECK(fixture_start(&fixture) == 0);
  ui = fixture_ui(fixture.fds[0][1]);
  CHECK(ui != NULL);
  ui->cfg.flags = TIMUI_FLAG_RESTORE_ON_EXIT;
  memset(&action, 0, sizeof action);
  action.sa_handler = returning_signal;
  sigemptyset(&action.sa_mask);
  CHECK(sigaction(SIGTERM, &action, &saved) == 0);
  CHECK(timui_install_sig_handlers(ui));
  ui->framing_debt = !sync;
  ui->sync_open = sync;
  allowance[0] = 1;
  CHECK(raise(SIGTERM) == 0);
  debt_held = captured_len[0] == 1 && (sync ? ui->sync_open : ui->framing_debt);
  allowance[0] = 0;
  args[0] = io_hand((u64)(uintptr_t)ui);
  timui_close_run(env, args, NULL);
  allowance[0] = recover ? sizeof captured[0] : 0;
  if (!setjmp(final_exit))
    sys_exit_done_run(env, NULL, NULL);
  CHECK(sigaction(SIGTERM, &saved, NULL) == 0);
  CHECK(fixture_stop(&fixture) == 0);
  CHECK(debt_held);
  CHECK(recover ? captured_len[0] == 1 + repair_len + 8 &&
      memcmp(captured[0] + 1, repair, repair_len) == 0 &&
      memcmp(captured[0] + captured_len[0] - 8, "birc=ok\n", 8) == 0 :
      captured_len[0] == 1);
  return 0;
}

static int signal_title_pop(size_t cut) {
  static const char prefix[] = "\x1b[?25h\x1b[?7h";
  static const char pop[] = "\x1b[23;0t";
  SinkFixture fixture;
  Env env = {0};
  Term args[1];
  struct sigaction action, saved;
  Timui *ui;
  int ownership_ok;
  CHECK(fixture_start(&fixture) == 0);
  ui = fixture_ui(fixture.fds[0][1]);
  CHECK(ui != NULL);
  allowance[0] = sizeof captured[0];
  timui_screen_enter(&ui->transport, &ui->screen, 0, timui_str_from_cstr("owned"));
  CHECK(ui->screen.flags != 0); /* actual accepted title push, no forged bit */
  ui->cfg.flags = TIMUI_FLAG_RESTORE_ON_EXIT;
  memset(&action, 0, sizeof action);
  action.sa_handler = returning_signal;
  sigemptyset(&action.sa_mask);
  CHECK(sigaction(SIGTERM, &action, &saved) == 0 && timui_install_sig_handlers(ui));
  captured_len[0] = 0;
  allowance[0] = sizeof prefix - 1 + cut;
  CHECK(raise(SIGTERM) == 0);
  ownership_ok = (ui->screen.flags != 0) == (cut < sizeof pop - 1);
  allowance[0] = sizeof captured[0] - captured_len[0];
  args[0] = io_hand((u64)(uintptr_t)ui);
  timui_close_run(env, args, NULL);
  CHECK(sigaction(SIGTERM, &saved, NULL) == 0 && fixture_stop(&fixture) == 0);
  CHECK(ownership_ok);
  CHECK(captured_len[0] == 2 * (sizeof prefix - 1) + cut +
      (cut < sizeof pop - 1 ? sizeof pop - 1 : 0));
  CHECK(memcmp(captured[0], prefix, sizeof prefix - 1) == 0 &&
      memcmp(captured[0] + sizeof prefix - 1, pop, cut) == 0);
  return 0;
}

int main(int argc, char **argv) {
  size_t cut, repair;
  if (argc == 4 && strcmp(argv[1], "flags") == 0)
    return signal_next_payload(atoi(argv[2]), atoi(argv[3]));
  if (argc == 3 && strcmp(argv[1], "budget") == 0)
    return successful_short_budget(atoi(argv[2]));
  if (argc == 3 && strcmp(argv[1], "lifetime") == 0)
    return handler_close_lifetime(atoi(argv[2]));
  if (argc == 2 && strcmp(argv[1], "closing") == 0)
    return signal_during_close();
  if (argc == 2 && strcmp(argv[1], "late") == 0)
    return late_signal_entry();
  if (argc == 4 && strcmp(argv[1], "signal-debt") == 0)
    return short_signal_debt(atoi(argv[2]), atoi(argv[3]));
  if (argc == 3 && strcmp(argv[1], "signal-title") == 0)
    return signal_title_pop((size_t)atoi(argv[2]));
  for (cut = 1; cut < 4; cut++) {
    for (repair = 0; repair < 4 - cut; repair++) {
      CHECK(run_final(cut, repair, 0, 0, 0) == 0);
      CHECK(run_final(cut, repair, 1, 0, 0) == 0);
    }
    CHECK(run_final(cut, sizeof captured[0], 0, 0, 0) == 0);
    CHECK(run_final(cut, sizeof captured[0], 1, 0, 0) == 0);
  }
  CHECK(run_final(1, 0, 0, 1, 0) == 0);
  CHECK(run_final(1, 0, 1, 1, 0) == 0);
  CHECK(run_final(1, sizeof captured[0], 0, 0, 1) == 0);
  CHECK(run_final(1, 0, 0, 1, 1) == 0);
  CHECK(unicode_failure() == 0);
  CHECK(profile_alias(0) == 0);
  CHECK(profile_alias(1) == 0);
  CHECK(signal_borrow(1, 1) == 0);
  CHECK(signal_borrow(0, 1) == 0);
  CHECK(signal_borrow(1, 0) == 0);
  CHECK(signal_borrow(0, 0) == 0);
  for (int debt = 1; debt <= 3; debt++) {
    size_t owed = 3 + (debt & 1 ? 3 : 0) + (debt & 2 ? 8 : 0);
    for (repair = 0; repair < owed; repair++) {
      CHECK(run_final_debt(1, repair, 0, 0, 0, debt) == 0);
      CHECK(run_final_debt(1, repair, 1, 0, 0, debt) == 0);
    }
    CHECK(run_final_debt(1, sizeof captured[0], 0, 0, 1, debt) == 0);
    CHECK(run_final_debt(1, sizeof captured[0], 1, 0, 0, debt) == 0);
    CHECK(run_final_debt(1, 0, 0, 1, 1, debt) == 0);
    CHECK(run_final_debt(1, 0, 1, 1, 0, debt) == 0);
  }
  CHECK(output_failure_status() == 0);
  CHECK(signal_next_payload(1, 0) == 0);
  CHECK(signal_next_payload(0, 0) == 0);
  CHECK(signal_next_payload(1, 1) == 0);
  CHECK(signal_next_payload(0, 1) == 0);
  CHECK(successful_short_budget(0) == 0);
  CHECK(successful_short_budget(1) == 0);
#ifdef BIRC_OUTPUT_H
  CHECK(capture_failure_preserves_debt(1) == 0);
  CHECK(capture_failure_preserves_debt(0) == 0);
  CHECK(latest_frame_pending() == 0);
  CHECK(serialized_frame_budget(0) == 0);
  CHECK(serialized_frame_budget(1) == 0);
#endif
  CHECK(handler_close_lifetime(0) == 0);
  CHECK(handler_close_lifetime(1) == 0);
  CHECK(handler_close_lifetime(2) == 0);
  CHECK(handler_close_lifetime(3) == 0);
  CHECK(signal_during_close() == 0);
  CHECK(late_signal_entry() == 0);
  CHECK(short_signal_debt(0, 0) == 0);
  CHECK(short_signal_debt(0, 1) == 0);
  CHECK(short_signal_debt(1, 0) == 0);
  CHECK(short_signal_debt(1, 1) == 0);
  CHECK(signal_title_pop(0) == 0);
  CHECK(signal_title_pop(1) == 0);
  CHECK(signal_title_pop(6) == 0);
  CHECK(signal_title_pop(7) == 0);
  puts("output_shutdown=ok");
  return 0;
}
