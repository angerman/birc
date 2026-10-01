/* Bounded writes must advance one frame, never replay its accepted prefix. */
#define TIMUI_IMPLEMENTATION
#include "timui.h"
static int fail_allocation;
static void *controlled_realloc(void *data, size_t size) {
  return fail_allocation ? NULL : realloc(data, size);
}
#define realloc controlled_realloc
static int bounded_clock;
static uint64_t bounded_now;
static uint64_t output_clock(void) {
  return bounded_clock ? bounded_now++ : timui_now_ms();
}
#define timui_now_ms output_clock
#include "birc_output.h"
#undef realloc
#undef timui_now_ms
#include <stdio.h>

#define CHECK(test) do { if (!(test)) { \
  fprintf(stderr, "output_progress: line %d: %s\n", __LINE__, #test); return 1; \
} } while (0)

typedef struct {
  BircOutput output;
  unsigned char physical[65536];
  size_t length, allowance, write_chunk;
  const char *input;
  size_t input_size;
} Test;

static int capture(TimuiTransport *t, const void *data, size_t size) {
  Test *test = (Test *)t->ctx;
  return birc_output_capture(&test->output, data, size);
}
static int physical(TimuiTransport *t, const void *data, size_t size) {
  Test *test = (Test *)t->ctx;
  if (test->write_chunk && size > test->write_chunk)
    size = test->write_chunk;
  if (size > test->allowance)
    size = test->allowance;
  if (size > sizeof test->physical - test->length)
    return -1;
  if (size == 0)
    return -1;
  memcpy(test->physical + test->length, data, size);
  test->length += size;
  test->allowance -= size;
  return (int)size;
}
static int read_input(TimuiTransport *t, void *buf, size_t cap) {
  Test *test = (Test *)t->ctx;
  size_t size = test->input_size < cap ? test->input_size : cap;
  if (size > 0)
    memcpy(buf, test->input, size);
  if (size > 0)
    test->input += size;
  test->input_size -= size;
  return (int)size;
}
static int flush(TimuiTransport *t) { (void)t; return 0; }
static void close_transport(TimuiTransport *t) { (void)t; }

static size_t find_bytes(const unsigned char *bytes, size_t size,
                         const char *needle, size_t length);

/* Characterize the replaced repair path with the same deterministic sink.
 * Repainting from row zero cannot reach the last row with a 31-byte quota,
 * although the ordinary writable control completes its first full frame. */
static int restart_repair(int limited) {
  Test test = {0};
  TimuiTransport transport = {physical, read_input, flush, close_transport, &test};
  TimuiAllocator allocator = timui_default_allocator();
  TimuiStyle style = timui_style_make(TIMUI_COLOR_DEFAULT, TIMUI_COLOR_DEFAULT, 0);
  Timui *ui = NULL;
  TimuiFrame *frame = NULL;
  int tick;
  CHECK(timui_open_for_test(&ui, transport, 200, 50, &allocator) == TIMUI_OK);
  timui_full_redraw(ui);
  for (tick = 0; tick < (limited ? 100 : 1); tick++) {
    test.allowance = limited ? 31u : sizeof test.physical;
    CHECK(timui_begin(ui, &frame));
    timui_label(frame, 0, 49, (TimuiStr){"LAST-ROW", 8}, style);
    timui_end(frame);
    timui_full_redraw(ui);
  }
  CHECK((find_bytes(test.physical, test.length, "LAST-ROW", 8) == SIZE_MAX) == limited);
  test.allowance = sizeof test.physical - test.length;
  timui_close(ui);
  return 0;
}

static int delayed_escape(int continuation) {
  Test test = {0};
  TimuiTransport transport = {capture, read_input, flush, close_transport, &test};
  TimuiAllocator allocator = timui_default_allocator();
  Timui *ui = NULL;
  TimuiFrame *frame = NULL;
  CHECK(timui_open_for_test(&ui, transport, 80, 24, &allocator) == TIMUI_OK);
  test.input = "\x1b";
  test.input_size = 1;
  birc_output_start(&test.output);
  CHECK(timui_begin(ui, &frame));
  CHECK(ui->input.state == 1 && ui->key_pressed != TIMUI_KEY_ESCAPE);
  timui_end(frame);
  birc_output_finish(&test.output);
  /* The loop was delayed by a bounded repair, but the continuation is already
   * readable. Only an empty read proves a lone Esc has had genuine idle time. */
  ui->input.esc_since_ms = timui_now_ms() - 100;
  test.input = continuation ? "[A" : "";
  test.input_size = continuation ? 2u : 0u;
  CHECK(timui_begin(ui, &frame));
  CHECK(ui->key_pressed == (continuation ? TIMUI_KEY_UP : TIMUI_KEY_ESCAPE));
  timui_end(frame);
  timui_close(ui);
  birc_output_destroy(&test.output);
  return 0;
}

static int finite_progress(void) {
  Test test = {0};
  TimuiTransport transport = {capture, read_input, flush, close_transport, &test};
  TimuiTransport sink = {physical, read_input, flush, close_transport, &test};
  TimuiAllocator allocator = timui_default_allocator();
  TimuiStyle style = timui_style_make(TIMUI_COLOR_DEFAULT, TIMUI_COLOR_DEFAULT, 0);
  Timui *ui = NULL;
  TimuiFrame *frame = NULL;
  unsigned char expected[65536];
  size_t expected_size, old_offset;
  int tick;
  CHECK(timui_open_for_test(&ui, transport, 200, 50, &allocator) == TIMUI_OK);
  CHECK(birc_output_start(&test.output));
  CHECK(timui_begin(ui, &frame));
  timui_draw_fill(timui_frame_buffer(frame), (TimuiRect){0,0,200,50}, style);
  timui_label_hyperlink(frame, 0, 48, (TimuiStr){"linked", 6},
                         "https://example.test/progress", style);
  timui_label(frame, 0, 49, (TimuiStr){"LAST-ROW \xf0\x9f\x98\x80", 13}, style);
  timui_end(frame);
  CHECK(capture(&transport, "\a", 1) == 1);
  CHECK(birc_output_finish(&test.output));
  CHECK(test.output.size > 8192 && test.output.size < sizeof expected);
  expected_size = test.output.size;
  memcpy(expected, test.output.bytes, expected_size);
  for (tick = 0; test.output.size && tick < 1000; tick++) {
    old_offset = test.output.offset;
    test.allowance = tick == 0 ? 0u : 31u;
    (void)birc_output_drain(&test.output, &sink, UINT64_MAX);
    if (test.output.size) {
      CHECK(tick == 0 || test.output.offset > old_offset);
      CHECK(!birc_output_start(&test.output));
      if (tick == 20)
        CHECK(timui_ui_resize(ui, 160, 45) == TIMUI_OK);
      /* Changed input/model while output is pending cannot append another
       * frame or advance the baseline to content the sink never accepted. */
      CHECK(timui_begin(ui, &frame));
      timui_label(frame, 0, ui->h - 1, (TimuiStr){"LATEST-ROW", 10}, style);
      timui_end(frame);
      CHECK(birc_output_finish(&test.output));
    }
  }
  CHECK(test.output.size == 0 && tick < 1000);
  CHECK(test.output.repaint); /* completion of the old frame is not a paint */
  CHECK(test.length == expected_size);
  CHECK(memcmp(test.physical, expected, expected_size) == 0);
  CHECK(birc_output_start(&test.output));
  CHECK(!test.output.repaint);
  CHECK(timui_begin(ui, &frame));
  timui_label(frame, 0, ui->h - 1, (TimuiStr){"LATEST-ROW", 10}, style);
  timui_end(frame);
  CHECK(birc_output_finish(&test.output));
  CHECK(test.output.size > 0);
  test.allowance = sizeof test.physical - test.length;
  CHECK(birc_output_drain(&test.output, &sink, UINT64_MAX));
  timui_close(ui);
  birc_output_destroy(&test.output);
  return 0;
}

static int drain_budget(void) {
  Test test = {0};
  TimuiTransport sink = {physical, read_input, flush, close_transport, &test};
  static const char text[] = "abcdefgh";
  CHECK(birc_output_start(&test.output));
  CHECK(birc_output_capture(&test.output, text, sizeof text - 1) == (int)(sizeof text - 1));
  CHECK(birc_output_finish(&test.output));
  test.allowance = sizeof test.physical;
  test.write_chunk = 1;
  bounded_clock = 1;
  bounded_now = 100;
  int done = birc_output_drain(&test.output, &sink, 100);
  bounded_clock = 0;
  CHECK(!done && test.output.offset == 1 && test.length == 1);
  bounded_clock = 1;
  bounded_now = 100;
  done = birc_output_drain(&test.output, &sink, 1000);
  bounded_clock = 0;
  CHECK(done && test.length == sizeof text - 1);
  CHECK(memcmp(test.physical, text, sizeof text - 1) == 0);
  birc_output_destroy(&test.output);
  return 0;
}

static int capture_limit(void) {
  BircOutput output = {0};
  TimuiTransport sink = {0};
  CHECK(birc_output_start(&output));
  CHECK(birc_output_capture(&output, "first", 5) == 5);
  CHECK(birc_output_capture(&output, "", BIRC_OUTPUT_LIMIT) < 0);
  CHECK(!birc_output_finish(&output));
  CHECK(output.size == 0 && output.offset == 0);
  CHECK(!birc_output_drain(&output, &sink, UINT64_MAX));
  birc_output_destroy(&output);
  CHECK(birc_output_start(&output));
  fail_allocation = 1;
  CHECK(birc_output_capture(&output, "never emitted", 13) < 0);
  fail_allocation = 0;
  CHECK(!birc_output_finish(&output));
  CHECK(output.size == 0 && output.offset == 0);
  birc_output_destroy(&output);
  return 0;
}

static size_t find_bytes(const unsigned char *bytes, size_t size,
                         const char *needle, size_t length) {
  size_t at;
  for (at = 0; at + length <= size; at++)
    if (memcmp(bytes + at, needle, length) == 0)
      return at;
  return SIZE_MAX;
}

static int cancel_control_frame(int image_cut) {
  Test test = {0};
  TimuiTransport transport = {capture, read_input, flush, close_transport, &test};
  TimuiTransport sink = {physical, read_input, flush, close_transport, &test};
  TimuiAllocator allocator = timui_default_allocator();
  TimuiStyle style = timui_style_make(TIMUI_COLOR_DEFAULT, TIMUI_COLOR_DEFAULT, 0);
  Timui *ui = NULL;
  TimuiFrame *frame = NULL;
  TimuiImage *image;
  static const unsigned char pixel[4] = {255, 0, 0, 255};
  size_t cut, suffix, restore, sync;
  CHECK(timui_open_for_test(&ui, transport, 20, 4, &allocator) == TIMUI_OK);
  ui->cfg.flags |= TIMUI_FLAG_SYNC_OUTPUT;
  ui->screen_active = 1;
  ui->screen.flags = TIMUI_FLAG_ALT_SCREEN | TIMUI_FLAG_MOUSE;
  timui_force_image_protocol(ui, TIMUI_IMAGE_PROTOCOL_KITTY);
  image = timui_image_from_rgba(ui, pixel, 1, 1, 4);
  CHECK(image != NULL);
  CHECK(birc_output_start(&test.output));
  CHECK(timui_begin(ui, &frame));
  timui_clipboard_set(&ui->transport, (TimuiStr){"copied", 6});
  timui_label(frame, 0, 0, (TimuiStr){"content", 7}, style);
  timui_image_draw(frame, image, (TimuiRect){0,1,2,2});
  timui_end(frame);
  CHECK(capture(&transport, "\a", 1) == 1);
  CHECK(birc_output_finish(&test.output));
  cut = find_bytes(test.output.bytes, test.output.size,
                   image_cut ? "\x1b_G" : "\x1b]52;", image_cut ? 3u : 5u);
  CHECK(cut != SIZE_MAX);
  cut += image_cut ? 12u : 8u;
  test.allowance = cut;
  CHECK(!birc_output_drain(&test.output, &sink, UINT64_MAX));
  CHECK(test.output.offset == cut);
  /* Mirror the FFI's conservative physical debt before ordinary close. */
  ui->framing_debt = 1;
  ui->sync_open = 1;
  ui->transport = sink;
  test.allowance = sizeof test.physical - test.length;
  suffix = test.length;
  timui_close(ui);
  CHECK(test.length > suffix + 3);
  CHECK(memcmp(test.physical + suffix, "\\\x1b\\", 3) == 0);
  sync = find_bytes(test.physical + suffix, test.length - suffix, "\x1b[?2026l", 8);
  restore = find_bytes(test.physical + suffix, test.length - suffix, "\x1b[?1049l", 8);
  CHECK(sync != SIZE_MAX && restore != SIZE_MAX && sync < restore);
  timui_image_free(NULL, image);
  birc_output_destroy(&test.output);
  return 0;
}

static int retirement_lifetime(int complete) {
  Test test = {0};
  TimuiTransport transport = {capture, read_input, flush, close_transport, &test};
  TimuiTransport sink = {physical, read_input, flush, close_transport, &test};
  TimuiAllocator allocator = timui_default_allocator();
  Timui *ui = NULL;
  TimuiFrame *frame = NULL;
  TimuiImage *image;
  static const unsigned char pixel[4] = {255, 0, 0, 255};
  size_t suffix;
  CHECK(timui_open_for_test(&ui, transport, 20, 4, &allocator) == TIMUI_OK);
  ui->screen_active = 1;
  ui->screen.flags = TIMUI_FLAG_ALT_SCREEN;
  timui_force_image_protocol(ui, TIMUI_IMAGE_PROTOCOL_KITTY);
  image = timui_image_from_rgba(ui, pixel, 1, 1, 4);
  CHECK(image != NULL);
  CHECK(birc_output_start(&test.output));
  CHECK(timui_begin(ui, &frame));
  timui_image_draw(frame, image, (TimuiRect){0,1,2,2});
  timui_end(frame);
  CHECK(birc_output_finish(&test.output));
  test.allowance = sizeof test.physical;
  CHECK(birc_output_drain(&test.output, &sink, UINT64_MAX));
  CHECK(image_id_slot_find_(image, ui) >= 0);
  CHECK(birc_output_start(&test.output));
  CHECK(timui_image_retire_capture_(ui, image) == TIMUI_FRAME_DONE);
  CHECK(image_id_slot_find_(image, ui) >= 0); /* memory acceptance is not IO */
  CHECK(birc_output_finish(&test.output));
  test.allowance = complete ? sizeof test.physical - test.length : 4u;
  if (complete) {
    CHECK(birc_output_drain(&test.output, &sink, UINT64_MAX));
    timui_image_retire_done_(ui, image);
    CHECK(ui->id_head == NULL);
    ui->transport = sink;
    timui_close(ui);
  } else {
    CHECK(!birc_output_drain(&test.output, &sink, UINT64_MAX));
    ui->framing_debt = 1;
    ui->sync_open = 1;
    ui->transport = sink;
    test.allowance = sizeof test.physical - test.length;
    suffix = test.length;
    timui_close(ui);
    CHECK(find_bytes(test.physical + suffix, test.length - suffix,
                      "a=d,d=I", 7) != SIZE_MAX);
    timui_image_free(NULL, image);
  }
  birc_output_destroy(&test.output);
  return 0;
}

int main(void) {
  CHECK(restart_repair(1) == 0);
  CHECK(restart_repair(0) == 0);
  CHECK(delayed_escape(1) == 0);
  CHECK(delayed_escape(0) == 0);
  CHECK(finite_progress() == 0);
  CHECK(drain_budget() == 0);
  CHECK(capture_limit() == 0);
  CHECK(cancel_control_frame(0) == 0);
  CHECK(cancel_control_frame(1) == 0);
  CHECK(retirement_lifetime(1) == 0);
  CHECK(retirement_lifetime(0) == 0);
  puts("output_progress=ok");
  return 0;
}
