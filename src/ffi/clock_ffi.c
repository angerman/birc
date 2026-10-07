/* Local seconds-of-day as U32. Bend formats with Clock.fmt_hms. */
#ifndef BIRC_CLOCK_FFI_C
#define BIRC_CLOCK_FFI_C
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#ifndef CID_LOCAL_SECS
#define CID_LOCAL_SECS CID(local_secs)
#endif
#ifndef CID_MILLIS
#define CID_MILLIS CID(millis)
#endif
#ifndef CID_NET_TRACE
#define CID_NET_TRACE CID(net_trace)
#endif
#ifndef CID_UTC_LOCAL_PARTS
#define CID_UTC_LOCAL_PARTS CID(utc_local_parts)
#endif

#if CID_UTC_LOCAL_PARTS
struct birc_clock_parts {
  uint32_t hour, minute, second;
};

static uint32_t birc_month_days(uint32_t year, uint32_t month) {
  static const uint32_t days[12] = {31u, 28u, 31u, 30u, 31u, 30u,
                                   31u, 31u, 30u, 31u, 30u, 31u};
  uint32_t leap = year % 4u == 0u && (year % 100u != 0u || year % 400u == 0u);
  return days[month - 1u] + (month == 2u ? leap : 0u);
}

/* timegm/localtime_r use the event's date for DST and calendar rollover.
 * Convert a leap second at :59, then retain its extra second for display. */
static struct birc_clock_parts birc_utc_local_parts(
    uint32_t year, uint32_t month, uint32_t day, uint32_t hour,
    uint32_t minute, uint32_t second) {
  struct birc_clock_parts result = {24u, 0u, 0u};
  struct tm utc = {0}, local;
  time_t epoch;
  if (year < 1u || year > 9999u || month < 1u || month > 12u
      || day < 1u || day > 31u || hour >= 24u || minute >= 60u
      || second > 60u)
    return result;
  if (day > birc_month_days(year, month)
      || (second == 60u && (hour != 23u || minute != 59u
                           || day != birc_month_days(year, month))))
    return result;
  utc.tm_year = (int)year - 1900;
  utc.tm_mon = (int)month - 1;
  utc.tm_mday = (int)day;
  utc.tm_hour = (int)hour;
  utc.tm_min = (int)minute;
  utc.tm_sec = (int)(second == 60u ? 59u : second);
  errno = 0;
  epoch = timegm(&utc);
  if ((epoch == (time_t)-1 && errno != 0)
      || utc.tm_year != (int)year - 1900 || utc.tm_mon != (int)month - 1
      || utc.tm_mday != (int)day || utc.tm_hour != (int)hour
      || utc.tm_min != (int)minute
      || utc.tm_sec != (int)(second == 60u ? 59u : second)
      || !localtime_r(&epoch, &local)
      || local.tm_hour < 0 || local.tm_hour >= 24
      || local.tm_min < 0 || local.tm_min >= 60
      || local.tm_sec < 0 || local.tm_sec >= 60)
    return result;
  result.hour = (uint32_t)local.tm_hour;
  result.minute = (uint32_t)local.tm_min;
  result.second = (uint32_t)local.tm_sec + (second == 60u ? 1u : 0u);
  return result;
}

Term utc_local_parts_run(Env e, Term *f, IoWork *w) {
  struct birc_clock_parts local = birc_utc_local_parts(
      (uint32_t)f[0], (uint32_t)f[1], (uint32_t)f[2],
      (uint32_t)f[3], (uint32_t)f[4], (uint32_t)f[5]);
  (void)w;
  return io_tup(e, (Term)local.hour,
                io_tup(e, (Term)local.minute, (Term)local.second));
}
static void __attribute__((constructor)) utc_local_parts_use(void) {
  io_eff(CID_UTC_LOCAL_PARTS, utc_local_parts_run, 0);
}
#endif

#if CID_LOCAL_SECS
Term local_secs_run(Env e, Term *f, IoWork *w) {
  time_t t = time(NULL);
  struct tm lt;
  (void)e;
  (void)f;
  (void)w;
  if (!localtime_r(&t, &lt))
    return (Term)0;
  return (Term)((uint32_t)lt.tm_hour * 3600u + (uint32_t)lt.tm_min * 60u
                + (uint32_t)lt.tm_sec);
}
static void __attribute__((constructor)) local_secs_use(void) {
  io_eff(CID_LOCAL_SECS, local_secs_run, 0);
}
#endif
#if CID_MILLIS
Term millis_run(Env e, Term *f, IoWork *w) {
  struct timespec ts;
  (void)e;
  (void)f;
  (void)w;
  if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
    return (Term)0;
  uint64_t sec = ts.tv_sec > 0 ? (uint64_t)ts.tv_sec : 0ULL;
  uint64_t nsec = ts.tv_nsec > 0 ? (uint64_t)ts.tv_nsec : 0ULL;
  uint32_t ms = (uint32_t)((sec * 1000ULL + nsec / 1000000ULL) & 0xFFFFFFFFULL);
  return (Term)ms;
}
static void __attribute__((constructor)) millis_use(void) {
  io_eff(CID_MILLIS, millis_run, 0);
}
#endif
#if CID_NET_TRACE
/* Default-off numeric PONG-path trace. One bounded stderr line per mark:
 * sequence, stage, batch txn, monotonic milliseconds, and a small counter.
 * Never chat or wire bytes. PONG stages 6/1/2/4/5 share the read's
 * carried high-space request ID so every hop matches by ID, never by
 * order; Cont 4/5 carry the low batch txn so FIFO sends match their
 * receive by ID; txn 0 is unidentified (non-PING chunks, stage 3, bare
 * sends). Each mark is bounded and
 * never blocks:
 * stderr is borrowed
 * O_NONBLOCK for the attempt (flags restored before return), poll(0) gates
 * every write, short writes and EINTR retry finitely (4 polls, 4 writes),
 * and EAGAIN or any other error drops the mark without advancing the
 * sequence. Drop accounting: drops are silent (seq stays contiguous, so a
 * stalled reader loses marks instead of parking the app); harnesses must
 * not assume every event produced a mark. A blocking write after poll(0)
 * alone is not bounded (TOCTOU: the pipe can fill between poll and write),
 * so O_NONBLOCK is required, not advisory. Regular-file sinks are refused
 * with no write attempt and no sequence advance: O_NONBLOCK is a silent
 * no-op on regular files whose writes can still block (NFS, slow disk,
 * quota); pipes/sockets keep borrow+restore. A failed fstat also refuses.
 * Measurement harnesses must keep stderr separate from the terminal. The
 * pinned runtime serializes normal effects and no trace-global race is
 * verified, so this stays lock-free by design. */
static int birc_net_trace_state = -1;
static unsigned long long birc_net_trace_seq = 0ULL;

#define BIRC_NET_TRACE_POLLS 4
#define BIRC_NET_TRACE_WRITES 4

static int birc_net_trace_writable(void) {
  int attempt;
  for (attempt = 0; attempt < BIRC_NET_TRACE_POLLS; attempt++) {
    struct pollfd pfd;
    int ready;
    pfd.fd = STDERR_FILENO;
    pfd.events = POLLOUT;
    pfd.revents = 0;
    ready = poll(&pfd, 1, 0);
    if (ready < 0) {
      if (errno == EINTR)
        continue;
      return 0;
    }
    if (ready == 0)
      return 0;
    if (pfd.revents & (POLLERR | POLLNVAL))
      return 0;
    return (pfd.revents & POLLOUT) != 0;
  }
  return 0;
}

static void birc_net_trace_mark(uint32_t stage, uint32_t txn, uint32_t count) {
  struct timespec ts;
  uint64_t sec;
  uint64_t nsec;
  uint64_t ms;
  char line[128];
  int len;
  size_t off;
  int attempt;
  int saved_flags;
  int need_restore;
  if (birc_net_trace_state < 0)
    birc_net_trace_state = getenv("BIRC_NET_TRACE") != NULL ? 1 : 0;
  if (!birc_net_trace_state)
    return;
  if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
    return;
  sec = ts.tv_sec > 0 ? (uint64_t)ts.tv_sec : 0ULL;
  nsec = ts.tv_nsec > 0 ? (uint64_t)ts.tv_nsec : 0ULL;
  ms = sec * 1000ULL + nsec / 1000000ULL;
  len = snprintf(line, sizeof line, "birc_net_trace seq=%llu stage=%u txn=%u ms=%llu count=%u\n",
      birc_net_trace_seq, stage, txn, (unsigned long long)ms, count);
  if (len <= 0 || (size_t)len >= sizeof line)
    return;
  /* Regular files ignore O_NONBLOCK (silent no-op) and their writes can
   * still block. Refuse them with no write attempt and no sequence advance;
   * pipes/sockets (and other non-regular sinks) keep borrow+restore below.
   * A failed fstat also refuses (fail closed). */
  {
    struct stat sink_st;
    if (fstat(STDERR_FILENO, &sink_st) != 0)
      return;
    if (S_ISREG(sink_st.st_mode))
      return;
  }
  /* Borrow O_NONBLOCK so the write below can never park the live path.
   * A poll(0)-then-blocking-write alone still blocks when the pipe holds
   * fewer free bytes than the line (TOCTOU). Flags are restored on every
   * exit, including drops. */
  saved_flags = fcntl(STDERR_FILENO, F_GETFL);
  if (saved_flags < 0)
    return;
  need_restore = 0;
  if ((saved_flags & O_NONBLOCK) == 0) {
    if (fcntl(STDERR_FILENO, F_SETFL, saved_flags | O_NONBLOCK) != 0)
      return;
    need_restore = 1;
  }
  off = 0;
  for (attempt = 0; attempt < BIRC_NET_TRACE_WRITES && off < (size_t)len; attempt++) {
    ssize_t done;
    if (!birc_net_trace_writable())
      goto drop;
    done = write(STDERR_FILENO, line + off, (size_t)len - off);
    if (done > 0) {
      off += (size_t)done;
      continue;
    }
    if (done < 0 && errno == EINTR)
      continue;
    /* EAGAIN/EWOULDBLOCK (full pipe under O_NONBLOCK) and any other error
     * drop the mark; the sequence does not advance. */
    goto drop;
  }
  if (off < (size_t)len)
    goto drop;
  birc_net_trace_seq += 1ULL;
drop:
  if (need_restore)
    (void)fcntl(STDERR_FILENO, F_SETFL, saved_flags);
}

Term net_trace_run(Env e, Term *f, IoWork *w) {
  (void)e;
  (void)w;
  birc_net_trace_mark((uint32_t)f[0], (uint32_t)f[1], (uint32_t)f[2]);
  return term_pak(CID_UNIT, 0);
}
static void __attribute__((constructor)) net_trace_use(void) {
  io_eff(CID_NET_TRACE, net_trace_run, 0);
}
#endif
#endif /* BIRC_CLOCK_FFI_C */
