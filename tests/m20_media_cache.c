/* SPDX-License-Identifier: Apache-2.0 */
#define main existing_cache_controls
#include "media_cache.c"
#undef main

int main(void) {
  BircMediaCache cache = {0};
  unsigned char bytes[256];
  const unsigned char *held_bytes[8];
  size_t held_sizes[8];
  uint32_t tokens[8], kept[7], refreshed, spent;
  size_t length = payload(bytes, 0);
  unsigned i;
  for (i = 0; i < 8; i++) {
    tokens[i] = add(&cache, bytes, length);
    CHECK(tokens[i] != 0);
  }
  /* All eight Bend-retained: a ninth valid payload must not evict. */
  birc_media_retain(&cache, tokens, 8);
  for (i = 0; i < 8; i++) {
    CHECK(birc_media_find(&cache, tokens[i]) != NULL);
    held_bytes[i] = cache.slots[i].bytes;
    held_sizes[i] = cache.slots[i].size;
  }
  spent = cache.next_token;
  CHECK(add(&cache, bytes, length) == 0);
  CHECK(cache.next_token == spent);
  for (i = 0; i < 8; i++) {
    CHECK(cache.slots[i].token == tokens[i]);
    CHECK(cache.slots[i].bytes == held_bytes[i]);
    CHECK(cache.slots[i].size == held_sizes[i]);
    CHECK(birc_media_find(&cache, tokens[i]) != NULL);
  }
  /* Seven live inline results and one obsolete manual result. */
  memcpy(kept, tokens, sizeof kept);
  birc_media_retain(&cache, kept, 7);
  refreshed = add(&cache, bytes, length); CHECK(refreshed > tokens[7]);
  for (i = 0; i < 7; i++) CHECK(birc_media_find(&cache, kept[i]) != NULL);
  CHECK(!birc_media_find(&cache, tokens[7]));
  CHECK(birc_media_find(&cache, refreshed));
  /* A ninth distinct result drops the oldest Bend result, not the manual one. */
  memcpy(kept, tokens + 1, 6 * sizeof *kept); kept[6] = refreshed;
  birc_media_retain(&cache, kept, 7);
  CHECK(add(&cache, bytes, length) > refreshed);
  CHECK(!birc_media_find(&cache, tokens[0]));
  for (i = 0; i < 7; i++) CHECK(birc_media_find(&cache, kept[i]));
  /* Failed refresh preserves every retained payload and does not spend tokens. */
  birc_media_retain(&cache, kept, 7);
  refreshed = cache.next_token;
  CHECK(birc_media_add(&cache, "invalid", 7) == 0);
  CHECK(cache.next_token == refreshed);
  for (i = 0; i < 7; i++) CHECK(birc_media_find(&cache, kept[i]));
  /* Stale targets and empty lists release bytes, without reviving token ids. */
  birc_media_retain(&cache, NULL, 0);
  for (i = 0; i < 8; i++) CHECK(cache.slots[i].bytes == NULL);
  CHECK(add(&cache, bytes, length) > refreshed);
  birc_media_clear(&cache);
  puts("m20_media_cache=ok"); return 0;
}
