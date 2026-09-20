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
static uint32_t birc_ui_click = 0; /* 0 none, 1+i = TabSet i */
static uint32_t birc_ui_scroll_up = 0;
static uint32_t birc_ui_scroll_dn = 0;
static uint32_t birc_ui_hist = 0; /* 0 none, 1 prev, 2 next */
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
  cfg.theme = TIMUI_THEME_MODERN_DARK;
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

/* Packed BodyLine wire: k|ts|spans\n  spans: P/B/I/C text or L url GS text,
 * units separated by US (0x1f). C does not tokenize. */
static uint32_t birc_kind_fg(int k) {
  switch (k) {
  case 1:
    return 0x59ee3fu;
  case 2:
    return 0xa0a0a0u;
  case 3:
    return 0xc792eau;
  case 4:
    return 0x82aaffu;
  case 5:
    return 0xf78c6cu;
  default:
    return 0xc8c8c8u;
  }
}

static int birc_glyph_cols(const char *s, size_t n) {
  size_t i = 0;
  int w = 0;
  while (i < n) {
    uint32_t cp = 0;
    int adv = timui_utf8_decode(s + i, n - i, &cp);
    if (adv <= 0)
      adv = 1;
    w += timui_utf8_width(cp);
    i += (size_t)adv;
  }
  return w;
}

static int birc_put_span(TimuiFrame *fr, int x, int y, int maxx, const char *p,
                         size_t n, uint32_t fg, uint32_t attrs) {
  int w;
  TimuiStyle st;
  if (!fr || n == 0 || x >= maxx)
    return x;
  w = birc_glyph_cols(p, n);
  while (n > 0 && x + birc_glyph_cols(p, n) > maxx)
    n--;
  if (n == 0)
    return x;
  w = birc_glyph_cols(p, n);
  st = timui_style_make(fg, TIMUI_COLOR_DEFAULT, attrs);
  timui_label(fr, x, y, (TimuiStr){p, n}, st);
  return x + w;
}

static int birc_put_link(TimuiFrame *fr, int x, int y, int maxx, const char *url,
                         size_t ulen, const char *text, size_t tlen,
                         uint32_t fg) {
  char uri[512];
  int w;
  TimuiStyle st;
  if (!fr || tlen == 0 || x >= maxx)
    return x;
  if (ulen >= sizeof uri)
    ulen = sizeof uri - 1;
  memcpy(uri, url, ulen);
  uri[ulen] = '\0';
  w = birc_glyph_cols(text, tlen);
  while (tlen > 0 && x + birc_glyph_cols(text, tlen) > maxx)
    tlen--;
  if (tlen == 0)
    return x;
  w = birc_glyph_cols(text, tlen);
  st = timui_style_make(fg, TIMUI_COLOR_DEFAULT, TIMUI_ATTR_UNDERLINE);
  timui_label_hyperlink(fr, x, y, (TimuiStr){text, tlen}, uri, st);
  return x + w;
}

static void draw_packed_line(TimuiFrame *fr, int x, int y, int maxx,
                             const char *line, size_t len) {
  const char *p = line;
  const char *end = line + len;
  const char *ts;
  size_t tslen;
  int kind = 0;
  uint32_t fg;
  TimuiStyle dim;
  if (!fr || !line || len == 0)
    return;
  if (*p >= '0' && *p <= '5') {
    kind = *p - '0';
    p++;
  }
  if (p < end && *p == '|')
    p++;
  ts = p;
  while (p < end && *p != '|')
    p++;
  tslen = (size_t)(p - ts);
  if (p < end && *p == '|')
    p++;
  fg = birc_kind_fg(kind);
  dim = timui_style_make(0xa0a0a0u, TIMUI_COLOR_DEFAULT, 0);
  if (tslen > 0) {
    timui_label(fr, x, y, (TimuiStr){ts, tslen}, dim);
    x += birc_glyph_cols(ts, tslen) + 1;
  }
  while (p < end) {
    const char *unit = p;
    const char *sep;
    char tag;
    uint32_t attrs = 0;
    while (p < end && (unsigned char)*p != 0x1fu)
      p++;
    sep = p;
    if (p < end)
      p++;
    if (unit >= sep)
      continue;
    tag = *unit++;
    if (tag == 'L') {
      const char *gs = unit;
      while (gs < sep && (unsigned char)*gs != 0x1du)
        gs++;
      if (gs < sep)
        x = birc_put_link(fr, x, y, maxx, unit, (size_t)(gs - unit), gs + 1,
                          (size_t)(sep - (gs + 1)), fg);
      else
        x = birc_put_span(fr, x, y, maxx, unit, (size_t)(sep - unit), fg, 0);
    } else {
      if (tag == 'B')
        attrs = TIMUI_ATTR_BOLD;
      else if (tag == 'I')
        attrs = TIMUI_ATTR_ITALIC;
      else if (tag == 'C')
        attrs = 0;
      else if (tag != 'P') {
        unit--;
      }
      x = birc_put_span(fr, x, y, maxx, unit, (size_t)(sep - unit), fg, attrs);
    }
  }
}

static int packed_line_count(const char *s) {
  int n = 0;
  if (!s)
    return 0;
  for (; *s; s++)
    if (*s == '\n')
      n++;
  return n;
}

static void draw_packed_body(TimuiFrame *fr, int x, int y, int max_y, int maxx,
                             const char *text) {
  const char *p = text ? text : "";
  int n = packed_line_count(p);
  int y0 = max_y - n;
  if (y0 < y)
    y0 = y;
  while (*p && y0 < max_y) {
    const char *start = p;
    size_t nline = 0;
    while (p[nline] && p[nline] != '\n')
      nline++;
    draw_packed_line(fr, x, y0, maxx, start, nline);
    p += nline;
    if (*p == '\n')
      p++;
    y0++;
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

static int birc_parse_tabs(const char *tabs, char store[][64],
                           const char **labs, int max, int *n_out) {
  const char *p = tabs ? tabs : "";
  int active = 0;
  int n = 0;
  while (*p && *p != '\t') {
    if (*p >= '0' && *p <= '9')
      active = active * 10 + (*p - '0');
    p++;
  }
  if (*p == '\t')
    p++;
  while (*p && n < max) {
    const char *start = p;
    size_t len;
    while (*p && (unsigned char)*p != 0x1fu)
      p++;
    len = (size_t)(p - start);
    if (len >= 63)
      len = 63;
    memcpy(store[n], start, len);
    store[n][len] = '\0';
    labs[n] = store[n];
    n++;
    if ((unsigned char)*p == 0x1fu)
      p++;
  }
  *n_out = n;
  return active;
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
  birc_ui_click = 0;
  birc_ui_scroll_up = 0;
  birc_ui_scroll_dn = 0;
  birc_ui_hist = 0;

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
    TimuiCellBuffer *buf = timui_frame_buffer(fr);
    TimuiStyle panel = timui_theme_style(&ui->theme, TIMUI_SLOT_PANEL);
    TimuiStyle text = timui_theme_style(&ui->theme, TIMUI_SLOT_TEXT);
    TimuiStyle dim = timui_theme_style(&ui->theme, TIMUI_SLOT_TEXT_DIM);
    TimuiStyle border = timui_theme_style(&ui->theme, TIMUI_SLOT_BORDER);
    TimuiStyle status_st = timui_theme_style(&ui->theme, TIMUI_SLOT_STATUS);
    int mid = root.w > 24 ? root.w - 18 : root.w / 2;
    int status_y = root.h >= 2 ? root.y + root.h - 2 : root.y;
    int input_y = root.h >= 1 ? root.y + root.h - 1 : root.y;
    int body_y = root.y + 2;
    int body_h = status_y - body_y;
    TimuiRect body_r;
    TimuiRect nick_r;
    TimuiRect tab_r;
    char tabstore[16][64];
    const char *tablabs[16];
    int ntabs = 0;
    int sel;
    int orig;
    const char *nick_p;
    birc_ui_rows = root.h < 4 ? 4u : (uint32_t)root.h;
    timui_draw_fill(buf, root, panel);
    timui_label(fr, root.x, root.y,
                (TimuiStr){header ? header : "", header ? (size_t)n0 : 0},
                text);
    tab_r.x = root.x;
    tab_r.y = root.y + 1;
    tab_r.w = root.w;
    tab_r.h = 1;
    orig = birc_parse_tabs(tabs, tabstore, tablabs, 16, &ntabs);
    sel = orig;
    if (ntabs > 0)
      (void)timui_tabs(fr, TIMUI_ID("birc.bufs"), tab_r, tablabs, ntabs, &sel);
    if (sel != orig && sel >= 0)
      birc_ui_click = (uint32_t)sel + 1u;
    if (body_h < 1)
      body_h = 1;
    body_r.x = root.x;
    body_r.y = body_y;
    body_r.w = mid > 2 ? mid : root.w;
    body_r.h = body_h;
    nick_r.x = root.x + body_r.w;
    nick_r.y = body_y;
    nick_r.w = root.w - body_r.w;
    nick_r.h = body_h;
    timui_draw_box(buf, body_r, TIMUI_BORDER_ROUND, border);
    if (nick_r.w > 2)
      timui_draw_box(buf, nick_r, TIMUI_BORDER_ROUND, border);
    draw_packed_body(fr, body_r.x + 1, body_r.y + 1, body_r.y + body_r.h - 1,
                     body_r.x + body_r.w - 1, body);
    nick_p = nicks ? nicks : "";
    if (*nick_p) {
      const char *nl = strchr(nick_p, '\n');
      size_t tlen = nl ? (size_t)(nl - nick_p) : strlen(nick_p);
      timui_label(fr, nick_r.x + 1, nick_r.y, (TimuiStr){nick_p, tlen}, dim);
      if (nl)
        draw_lines(fr, nick_r.x + 1, nick_r.y + 1, nick_r.y + nick_r.h - 1,
                   nl + 1, dim);
    }
    if (root.h >= 2)
      timui_label(fr, root.x, status_y,
                  (TimuiStr){status ? status : "", status ? (size_t)n4 : 0},
                  status_st);
    if (input && input[0] && strcmp(birc_composer, input) != 0) {
      size_t ilen = strlen(input);
      if (ilen >= sizeof birc_composer)
        ilen = sizeof birc_composer - 1;
      memcpy(birc_composer, input, ilen);
      birc_composer[ilen] = '\0';
      birc_composer_st.cursor = ilen;
    }
    if (draw_composer(fr, root.x, input_y, root.w, text))
      birc_ui_enter = 1;
    if (timui_key_pressed_mods(fr, TIMUI_KEY_RIGHT, TIMUI_MOD_SHIFT))
      birc_ui_tab = 1;
    else if (timui_key_pressed_mods(fr, TIMUI_KEY_LEFT, TIMUI_MOD_SHIFT))
      birc_ui_tab = 2;
    if (timui_key_pressed(fr, TIMUI_KEY_PAGE_UP))
      birc_ui_scroll_up = 1;
    if (timui_key_pressed(fr, TIMUI_KEY_PAGE_DOWN))
      birc_ui_scroll_dn = 1;
    {
      int wheel = timui_mouse_wheel(fr);
      if (wheel > 0)
        birc_ui_scroll_up += (uint32_t)wheel;
      else if (wheel < 0)
        birc_ui_scroll_dn += (uint32_t)(-wheel);
    }
    if (timui_key_pressed(fr, TIMUI_KEY_UP) &&
        !timui_key_pressed_mods(fr, TIMUI_KEY_UP, TIMUI_MOD_SHIFT))
      birc_ui_hist = 1;
    if (timui_key_pressed(fr, TIMUI_KEY_DOWN) &&
        !timui_key_pressed_mods(fr, TIMUI_KEY_DOWN, TIMUI_MOD_SHIFT))
      birc_ui_hist = 2;
    if (timui_key_pressed(fr, TIMUI_KEY_ESCAPE) ||
        timui_key_pressed(fr, TIMUI_KEY_F10)) {
      timui_quit(ui);
      birc_ui_quit = 1;
    }
    timui_set_focus(fr, TIMUI_ID("birc.composer"));
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
            io_tup(e, (Term)(uint64_t)birc_ui_tab,
              io_tup(e, (Term)(uint64_t)birc_ui_click,
                io_tup(e, (Term)(uint64_t)birc_ui_scroll_up,
                  io_tup(e, (Term)(uint64_t)birc_ui_scroll_dn,
                    (Term)(uint64_t)birc_ui_hist)))))))));
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
