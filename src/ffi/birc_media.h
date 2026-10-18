/* UI-owned helper payloads. Validation does not decode images or write output.
 * A painted image owns copies, so eviction cannot alter an in-flight frame.
 *
 * Caps duplicated with media.bend (no single source of truth):
 *   BIRC_MEDIA_CAP 8 == media.bend CAP() for pending and for ready.
 *   BIRC_MEDIA_FRAME_CAP 24, BIRC_MEDIA_LIMIT (2 MiB), width/height <= 320,
 *   and pixels*count <= 1536000 have no Bend twin. Envelope framing and
 *   base64 stay here until a measured Bend decoder replaces them;
 *   image_png_header_ stays native either way.
 */
#ifndef BIRC_MEDIA_H
#define BIRC_MEDIA_H
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

enum { BIRC_MEDIA_CAP = 8, BIRC_MEDIA_FRAME_CAP = 24,
       BIRC_MEDIA_LIMIT = 2 * 1024 * 1024 };
typedef struct {
  const unsigned char *png;
  size_t png_len;
  uint32_t duration;
} BircMediaFrame;
typedef struct {
  unsigned char *bytes;
  size_t size;
  uint32_t token, width, height, count, iterations;
  const unsigned char *rgba, *gif;
  size_t rgba_len, gif_len;
  BircMediaFrame frames[BIRC_MEDIA_FRAME_CAP];
} BircMedia;
typedef struct {
  BircMedia slots[BIRC_MEDIA_CAP];
  uint32_t next_token;
  unsigned next_slot;
} BircMediaCache;

static uint32_t birc_media_u32(const unsigned char *p) {
  return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
         ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static int birc_media_parse(BircMedia *out, unsigned char *bytes, size_t size) {
  BircMedia media;
  size_t offset, i;
  uint64_t pixels;
  if (!out || !bytes || size < 32 || size > BIRC_MEDIA_LIMIT ||
      memcmp(bytes, "BIRCIMG1", 8) != 0)
    return 0;
  memset(&media, 0, sizeof media);
  media.width = birc_media_u32(bytes + 8);
  media.height = birc_media_u32(bytes + 12);
  media.count = birc_media_u32(bytes + 16);
  media.iterations = birc_media_u32(bytes + 20);
  media.rgba_len = birc_media_u32(bytes + 24);
  media.gif_len = birc_media_u32(bytes + 28);
  pixels = (uint64_t)media.width * media.height;
  if (!media.width || !media.height || media.width > 320 || media.height > 320 ||
      !media.count || media.count > BIRC_MEDIA_FRAME_CAP ||
      media.iterations > 65535 || pixels * media.count > 1536000 ||
      media.rgba_len != pixels * 4 || media.rgba_len > size - 32)
    return 0;
  media.rgba = bytes + 32;
  offset = 32 + media.rgba_len;
  if (media.gif_len > size - offset)
    return 0;
  media.gif = bytes + offset;
  if (media.count == 1) {
    if (media.gif_len != 0)
      return 0;
  } else if (media.gif_len < 14 ||
             (memcmp(media.gif, "GIF87a", 6) != 0 &&
              memcmp(media.gif, "GIF89a", 6) != 0) ||
             ((uint32_t)media.gif[6] | ((uint32_t)media.gif[7] << 8)) != media.width ||
             ((uint32_t)media.gif[8] | ((uint32_t)media.gif[9] << 8)) != media.height ||
             media.gif[media.gif_len - 1] != 0x3b) {
    return 0;
  }
  offset += media.gif_len;
  for (i = 0; i < media.count; i++) {
    BircMediaFrame *frame = &media.frames[i];
    int width, height;
    if (size - offset < 8)
      return 0;
    frame->duration = birc_media_u32(bytes + offset);
    frame->png_len = birc_media_u32(bytes + offset + 4);
    offset += 8;
    if (frame->duration < 20 || frame->duration > 10000 ||
        frame->png_len < 33 || frame->png_len > size - offset)
      return 0;
    frame->png = bytes + offset;
    if (birc_media_u32(frame->png + 8) != 13 ||
        !image_png_header_(frame->png, frame->png_len, &width, &height) ||
        (uint32_t)width != media.width || (uint32_t)height != media.height)
      return 0;
    offset += frame->png_len;
  }
  if (offset != size)
    return 0;
  media.bytes = bytes;
  media.size = size;
  *out = media;
  return 1;
}

static int birc_media_b64_digit(unsigned char c) {
  if (c >= 'A' && c <= 'Z') return c - 'A';
  if (c >= 'a' && c <= 'z') return c - 'a' + 26;
  if (c >= '0' && c <= '9') return c - '0' + 52;
  if (c == '+') return 62;
  if (c == '/') return 63;
  return -1;
}

static uint32_t birc_media_add(BircMediaCache *cache, const char *text, size_t length) {
  unsigned char *bytes;
  size_t size, offset = 0, i;
  BircMedia media;
  if (!cache || !text || cache->next_token == UINT32_MAX ||
      length > ((BIRC_MEDIA_LIMIT + 2u) / 3u) * 4u + 2u)
    return 0;
  /* Process.run retains the helper's final newline. No embedded whitespace or
   * alternate spelling is accepted; padding and its unused bits are checked. */
  if (length && text[length - 1] == '\n') {
    length--;
    if (length && text[length - 1] == '\r') length--;
  }
  if (!length || length % 4 || length > ((BIRC_MEDIA_LIMIT + 2u) / 3u) * 4u)
    return 0;
  size = length / 4 * 3;
  if (text[length - 1] == '=') size--;
  if (text[length - 2] == '=') size--;
  if (size > BIRC_MEDIA_LIMIT)
    return 0;
  bytes = (unsigned char *)malloc(size ? size : 1);
  if (!bytes)
    return 0;
  for (i = 0; i < length; i += 4) {
    int a = birc_media_b64_digit((unsigned char)text[i]);
    int b = birc_media_b64_digit((unsigned char)text[i + 1]);
    int c = text[i + 2] == '=' ? 0 : birc_media_b64_digit((unsigned char)text[i + 2]);
    int d = text[i + 3] == '=' ? 0 : birc_media_b64_digit((unsigned char)text[i + 3]);
    int pad = (text[i + 2] == '=') + (text[i + 3] == '=');
    if (a < 0 || b < 0 || c < 0 || d < 0 ||
        (pad && i + 4 != length) ||
        (text[i + 2] == '=' && text[i + 3] != '=') ||
        (pad == 2 && (b & 15)) || (pad == 1 && (c & 3)))
      goto invalid;
    bytes[offset++] = (unsigned char)((a << 2) | (b >> 4));
    if (pad < 2) bytes[offset++] = (unsigned char)((b << 4) | (c >> 2));
    if (!pad) bytes[offset++] = (unsigned char)((c << 6) | d);
  }
  if (offset != size || !birc_media_parse(&media, bytes, size))
    goto invalid;
  /* Reuse released payload slots only. Native FIFO must not evict a token
   * Bend still owns; with no empty slot, drop the newly parsed media. */
  for (i = 0; i < BIRC_MEDIA_CAP; i++) {
    unsigned slot = (cache->next_slot + (unsigned)i) % BIRC_MEDIA_CAP;
    if (!cache->slots[slot].token) { cache->next_slot = slot; break; }
  }
  if (cache->slots[cache->next_slot].token) {
    free(media.bytes);
    return 0;
  }
  media.token = ++cache->next_token;
  free(cache->slots[cache->next_slot].bytes);
  cache->slots[cache->next_slot] = media;
  cache->next_slot = (cache->next_slot + 1) % BIRC_MEDIA_CAP;
  return media.token;
invalid:
  free(bytes);
  return 0;
}

static const BircMedia *birc_media_find(const BircMediaCache *cache, uint32_t token) {
  unsigned i;
  if (!cache || !token) return NULL;
  for (i = 0; i < BIRC_MEDIA_CAP; i++)
    if (cache->slots[i].token == token) return &cache->slots[i];
  return NULL;
}

/* Payload ownership follows Bend's bounded ready list, not viewport visibility.
 * Copied terminal images remain owned until an accepted frame retires them. */
static inline void birc_media_retain(BircMediaCache *cache, const uint32_t *tokens,
                                     size_t count) {
  unsigned i;
  size_t j;
  if (!cache || count > BIRC_MEDIA_CAP || (count && !tokens)) return;
  for (i = 0; i < BIRC_MEDIA_CAP; i++) {
    for (j = 0; j < count; j++)
      if (cache->slots[i].token == tokens[j]) break;
    if (j == count) {
      free(cache->slots[i].bytes);
      memset(&cache->slots[i], 0, sizeof cache->slots[i]);
    }
  }
}

static void birc_media_clear(BircMediaCache *cache) {
  unsigned i;
  if (!cache) return;
  for (i = 0; i < BIRC_MEDIA_CAP; i++) {
    free(cache->slots[i].bytes);
    memset(&cache->slots[i], 0, sizeof cache->slots[i]);
  }
  cache->next_slot = 0;
}
#endif
