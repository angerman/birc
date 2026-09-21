/* Wall-clock HH:MM:SS for Line.ts. C formats; Bend stores it at buf_log_ts. */
#ifndef BIRC_CLOCK_FFI_C
#define BIRC_CLOCK_FFI_C

#include <string.h>
#include <time.h>

#ifdef CID_HHMMSS
Term hhmmss_run(Env e, Term *f, IoWork *w) {
  time_t t = time(NULL);
  struct tm lt;
  struct tm *got;
  char buf[9];
  (void)f;
  (void)w;
  buf[0] = '\0';
#if defined(_POSIX_THREAD_SAFE_FUNCTIONS) || defined(_POSIX_C_SOURCE)
  got = localtime_r(&t, &lt);
#else
  got = localtime(&t);
  if (got) {
    lt = *got;
    got = &lt;
  }
#endif
  if (got)
    strftime(buf, sizeof buf, "%H:%M:%S", got);
  return io_str(e, buf, strlen(buf));
}

static void __attribute__((constructor)) hhmmss_use(void) {
  io_eff(CID_HHMMSS, hhmmss_run, 0);
}
#endif

#endif /* BIRC_CLOCK_FFI_C */
