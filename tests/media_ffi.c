/* Reuse the actual FFI transport harness; no native image work at ingestion. */
#define main output_shutdown_controls
#include "output_shutdown.c"
#undef main
#undef CHECK
static FILE *media_debug;
#define CHECK(x) do { if (!(x)) { fprintf(media_debug ? media_debug : stderr, "media_ffi:%d: %s\n", __LINE__, #x); return 1; } } while (0)
static int media_read(TimuiTransport *transport, void *data, size_t size) {
  (void)transport; (void)data; (void)size; return 0;
}

static int image_support_probe(void) {
  static const TimuiImageProtocol protocols[] = {
    TIMUI_IMAGE_PROTOCOL_NONE, TIMUI_IMAGE_PROTOCOL_KITTY,
    TIMUI_IMAGE_PROTOCOL_ITERM2, TIMUI_IMAGE_PROTOCOL_SIXEL
  };
  SinkFixture fixture; Timui ui = {0}; BircUi state = {0}, before;
  Env env = {0}; Term fields[1]; size_t i;
  CHECK(fixture_start(&fixture) == 0);
  ui.fd.write_fd = fixture.fds[0][1]; install_writer(&ui);
  ui.cfg.userdata = &state;
  ui.caps.flags = TIMUI_CAP_TRUECOLOR | TIMUI_CAP_OSC8_HYPERLINKS;
  ui.caps.colors = 256; ui.caps.width = 80; ui.caps.height = 24;
  fields[0] = io_hand((uint64_t)(uintptr_t)&ui);
  memcpy(&before, &state, sizeof before);
  for (i = 0; i < sizeof protocols / sizeof protocols[0]; i++) {
    TimuiCaps caps;
    timui_force_image_protocol(&ui, protocols[i]);
    memcpy(&caps, &ui.caps, sizeof caps);
    CHECK(timui_image_supported_run(env, fields, NULL) == (Term)(i != 0));
    CHECK(fields[0] == io_hand((uint64_t)(uintptr_t)&ui));
    CHECK(timui_image_protocol(&ui) == protocols[i]);
    CHECK(memcmp(&caps, &ui.caps, sizeof caps) == 0);
    CHECK(memcmp(&before, &state, sizeof state) == 0);
    CHECK(ui.id_head == NULL);
    CHECK(attempts[0] == 0 && attempts[1] == 0);
    CHECK(captured_len[0] == 0 && captured_len[1] == 0);
  }
  CHECK(fixture_stop(&fixture) == 0);
  return 0;
}

static const unsigned char media_png[33] = {
  137,80,78,71,13,10,26,10,0,0,0,13,'I','H','D','R',
  0,0,0,1,0,0,0,1,8,6,0,0,0,0,0,0,0
};
static void media_be32(unsigned char *p, uint32_t n) {
  p[0] = (unsigned char)(n >> 24); p[1] = (unsigned char)(n >> 16);
  p[2] = (unsigned char)(n >> 8); p[3] = (unsigned char)n;
}
static void helper_output(char *text, int animated) {
  unsigned char bytes[160]; size_t length = 36; int i;
  static const unsigned char gif[14] = {'G','I','F','8','9','a',1,0,1,0,0,0,0,59};
  memcpy(bytes, "BIRCIMG1", 8);
  media_be32(bytes + 8, 1); media_be32(bytes + 12, 1);
  media_be32(bytes + 16, animated ? 2u : 1u); media_be32(bytes + 20, 0);
  media_be32(bytes + 24, 4); media_be32(bytes + 28, animated ? sizeof gif : 0);
  memset(bytes + 32, 255, 4);
  if (animated) { memcpy(bytes + length, gif, sizeof gif); length += sizeof gif; }
  for (i = 0; i < (animated ? 2 : 1); i++) {
    media_be32(bytes + length, 100); media_be32(bytes + length + 4, sizeof media_png);
    length += 8; memcpy(bytes + length, media_png, sizeof media_png); length += sizeof media_png;
  }
  length = b64_encode(bytes, length, text, 255); text[length] = '\0';
}
static int draw_media(Timui *ui, BircUi *state, uint32_t token, int *saved_flags,
                       TimuiTransportWrite *saved) {
  TimuiFrame *frame = NULL;
  *saved = birc_output_begin(ui, saved_flags);
  CHECK(timui_begin(ui, &frame));
  state->preview_count = 0;
  birc_media_prune(ui, state);
  birc_draw_media(frame, state, ui, 1, 1, 2, 2, 0, 2, token);
  timui_end(frame);
  return 0;
}

static int cache_frame_ownership(void) {
  SinkFixture fixture; Timui *ui; BircUi *state; Env env = {0}; Term fields[3];
  char text[256]; uint32_t token, next; int flags, i;
  TimuiTransportWrite saved; TimuiTransport transport = {NULL, media_read, NULL, NULL, NULL};
  TimuiAllocator allocator = timui_default_allocator();
  TimuiImage *painted; const unsigned char *frame_bytes;
  size_t frame_size;
  CHECK(fixture_start(&fixture) == 0); clock_paused = 1; clock_seconds = 1;
  CHECK(timui_open_for_test(&ui, transport, 4, 4, &allocator) == TIMUI_OK);
  ui->fd.write_fd = fixture.fds[0][1]; install_writer(ui);
  state = calloc(1, sizeof *state); CHECK(state); ui->cfg.userdata = state; birc_ui_live = ui;
  fields[0] = io_hand((uint64_t)(uintptr_t)ui); helper_output(text, 1);
  fields[1] = (Term)(uintptr_t)text; fields[2] = CID_NIL;
  token = (uint32_t)timui_media_add_run(env, fields, NULL); CHECK(token != 0);
  CHECK(captured_len[0] == 0 && ui->id_head == NULL && !state->previews[0].image);
  timui_force_image_protocol(ui, TIMUI_IMAGE_PROTOCOL_KITTY);
  ui->fd.write_owner = 3; /* physical refusal: ingestion/draw never bypass it */
  CHECK(draw_media(ui, state, token, &flags, &saved) == 0);
  birc_output_end(ui, saved, flags);
  CHECK(captured_len[0] == 0 && state->output.size > 0);
  painted = state->previews[0].image; CHECK(painted && painted->animation);
  frame_bytes = state->output.bytes; frame_size = state->output.size;
  CHECK(frame_size < sizeof captured[0]);
  /* Eviction while an old wire frame is pending cannot invalidate any image
   * bytes, native ids, or the single exact serialized frame. */
  next = token;
  for (i = 0; i < BIRC_MEDIA_CAP; i++) { next = (uint32_t)timui_media_add_run(env, fields, NULL); CHECK(next > token); }
  CHECK(!birc_media_find(&state->media, token) && state->previews[0].image == painted);
  CHECK(state->output.bytes == frame_bytes && state->output.size == frame_size);
  CHECK(painted->animation->frames[0].png == painted->data && painted->animation->gif[0] == 'G');
  CHECK(draw_media(ui, state, next, &flags, &saved) == 0);
  birc_output_end(ui, saved, flags);
  CHECK(state->previews[0].image == painted); /* refused capture cannot replace */
  ui->fd.write_owner = 0; allowance[0] = sizeof captured[0];
  CHECK(draw_media(ui, state, next, &flags, &saved) == 0);
  CHECK(state->previews[0].image && state->previews[0].image != painted);
  CHECK(state->previews[0].retiring == painted); /* one old plus one new, not a queue */
  ui->fd.write_owner = 3;
  birc_output_end(ui, saved, flags);
  CHECK(captured_len[0] == frame_size && state->output.size > 0);
  painted = state->previews[0].image;
  CHECK(timui_media_clear_run(env, fields, NULL) == fields[0]);
  CHECK(!birc_media_find(&state->media, next) && state->previews[0].image == painted);
  captured_len[0] = 0; ui->fd.write_owner = 0; allowance[0] = sizeof captured[0];
  CHECK(draw_media(ui, state, next, &flags, &saved) == 0);
  CHECK(state->previews[0].image == NULL && state->previews[0].retiring == painted);
  birc_output_end(ui, saved, flags);
  CHECK(state->previews[0].retiring == NULL && ui->id_head == NULL);
  CHECK(!birc_output_pending(ui));
  /* Invalid geometry never creates/updates an image. */
  {
    TimuiFrame *frame;
    CHECK(timui_begin(ui, &frame));
    state->preview_count = 0;
    birc_draw_media(frame, state, ui, 1, 1, 2, 2, 2, 1, next);
    birc_draw_media(frame, state, ui, UINT32_MAX, 1, 2, 2, 0, 2, next);
    CHECK(state->preview_count == 0); timui_end(frame);
  }
  memset(&ui->transport, 0, sizeof ui->transport); /* captured sink is intentionally tiny */
  birc_ui_live = NULL; timui_close(ui); birc_output_destroy(&state->output);
  birc_media_clear(&state->media); free(state); clock_paused = 0;
  CHECK(fixture_stop(&fixture) == 0); return 0;
}
/* Duplicate OpMedia for one ready token (split panes) must reuse the slot. */
static int duplicate_token_reuses_preview(void) {
  SinkFixture fixture; Timui *ui; BircUi *state; Env env = {0}; Term fields[3];
  char text[256]; uint32_t token; int flags;
  TimuiTransportWrite saved; TimuiFrame *frame = NULL;
  TimuiTransport transport = {NULL, media_read, NULL, NULL, NULL};
  TimuiAllocator allocator = timui_default_allocator();
  TimuiImage *painted;
  CHECK(fixture_start(&fixture) == 0); clock_paused = 1; clock_seconds = 1;
  CHECK(timui_open_for_test(&ui, transport, 8, 4, &allocator) == TIMUI_OK);
  ui->fd.write_fd = fixture.fds[0][1]; install_writer(ui);
  state = calloc(1, sizeof *state); CHECK(state); ui->cfg.userdata = state; birc_ui_live = ui;
  fields[0] = io_hand((uint64_t)(uintptr_t)ui); helper_output(text, 0);
  fields[1] = (Term)(uintptr_t)text; fields[2] = CID_NIL;
  token = (uint32_t)timui_media_add_run(env, fields, NULL); CHECK(token != 0);
  timui_force_image_protocol(ui, TIMUI_IMAGE_PROTOCOL_KITTY);
  ui->fd.write_owner = 3; /* refuse physical write; assert slot reuse only */
  saved = birc_output_begin(ui, &flags);
  CHECK(timui_begin(ui, &frame));
  state->preview_count = 0;
  birc_media_prune(ui, state);
  birc_draw_media(frame, state, ui, 1, 1, 2, 2, 0, 2, token);
  birc_draw_media(frame, state, ui, 4, 1, 2, 2, 0, 2, token);
  CHECK(state->preview_count == 1);
  painted = state->previews[0].image;
  CHECK(painted && state->previews[0].token == token);
  CHECK(state->previews[1].image == NULL && state->previews[1].token == 0);
  CHECK(ui->img_place_count == 2);
  CHECK(ui->img_place[0].img == painted && ui->img_place[1].img == painted);
  timui_end(frame);
  birc_output_end(ui, saved, flags);
  CHECK(captured_len[0] == 0 && state->output.size > 0);
  memset(&ui->transport, 0, sizeof ui->transport);
  birc_ui_live = NULL; timui_close(ui); birc_output_destroy(&state->output);
  birc_media_clear(&state->media); free(state); clock_paused = 0;
  CHECK(fixture_stop(&fixture) == 0); return 0;
}

int main(void) {
  media_debug = fdopen(dup(STDERR_FILENO), "w");
  CHECK(image_support_probe() == 0);
  CHECK(cache_frame_ownership() == 0);
  CHECK(duplicate_token_reuses_preview() == 0);
  if (media_debug) fclose(media_debug);
  puts("media_ffi=ok"); return 0;
}
