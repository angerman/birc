/* SPDX-License-Identifier: Apache-2.0
 * A launch-owned secret pipe and a one-shot authentication event pipe.
 * Environment values hold descriptor numbers only, never credentials.
 * Setup runs before actors start; notify runs on the single UI actor.
 * Bend's runtime ignores SIGPIPE. The native guard does the same. */
#ifndef BIRC_AUTH_BRIDGE_FFI_C
#define BIRC_AUTH_BRIDGE_FFI_C
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define BIRC_SECRET_FD "BIRC_AUTH_SECRET_FD"
#define BIRC_EVENT_FD "BIRC_AUTH_EVENT_FD"
#define BIRC_SECRET_CAP 1024u

static int birc_auth_fd(const char *value) {
  unsigned int number = 0;
  if (!value || !*value) return -1;
  for (; *value; ++value) {
    unsigned int digit = (unsigned int)(unsigned char)*value - (unsigned int)'0';
    if (digit > 9u || number > ((unsigned int)INT_MAX - digit) / 10u) return -1;
    number = number * 10u + digit;
  }
  return number > 2u ? (int)number : -1;
}

static int birc_auth_pipe(int fd, int mode) {
  struct stat info;
  int flags = fcntl(fd, F_GETFL);
  if (fd < 0 || flags < 0 || fstat(fd, &info) != 0) return 0;
  return S_ISFIFO(info.st_mode) && info.st_uid == geteuid()
      && (flags & O_ACCMODE) == mode;
}

static int birc_auth_utf8(const unsigned char *bytes, size_t size) {
  size_t at = 0;
  if (!bytes) return 0;
  while (at < size) {
    unsigned int lead = bytes[at++], count, low = 0x80u, high = 0xbfu;
    if (lead < 0x80u) {
      if (lead == 0u || lead == 10u || lead == 13u) return 0;
      continue;
    }
    if (lead >= 0xc2u && lead <= 0xdfu) count = 1u;
    else if (lead >= 0xe0u && lead <= 0xefu) {
      count = 2u;
      if (lead == 0xe0u) low = 0xa0u;
      if (lead == 0xedu) high = 0x9fu;
    } else if (lead >= 0xf0u && lead <= 0xf4u) {
      count = 3u;
      if (lead == 0xf0u) low = 0x90u;
      if (lead == 0xf4u) high = 0x8fu;
    } else return 0;
    if (size - at < count || bytes[at] < low || bytes[at] > high) return 0;
    ++at;
    while (--count > 0u) {
      if (bytes[at] < 0x80u || bytes[at] > 0xbfu) return 0;
      ++at;
    }
  }
  return size > 0u;
}

static int64_t birc_auth_ms(void) {
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return -1;
  return (int64_t)now.tv_sec * 1000 + (int64_t)now.tv_nsec / 1000000;
}

static uint32_t birc_auth_setup(char *bytes, size_t *size) {
  const char *secret = getenv(BIRC_SECRET_FD), *event = getenv(BIRC_EVENT_FD);
  int input = birc_auth_fd(secret), output = birc_auth_fd(event);
  uint32_t code = 0;
  if (!size) return (uint32_t)EINVAL;
  *size = 0u;
  if (!bytes) return (uint32_t)EINVAL;
  if (!secret && !event) return 0u;
  if (input == output || !birc_auth_pipe(input, O_RDONLY)
      || !birc_auth_pipe(output, O_WRONLY)) code = (uint32_t)EINVAL;
  else if (fcntl(input, F_SETFD, FD_CLOEXEC) != 0
      || fcntl(output, F_SETFD, FD_CLOEXEC) != 0
      || fcntl(input, F_SETFL, fcntl(input, F_GETFL) | O_NONBLOCK) != 0
      || fcntl(output, F_SETFL, fcntl(output, F_GETFL) | O_NONBLOCK) != 0)
    code = (uint32_t)errno;
  else {
    int64_t start = birc_auth_ms();
    if (start < 0) code = (uint32_t)EIO;
    while (code == 0u) {
      ssize_t got = read(input, bytes + *size, BIRC_SECRET_CAP + 1u - *size);
      if (got > 0) {
        *size += (size_t)got;
        if (*size > BIRC_SECRET_CAP) code = (uint32_t)EOVERFLOW;
        continue;
      }
      if (got == 0) {
        if (!birc_auth_utf8((const unsigned char *)bytes, *size)) code = (uint32_t)EILSEQ;
        break;
      }
      if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
        code = (uint32_t)errno;
        break;
      }
      int64_t now = birc_auth_ms(), remaining = 1000 - (now - start);
      if (now < 0 || remaining <= 0) { code = (uint32_t)ETIMEDOUT; break; }
      struct pollfd wait = {input, POLLIN, 0};
      if (poll(&wait, 1u, (int)remaining) < 0 && errno != EINTR) {
        code = (uint32_t)errno;
        break;
      }
    }
  }
  /* Only close validated owned pipes; malformed environment must not close
   * an unrelated process descriptor. */
  if (birc_auth_pipe(input, O_RDONLY)) (void)close(input);
  (void)unsetenv(BIRC_SECRET_FD);
  if (code != 0u) {
    if (output != input && birc_auth_pipe(output, O_WRONLY)) (void)close(output);
    (void)unsetenv(BIRC_EVENT_FD);
    *size = 0u;
  }
  return code;
}

static uint32_t birc_auth_notify(void) {
  const char *event = getenv(BIRC_EVENT_FD);
  int output = birc_auth_fd(event);
  static const char frame[] = "BIRC_AUTH_OK\n";
  if (!event) return 0u;
  (void)unsetenv(BIRC_EVENT_FD);
  if (output < 0) return (uint32_t)EINVAL;
  if (!birc_auth_pipe(output, O_WRONLY)) return (uint32_t)EINVAL;
  /* Below PIPE_BUF, nonblocking, one write. Failure never means success. */
  ssize_t written = write(output, frame, sizeof frame - 1u);
  uint32_t code = written == (ssize_t)(sizeof frame - 1u) ? 0u
      : (uint32_t)(written < 0 ? errno : EIO);
  if (close(output) != 0 && code == 0u) code = (uint32_t)errno;
  return code;
}

#ifndef BIRC_AUTH_BRIDGE_CORE_ONLY
#ifndef CID_SETUP
#define CID_SETUP CID(setup)
#endif
#ifndef CID_NOTIFY
#define CID_NOTIFY CID(notify)
#endif
#if CID_SETUP
Term setup_run(Env e, Term *f, IoWork *w) {
  char bytes[BIRC_SECRET_CAP + 1u];
  size_t size = 0u;
  (void)f; (void)w;
  uint32_t code = birc_auth_setup(bytes, &size);
  Term value = io_str(e, bytes, (u64)size);
  volatile unsigned char *wipe = (volatile unsigned char *)bytes;
  for (size_t i = 0; i < sizeof bytes; ++i) wipe[i] = 0u;
  return io_tup(e, (Term)code, value);
}
static void __attribute__((constructor)) setup_use(void) {
  io_eff(CID_SETUP, setup_run, 0);
}
#endif
#if CID_NOTIFY
Term notify_run(Env e, Term *f, IoWork *w) {
  (void)e; (void)f; (void)w;
  return (Term)birc_auth_notify();
}
static void __attribute__((constructor)) notify_use(void) {
  io_eff(CID_NOTIFY, notify_run, 0);
}
#endif
#endif
#endif
