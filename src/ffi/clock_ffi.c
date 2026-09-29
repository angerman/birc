/* Local seconds-of-day as U32. Bend formats with Clock.fmt_hms. */
#ifndef BIRC_CLOCK_FFI_C
#define BIRC_CLOCK_FFI_C
#include <stdint.h>
#include <time.h>
#ifndef CID_LOCAL_SECS
#define CID_LOCAL_SECS CID(local_secs)
#endif
#ifndef CID_MILLIS
#define CID_MILLIS CID(millis)
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
#endif /* BIRC_CLOCK_FFI_C */
