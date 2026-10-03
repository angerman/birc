/* Local seconds-of-day as U32. Bend formats with Clock.fmt_hms. */
#ifndef BIRC_CLOCK_FFI_C
#define BIRC_CLOCK_FFI_C
#include <errno.h>
#include <stdint.h>
#include <time.h>
#ifndef CID_LOCAL_SECS
#define CID_LOCAL_SECS CID(local_secs)
#endif
#ifndef CID_MILLIS
#define CID_MILLIS CID(millis)
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
#endif /* BIRC_CLOCK_FFI_C */
