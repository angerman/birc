/* UTF-8 code-point boundary clip. Shared by timui_ffi.c and tests. */
#ifndef BIRC_UTF8_FIT_H
#define BIRC_UTF8_FIT_H

#include <stddef.h>

static size_t birc_utf8_fit(const char *s, size_t n) {
  if (!s)
    return 0;
  while (n > 0 && (((unsigned char)s[n] & 0xC0u) == 0x80u))
    n -= 1;
  return n;
}

#endif /* BIRC_UTF8_FIT_H */
