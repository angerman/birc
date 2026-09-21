/* A7: tab-label cap must not split a UTF-8 code point.
 *
 * Keep birc_utf8_fit in sync with src/ffi/timui_ffi.c.
 * (-) fit then clamp to 63 lands on the lead byte of é (index 62).
 * (+) fit(s, min(len, 63)) backs up to 62.
 */
#include <stdio.h>
#include <string.h>

static size_t birc_utf8_fit(const char *s, size_t n) {
  if (!s)
    return 0;
  while (n > 0 && (((unsigned char)s[n] & 0xC0u) == 0x80u))
    n -= 1;
  return n;
}

static size_t cut_old(const char *s, size_t len) {
  size_t nlen = birc_utf8_fit(s, len);
  if (nlen >= 63)
    nlen = 63;
  return nlen;
}

static size_t cut_new(const char *s, size_t len) {
  return birc_utf8_fit(s, len < 63 ? len : 63);
}

int main(void) {
  unsigned char s[81];
  size_t i;
  size_t old;
  size_t neu;
  memset(s, 0, sizeof s);
  for (i = 0; i < 40; i++) {
    s[2 * i] = 0xC3u;
    s[2 * i + 1] = 0xA9u;
  }
  old = cut_old((char *)s, 80);
  neu = cut_new((char *)s, 80);
  if (old != 63 || s[62] != 0xC3u) {
    fprintf(stderr, "utf8_fit_cap: (-) fixture drifted old=%zu s[62]=0x%02x\n",
            old, s[62]);
    return 1;
  }
  if (neu != 62) {
    fprintf(stderr, "utf8_fit_cap: (+) want 62 got %zu\n", neu);
    return 1;
  }
  if ((s[neu] & 0xC0u) == 0x80u) {
    fprintf(stderr, "utf8_fit_cap: (+) cut inside a code point\n");
    return 1;
  }
  puts("utf8_fit_cap=ok");
  return 0;
}
