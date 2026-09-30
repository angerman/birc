/* A bounded fd writer must finish an accepted UTF-8 scalar before new output. */
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static char captured[128];
static size_t captured_len;
static size_t allowance;

static ssize_t test_write_syscall(int fd, const void *data, size_t size) {
  (void)fd;
  if (allowance == 0) {
    errno = EAGAIN;
    return -1;
  }
  if (size > allowance)
    size = allowance;
  if (size > sizeof captured - captured_len) {
    errno = EIO;
    return -1;
  }
  memcpy(captured + captured_len, data, size);
  captured_len += size;
  allowance -= size;
  return (ssize_t)size;
}

#define write test_write_syscall
#define TIMUI_IMPLEMENTATION
#include "timui.h"
static void use_fd_writer(TimuiTransport *transport) {
  transport->write = fd_write;
}
#undef write

#define CHECK(test) do { if (!(test)) { \
  fprintf(stderr, "output_utf8: line %d: %s\n", __LINE__, #test); return 1; \
} } while (0)

static void setup(TimuiFdCtx *ctx, TimuiTransport *transport) {
  memset(ctx, 0, sizeof *ctx);
  memset(transport, 0, sizeof *transport);
  ctx->write_fd = 73;
  ctx->teardown_bounded = 1;
  ctx->teardown_deadline_ms = 0;
  transport->ctx = ctx;
  captured_len = 0;
}

static int full_write(void) {
  TimuiFdCtx ctx;
  TimuiTransport transport;
  static const char text[] = "ascii \xc3\xa9 \xe2\x94\x80 \xf0\x9f\x98\x80";
  setup(&ctx, &transport);
  allowance = sizeof captured;
  CHECK(fd_write(&transport, text, sizeof text - 1) == (int)(sizeof text - 1));
  CHECK(captured_len == sizeof text - 1);
  CHECK(memcmp(captured, text, captured_len) == 0);
  return 0;
}

static int ascii_short(void) {
  TimuiFdCtx ctx;
  TimuiTransport transport;
  setup(&ctx, &transport);
  allowance = 3;
  CHECK(fd_write(&transport, "abcde", 5) == 3);
  CHECK(ctx.write_utf8_tail_len == 0);
  CHECK(fd_write(&transport, "de", 2) < 0);
  allowance = sizeof captured;
  CHECK(fd_write(&transport, "de", 2) == 2);
  CHECK(captured_len == 5 && memcmp(captured, "abcde", 5) == 0);
  return 0;
}

static int scalar_only(void) {
  TimuiFdCtx ctx;
  TimuiTransport transport;
  static const char scalar[] = "\xe2\x94\x80";
  setup(&ctx, &transport);
  allowance = 2;
  CHECK(fd_write(&transport, scalar, sizeof scalar - 1) == 3);
  CHECK(ctx.write_utf8_tail_len == 1 && captured_len == 2);
  CHECK(fd_write(&transport, "\x1b[0m", 4) < 0);
  allowance = sizeof captured;
  CHECK(fd_write(&transport, "\x1b[0m", 4) == 4);
  CHECK(captured_len == 7 && memcmp(captured, "\xe2\x94\x80\x1b[0m", 7) == 0);
  return 0;
}

static int restore_after_cut(void) {
  Timui ui;
  size_t i;
  memset(&ui, 0, sizeof ui);
  setup(&ui.fd, &ui.transport);
  use_fd_writer(&ui.transport);
  ui.have_transport = 1;
  ui.screen_active = 1;
  ui.screen.flags = TIMUI_FLAG_ALT_SCREEN;
  allowance = 2;
  CHECK(fd_write(&ui.transport, "\xe2\x94\x80", 3) == 3);
  timui_restore_terminal_armed_(&ui, 1);
  CHECK(captured_len == 2 && ui.fd.write_utf8_tail_len == 1);
  ui.fd.teardown_bounded = 1;
  allowance = sizeof captured;
  timui_restore_terminal_armed_(&ui, 1);
  CHECK(ui.fd.write_utf8_tail_len == 0 && captured_len > 3);
  CHECK(memcmp(captured, "\xe2\x94\x80", 3) == 0 && captured[3] == '\x1b');
  for (i = 3; i < captured_len; i++)
    CHECK((unsigned char)captured[i] < 0x80u);
  return 0;
}

static int empty_flush(void) {
  TimuiFdCtx ctx;
  TimuiTransport transport;
  setup(&ctx, &transport);
  allowance = 2;
  CHECK(fd_write(&transport, "\xe2\x94\x80", 3) == 3);
  CHECK(fd_write(&transport, "", 0) < 0);
  CHECK(captured_len == 2 && ctx.write_utf8_tail_len == 1);
  allowance = 1;
  CHECK(fd_write(&transport, "", 0) == 0);
  CHECK(captured_len == 3 && ctx.write_utf8_tail_len == 0);
  CHECK(memcmp(captured, "\xe2\x94\x80", 3) == 0);
  return 0;
}

static int signal_after_cut(size_t repair) {
  Timui ui;
  int fds[2], flags;
  static const char scalar[] = "\xf0\x9f\x98\x80";
  memset(&ui, 0, sizeof ui);
  setup(&ui.fd, &ui.transport);
  use_fd_writer(&ui.transport);
  CHECK(pipe(fds) == 0);
  flags = fcntl(fds[1], F_GETFL, 0);
  CHECK(flags >= 0);
  ui.fd.write_fd = fds[1];
  ui.have_transport = 1;
  ui.screen_active = 1;
  ui.screen.flags = TIMUI_FLAG_ALT_SCREEN;
  allowance = 1;
  CHECK(fd_write(&ui.transport, scalar, sizeof scalar - 1) == 4);
  allowance = repair;
  errno = EINTR;
  timui_signal_restore_terminal_(&ui);
  CHECK(errno == EINTR && fcntl(fds[1], F_GETFL, 0) == flags);
  CHECK(close(fds[0]) == 0 && close(fds[1]) == 0);
  if (repair < 3) {
    CHECK(captured_len == 1 + repair);
    CHECK(memcmp(captured, scalar, captured_len) == 0);
    CHECK(ui.fd.write_utf8_tail_len == 3 - repair);
  } else {
    CHECK(captured_len > 4 && memcmp(captured, scalar, 4) == 0);
    CHECK(ui.fd.write_utf8_tail_len == 0 && captured[4] == '\x1b');
  }
  return 0;
}

static int cut_scalar(const char *scalar, size_t width, size_t cut, int cancel) {
  TimuiFdCtx ctx;
  TimuiTransport transport;
  char text[8], expected[16];
  static const char teardown[] = "\x1b[0m";
  const char *next = cancel ? teardown : "y";
  size_t next_len = cancel ? sizeof teardown - 1 : 1;
  size_t prefix = 1 + cut;
  setup(&ctx, &transport);
  text[0] = 'x';
  memcpy(text + 1, scalar, width);
  text[1 + width] = 'y';
  allowance = prefix;
  /* The writer owns the missing scalar bytes, so its acknowledgement must
   * include them. A caller retry starts at y, never at the staged suffix. */
  CHECK(fd_write(&transport, text, width + 2) == (int)(width + 1));
  CHECK(captured_len == prefix);
  CHECK(fd_write(&transport, next, next_len) < 0);
  CHECK(captured_len == prefix);
  if (width - cut > 1) {
    allowance = 1;
    CHECK(fd_write(&transport, next, next_len) < 0);
    CHECK(captured_len == prefix + 1);
  }
  allowance = sizeof captured;
  CHECK(fd_write(&transport, next, next_len) == (int)next_len);
  expected[0] = 'x';
  memcpy(expected + 1, scalar, width);
  memcpy(expected + 1 + width, next, next_len);
  CHECK(captured_len == 1 + width + next_len);
  CHECK(memcmp(captured, expected, captured_len) == 0);
  /* Empty debt must not replay a suffix on the next independent write. */
  CHECK(fd_write(&transport, "z", 1) == 1);
  CHECK(captured_len == 2 + width + next_len);
  CHECK(captured[captured_len - 1] == 'z');
  return 0;
}

int main(void) {
  static const char *const scalars[] = {"\xc3\xa9", "\xe2\x94\x80", "\xf0\x9f\x98\x80"};
  size_t width, cut;
  CHECK(full_write() == 0);
  CHECK(ascii_short() == 0);
  CHECK(scalar_only() == 0);
  CHECK(restore_after_cut() == 0);
  CHECK(empty_flush() == 0);
  CHECK(signal_after_cut(0) == 0);
  CHECK(signal_after_cut(1) == 0);
  CHECK(signal_after_cut(2) == 0);
  CHECK(signal_after_cut(sizeof captured) == 0);
  for (width = 2; width <= 4; width++)
    for (cut = 1; cut < width; cut++) {
      CHECK(cut_scalar(scalars[width - 2], width, cut, 0) == 0);
      CHECK(cut_scalar(scalars[width - 2], width, cut, 1) == 0);
    }
  puts("output_utf8=ok");
  return 0;
}
