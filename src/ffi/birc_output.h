/* One owned frame, not an output queue. Capture is atomic; draining keeps the
 * exact accepted-byte offset across bounded writes. The caller supplies the
 * shared UTF-8/deadline writer and may read input while this frame is pending. */
#ifndef BIRC_OUTPUT_H
#define BIRC_OUTPUT_H
#include <limits.h>
#include <stdlib.h>
#include <string.h>

/* Production supports two maximum-size PNG previews plus cell output.
 * A lower compile-time value is the native failure-test seam, not an env knob. */
#ifndef BIRC_OUTPUT_LIMIT
#define BIRC_OUTPUT_LIMIT (64u * 1024u * 1024u)
#endif
typedef struct {
  unsigned char *bytes;
  size_t size, offset, capacity;
  int capturing, failed, repaint;
} BircOutput;

static int birc_output_capture(BircOutput *out, const void *data, size_t size) {
  size_t need, capacity;
  unsigned char *next;
  if (!out || !out->capturing || out->failed)
    return -1;
  if (size > INT_MAX || size > BIRC_OUTPUT_LIMIT - out->size) {
    out->failed = 1;
    return -1;
  }
  need = out->size + size;
  if (need > out->capacity) {
    capacity = out->capacity ? out->capacity : 4096;
    while (capacity < need)
      capacity *= 2;
    next = (unsigned char *)realloc(out->bytes, capacity);
    if (!next) {
      out->failed = 1;
      return -1;
    }
    out->bytes = next;
    out->capacity = capacity;
  }
  if (size > 0)
    memcpy(out->bytes + out->size, data, size);
  out->size = need;
  return (int)size;
}

static int birc_output_start(BircOutput *out) {
  out->capturing = out->size == 0;
  out->failed = 0;
  /* The latest model was not captured. If the old frame drains at end(),
   * keep one repair due even though no serialized bytes remain. */
  out->repaint = !out->capturing;
  return out->capturing;
}

static int birc_output_finish(BircOutput *out) {
  out->capturing = 0;
  if (out->failed) {
    /* No part of a failed capture may reach the physical transport. */
    out->size = out->offset = 0;
    return 0;
  }
  return 1;
}

static int birc_output_drain(BircOutput *out, TimuiTransport *transport,
                             uint64_t deadline) {
  if (!out || !transport || !transport->write || out->capturing || out->failed)
    return 0;
  while (out->offset < out->size) {
    size_t left = out->size - out->offset;
    int written = transport->write(transport, out->bytes + out->offset, left);
    if (written <= 0)
      return 0;
    out->offset += (size_t)written > left ? left : (size_t)written;
    /* A successful short call consumed the same physical-frame budget too.
     * Never turn each native writer's permitted first attempt into a retry
     * loop after that shared deadline. */
    if (out->offset < out->size && timui_now_ms() >= deadline)
      return 0;
  }
  out->size = out->offset = 0;
  return 1;
}

static void birc_output_destroy(BircOutput *out) {
  free(out->bytes);
  memset(out, 0, sizeof *out);
}
#endif
