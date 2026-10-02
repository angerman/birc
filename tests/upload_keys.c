/* SPDX-License-Identifier: Apache-2.0 */
/* Actual FFI forwards keys. Bend decides whether Escape cancels or quits. */
#define main input_wake_original_main
#include "input_wake.c"
#undef main

static int key_policy(void) {
  Fixture f;
  uint32_t key, more;
  CHECK(fixture_start(&f) == 0);
  CHECK(feed(&f, "\x1b[19~", 5, &key, &more) == 0);
  CHECK(key == TIMUI_KEY_F8 && !timui_should_quit(f.ui));
  CHECK(feed(&f, "\x1b", 1, &key, &more) == 0);
  now_ms += 100;
  CHECK(paint(&f, &key, &more) == 0);
  CHECK(key == TIMUI_KEY_ESCAPE && !timui_should_quit(f.ui));
  CHECK(feed(&f, "\x1b[21~", 5, &key, &more) == 0);
  CHECK(key == TIMUI_KEY_F10 && !timui_should_quit(f.ui));
  /* A transport failure cannot be mistaken for a cancelable Escape. */
  birc_output_failure = 1;
  CHECK(paint(&f, &key, &more) == 0);
  birc_output_failure = 0;
  CHECK(key == TIMUI_KEY_F10);
  timui_quit(f.ui);
  CHECK(paint(&f, &key, &more) == 0 && key == TIMUI_KEY_F10);
  CHECK(fixture_stop(&f) == 0);
  memset(&f, 0, sizeof f);
  CHECK(paint(&f, &key, &more) == 0 && key == TIMUI_KEY_F10);
  return 0;
}

int main(void) {
  if (key_policy()) return 1;
  puts("upload_keys=ok");
  return 0;
}
