/* Bend TimUI foreign effects — thin open / frame / close / budget / config.
 * TIMUI_IMPLEMENTATION once. Include-guarded for multi-import. */
#ifndef BIRC_TIMUI_FFI_C
#define BIRC_TIMUI_FFI_C

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef TIMUI_IMPLEMENTATION
#define TIMUI_IMPLEMENTATION
#endif
#include "timui.h"

/* Latched by Timui.frame; read via Timui.keys. Default rows 24 until the
 * first successful frame. The composer is a TimUI input_field so typed
 * chars and Backspace apply in event order (not last-key-wins / one BS
 * per frame). On Enter, typed is the submitted line and the field clears. */
static int birc_ui_quit = 0;
static int birc_ui_enter = 0;
static int birc_ui_backspace = 0;
static char birc_ui_typed[256];
static size_t birc_ui_typed_len = 0;
static uint32_t birc_ui_rows = 24;
static uint32_t birc_ui_tab = 0; /* 0 none, 1 next, 2 prev */
static char birc_composer[512];
static TimuiInputState birc_composer_st = {birc_composer, sizeof birc_composer,
                                           0, 0};

/* ---- Timui.open : IO(Result<&1,&1,U32 & String, Ui>) ------------------- *
 * Same packing as Window.open / TCP.connect: io_fail on error, io_done
 * with the handle on success. Callers use IO.try. */

Term timui_open_run(Env e, Term *f, IoWork *w) {
  TimuiConfig cfg = TIMUI_CONFIG_INIT;
  Timui *ui = NULL;
  (void)f;
  (void)w;
  cfg.title = "birc";
  cfg.flags = TIMUI_FLAG_ALT_SCREEN | TIMUI_FLAG_RESTORE_ON_EXIT;
  cfg.theme = TIMUI_THEME_DOS_BLUE;
  if (timui_open(&cfg, &ui) != TIMUI_OK)
    return io_fail(e, 1u, "timui_open failed");
  /* Alt-screen (1049h) does not always wipe a nested tmux pane. Force a
     full erase so the first paint cannot sit on leftover glyphs. */
  if (ui->transport.write)
    (void)ui->transport.write(&ui->transport, "\x1b[2J\x1b[H", 7);
  return io_done(e, io_hand((uint64_t)(uintptr_t)ui));
}

static void __attribute__((constructor)) timui_open_use(void) {
  io_eff(CID_TIMUI_OPEN, timui_open_run, 0);
}

/* ---- Timui.frame : Ui -> String×6 -> IO(Ui) --------------------------- *
 * ONE begin/draw/end. Layout: header, tabs, body|nicks, status, input. */

static void draw_lines(TimuiFrame *fr, int x, int y, int max_y, const char *text,
                       TimuiStyle st) {
  const char *p = text ? text : "";
  while (*p && y < max_y) {
    char line[512];
    size_t n = 0;
    while (p[n] && p[n] != '\n' && n + 1 < sizeof line)
      n++;
    memcpy(line, p, n);
    line[n] = '\0';
    timui_label(fr, x, y, (TimuiStr){line, n}, st);
    p += n;
    if (*p == '\n')
      p++;
    y++;
  }
}

/* Composer: TimUI input_field walks the per-frame edit stream (text,
 * Backspace, Delete, arrows) in order. Returns 1 if Enter submitted. */
static int draw_composer(TimuiFrame *fr, int x, int y, int width,
                         TimuiStyle st) {
  TimuiId id;
  TimuiRect r;
  int prompt_w = 2;
  if (!fr || width < 1)
    return 0;
  timui_label(fr, x, y, (TimuiStr){"> ", 2}, st);
  if (width <= prompt_w)
    return 0;
  id = TIMUI_ID("birc.composer");
  timui_set_focus(fr, id);
  r.x = x + prompt_w;
  r.y = y;
  r.w = width - prompt_w;
  r.h = 1;
  if (timui_input_field_styled(fr, id, r, &birc_composer_st, st)) {
    size_t n = strlen(birc_composer);
    if (n >= sizeof birc_ui_typed)
      n = sizeof birc_ui_typed - 1;
    memcpy(birc_ui_typed, birc_composer, n);
    birc_ui_typed[n] = '\0';
    birc_ui_typed_len = n;
    birc_composer[0] = '\0';
    birc_composer_st.cursor = 0;
    birc_composer_st.scroll_x = 0;
    return 1;
  }
  return 0;
}

static void birc_free_frame_strs(char *header, char *tabs, char *body,
                                 char *nicks, char *status, char *input) {
  if (header)
    free(header);
  if (tabs)
    free(tabs);
  if (body)
    free(body);
  if (nicks)
    free(nicks);
  if (status)
    free(status);
  if (input)
    free(input);
}

Term timui_frame_run(Env e, Term *f, IoWork *w) {
  Timui *ui = (Timui *)(uintptr_t)io_hand_v(f[0]);
  uint64_t n0, n1, n2, n3, n4, n5;
  char *header = io_cstr(e, f[1], &n0);
  char *tabs = io_cstr(e, f[2], &n1);
  char *body = io_cstr(e, f[3], &n2);
  char *nicks = io_cstr(e, f[4], &n3);
  char *status = io_cstr(e, f[5], &n4);
  char *input = io_cstr(e, f[6], &n5);
  TimuiFrame *fr = NULL;
  (void)w;
  (void)n2;
  (void)n3;
  (void)n5;
  birc_ui_quit = 0;
  birc_ui_enter = 0;
  birc_ui_backspace = 0;
  birc_ui_typed_len = 0;
  birc_ui_typed[0] = '\0';
  birc_ui_tab = 0;

  if (!ui) {
    birc_ui_quit = 1;
    birc_free_frame_strs(header, tabs, body, nicks, status, input);
    return io_hand(0);
  }

  if (!timui_begin(ui, &fr)) {
    birc_ui_quit = 1;
    birc_free_frame_strs(header, tabs, body, nicks, status, input);
    return io_hand((uint64_t)(uintptr_t)ui);
  }

  {
    TimuiRect root = timui_root(fr);
    TimuiStyle fg = timui_style_make(0x59ee3f, TIMUI_COLOR_DEFAULT, 0);
    TimuiStyle dim = timui_style_make(0xa0a0a0, TIMUI_COLOR_DEFAULT, 0);
    int mid = root.w > 24 ? root.w - 18 : root.w / 2;
    int body_bottom = root.h >= 2 ? root.y + root.h - 2 : root.y + root.h;
    int status_y = root.h >= 2 ? root.y + root.h - 2 : root.y;
    int input_y = root.h >= 1 ? root.y + root.h - 1 : root.y;
    TimuiStyle panel;
    birc_ui_rows = root.h < 4 ? 4u : (uint32_t)root.h;
    /* Paint every cell so the first frame (and resizes) cannot leave
     * leftover terminal glyphs. Default-empty cells are skipped by the
     * diff renderer. */
    panel = timui_theme_style(&ui->theme, TIMUI_SLOT_PANEL);
    timui_draw_fill(timui_frame_buffer(fr), root, panel);
    timui_label(fr, root.x, root.y,
                (TimuiStr){header ? header : "", header ? (size_t)n0 : 0},
                fg);
    timui_label(fr, root.x, root.y + 1,
                (TimuiStr){tabs ? tabs : "", tabs ? (size_t)n1 : 0}, dim);
    draw_lines(fr, root.x, root.y + 2, body_bottom, body, fg);
    draw_lines(fr, root.x + mid, root.y + 2, body_bottom, nicks, dim);
    if (root.h >= 2)
      timui_label(fr, root.x, status_y,
                  (TimuiStr){status ? status : "", status ? (size_t)n4 : 0},
                  dim);
    if (draw_composer(fr, root.x, input_y, root.w, fg))
      birc_ui_enter = 1;
    if (timui_key_pressed_mods(fr, TIMUI_KEY_RIGHT, TIMUI_MOD_SHIFT))
      birc_ui_tab = 1;
    else if (timui_key_pressed_mods(fr, TIMUI_KEY_LEFT, TIMUI_MOD_SHIFT))
      birc_ui_tab = 2;
    if (timui_key_pressed(fr, TIMUI_KEY_ESCAPE)) {
      timui_quit(ui);
      birc_ui_quit = 1;
    }
  }
  timui_end(fr);
  if (timui_should_quit(ui))
    birc_ui_quit = 1;
  if (header)
    free(header);
  if (tabs)
    free(tabs);
  if (body)
    free(body);
  if (nicks)
    free(nicks);
  if (status)
    free(status);
  if (input)
    free(input);
  return io_hand((uint64_t)(uintptr_t)ui);
}

static void __attribute__((constructor)) timui_frame_use(void) {
  io_eff(CID_TIMUI_FRAME, timui_frame_run, 0);
}

#ifdef CID_TIMUI_DID_QUIT
Term timui_did_quit_run(Env e, Term *f, IoWork *w) {
  (void)e;
  (void)f;
  (void)w;
  return term_pak(birc_ui_quit ? CID_TRUE : CID_FALSE, 0);
}

static void __attribute__((constructor)) timui_did_quit_use(void) {
  io_eff(CID_TIMUI_DID_QUIT, timui_did_quit_run, 0);
}
#endif

Term timui_rows_run(Env e, Term *f, IoWork *w) {
  (void)e;
  (void)f;
  (void)w;
  return (Term)(uint64_t)birc_ui_rows;
}

static void __attribute__((constructor)) timui_rows_use(void) {
  io_eff(CID_TIMUI_ROWS, timui_rows_run, 0);
}

#ifdef CID_TIMUI_TYPED
Term timui_typed_run(Env e, Term *f, IoWork *w) {
  (void)f;
  (void)w;
  return io_str(e, birc_ui_typed, birc_ui_typed_len);
}

static void __attribute__((constructor)) timui_typed_use(void) {
  io_eff(CID_TIMUI_TYPED, timui_typed_run, 0);
}
#endif

#ifdef CID_TIMUI_ENTER
Term timui_enter_run(Env e, Term *f, IoWork *w) {
  (void)e;
  (void)f;
  (void)w;
  return term_pak(birc_ui_enter ? CID_TRUE : CID_FALSE, 0);
}

static void __attribute__((constructor)) timui_enter_use(void) {
  io_eff(CID_TIMUI_ENTER, timui_enter_run, 0);
}
#endif

#ifdef CID_TIMUI_BACKSPACE
Term timui_backspace_run(Env e, Term *f, IoWork *w) {
  (void)e;
  (void)f;
  (void)w;
  return term_pak(birc_ui_backspace ? CID_TRUE : CID_FALSE, 0);
}

static void __attribute__((constructor)) timui_backspace_use(void) {
  io_eff(CID_TIMUI_BACKSPACE, timui_backspace_run, 0);
}
#endif

/* ---- Timui.keys : IO(Bool & Bool & Bool & String & U32) --------------- *
 * Right-nested tuples: quit, enter, bs, typed, rows. Data constructor
 * Keys mangles to CID_TIMUI_KEYS and collides with this law. Guarded:
 * unused Timui.keys does not define the CID, but this file is still
 * inlined via Timui.open. */

#ifdef CID_TIMUI_KEYS
Term timui_keys_run(Env e, Term *f, IoWork *w) {
  (void)f;
  (void)w;
  return io_tup(e, term_pak(birc_ui_quit ? CID_TRUE : CID_FALSE, 0),
    io_tup(e, term_pak(birc_ui_enter ? CID_TRUE : CID_FALSE, 0),
      io_tup(e, term_pak(birc_ui_backspace ? CID_TRUE : CID_FALSE, 0),
        io_tup(e, io_str(e, birc_ui_typed, birc_ui_typed_len),
          io_tup(e, (Term)(uint64_t)birc_ui_rows,
            (Term)(uint64_t)birc_ui_tab)))));
}

static void __attribute__((constructor)) timui_keys_use(void) {
  io_eff(CID_TIMUI_KEYS, timui_keys_run, 0);
}
#endif

/* ---- Timui.close : Ui -> IO(Unit) ------------------------------------- */

Term timui_close_run(Env e, Term *f, IoWork *w) {
  Timui *ui = (Timui *)(uintptr_t)io_hand_v(f[0]);
  (void)e;
  (void)w;
  if (ui)
    timui_close(ui);
  return term_pak(CID_UNIT, 0);
}

static void __attribute__((constructor)) timui_close_use(void) {
  io_eff(CID_TIMUI_CLOSE, timui_close_run, 0);
}

#endif /* BIRC_TIMUI_FFI_C */
