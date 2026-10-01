/* View timing uses the actual FFI and its deterministic monotonic clock. */
#define main output_shutdown_controls
#include "output_shutdown.c"
#undef main
#undef CHECK
#define CHECK(test) do { if (!(test)) { \
  fprintf(stderr, "view_profile: line %d: %s\n", __LINE__, #test); return 1; \
} } while (0)

int main(void) {
  BircUi state = {0};
  Timui ui = {0};
  Env env = {0};
  Term fields[1];
  ui.cfg.userdata = &state;
  fields[0] = io_hand((uint64_t)(uintptr_t)&ui);
  clock_seconds = 10;
  clock_paused = 0;

  /* Default-off instrumentation returns the same handle without a clock read. */
  CHECK(timui_view_begin_run(env, fields, NULL) == fields[0]);
  CHECK(clock_seconds == 10 && state.profile_view_start_ns == 0);
  CHECK(state.profile_view_ns == 0);
  fields[0] = 0;
  CHECK(timui_view_begin_run(env, fields, NULL) == 0);
  CHECK(clock_seconds == 10);
  birc_profile_view_end(NULL, 1);
  fields[0] = io_hand((uint64_t)(uintptr_t)&ui);
  ui.cfg.userdata = NULL;
  CHECK(timui_view_begin_run(env, fields, NULL) == fields[0]);
  CHECK(clock_seconds == 10);
  ui.cfg.userdata = &state;

  state.profile_enabled = 1;
  CHECK(timui_view_begin_run(env, fields, NULL) == fields[0]);
  CHECK(state.profile_view_start_ns == 11000000000ULL);
  clock_seconds = 14;
  birc_profile_view_end(&state, birc_profile_now_ns());
  CHECK(state.profile_view_ns == 4000000000ULL);
  CHECK(state.profile_view_start_ns == 0);
  birc_profile_view_end(&state, 20000000000ULL);
  CHECK(state.profile_view_ns == 4000000000ULL); /* consume each mark once */

  /* A later mark replaces an abandoned one rather than counting idle time. */
  CHECK(timui_view_begin_run(env, fields, NULL) == fields[0]);
  CHECK(timui_view_begin_run(env, fields, NULL) == fields[0]);
  CHECK(state.profile_view_start_ns == 17000000000ULL);
  birc_profile_view_end(&state, 18000000000ULL);
  CHECK(state.profile_view_ns == 5000000000ULL);
  CHECK(state.profile_view_start_ns == 0);
  CHECK(birc_profile_us(state.profile_view_ns, 2) == 2500000ULL);
  CHECK(birc_profile_us(state.profile_view_ns, 0) == 0);

  /* A failed clock read cannot underflow elapsed time or leave a stale mark. */
  CHECK(timui_view_begin_run(env, fields, NULL) == fields[0]);
  birc_profile_view_end(&state, 0);
  CHECK(state.profile_view_ns == 5000000000ULL);
  CHECK(state.profile_view_start_ns == 0);
  puts("view_profile=ok");
  return 0;
}
