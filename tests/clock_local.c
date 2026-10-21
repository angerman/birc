/* SPDX-License-Identifier: Apache-2.0
 * Date-aware local conversion through libc, including leap-second display. */
#define _GNU_SOURCE
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "lint-ffi/ffi_stub.h"
#define CID_UTC_LOCAL_PARTS 99u
#include "../src/ffi/clock_ffi.c"

static Term tuple_a[4], tuple_b[4];
static unsigned tuples;
void io_eff(u32 cid, Effect run) { (void)cid; (void)run; }
Term io_tup(Env e, Term a, Term b) {
  (void)e;
  if (tuples >= 4u) abort();
  tuple_a[tuples] = a;
  tuple_b[tuples++] = b;
  return 100u;
}

static void must(int ok, const char *label) {
  if (!ok) { fprintf(stderr, "clock_local: %s\n", label); exit(1); }
}

/* Bend pastes FFI into a temp .c with no -I. Those files carry the header
 * text in a #else. Reject a drift between that copy and the header. */
static void header_copy(const char *path) {
  FILE *hf = fopen("src/ffi/birc_utf8_valid.h", "rb");
  FILE *cf = fopen(path, "rb");
  long hs, cs;
  char *h, *c;
  must(hf != NULL && cf != NULL, "open utf8 sources");
  must(fseek(hf, 0, SEEK_END) == 0 && fseek(cf, 0, SEEK_END) == 0, "seek utf8");
  hs = ftell(hf);
  cs = ftell(cf);
  must(hs > 0 && cs > hs, "utf8 sizes");
  must(fseek(hf, 0, SEEK_SET) == 0 && fseek(cf, 0, SEEK_SET) == 0, "rewind utf8");
  h = malloc((size_t)hs);
  c = malloc((size_t)cs);
  must(h != NULL && c != NULL, "alloc utf8");
  must(fread(h, 1, (size_t)hs, hf) == (size_t)hs, "read header");
  must(fread(c, 1, (size_t)cs, cf) == (size_t)cs, "read caller");
  must(memmem(c, (size_t)cs, h, (size_t)hs) != NULL, path);
  free(h);
  free(c);
  must(fclose(hf) == 0 && fclose(cf) == 0, "close utf8");
}

static void zone(const char *name) {
  must(setenv("TZ", name, 1) == 0, "set TZ");
  tzset();
}

static void converted(uint32_t y, uint32_t m, uint32_t d, uint32_t h,
                      uint32_t n, uint32_t s, uint32_t ymd, uint32_t wday,
                      uint32_t lh, uint32_t ln, uint32_t ls, const char *label) {
  struct birc_clock_parts result = birc_utc_local_parts(y, m, d, h, n, s);
  must(result.ymd == ymd && result.wday == wday
       && result.hour == lh && result.minute == ln && result.second == ls, label);
}

int main(void) {
  Env e = {0};
  header_copy("src/ffi/auth_bridge_ffi.c");
  header_copy("src/ffi/history_search_ffi.c");
  Term fields[6] = {2026u, 9u, 28u, 17u, 40u, 27u};
  zone("UTC0");
  converted(2026u, 9u, 28u, 17u, 40u, 27u, 20260928u, 1u, 17u, 40u, 27u, "UTC");
  converted(1969u, 12u, 31u, 23u, 59u, 59u, 19691231u, 3u, 23u, 59u, 59u, "valid epoch minus one");
  converted(2023u, 2u, 29u, 0u, 0u, 0u, 0u, 0u, 24u, 0u, 0u, "non-leap date rejects");
  converted(2024u, 2u, 29u, 0u, 0u, 0u, 20240229u, 4u, 0u, 0u, 0u, "leap date accepts");
  converted(2024u, 13u, 1u, 0u, 0u, 0u, 0u, 0u, 24u, 0u, 0u, "bad month rejects");
  converted(2024u, 1u, 1u, 24u, 0u, 0u, 0u, 0u, 24u, 0u, 0u, "bad hour rejects");
  converted(2024u, 1u, 1u, 0u, 0u, 61u, 0u, 0u, 24u, 0u, 0u, "bad second rejects");
  /* Leap-second placement is Utc.valid. libc sees :59 and the extra
   * second is display-only, so a non-policy :60 still converts here. */
  converted(2024u, 1u, 31u, 12u, 34u, 60u, 20240131u, 3u, 12u, 34u, 60u, "leap second is display-only");
  converted(2024u, 1u, 1u, 23u, 59u, 60u, 20240101u, 1u, 23u, 59u, 60u, "leap second date is not rechecked");
  zone("Asia/Seoul");
  converted(2026u, 9u, 28u, 17u, 40u, 27u, 20260929u, 2u, 2u, 40u, 27u, "Seoul next day");
  converted(2012u, 6u, 30u, 23u, 59u, 60u, 20120701u, 0u, 8u, 59u, 60u, "leap second retained");
  zone("EST5EDT,M3.2.0/2,M11.1.0/2");
  converted(2026u, 1u, 1u, 2u, 0u, 0u, 20251231u, 3u, 21u, 0u, 0u, "previous day winter");
  converted(2026u, 7u, 1u, 12u, 0u, 0u, 20260701u, 3u, 8u, 0u, 0u, "event-date summer DST");
  converted(2026u, 3u, 8u, 6u, 59u, 59u, 20260308u, 0u, 1u, 59u, 59u, "before DST boundary");
  converted(2026u, 3u, 8u, 7u, 0u, 0u, 20260308u, 0u, 3u, 0u, 0u, "after DST boundary");
  zone("UTC0");
  (void)utc_local_parts_run(e, fields, NULL);
  must(tuples == 4u && tuple_a[0] == 40u && tuple_b[0] == 27u
       && tuple_a[1] == 17u && tuple_b[1] == 100u
       && tuple_a[2] == 1u && tuple_b[2] == 100u
       && tuple_a[3] == 20260928u && tuple_b[3] == 100u, "FFI numeric tuple ABI");
  puts("clock_local=ok");
  return 0;
}
