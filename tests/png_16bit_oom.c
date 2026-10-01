/* SPDX-License-Identifier: Apache-2.0
 * Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
 * Decoder allocator ownership, including 8-to-16 postprocessing failure. */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static size_t requests, deny_request, live;
static void *tracked_alloc(size_t n) {
  void *p;
  requests++;
  if (requests == deny_request) return NULL;
  p = malloc(n);
  if (p) live++;
  return p;
}
static void tracked_free(void *p) {
  if (p) { live--; free(p); }
}
static void *tracked_realloc(void *p, size_t n) {
  if (!p) return tracked_alloc(n);
  requests++;
  if (requests == deny_request) return NULL;
  return realloc(p, n);
}
#define STBI_MALLOC(n) tracked_alloc(n)
#define STBI_REALLOC(p, n) tracked_realloc(p, n)
#define STBI_REALLOC_SIZED(p, old, n) tracked_realloc(p, n)
#define STBI_FREE(p) tracked_free(p)
#define TIMUI_IMPLEMENTATION
#include "timui.h"
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "png_16bit_oom:%d: %s live=%zu\n", __LINE__, #x, live); return 1; } } while (0)

static int conversion(void) {
  stbi_uc *input;
  stbi__uint16 *result;
  requests = deny_request = 0;
  input = tracked_alloc(4);
  CHECK(input);
  memcpy(input, "\x11\x22\x33\xff", 4);
  result = stbi__convert_8_to_16(input, 1, 1, 4);
  CHECK(result && live == 1);
  CHECK(result[0] == 0x1111 && result[1] == 0x2222 && result[2] == 0x3333 && result[3] == 0xffff);
  tracked_free(result);
  CHECK(live == 0);
  input = tracked_alloc(4);
  CHECK(input);
  deny_request = requests + 1;
  CHECK(stbi__convert_8_to_16(input, 1, 1, 4) == NULL);
  CHECK(live == 0);
  deny_request = 0;
  return 0;
}
static int decoding(const stbi_uc *data, int len) {
  stbi__context context;
  stbi__uint16 *pixels;
  int w, h, comp;
  size_t count, denial;
  stbi_set_flip_vertically_on_load(1);
  requests = deny_request = 0;
  stbi__start_mem(&context, data, len);
  pixels = stbi__load_and_postprocess_16bit(&context, &w, &h, &comp, 4);
  CHECK(pixels && w == 1 && h == 2);
  CHECK(pixels[0] == 0x6666 && pixels[1] == 0x7777 && pixels[2] == 0x8888 && pixels[3] == 0x9999);
  CHECK(pixels[4] == 0x1111 && pixels[5] == 0x2222 && pixels[6] == 0x3333 && pixels[7] == 0xffff);
  count = requests;
  tracked_free(pixels);
  CHECK(live == 0);
  for (denial = 1; denial <= count; denial++) {
    requests = 0; deny_request = denial;
    stbi__start_mem(&context, data, len);
    pixels = stbi__load_and_postprocess_16bit(&context, &w, &h, &comp, 4);
    CHECK(!pixels && context.allocation_failed);
    CHECK(live == 0);
  }
  deny_request = 0;
  stbi_set_flip_vertically_on_load(0);
  return 0;
}
int main(int argc, char **argv) {
  unsigned char data[256];
  size_t n;
  if (argc == 1 || !strcmp(argv[1], "convert")) CHECK(conversion() == 0);
  if (argc == 1 || !strcmp(argv[1], "flip")) {
    n = fread(data, 1, sizeof data, stdin);
    CHECK(n > 0 && n < sizeof data && !ferror(stdin));
    CHECK(decoding(data, (int)n) == 0);
  }
  puts("png_16bit_oom=ok");
  return 0;
}
