/* SPDX-License-Identifier: Apache-2.0
 * Native auth-pipe controls. All descriptors and passwords are synthetic. */
#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

enum { NORMAL, READ_PARTIAL_EINTR, READ_ERROR, CLOCK_ERROR, FOREIGN_OWNER,
       WRITE_PARTIAL, WRITE_EINTR, CLOSE_ERROR };
static int fault, reads, writes, read_flags, write_flags;
static ssize_t probe_read(int fd, void *bytes, size_t size) {
  reads++;
  read_flags = ((fcntl(fd, F_GETFD) & FD_CLOEXEC) != 0)
      && ((fcntl(fd, F_GETFL) & O_NONBLOCK) != 0);
  if (fault == READ_ERROR) { errno = EIO; return -1; }
  if (fault == READ_PARTIAL_EINTR && reads == 1) { errno = EINTR; return -1; }
  if (fault == READ_PARTIAL_EINTR && size > 1u) size = 1u;
  return read(fd, bytes, size);
}
static ssize_t probe_write(int fd, const void *bytes, size_t size) {
  writes++;
  write_flags = ((fcntl(fd, F_GETFD) & FD_CLOEXEC) != 0)
      && ((fcntl(fd, F_GETFL) & O_NONBLOCK) != 0);
  if (fault == WRITE_EINTR) { errno = EINTR; return -1; }
  if (fault == WRITE_PARTIAL && size > 4u) size = 4u;
  return write(fd, bytes, size);
}
static int probe_clock(clockid_t clock, struct timespec *now) {
  if (fault == CLOCK_ERROR) { errno = EIO; return -1; }
  return clock_gettime(clock, now);
}
static int probe_stat(int fd, struct stat *info) {
  if (fstat(fd, info) != 0) return -1;
  if (fault == FOREIGN_OWNER) info->st_uid = geteuid() == 0 ? (uid_t)1 : (uid_t)0;
  return 0;
}
static int probe_close(int fd) {
  int result = close(fd);
  if (fault == CLOSE_ERROR) { errno = EIO; return -1; }
  return result;
}
#define BIRC_AUTH_BRIDGE_CORE_ONLY
#define read probe_read
#define write probe_write
#define clock_gettime probe_clock
#define fstat probe_stat
#define close probe_close
#include "../src/ffi/auth_bridge_ffi.c"
#undef read
#undef write
#undef clock_gettime
#undef fstat
#undef close

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "auth_bridge:%d: %s\n", __LINE__, #x); return 1; } } while (0)
typedef struct { int input[2], event[2]; } Pipes;
static int clear_env(void) {
  CHECK(unsetenv(BIRC_SECRET_FD) == 0 && unsetenv(BIRC_EVENT_FD) == 0);
  return 0;
}
static int set_fd(const char *name, int fd) {
  char text[32];
  int size = snprintf(text, sizeof text, "%d", fd);
  CHECK(size > 0 && (size_t)size < sizeof text && setenv(name, text, 1) == 0);
  return 0;
}
static int pipes(Pipes *p) {
  CHECK(p != NULL && pipe(p->input) == 0 && pipe(p->event) == 0);
  CHECK(set_fd(BIRC_SECRET_FD, p->input[0]) == 0 && set_fd(BIRC_EVENT_FD, p->event[1]) == 0);
  fault = NORMAL; reads = 0; writes = 0; read_flags = 0; write_flags = 0;
  return 0;
}
static int closed(int fd) { errno = 0; return fcntl(fd, F_GETFD) == -1 && errno == EBADF; }
static int frame(int fd, const char *wanted) {
  char bytes[32];
  size_t size = 0;
  for (;;) {
    ssize_t got = read(fd, bytes + size, sizeof bytes - size);
    CHECK(got >= 0);
    if (got == 0) break;
    size += (size_t)got;
    CHECK(size < sizeof bytes);
  }
  CHECK(size == strlen(wanted) && memcmp(bytes, wanted, size) == 0);
  CHECK(close(fd) == 0);
  return 0;
}
static int setup_case(const unsigned char *secret, size_t length, uint32_t wanted, int failure) {
  Pipes p;
  char bytes[BIRC_SECRET_CAP + 1u];
  size_t size = 999u;
  CHECK(secret != NULL && pipes(&p) == 0);
  CHECK(write(p.input[1], secret, length) == (ssize_t)length && close(p.input[1]) == 0);
  fault = failure;
  CHECK(birc_auth_setup(bytes, &size) == wanted);
  CHECK(closed(p.input[0]) && getenv(BIRC_SECRET_FD) == NULL);
  if (wanted != 0u) {
    CHECK(size == 0u && closed(p.event[1]) && getenv(BIRC_EVENT_FD) == NULL);
    CHECK(frame(p.event[0], "") == 0);
  } else {
    CHECK(size == length && memcmp(bytes, secret, length) == 0 && read_flags);
    CHECK((fcntl(p.event[1], F_GETFD) & FD_CLOEXEC) != 0);
    CHECK((fcntl(p.event[1], F_GETFL) & O_NONBLOCK) != 0);
    CHECK(getenv(BIRC_EVENT_FD) != NULL);
    fault = NORMAL;
    CHECK(birc_auth_notify() == 0u && writes == 1 && write_flags && closed(p.event[1]));
    CHECK(birc_auth_notify() == 0u && writes == 1 && getenv(BIRC_EVENT_FD) == NULL);
    CHECK(frame(p.event[0], "BIRC_AUTH_OK\n") == 0);
  }
  fault = NORMAL;
  return 0;
}
static int secrets(void) {
  unsigned char maximum[BIRC_SECRET_CAP + 1u];
  static const unsigned char good[] = "  p\xc3\xa4ss'\\ word  ";
  static const unsigned char nul[] = {'a', 0u, 'b'};
  static const unsigned char bad[][4] = {{0xc0u, 0xafu, 0u, 0u}, {0xedu, 0xa0u, 0x80u, 0u},
      {0xf4u, 0x90u, 0x80u, 0x80u}, {0x80u, 0u, 0u, 0u}, {0xe2u, 0x82u, 0u, 0u}};
  static const size_t lengths[] = {2u, 3u, 4u, 1u, 2u};
  static const unsigned char bounds[] = {0xe0u, 0xa0u, 0x80u, 0xedu, 0x9fu, 0xbfu,
      0xf0u, 0x90u, 0x80u, 0x80u, 0xf4u, 0x8fu, 0xbfu, 0xbfu};
  CHECK(setup_case(good, sizeof good - 1u, 0u, NORMAL) == 0);
  CHECK(setup_case(bounds, sizeof bounds, 0u, NORMAL) == 0);
  CHECK(setup_case(good, sizeof good - 1u, 0u, READ_PARTIAL_EINTR) == 0);
  CHECK(setup_case(good, sizeof good - 1u, (uint32_t)EIO, READ_ERROR) == 0);
  CHECK(setup_case(good, sizeof good - 1u, (uint32_t)EIO, CLOCK_ERROR) == 0);
  memset(maximum, 'x', sizeof maximum);
  CHECK(setup_case(maximum, BIRC_SECRET_CAP, 0u, NORMAL) == 0);
  CHECK(setup_case(maximum, sizeof maximum, (uint32_t)EOVERFLOW, NORMAL) == 0);
  CHECK(setup_case(good, 0u, (uint32_t)EILSEQ, NORMAL) == 0);
  CHECK(setup_case(nul, sizeof nul, (uint32_t)EILSEQ, NORMAL) == 0);
  CHECK(setup_case((const unsigned char *)"a\nb", 3u, (uint32_t)EILSEQ, NORMAL) == 0);
  CHECK(setup_case((const unsigned char *)"a\rb", 3u, (uint32_t)EILSEQ, NORMAL) == 0);
  for (size_t i = 0; i < sizeof lengths / sizeof lengths[0]; ++i)
    CHECK(setup_case(bad[i], lengths[i], (uint32_t)EILSEQ, NORMAL) == 0);
  for (size_t i = 0; i < BIRC_SECRET_CAP; i += 2u) { maximum[i] = 0xc3u; maximum[i + 1u] = 0xa9u; }
  CHECK(setup_case(maximum, BIRC_SECRET_CAP, 0u, NORMAL) == 0);
  return 0;
}
static int no_eof(void) {
  Pipes p;
  char bytes[BIRC_SECRET_CAP + 1u];
  size_t size = 0u;
  CHECK(pipes(&p) == 0 && write(p.input[1], "valid", 5u) == 5);
  CHECK(birc_auth_setup(bytes, &size) == (uint32_t)ETIMEDOUT && size == 0u);
  CHECK(closed(p.input[0]) && closed(p.event[1]));
  CHECK(close(p.input[1]) == 0 && frame(p.event[0], "") == 0);
  CHECK(getenv(BIRC_SECRET_FD) == NULL && getenv(BIRC_EVENT_FD) == NULL);
  return 0;
}
static int descriptors(void) {
  static const char *invalid[] = {"", "-1", "+3", "3x", " 3", "2147483648", "9999999999999999", "0", "1", "2"};
  char bytes[BIRC_SECRET_CAP + 1u];
  size_t size = 999u;
  Pipes p;
  CHECK(clear_env() == 0 && birc_auth_setup(bytes, &size) == 0u && size == 0u);
  CHECK(birc_auth_notify() == 0u && birc_auth_fd(NULL) == -1);
  CHECK(birc_auth_fd("3") == 3 && birc_auth_fd("0003") == 3 && birc_auth_fd("2147483647") == INT_MAX);
  for (size_t i = 0; i < sizeof invalid / sizeof invalid[0]; ++i) {
    CHECK(birc_auth_fd(invalid[i]) == -1 && pipes(&p) == 0);
    CHECK(setenv(BIRC_SECRET_FD, invalid[i], 1) == 0);
    CHECK(birc_auth_setup(bytes, &size) == (uint32_t)EINVAL && size == 0u);
    CHECK(!closed(p.input[0]) && closed(p.event[1]));
    CHECK(close(p.input[0]) == 0 && close(p.input[1]) == 0 && frame(p.event[0], "") == 0);
  }
  CHECK(pipes(&p) == 0 && unsetenv(BIRC_SECRET_FD) == 0);
  CHECK(birc_auth_setup(bytes, &size) == (uint32_t)EINVAL && !closed(p.input[0]));
  CHECK(close(p.input[0]) == 0 && close(p.input[1]) == 0 && frame(p.event[0], "") == 0);
  CHECK(pipes(&p) == 0 && unsetenv(BIRC_EVENT_FD) == 0);
  CHECK(birc_auth_setup(bytes, &size) == (uint32_t)EINVAL && closed(p.input[0]));
  CHECK(close(p.input[1]) == 0 && close(p.event[1]) == 0 && frame(p.event[0], "") == 0);
  CHECK(pipes(&p) == 0 && set_fd(BIRC_EVENT_FD, p.input[0]) == 0);
  CHECK(birc_auth_setup(bytes, &size) == (uint32_t)EINVAL && closed(p.input[0]));
  CHECK(close(p.input[1]) == 0 && close(p.event[1]) == 0 && frame(p.event[0], "") == 0);
  CHECK(pipes(&p) == 0 && set_fd(BIRC_SECRET_FD, p.input[1]) == 0);
  CHECK(birc_auth_setup(bytes, &size) == (uint32_t)EINVAL && !closed(p.input[1]));
  CHECK(close(p.input[0]) == 0 && close(p.input[1]) == 0 && frame(p.event[0], "") == 0);
  CHECK(pipes(&p) == 0);
  fault = FOREIGN_OWNER;
  CHECK(birc_auth_setup(bytes, &size) == (uint32_t)EINVAL);
  fault = NORMAL;
  CHECK(!closed(p.input[0]) && !closed(p.event[1]));
  CHECK(close(p.input[0]) == 0 && close(p.input[1]) == 0 && close(p.event[1]) == 0 && frame(p.event[0], "") == 0);
  return 0;
}
static int nonpipes(void) {
  char path[] = "/tmp/birc-auth-bridge-XXXXXX", bytes[BIRC_SECRET_CAP + 1u];
  size_t size = 0u;
  int file = mkstemp(path), socket[2];
  Pipes p;
  CHECK(file >= 0 && unlink(path) == 0 && socketpair(AF_UNIX, SOCK_STREAM, 0, socket) == 0);
  for (size_t i = 0; i < 2u; ++i) {
    int other = i == 0u ? file : socket[0];
    CHECK(pipes(&p) == 0 && set_fd(BIRC_SECRET_FD, other) == 0);
    CHECK(birc_auth_setup(bytes, &size) == (uint32_t)EINVAL && !closed(other));
    CHECK(close(p.input[0]) == 0 && close(p.input[1]) == 0 && frame(p.event[0], "") == 0);
    CHECK(pipes(&p) == 0 && set_fd(BIRC_EVENT_FD, other) == 0);
    CHECK(birc_auth_setup(bytes, &size) == (uint32_t)EINVAL && !closed(other));
    CHECK(close(p.input[1]) == 0 && close(p.event[1]) == 0 && frame(p.event[0], "") == 0);
    CHECK(set_fd(BIRC_EVENT_FD, other) == 0);
    CHECK(birc_auth_notify() == (uint32_t)EINVAL && !closed(other) && getenv(BIRC_EVENT_FD) == NULL);
  }
  CHECK(close(file) == 0 && close(socket[0]) == 0 && close(socket[1]) == 0);
  return 0;
}
static int notify_failures(void) {
  static const int failures[] = {WRITE_PARTIAL, WRITE_EINTR, CLOSE_ERROR};
  static const uint32_t codes[] = {(uint32_t)EIO, (uint32_t)EINTR, (uint32_t)EIO};
  static const char *frames[] = {"BIRC", "", "BIRC_AUTH_OK\n"};
  Pipes p;
  char bytes[BIRC_SECRET_CAP + 1u], fill[1024];
  size_t size = 0u;
  for (size_t i = 0; i < sizeof failures / sizeof failures[0]; ++i) {
    CHECK(pipes(&p) == 0 && write(p.input[1], "x", 1u) == 1 && close(p.input[1]) == 0);
    CHECK(birc_auth_setup(bytes, &size) == 0u);
    fault = failures[i];
    CHECK(birc_auth_notify() == codes[i] && writes == 1 && closed(p.event[1]));
    CHECK(birc_auth_notify() == 0u && writes == 1 && getenv(BIRC_EVENT_FD) == NULL);
    fault = NORMAL;
    CHECK(frame(p.event[0], frames[i]) == 0);
  }
  CHECK(pipes(&p) == 0 && write(p.input[1], "x", 1u) == 1 && close(p.input[1]) == 0);
  CHECK(birc_auth_setup(bytes, &size) == 0u && close(p.event[0]) == 0);
  CHECK(birc_auth_notify() == (uint32_t)EPIPE && closed(p.event[1]));
  CHECK(pipes(&p) == 0 && write(p.input[1], "x", 1u) == 1 && close(p.input[1]) == 0);
  CHECK(birc_auth_setup(bytes, &size) == 0u);
  memset(fill, 'f', sizeof fill);
  for (;;) {
    ssize_t got = write(p.event[1], fill, sizeof fill);
    if (got < 0) { CHECK(errno == EAGAIN || errno == EWOULDBLOCK); break; }
    CHECK(got > 0);
  }
  CHECK(birc_auth_notify() == (uint32_t)EAGAIN && closed(p.event[1]));
  for (;;) {
    ssize_t got = read(p.event[0], fill, sizeof fill);
    CHECK(got >= 0);
    if (got == 0) break;
    for (ssize_t i = 0; i < got; ++i) CHECK(fill[i] == 'f');
  }
  CHECK(close(p.event[0]) == 0);
  CHECK(setenv(BIRC_EVENT_FD, "nonsense", 1) == 0);
  CHECK(birc_auth_notify() == (uint32_t)EINVAL && getenv(BIRC_EVENT_FD) == NULL);
  CHECK(setenv(BIRC_EVENT_FD, "1", 1) == 0);
  CHECK(birc_auth_notify() == (uint32_t)EINVAL && !closed(STDOUT_FILENO) && getenv(BIRC_EVENT_FD) == NULL);
  return 0;
}
static int exec_check(char *program) {
  Pipes p;
  char bytes[BIRC_SECRET_CAP + 1u], text[32];
  size_t size = 0u;
  int status;
  CHECK(program != NULL && pipes(&p) == 0 && write(p.input[1], "x", 1u) == 1 && close(p.input[1]) == 0);
  CHECK(birc_auth_setup(bytes, &size) == 0u);
  CHECK(snprintf(text, sizeof text, "%d", p.event[1]) > 0);
  pid_t pid = fork();
  CHECK(pid >= 0);
  if (pid == 0) {
    char *const args[] = {program, "--closed", text, NULL};
    execv(program, args);
    _Exit(77);
  }
  CHECK(waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0);
  CHECK(birc_auth_notify() == 0u && frame(p.event[0], "BIRC_AUTH_OK\n") == 0);
  return 0;
}
static int nulls(void) {
  char bytes[BIRC_SECRET_CAP + 1u];
  size_t size = 5u;
  CHECK(clear_env() == 0);
  CHECK(birc_auth_setup(bytes, NULL) == (uint32_t)EINVAL);
  CHECK(birc_auth_setup(NULL, &size) == (uint32_t)EINVAL && size == 0u);
  CHECK(!birc_auth_utf8(NULL, 1u) && !birc_auth_utf8(NULL, 0u));
  return 0;
}
int main(int argc, char **argv) {
  CHECK(signal(SIGPIPE, SIG_IGN) != SIG_ERR);
  if (argc == 3 && argv != NULL && argv[1] != NULL && argv[2] != NULL && strcmp(argv[1], "--closed") == 0)
    return closed(birc_auth_fd(argv[2])) ? 0 : 1;
  CHECK(clear_env() == 0);
  if (argc == 2 && argv != NULL && argv[1] != NULL && strcmp(argv[1], "--null") == 0) return nulls();
  CHECK(secrets() == 0 && no_eof() == 0 && descriptors() == 0 && nonpipes() == 0);
  CHECK(notify_failures() == 0 && exec_check(argv[0]) == 0 && nulls() == 0);
  puts("auth_bridge=ok");
  return 0;
}
