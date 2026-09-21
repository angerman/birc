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

/* Composer state lives on the Ui handle (cfg.userdata), not file statics. */
typedef struct {
  char composer[512];
  TimuiTextAreaState st;
} BircUi;

static BircUi *birc_state(const Timui *ui) {
  return ui ? (BircUi *)timui_userdata(ui) : NULL;
}

/* Drop trailing UTF-8 continuation bytes so n is a code-point boundary. */
static size_t birc_utf8_fit(const char *s, size_t n) {
  if (!s)
    return 0;
  while (n > 0 && (((unsigned char)s[n] & 0xC0u) == 0x80u))
    n -= 1;
  return n;
}

/* Live handle for atexit restore. Timui.close clears it first so the hook
 * is idempotent with the normal P5 path. err_fail/_exit skip atexit. */
static Timui *birc_ui_live;

static void birc_ui_atexit(void) {
  Timui *ui = birc_ui_live;
  birc_ui_live = NULL;
  if (ui)
    timui_restore_terminal(ui);
}

#ifdef CID_UIKEYS
static Term birc_uikeys(Env e, int quit, int enter, const char *typed,
                        size_t tlen, uint32_t rows, uint32_t tab,
                        uint32_t click, uint32_t up, uint32_t dn,
                        uint32_t hist) {
  Loc l = heap_alloc(e, cls_fit(9));
  e.mem[l + 0] = io_seal(e, (Term)(uint64_t)(quit ? 1u : 0u), CID_UIKEYS);
  e.mem[l + 1] = io_seal(e, (Term)(uint64_t)(enter ? 1u : 0u), CID_UIKEYS);
  e.mem[l + 2] = io_seal(e, io_str(e, typed ? typed : "", tlen), CID_UIKEYS);
  e.mem[l + 3] = io_seal(e, (Term)(uint64_t)rows, CID_UIKEYS);
  e.mem[l + 4] = io_seal(e, (Term)(uint64_t)tab, CID_UIKEYS);
  e.mem[l + 5] = io_seal(e, (Term)(uint64_t)click, CID_UIKEYS);
  e.mem[l + 6] = io_seal(e, (Term)(uint64_t)up, CID_UIKEYS);
  e.mem[l + 7] = io_seal(e, (Term)(uint64_t)dn, CID_UIKEYS);
  e.mem[l + 8] = io_seal(e, (Term)(uint64_t)hist, CID_UIKEYS);
  return term_ctr(CID_UIKEYS, l);
}

static Term birc_frame_out(Env e, Timui *ui, int quit, int enter,
                           const char *typed, size_t tlen, uint32_t rows,
                           uint32_t tab, uint32_t click, uint32_t up,
                           uint32_t dn, uint32_t hist) {
  return io_tup(e, io_hand((uint64_t)(uintptr_t)ui),
                birc_uikeys(e, quit, enter, typed, tlen, rows, tab, click, up,
                            dn, hist));
}
#endif

/* ---- Timui.open : IO(Result<&1,&1,U32 & String, Ui>) ------------------- *
 * Same packing as Window.open / TCP.connect: io_fail on error, io_done
 * with the handle on success. Callers use IO.try. */

Term timui_open_run(Env e, Term *f, IoWork *w) {
  TimuiConfig cfg = TIMUI_CONFIG_INIT;
  Timui *ui = NULL;
  BircUi *st;
  (void)f;
  (void)w;
  st = (BircUi *)calloc(1, sizeof(BircUi));
  if (!st)
    return io_fail(e, 1u, "timui_open failed");
  st->st.text = st->composer;
  st->st.cap = sizeof st->composer;
  cfg.title = "birc";
  cfg.flags = TIMUI_FLAG_ALT_SCREEN | TIMUI_FLAG_RESTORE_ON_EXIT |
              TIMUI_FLAG_MOUSE | TIMUI_FLAG_BRACKETED_PASTE;
  cfg.theme = TIMUI_THEME_MODERN_DARK;
  cfg.userdata = st;
  if (timui_open(&cfg, &ui) != TIMUI_OK) {
    free(st);
    return io_fail(e, 1u, "timui_open failed");
  }
  /* Alt-screen (1049h) does not always wipe a nested tmux pane. Force a
     full erase so the first paint cannot sit on leftover glyphs. */
  timui_full_redraw(ui);
  birc_ui_live = ui;
  atexit(birc_ui_atexit);
  return io_done(e, io_hand((uint64_t)(uintptr_t)ui));
}

static void __attribute__((constructor)) timui_open_use(void) {
  io_eff(CID_TIMUI_OPEN, timui_open_run, 0);
}

/* ---- Timui.frame : Ui -> List<DrawOp> -> String -> U32 -> IO(Ui & UiKeys)
 * ONE begin/draw/end. C walks ops; layout chrome stays here until R6. */

/* DrawOp list walker. Bend owns colours, spans, and tab names. */

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

static size_t birc_clip_cols(const char *s, size_t n, int x, int maxx) {
  size_t i = 0;
  int cx = x;
  if (!s)
    return 0;
  while (i < n) {
    uint32_t cp = 0;
    int adv = timui_utf8_decode(s + i, n - i, &cp);
    int w;
    if (adv <= 0) {
      cp = 0xFFFDu;
      adv = 1;
    }
    w = timui_utf8_width(cp);
    if (w > 0 && cx > maxx - w)
      break;
    if (w > 0)
      cx += w;
    i += (size_t)adv;
  }
  return i;
}

static int birc_put_span(TimuiFrame *fr, int x, int y, int maxx, const char *p,
                         size_t n, uint32_t fg, uint32_t attrs) {
  int w;
  TimuiStyle st;
  if (!fr || n == 0 || x >= maxx)
    return x;
  n = birc_clip_cols(p, n, x, maxx);
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
    return birc_put_span(fr, x, y, maxx, text, tlen, fg, 0);
  memcpy(uri, url, ulen);
  uri[ulen] = '\0';
  tlen = birc_clip_cols(text, tlen, x, maxx);
  if (tlen == 0)
    return x;
  w = birc_glyph_cols(text, tlen);
  st = timui_style_make(fg, TIMUI_COLOR_DEFAULT, TIMUI_ATTR_UNDERLINE);
  timui_label_hyperlink(fr, x, y, (TimuiStr){text, tlen}, uri, st);
  return x + w;
}

#if defined(CID_CON)
static Term birc_cons_head(Env e, Term xs, Term *tail) {
  Term fb[2];
  Loc sp = ctr_take(e, xs, 2, fb);
  *tail = fb[1];
  spare_free(e, cls_fit(2), sp);
  return fb[0];
}

static int birc_str_list(Env e, Term xs, char store[][64], const char **labs,
                         int max) {
  int n = 0;
  while (n < max && term_aux(xs) == CID_CON) {
    Term t;
    u64 len = 0;
    char *s;
    size_t nlen;
    Term h = birc_cons_head(e, xs, &t);
    xs = t;
    s = io_cstr(e, h, &len);
    nlen = birc_utf8_fit(s ? s : "", (size_t)len);
    if (nlen >= 63)
      nlen = 63;
    if (s && nlen > 0)
      memcpy(store[n], s, nlen);
    store[n][nlen] = '\0';
    labs[n] = store[n];
    free(s);
    n++;
  }
  return n;
}

static char *birc_cstr(Env e, Term t, u64 *n) {
  char *s = io_cstr(e, t, n);
  if (!s) {
    *n = 0;
    return NULL;
  }
  return s;
}

static int birc_draw_spans(Env e, TimuiFrame *fr, int x, int y, int maxx,
                           uint32_t fg, Term xs) {
  while (term_aux(xs) == CID_CON) {
    Term rest, f[2];
    Term sp = birc_cons_head(e, xs, &rest);
    u64 cid = term_aux(sp);
    Loc loc = ctr_take(e, sp, 2, f);
    xs = rest;
    if (cid == CID_VIEW_LNK) {
      u64 ulen = 0, tlen = 0;
      char *url = birc_cstr(e, f[0], &ulen);
      char *text = birc_cstr(e, f[1], &tlen);
      x = birc_put_link(fr, x, y, maxx, url ? url : "", (size_t)ulen,
                        text ? text : "", (size_t)tlen, fg);
      free(url);
      free(text);
    } else if (cid == CID_VIEW_SPN) {
      u64 tlen = 0;
      char *text = birc_cstr(e, f[1], &tlen);
      x = birc_put_span(fr, x, y, maxx, text ? text : "", (size_t)tlen, fg,
                        (uint32_t)f[0]);
      free(text);
    }
    spare_free(e, cls_fit(2), loc);
  }
  return x;
}

static void birc_draw_bodyln(Env e, TimuiFrame *fr, int x, int y, int maxx,
                             Term ln) {
  Term f[3];
  Loc loc;
  u64 tslen = 0;
  char *ts;
  if (term_aux(ln) != CID_VIEW_BODYLN)
    return;
  loc = ctr_take(e, ln, 3, f);
  ts = birc_cstr(e, f[1], &tslen);
  if (ts && tslen > 0) {
    TimuiStyle dim = timui_style_make(0xa0a0a0u, TIMUI_COLOR_DEFAULT, 0);
    timui_label(fr, x, y, (TimuiStr){ts, (size_t)tslen}, dim);
    x += birc_glyph_cols(ts, (size_t)tslen) + 1;
  }
  free(ts);
  (void)birc_draw_spans(e, fr, x, y, maxx, (uint32_t)f[0], f[2]);
  spare_free(e, cls_fit(3), loc);
}

typedef struct {
  TimuiRect root;
  TimuiRect tab_r;
  TimuiRect body_r;
  TimuiRect nick_r;
  int status_y;
  uint32_t *click;
} BircLay;

static void birc_label(TimuiFrame *fr, int x, int y, Env e, Term t, TimuiStyle st) {
  u64 n = 0;
  char *s = birc_cstr(e, t, &n);
  timui_label(fr, x, y, (TimuiStr){s ? s : "", s ? (size_t)n : 0}, st);
  free(s);
}

static void birc_draw_op(Env e, Timui *ui, TimuiFrame *fr, Term op, BircLay *ly) {
  u64 cid = term_aux(op);
  if (cid == CID_VIEW_OPHEADER) {
    Term f[1];
    Loc loc = ctr_take(e, op, 1, f);
    birc_label(fr, ly->root.x, ly->root.y, e, f[0],
               timui_theme_style(&ui->theme, TIMUI_SLOT_TEXT));
    spare_free(e, cls_fit(1), loc);
  } else if (cid == CID_VIEW_OPTABS) {
    Term f[2];
    Loc loc = ctr_take(e, op, 2, f);
    char store[16][64];
    const char *labs[16];
    int ntabs = birc_str_list(e, f[1], store, labs, 16);
    int orig = (int)(uint32_t)f[0];
    int sel = orig < 0 ? 0 : orig;
    if (ntabs > 0 && sel >= ntabs)
      sel = ntabs - 1;
    orig = sel;
    if (ntabs > 0)
      (void)timui_tabs(fr, TIMUI_ID("birc.bufs"), ly->tab_r, labs, ntabs, &sel);
    if (sel != orig && sel >= 0 && sel < ntabs)
      *ly->click = (uint32_t)sel + 1u;
    spare_free(e, cls_fit(2), loc);
  } else if (cid == CID_VIEW_OPBODY) {
    Term f[1];
    Loc loc = ctr_take(e, op, 1, f);
    Term xs = f[0];
    Term lns[64];
    int n = 0, i, max_y = ly->body_r.y + ly->body_r.h - 1;
    int min_y = ly->body_r.y + 1, maxx = ly->body_r.x + ly->body_r.w - 1, y;
    while (n < 64 && term_aux(xs) == CID_CON) {
      Term rest;
      lns[n++] = birc_cons_head(e, xs, &rest);
      xs = rest;
    }
    y = max_y - n;
    if (y < min_y)
      y = min_y;
    for (i = 0; i < n && y < max_y; i += 1, y += 1)
      birc_draw_bodyln(e, fr, ly->body_r.x + 1, y, maxx, lns[i]);
    spare_free(e, cls_fit(1), loc);
  } else if (cid == CID_VIEW_OPNICKS) {
    Term f[2];
    Loc loc = ctr_take(e, op, 2, f);
    TimuiStyle dim = timui_theme_style(&ui->theme, TIMUI_SLOT_TEXT_DIM);
    Term xs = f[1];
    int y = ly->nick_r.y, max_y = ly->nick_r.y + ly->nick_r.h - 1;
    if (ly->nick_r.w > 2) {
      birc_label(fr, ly->nick_r.x + 1, y, e, f[0], dim);
      y++;
      while (y < max_y && term_aux(xs) == CID_CON) {
        Term rest, h = birc_cons_head(e, xs, &rest);
        xs = rest;
        birc_label(fr, ly->nick_r.x + 1, y, e, h, dim);
        y++;
      }
    }
    spare_free(e, cls_fit(2), loc);
  } else if (cid == CID_VIEW_OPSTATUS) {
    Term f[1];
    Loc loc = ctr_take(e, op, 1, f);
    if (ly->root.h >= 2)
      birc_label(fr, ly->root.x, ly->status_y, e, f[0],
                 timui_theme_style(&ui->theme, TIMUI_SLOT_STATUS));
    spare_free(e, cls_fit(1), loc);
  }
}

static void birc_draw_ops(Env e, Timui *ui, TimuiFrame *fr, Term xs, BircLay *ly) {
  while (term_aux(xs) == CID_CON) {
    Term rest;
    Term op = birc_cons_head(e, xs, &rest);
    xs = rest;
    birc_draw_op(e, ui, fr, op, ly);
  }
}
#endif /* CID_CON */

/* Composer: same widget as timui.h/examples/irc.c — one-row textarea
 * with ENTER_SUBMITS. Copies the live field (or the submitted line). */
static int draw_composer(TimuiFrame *fr, int x, int y, int width, TimuiStyle st,
                         BircUi *stt, size_t *tlen) {
  TimuiId id;
  TimuiRect r;
  TimuiTextAreaResult res;
  int prompt_w = 2;
  size_t n;
  (void)st;
  if (!fr || !stt || width < 1)
    return 0;
  timui_label(fr, x, y, (TimuiStr){"> ", 2}, st);
  if (width <= prompt_w)
    return 0;
  id = TIMUI_ID("birc.composer");
  if (timui_focus(fr) != id)
    timui_set_focus(fr, id);
  r.x = x + prompt_w;
  r.y = y;
  r.w = width - prompt_w;
  r.h = 1;
  res = timui_text_area_mut(fr, id, r, &stt->st, TIMUI_TEXT_AREA_ENTER_SUBMITS);
  n = strlen(stt->composer);
  *tlen = birc_utf8_fit(stt->composer, n);
  return res.submitted ? 1 : 0;
}



/* ---- Timui.frame : Ui -> List<DrawOp> -> String -> U32 -> IO(Ui & UiKeys) */

Term timui_frame_run(Env e, Term *f, IoWork *w) {
  Timui *ui = (Timui *)(uintptr_t)io_hand_v(f[0]);
  Term ops = f[1];
  uint64_t n_in = 0;
  char *input = io_cstr(e, f[2], &n_in);
  u32 seed = (u32)f[3];
  TimuiFrame *fr = NULL;
  BircUi *bu = birc_state(ui);
  int quit = 0;
  int enter = 0;
  uint32_t rows = 24;
  uint32_t tab = 0;
  uint32_t click = 0;
  uint32_t up = 0;
  uint32_t dn = 0;
  uint32_t hist = 0;
  size_t tlen = 0;
  (void)w;

#ifndef CID_UIKEYS
#error "Timui.frame returns Ui & UiKeys; CID_UIKEYS is required"
#endif
  if (!ui) {
    free(input);
    return birc_frame_out(e, NULL, 1, 0, "", 0, 24, 0, 0, 0, 0, 0);
  }

  if (!timui_begin(ui, &fr)) {
    free(input);
    return birc_frame_out(e, ui, 1, 0, "", 0, 24, 0, 0, 0, 0, 0);
  }
  if (timui_focus(fr) != TIMUI_ID("birc.composer"))
    timui_set_focus(fr, TIMUI_ID("birc.composer"));

  {
    TimuiRect root = timui_root(fr);
    TimuiCellBuffer *buf = timui_frame_buffer(fr);
    TimuiStyle panel = timui_theme_style(&ui->theme, TIMUI_SLOT_PANEL);
    TimuiStyle text = timui_theme_style(&ui->theme, TIMUI_SLOT_TEXT);
    TimuiStyle border = timui_theme_style(&ui->theme, TIMUI_SLOT_BORDER);
    int mid = root.w > 24 ? root.w - 18 : root.w / 2;
    int status_y = root.h >= 2 ? root.y + root.h - 2 : root.y;
    int input_y = root.h >= 1 ? root.y + root.h - 1 : root.y;
    int body_y = root.y + 2;
    int body_h = status_y - body_y;
    BircLay ly;
    rows = root.h < 4 ? 4u : (uint32_t)root.h;
    if (body_h < 1)
      body_h = 1;
    ly.root = root;
    ly.tab_r.x = root.x;
    ly.tab_r.y = root.y + 1;
    ly.tab_r.w = root.w;
    ly.tab_r.h = 1;
    ly.body_r.x = root.x;
    ly.body_r.y = body_y;
    ly.body_r.w = mid > 2 ? mid : root.w;
    ly.body_r.h = body_h;
    ly.nick_r.x = root.x + ly.body_r.w;
    ly.nick_r.y = body_y;
    ly.nick_r.w = root.w - ly.body_r.w;
    ly.nick_r.h = body_h;
    ly.status_y = status_y;
    ly.click = &click;
    timui_draw_fill(buf, root, panel);
    timui_draw_box(buf, ly.body_r, TIMUI_BORDER_ROUND, border);
    if (ly.nick_r.w > 2)
      timui_draw_box(buf, ly.nick_r, TIMUI_BORDER_ROUND, border);
#ifdef CID_CON
    birc_draw_ops(e, ui, fr, ops, &ly);
#else
    (void)ops;
#endif
    if (seed != 0 && bu) {
      size_t ilen = input ? (size_t)n_in : 0;
      if (ilen >= sizeof bu->composer)
        ilen = birc_utf8_fit(input, sizeof bu->composer - 1);
      else if (input)
        ilen = birc_utf8_fit(input, ilen);
      if (input && ilen > 0)
        memcpy(bu->composer, input, ilen);
      bu->composer[ilen] = '\0';
      bu->st.cursor = ilen;
      bu->st.scroll_y = 0;
    }
    if (timui_focus(fr) != TIMUI_ID("birc.composer"))
      timui_set_focus(fr, TIMUI_ID("birc.composer"));
    if (timui_key_pressed_mods(fr, TIMUI_KEY_RIGHT, TIMUI_MOD_SHIFT))
      tab = 1;
    else if (timui_key_pressed_mods(fr, TIMUI_KEY_LEFT, TIMUI_MOD_SHIFT))
      tab = 2;
    if (timui_key_pressed(fr, TIMUI_KEY_PAGE_UP))
      up = rows >= 7u ? rows - 6u : 1u;
    if (timui_key_pressed(fr, TIMUI_KEY_PAGE_DOWN))
      dn = rows >= 7u ? rows - 6u : 1u;
    {
      int wheel = timui_mouse_wheel(fr);
      if (wheel > 0)
        up += (uint32_t)wheel;
      else if (wheel < 0)
        dn += (uint32_t)(-wheel);
    }
    if (timui_key_pressed(fr, TIMUI_KEY_UP) &&
        !timui_key_pressed_mods(fr, TIMUI_KEY_UP, TIMUI_MOD_SHIFT))
      hist = 1;
    if (timui_key_pressed(fr, TIMUI_KEY_DOWN) &&
        !timui_key_pressed_mods(fr, TIMUI_KEY_DOWN, TIMUI_MOD_SHIFT))
      hist = 2;
    if (timui_key_pressed(fr, TIMUI_KEY_ESCAPE) ||
        timui_key_pressed(fr, TIMUI_KEY_F10)) {
      timui_quit(ui);
      quit = 1;
    }
    enter = draw_composer(fr, root.x, input_y, root.w, text, bu, &tlen);
  }
  timui_end(fr);
  if (timui_should_quit(ui))
    quit = 1;
  {
    const char *typed = bu ? bu->composer : "";
    Term out;
    out = birc_frame_out(e, ui, quit, enter, typed, tlen, rows, tab, click, up,
                         dn, hist);
    if (enter && bu) {
      bu->composer[0] = '\0';
      bu->st.cursor = 0;
      bu->st.scroll_y = 0;
    }
    free(input);
    return out;
  }
}

static void __attribute__((constructor)) timui_frame_use(void) {
  io_eff(CID_TIMUI_FRAME, timui_frame_run, 0);
}

/* ---- Timui.close : Ui -> IO(Unit) ------------------------------------- */

Term timui_close_run(Env e, Term *f, IoWork *w) {
  Timui *ui = (Timui *)(uintptr_t)io_hand_v(f[0]);
  BircUi *st = birc_state(ui);
  (void)e;
  (void)w;
  if (ui == birc_ui_live)
    birc_ui_live = NULL;
  if (ui)
    timui_close(ui);
  free(st);
  return term_pak(CID_UNIT, 0);
}

static void __attribute__((constructor)) timui_close_use(void) {
  io_eff(CID_TIMUI_CLOSE, timui_close_run, 0);
}

#endif /* BIRC_TIMUI_FFI_C */
