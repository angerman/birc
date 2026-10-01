/* The UI accepts helper output as bounded data, never as terminal commands. */
#define TIMUI_IMPLEMENTATION
#include "timui.h"
static int fail_malloc;
static void *media_malloc(size_t size) { return fail_malloc ? NULL : malloc(size); }
#define malloc media_malloc
#include "birc_media.h"
#undef malloc
#include <stdio.h>

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "media_cache:%d: %s\n", __LINE__, #x); return 1; } } while (0)

static void be32(unsigned char *p, uint32_t n) {
  p[0] = (unsigned char)(n >> 24); p[1] = (unsigned char)(n >> 16);
  p[2] = (unsigned char)(n >> 8); p[3] = (unsigned char)n;
}

static size_t payload(unsigned char *p, int animated) {
  static const unsigned char png[33] = {
    137,80,78,71,13,10,26,10,0,0,0,13,'I','H','D','R',
    0,0,0,1,0,0,0,1,8,6,0,0,0,0,0,0,0
  };
  static const unsigned char gif[14] = {'G','I','F','8','9','a',1,0,1,0,0,0,0,59};
  size_t off = 32; int i;
  memcpy(p, "BIRCIMG1", 8);
  be32(p + 8, 1); be32(p + 12, 1); be32(p + 16, animated ? 2u : 1u);
  be32(p + 20, 0); be32(p + 24, 4); be32(p + 28, animated ? sizeof gif : 0);
  memset(p + off, 255, 4); off += 4;
  if (animated) { memcpy(p + off, gif, sizeof gif); off += sizeof gif; }
  for (i = 0; i < (animated ? 2 : 1); i++) {
    be32(p + off, 100); be32(p + off + 4, sizeof png); off += 8;
    memcpy(p + off, png, sizeof png); off += sizeof png;
  }
  return off;
}

static uint32_t add(BircMediaCache *cache, const unsigned char *p, size_t n) {
  char encoded[512]; size_t length = b64_encode(p, n, encoded, sizeof encoded - 1);
  encoded[length++] = '\n';
  return birc_media_add(cache, encoded, length);
}

static int exact_limits(void) {
  BircMediaCache cache = {0}; BircMedia parsed;
  unsigned char *bytes = calloc(1, BIRC_MEDIA_LIMIT + 1u);
  char *encoded = malloc(((BIRC_MEDIA_LIMIT + 2u) / 3u) * 4u + 2u);
  size_t length, i, offset;
  CHECK(bytes && encoded);
  length = payload(bytes, 0);
  be32(bytes + 20, 65535); be32(bytes + 36, 10000);
  CHECK(birc_media_parse(&parsed, bytes, length));
  /* Exact encoded-data cap succeeds; one byte more fails before allocation. */
  be32(bytes + 40, BIRC_MEDIA_LIMIT - 44u);
  length = b64_encode(bytes, BIRC_MEDIA_LIMIT, encoded, ((BIRC_MEDIA_LIMIT + 2u) / 3u) * 4u);
  encoded[length++] = '\n';
  CHECK(birc_media_add(&cache, encoded, length) != 0);
  CHECK(!birc_media_parse(&parsed, bytes, BIRC_MEDIA_LIMIT + 1u));
  birc_media_clear(&cache);
  /* Exactly 1,536,000 normalized frame pixels are accepted. */
  memcpy(bytes, "BIRCIMG1", 8);
  be32(bytes + 8, 320); be32(bytes + 12, 200); be32(bytes + 16, 24);
  be32(bytes + 20, 0); be32(bytes + 24, 320u * 200u * 4u); be32(bytes + 28, 14);
  offset = 32 + 320u * 200u * 4u;
  memcpy(bytes + offset, "GIF89a", 6); bytes[offset + 6] = 64; bytes[offset + 7] = 1;
  bytes[offset + 8] = 200; bytes[offset + 9] = 0; bytes[offset + 13] = 59; offset += 14;
  for (i = 0; i < 24; i++) {
    unsigned char small[256]; payload(small, 0);
    be32(bytes + offset, i ? 10000 : 20); be32(bytes + offset + 4, 33); offset += 8;
    memcpy(bytes + offset, small + 44, 33);
    be32(bytes + offset + 16, 320); be32(bytes + offset + 20, 200); offset += 33;
  }
  CHECK(birc_media_parse(&parsed, bytes, offset));
  CHECK(parsed.count == 24 && parsed.width == 320 && parsed.height == 200);
  free(encoded); free(bytes); return 0;
}

int main(void) {
  BircMediaCache cache = {0}; BircMedia parsed;
  unsigned char bytes[256]; size_t length = payload(bytes, 0);
  uint32_t first, last; int i;
  CHECK(exact_limits() == 0);
  CHECK(birc_media_parse(&parsed, bytes, length));
  CHECK(parsed.count == 1 && parsed.rgba_len == 4 && parsed.frames[0].duration == 100);
  first = add(&cache, bytes, length); CHECK(first != 0);
  CHECK(birc_media_find(&cache, first) != NULL);
  fail_malloc = 1; CHECK(add(&cache, bytes, length) == 0); fail_malloc = 0;
  CHECK(birc_media_find(&cache, first) != NULL && cache.next_token == first);
  /* A rejected replacement cannot evict the current payload or spend tokens. */
  bytes[0] = 'X'; CHECK(add(&cache, bytes, length) == 0);
  CHECK(birc_media_find(&cache, first) != NULL); bytes[0] = 'B';
  CHECK(!birc_media_parse(&parsed, bytes, length - 1));
  bytes[length] = 0; CHECK(!birc_media_parse(&parsed, bytes, length + 1));
  be32(bytes + 8, 321); CHECK(!birc_media_parse(&parsed, bytes, length)); be32(bytes + 8, 1);
  be32(bytes + 24, 3); CHECK(!birc_media_parse(&parsed, bytes, length)); be32(bytes + 24, 4);
  be32(bytes + 36, 19); CHECK(!birc_media_parse(&parsed, bytes, length)); be32(bytes + 36, 100);
  be32(bytes + 20, 65536); CHECK(!birc_media_parse(&parsed, bytes, length)); be32(bytes + 20, 0);
  bytes[36 + 8 + 19] = 2; CHECK(!birc_media_parse(&parsed, bytes, length)); bytes[36 + 8 + 19] = 1;
  length = payload(bytes, 1); CHECK(birc_media_parse(&parsed, bytes, length));
  CHECK(parsed.count == 2 && parsed.gif_len == 14);
  bytes[36] = 'X'; CHECK(!birc_media_parse(&parsed, bytes, length)); bytes[36] = 'G';
  bytes[42] = 2; CHECK(!birc_media_parse(&parsed, bytes, length)); bytes[42] = 1;
  be32(bytes + 16, 25); CHECK(!birc_media_parse(&parsed, bytes, length)); be32(bytes + 16, 2);
  be32(bytes + 8, 320); be32(bytes + 12, 320); be32(bytes + 16, 16);
  CHECK(!birc_media_parse(&parsed, bytes, length));
  length = payload(bytes, 1);
  last = first;
  for (i = 0; i < 8; i++) { uint32_t token = add(&cache, bytes, length); CHECK(token > last); last = token; }
  CHECK(birc_media_find(&cache, first) == NULL);
  CHECK(birc_media_find(&cache, last) != NULL);
  CHECK(birc_media_add(&cache, "AA=A", 4) == 0);
  CHECK(birc_media_add(&cache, "AB==", 4) == 0); /* noncanonical tail bits */
  CHECK(birc_media_add(&cache, "AAA=\n\n", 6) == 0);
  CHECK(birc_media_add(&cache, "AAAA", ((BIRC_MEDIA_LIMIT + 2u) / 3u) * 4u + 4u) == 0);
  birc_media_clear(&cache); CHECK(birc_media_find(&cache, last) == NULL);
  CHECK(add(&cache, bytes, length) > last); /* clearing never revives a stale token */
  birc_media_clear(&cache);
  cache.next_token = UINT32_MAX; CHECK(add(&cache, bytes, length) == 0);
  puts("media_cache=ok"); return 0;
}
