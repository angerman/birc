/* SPDX-License-Identifier: Apache-2.0
 * Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
 * Count PNG decoder allocations without permitting large actual allocations. */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef union {
  long double alignment;
  void *pointer_alignment;
  struct { size_t size; } meta;
} ProbeHeader;

static size_t allocation_cap = 8u * 1024u * 1024u;
static size_t live_bytes, peak_live, max_requested, requested_total, requests, refused;
static size_t deny_request;
static int deny_owned, owned_refused;

static void *probe_owned_alloc(void *userdata, size_t size) {
  (void)userdata;
  if (deny_owned) {
    deny_owned = 0;
    owned_refused++;
    return NULL;
  }
  return malloc(size);
}

static void count_request(size_t size) {
  requests++;
  if (size > max_requested)
    max_requested = size;
  if (size <= SIZE_MAX - requested_total)
    requested_total += size;
}

static void *probe_alloc(size_t size) {
  ProbeHeader *header;
  count_request(size);
  if (requests == deny_request || size > allocation_cap || size > allocation_cap - live_bytes ||
      size > SIZE_MAX - sizeof *header) {
    refused++;
    return NULL;
  }
  header = malloc(sizeof *header + size);
  if (!header)
    return NULL;
  header->meta.size = size;
  live_bytes += size;
  if (live_bytes > peak_live)
    peak_live = live_bytes;
  return header + 1;
}

static void probe_free(void *ptr) {
  if (ptr) {
    ProbeHeader *header = (ProbeHeader *)ptr - 1;
    live_bytes -= header->meta.size;
    free(header);
  }
}

static void *probe_realloc(void *ptr, size_t size) {
  ProbeHeader *header, *grown;
  size_t old_size;
  if (!ptr)
    return probe_alloc(size);
  header = (ProbeHeader *)ptr - 1;
  old_size = header->meta.size;
  count_request(size);
  if (requests == deny_request || size > allocation_cap || size > allocation_cap - (live_bytes - old_size) ||
      size > SIZE_MAX - sizeof *header) {
    refused++;
    return NULL;
  }
  grown = realloc(header, sizeof *header + size);
  if (!grown)
    return NULL;
  grown->meta.size = size;
  live_bytes = live_bytes - old_size + size;
  if (live_bytes > peak_live)
    peak_live = live_bytes;
  return grown + 1;
}

#define STBI_MALLOC(size) probe_alloc(size)
#define STBI_REALLOC(ptr, size) probe_realloc(ptr, size)
#define STBI_REALLOC_SIZED(ptr, old_size, size) probe_realloc(ptr, size)
#define STBI_FREE(ptr) probe_free(ptr)
#define TIMUI_IMPLEMENTATION
#include "timui.h"

static int probe_write(TimuiTransport *transport, const void *data, size_t size) {
  (void)transport;
  (void)data;
  return size > INT_MAX ? -1 : (int)size;
}

static int probe_read(TimuiTransport *transport, void *data, size_t size) {
  (void)transport;
  (void)data;
  (void)size;
  return 0;
}

static uint64_t now_ns(void) {
  struct timespec value;
  if (clock_gettime(CLOCK_MONOTONIC, &value) != 0)
    return 0;
  return (uint64_t)value.tv_sec * UINT64_C(1000000000) + (uint64_t)value.tv_nsec;
}

int main(int argc, char **argv) {
  unsigned char data[16384];
  size_t size, first_requests = 0, first_total = 0;
  int constructor = 0, preflight = 0, decoded = 0, first_decoded = 0, pixels_ok = 0;
  uint64_t elapsed_ns = 0;
  Timui *ui = NULL;
  TimuiImage *image = NULL;
  TimuiAllocator allocator = timui_default_allocator();
  TimuiTransport transport;
  unsigned expected[4] = {0, 0, 0, 0};
  if (argc != 7) {
    fprintf(stderr, "probe: argc=%d\n", argc);
    return 2;
  }
  deny_request = (size_t)strtoul(argv[2], NULL, 10);
  allocator.alloc = probe_owned_alloc;
  for (int channel = 0; channel < 4; channel++)
    expected[channel] = (unsigned)strtoul(argv[channel + 3], NULL, 10);
  size = fread(data, 1, sizeof data, stdin);
  if (size == sizeof data || ferror(stdin)) {
    fprintf(stderr, "probe: input size=%zu\n", size);
    return 2;
  }
  memset(&transport, 0, sizeof transport);
  transport.write = probe_write;
  transport.read = probe_read;
  {
    TimuiResult result = timui_open_for_test(&ui, transport, 4, 4, &allocator);
    if (result != TIMUI_OK) {
      fprintf(stderr, "probe: open=%d\n", result);
      return 2;
    }
  }
  timui_force_image_protocol(ui, TIMUI_IMAGE_PROTOCOL_SIXEL);
  image = timui_image_from_png(ui, data, size);
  constructor = image != NULL;
  if (image) {
    preflight = image_png_preflight_(image, NULL, NULL);
    for (int pass = 0; pass < 2; pass++) {
      TimuiFrame *frame = NULL;
      uint64_t started;
      {
        bool result = timui_begin(ui, &frame);
        if (!result || !frame) {
          fprintf(stderr, "probe: begin=%d frame=%d\n", result, frame != NULL);
          return 2;
        }
      }
      started = now_ns();
      if (pass == 0 && strcmp(argv[2], "owned") == 0)
        deny_owned = 1;
      timui_image_draw_clipped(frame, image, TIMUI_RECT(0, 0, 1, 1),
                               TIMUI_RECT(0, 0, 1, 1));
      elapsed_ns += now_ns() - started;
      decoded = image->rgba != NULL;
      if (decoded) {
        pixels_ok = image->rgba_len == (size_t)image->px_w * (size_t)image->px_h * 4u;
        for (size_t pixel = 0; pixels_ok && pixel < image->rgba_len; pixel++)
          pixels_ok = image->rgba[pixel] == expected[pixel % 4];
      }
      timui_end(frame);
      if (pass == 0) {
        first_requests = requests;
        first_total = requested_total;
        first_decoded = decoded;
      }
    }
    timui_image_free(ui, image);
  }
  timui_close(ui);
  printf("%s file=%zu constructor=%d preflight=%d decoded=%d first_decoded=%d pixels_ok=%d max_requested=%zu "
         "requested_total=%zu peak_live=%zu requests=%zu second_requests=%zu "
         "second_total=%zu refused=%zu owned_refused=%d live=%zu decode_us=%llu\n",
         argv[1], size, constructor, preflight, decoded, first_decoded, pixels_ok, max_requested,
         requested_total, peak_live, requests, requests - first_requests,
         requested_total - first_total, refused, owned_refused, live_bytes,
         (unsigned long long)(elapsed_ns / UINT64_C(1000)));
  return live_bytes == 0 ? 0 : 1;
}
