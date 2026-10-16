/* Strict UTF-8 (RFC 3629). Rejects overlong encodings, UTF-16 surrogates
 * (U+D800..U+DFFF), truncated sequences, and lead bytes outside
 * 0x00..0x7F / 0xC2..0xF4. U+0000, CR, and LF are valid UTF-8; callers
 * that forbid them apply that policy themselves. Empty input is valid.
 * A null pointer is not. */
#ifndef BIRC_UTF8_VALID_H
#define BIRC_UTF8_VALID_H

#include <stddef.h>

static int birc_utf8_valid(const unsigned char *bytes, size_t size) {
  size_t at = 0;
  if (!bytes)
    return 0;
  while (at < size) {
    unsigned int lead = bytes[at++];
    unsigned int count;
    unsigned int low = 0x80u;
    unsigned int high = 0xbfu;
    if (lead < 0x80u)
      continue;
    if (lead >= 0xc2u && lead <= 0xdfu)
      count = 1u;
    else if (lead >= 0xe0u && lead <= 0xefu) {
      count = 2u;
      if (lead == 0xe0u)
        low = 0xa0u;
      if (lead == 0xedu)
        high = 0x9fu;
    } else if (lead >= 0xf0u && lead <= 0xf4u) {
      count = 3u;
      if (lead == 0xf0u)
        low = 0x90u;
      if (lead == 0xf4u)
        high = 0x8fu;
    } else
      return 0;
    if (size - at < count || bytes[at] < low || bytes[at] > high)
      return 0;
    ++at;
    while (--count > 0u) {
      if (bytes[at] < 0x80u || bytes[at] > 0xbfu)
        return 0;
      ++at;
    }
  }
  return 1;
}

#endif /* BIRC_UTF8_VALID_H */
