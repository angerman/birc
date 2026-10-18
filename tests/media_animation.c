/* Terminal playback owns one image id and uses the shared framed encoder. */
#define TIMUI_IMPLEMENTATION
#include "timui.h"
#include <stdio.h>

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "media_animation:%d: %s\n", __LINE__, #x); return 1; } } while (0)
typedef struct {
  unsigned char bytes[65536]; size_t size, allowance; int fail_alloc, live, refuse_frame;
} Test;
static int write_bytes(TimuiTransport *t, const void *p, size_t n) {
  Test *test = (Test *)t->ctx;
  if (test->refuse_frame && n >= 6 && memcmp(p, "\x1b_Ga=f", 6) == 0) return -1;
  if (n > test->allowance) n = test->allowance;
  if (!n || n > sizeof test->bytes - test->size) return -1;
  memcpy(test->bytes + test->size, p, n); test->size += n; test->allowance -= n;
  return (int)n;
}
static int read_bytes(TimuiTransport *t, void *p, size_t n) { (void)t; (void)p; (void)n; return 0; }
static int flush(TimuiTransport *t) { (void)t; return 0; }
static void close_bytes(TimuiTransport *t) { (void)t; }
static void *allocate(void *ctx, size_t n) { Test *test = ctx; void *p = test->fail_alloc ? NULL : malloc(n); if (p) test->live++; return p; }
static void release(void *ctx, void *p, size_t n) { Test *test = ctx; (void)n; if (p) { test->live--; free(p); } }
static void *resize(void *ctx, void *p, size_t old, size_t n) { Test *test = ctx; (void)old; if (test->fail_alloc) return NULL; if (!p) return allocate(ctx, n); return realloc(p, n); }
static int contains(const Test *test, const char *text) {
  size_t i, n = strlen(text);
  for (i = 0; i + n <= test->size; i++) if (!memcmp(test->bytes + i, text, n)) return 1;
  return 0;
}
static size_t occurrences(const Test *test, const char *text) {
  size_t i, n = strlen(text), count = 0;
  for (i = 0; i + n <= test->size; i++) if (!memcmp(test->bytes + i, text, n)) count++;
  return count;
}
static const unsigned char png[33] = {
  137,80,78,71,13,10,26,10,0,0,0,13,'I','H','D','R',
  0,0,0,1,0,0,0,1,8,6,0,0,0,0,0,0,0
};
static const unsigned char gif[14] = {'G','I','F','8','9','a',1,0,1,0,0,0,0,59};

static int playback(TimuiImageProtocol protocol, uint32_t loops) {
  Test test = {0}; Timui *ui = NULL; TimuiFrame *frame;
  TimuiTransport transport = {write_bytes, read_bytes, flush, close_bytes, &test};
  TimuiAllocator allocator = {&test, allocate, resize, release};
  unsigned char rgba[4] = {255,0,0,255}, later[6000];
  TimuiImageFrame frames[2] = {{png,sizeof png,40},{later,sizeof later,120}};
  TimuiImage *image; TimuiImageAnimation_ *saved;
  CHECK(timui_open_for_test(&ui, transport, 20, 10, &allocator) == TIMUI_OK);
  test.allowance = sizeof test.bytes;
  timui_force_image_protocol(ui, protocol);
  protocol = timui_image_protocol(ui);
  memcpy(later, png, sizeof png); memset(later + sizeof png, 0, sizeof later - sizeof png);
  image = timui_image_from_png_rgba(ui, png, sizeof png, rgba, 1, 1, 4); CHECK(image);
  CHECK(timui_image_set_animation(image, frames, 2, loops, gif, sizeof gif) == TIMUI_OK);
  CHECK(image->animation && image->animation->frames[1].png != later);
  saved = image->animation;
  test.fail_alloc = 1;
  CHECK(timui_image_set_animation(image, frames, 2, loops, gif, sizeof gif) == TIMUI_ERR_OUT_OF_MEMORY);
  CHECK(image->animation == saved); test.fail_alloc = 0;
  frames[1].duration_ms = 19;
  CHECK(timui_image_set_animation(image, frames, 2, loops, gif, sizeof gif) == TIMUI_ERR_INVALID_ARGUMENT);
  CHECK(image->animation == saved); frames[1].duration_ms = 120;
  memset(later, 99, sizeof later); /* caller bytes are not borrowed */
  timui_set_image_id_for_test(ui, image, 7);
  CHECK(timui_begin(ui, &frame));
  timui_image_draw(frame, image, (TimuiRect){1,1,3,2}); timui_end(frame);
  if (protocol == TIMUI_IMAGE_PROTOCOL_KITTY) {
    CHECK(contains(&test, "a=t,t=d,f=100,q=2,i=7"));
    CHECK(contains(&test, "a=f,t=d,f=100,q=2,i=7,X=1,z=120,m=1"));
    CHECK(contains(&test, "a=f,q=2,i=7,m=0"));
    CHECK(contains(&test, "a=a,q=2,i=7,r=1,z=40"));
    CHECK(contains(&test, loops ? "a=a,q=2,i=7,s=3,v=3" : "a=a,q=2,i=7,s=3,v=1"));
    CHECK(occurrences(&test, "a=f") == 2);
    test.size = 0;
    CHECK(timui_begin(ui, &frame)); timui_image_draw(frame, image, (TimuiRect){2,1,3,2}); timui_end(frame);
    CHECK(!contains(&test, "a=f")); /* movement does not restart playback */
    test.size = 0;
    CHECK(timui_begin(ui, &frame)); timui_image_draw(frame, image, (TimuiRect){2,1,3,2}); timui_end(frame);
    CHECK(test.size == 0); /* unchanged: skip delete/transmit/place */
  } else if (protocol == TIMUI_IMAGE_PROTOCOL_ITERM2) {
    CHECK(contains(&test, "1337;File=inline=1;size=14"));
    CHECK(contains(&test, "R0lGODlh")); /* GIF, not the first PNG */
    CHECK(!contains(&test, "a=f"));
    test.size = 0;
    CHECK(timui_begin(ui, &frame)); timui_image_draw(frame, image, (TimuiRect){1,1,3,2}); timui_end(frame);
    CHECK(test.size == 0); /* unchanged: skip base64 re-emit */
  } else {
    CHECK(!contains(&test, "a=f") && !contains(&test, "1337;File="));
  }
  CHECK(timui_image_update_rgba(ui, image, rgba, 1, 1, 4) == TIMUI_OK);
  CHECK(!image->animation);
  timui_image_free(ui, image); timui_close(ui); CHECK(test.live == 0);
  return 0;
}

static int partial_retry(void) {
  Test test = {0}; Timui *ui; TimuiFrame *frame;
  TimuiTransport transport = {write_bytes, read_bytes, flush, close_bytes, &test};
  TimuiAllocator allocator = {&test, allocate, resize, release};
  unsigned char rgba[4] = {0}; TimuiImage *image;
  TimuiImageFrame frames[2] = {{png,sizeof png,40},{png,sizeof png,120}};
  CHECK(timui_open_for_test(&ui, transport, 20, 10, &allocator) == TIMUI_OK);
  timui_force_image_protocol(ui, TIMUI_IMAGE_PROTOCOL_KITTY);
  image = timui_image_from_png_rgba(ui, png, sizeof png, rgba, 1, 1, 4); CHECK(image);
  CHECK(timui_image_set_animation(image, frames, 2, 0, gif, sizeof gif) == TIMUI_OK);
  timui_set_image_id_for_test(ui, image, 7);
  /* Direct shared encoder seam: root landed, refused extra/control is torn. */
  test.allowance = 0;
  CHECK(kitty_animation_(&transport, allocator, 7, image) == TIMUI_FRAME_TORN);
  test.allowance = 30;
  CHECK(kitty_animation_(&transport, allocator, 7, image) != TIMUI_FRAME_DONE);
  test.allowance = sizeof test.bytes - test.size;
  test.refuse_frame = 1;
  CHECK(timui_begin(ui, &frame)); timui_image_draw(frame, image, (TimuiRect){1,1,3,2}); timui_end(frame);
  CHECK(image->id == 0 && image->kitty_dirty == 1);
  CHECK(!contains(&test, "s=3,v=1"));
  test.refuse_frame = 0;
  CHECK(timui_begin(ui, &frame)); timui_image_draw(frame, image, (TimuiRect){1,1,3,2}); timui_end(frame);
  CHECK(image->id == 8 && contains(&test, "a=t,t=d,f=100,q=2,i=8"));
  CHECK(contains(&test, "s=3,v=1"));
  timui_image_free(ui, image); timui_close(ui); CHECK(test.live == 0); return 0;
}

static int clipping(TimuiImageProtocol protocol) {
  Test test = {0}; Timui *ui; TimuiFrame *frame;
  TimuiTransport transport = {write_bytes, read_bytes, flush, close_bytes, &test};
  TimuiAllocator allocator = {&test, allocate, resize, release};
  unsigned char rgba[64], png4[33], gif4[14]; TimuiImage *image;
  TimuiImageFrame frames[2] = {{png4,sizeof png4,40},{png4,sizeof png4,120}};
  memcpy(png4, png, sizeof png); png4[19] = 4; png4[23] = 4;
  memcpy(gif4, gif, sizeof gif); gif4[6] = 4; gif4[8] = 4;
  memset(rgba, 255, sizeof rgba);
  CHECK(timui_open_for_test(&ui, transport, 10, 8, &allocator) == TIMUI_OK);
  timui_force_image_protocol(ui, protocol); protocol = timui_image_protocol(ui);
  timui_set_cell_pixels_for_test(ui, 2, 1); test.allowance = sizeof test.bytes;
  image = timui_image_from_png_rgba(ui, png4, sizeof png4, rgba, 4, 4, 16); CHECK(image);
  CHECK(timui_image_set_animation(image, frames, 2, 1, gif4, sizeof gif4) == TIMUI_OK);
  timui_set_image_id_for_test(ui, image, 9);
  CHECK(timui_begin(ui, &frame));
  timui_image_draw_clipped(frame, image, (TimuiRect){1,-2,2,4}, (TimuiRect){1,0,2,2});
  timui_end(frame);
  if (protocol == TIMUI_IMAGE_PROTOCOL_KITTY)
    CHECK(contains(&test, ",x=0,y=2,w=4,h=2,c=2,r=2"));
  else if (protocol == TIMUI_IMAGE_PROTOCOL_ITERM2)
    CHECK(!contains(&test, "1337;File=")); /* iTerm has no source-clip command */
  else
    CHECK(!contains(&test, "a=f")); /* Sixel uses exactly the first RGBA */
  timui_image_free(ui, image); timui_close(ui); CHECK(test.live == 0); return 0;
}
static int png_kind_only(void) {
  unsigned char bytes[36] = {0}, gif9[14]; TimuiImage *image;
  TimuiImageFrame frames[2] = {{bytes,sizeof bytes,40},{bytes,sizeof bytes,120}};
  memcpy(bytes, png, sizeof png); bytes[23] = 9;
  memcpy(gif9, gif, sizeof gif); gif9[8] = 9;
  image = timui_image_from_rgba(NULL, bytes, 1, 9, 4); CHECK(image);
  CHECK(timui_image_set_animation(image, frames, 2, 1, gif9, sizeof gif9) == TIMUI_ERR_INVALID_ARGUMENT);
  CHECK(!image->animation); timui_image_free(NULL, image);
  return 0;
}
int main(void) {
  CHECK(playback(TIMUI_IMAGE_PROTOCOL_KITTY, 0) == 0);
  CHECK(playback(TIMUI_IMAGE_PROTOCOL_KITTY, 2) == 0);
  CHECK(playback(TIMUI_IMAGE_PROTOCOL_ITERM2, 0) == 0);
  CHECK(playback(TIMUI_IMAGE_PROTOCOL_SIXEL, 0) == 0);
  CHECK(playback(TIMUI_IMAGE_PROTOCOL_NONE, 0) == 0);
#ifndef TIMUI_NO_IMAGES
  CHECK(partial_retry() == 0);
#else
  (void)partial_retry;
#endif
  CHECK(clipping(TIMUI_IMAGE_PROTOCOL_KITTY) == 0);
  CHECK(clipping(TIMUI_IMAGE_PROTOCOL_ITERM2) == 0);
  CHECK(clipping(TIMUI_IMAGE_PROTOCOL_SIXEL) == 0);
  CHECK(png_kind_only() == 0);
  puts("media_animation=ok"); return 0;
}
