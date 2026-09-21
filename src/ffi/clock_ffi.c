/* Local seconds-of-day as U32. Bend formats with Clock.fmt_hms. */
#ifndef BIRC_CLOCK_FFI_C
#define BIRC_CLOCK_FFI_C

#include <stdint.h>
#include <time.h>

#ifdef CID_LOCAL_SECS
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

#endif /* BIRC_CLOCK_FFI_C */
