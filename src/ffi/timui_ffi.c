/* Bend TimUI foreign effects — thin open / frame / close / budget / config.
 * TIMUI_IMPLEMENTATION once. Include-guarded for multi-import. */
#ifndef BIRC_TIMUI_FFI_C
#define BIRC_TIMUI_FFI_C
#include <errno.h>
#include <poll.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#ifndef TIMUI_IMPLEMENTATION
#define TIMUI_IMPLEMENTATION
#endif
#include "timui.h"
typedef struct {
  char composer[512];
  TimuiTextAreaState st;
  int wake_dead;
  int poke_rd;
  int poke_wr;
} BircUi;
static BircUi *birc_state(const Timui *ui) {
  return ui ? (BircUi *)timui_userdata(ui) : NULL;
}
#include "birc_utf8_fit.h"
static Timui *birc_ui_live;
static void birc_ui_atexit(void) {
  Timui *ui = birc_ui_live;
  birc_ui_live = NULL;
  if (ui)
    timui_restore_terminal(ui);
}
#ifdef CID_UIKEYS
static Term birc_uikeys(Env e, int quit, int enter, const char *typed,
                        size_t tlen, uint32_t rows, uint32_t cols, uint32_t tab,
                        uint32_t click, uint32_t up, uint32_t dn,
                        uint32_t hist) {
  Loc l = heap_alloc(e, cls_fit(10));
  e.mem[l + 0] = io_seal(e, (Term)(uint64_t)(quit ? 1u : 0u), CID_UIKEYS);
  e.mem[l + 1] = io_seal(e, (Term)(uint64_t)(enter ? 1u : 0u), CID_UIKEYS);
  e.mem[l + 2] = io_seal(e, io_str(e, typed ? typed : "", tlen), CID_UIKEYS);
  e.mem[l + 3] = io_seal(e, (Term)(uint64_t)rows, CID_UIKEYS);
  e.mem[l + 4] = io_seal(e, (Term)(uint64_t)cols, CID_UIKEYS);
  e.mem[l + 5] = io_seal(e, (Term)(uint64_t)tab, CID_UIKEYS);
  e.mem[l + 6] = io_seal(e, (Term)(uint64_t)click, CID_UIKEYS);
  e.mem[l + 7] = io_seal(e, (Term)(uint64_t)up, CID_UIKEYS);
  e.mem[l + 8] = io_seal(e, (Term)(uint64_t)dn, CID_UIKEYS);
  e.mem[l + 9] = io_seal(e, (Term)(uint64_t)hist, CID_UIKEYS);
  return term_ctr(CID_UIKEYS, l);
}
static Term birc_frame_out(Env e, Timui *ui, int quit, int enter,
                           const char *typed, size_t tlen, uint32_t rows,
                           uint32_t cols, uint32_t tab, uint32_t click,
                           uint32_t up, uint32_t dn, uint32_t hist) {
  return io_tup(e, io_hand((uint64_t)(uintptr_t)ui),
                birc_uikeys(e, quit, enter, typed, tlen, rows, cols, tab, click,
                            up, dn, hist));
}
#endif
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
  st->poke_rd = st->poke_wr = -1;
  {
    int pfd[2];
    if (pipe(pfd) == 0) {
      st->poke_rd = pfd[0];
      st->poke_wr = pfd[1];
    }
  }
  cfg.title = "birc";
  cfg.flags = TIMUI_FLAG_ALT_SCREEN | TIMUI_FLAG_RESTORE_ON_EXIT |
              TIMUI_FLAG_MOUSE | TIMUI_FLAG_BRACKETED_PASTE;
  cfg.theme = TIMUI_THEME_MODERN_DARK;
  cfg.userdata = st;
  cfg.input_poll_ms = 0;
  if (timui_open(&cfg, &ui) != TIMUI_OK) {
    free(st);
    return io_fail(e, 1u, "timui_open failed");
  }
  timui_full_redraw(ui);
  birc_ui_live = ui;
  atexit(birc_ui_atexit);
  return io_done(e, io_hand((uint64_t)(uintptr_t)ui));
}
static void __attribute__((constructor)) timui_open_use(void) {
  io_eff(CID_TIMUI_OPEN, timui_open_run, 0);
}
static size_t birc_clip_cols(const char *s, size_t n, int x, int maxx, int *out_w) {
  size_t i = 0;
  int cx = x;
  if (!s)
    n = 0;
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
  if (out_w)
    *out_w = cx - x;
  return i;
}
static int birc_put_span(TimuiFrame *fr, int x, int y, int maxx, const char *p,
                         size_t n, uint32_t fg, uint32_t attrs, const char *uri) {
  int w = 0;
  TimuiStyle st;
  if (!fr || n == 0 || x >= maxx)
    return x;
  n = birc_clip_cols(p, n, x, maxx, &w);
  if (n == 0)
    return x;
  st = timui_style_make(fg, TIMUI_COLOR_DEFAULT, attrs);
  if (uri)
    timui_label_hyperlink(fr, x, y, (TimuiStr){p, n}, uri, st);
  else
    timui_label(fr, x, y, (TimuiStr){p, n}, st);
  return x + w;
}
static int birc_put_link(TimuiFrame *fr, int x, int y, int maxx, const char *url,
                         size_t ulen, const char *text, size_t tlen,
                         uint32_t fg) {
  char uri[512];
  if (!fr || tlen == 0 || x >= maxx)
    return x;
  if (ulen >= sizeof uri)
    return birc_put_span(fr, x, y, maxx, text, tlen, fg, 0, NULL);
  memcpy(uri, url, ulen);
  uri[ulen] = '\0';
  return birc_put_span(fr, x, y, maxx, text, tlen, fg, TIMUI_ATTR_UNDERLINE, uri);
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
    nlen = birc_utf8_fit(s ? s : "", (size_t)len < 63 ? (size_t)len : (size_t)63);
    if (s && nlen > 0)
      memcpy(store[n], s, nlen);
    store[n][nlen] = '\0';
    labs[n] = store[n];
    free(s);
    n++;
  }
  return n;
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
      char *url = io_cstr(e, f[0], &ulen);
      char *text = io_cstr(e, f[1], &tlen);
      x = birc_put_link(fr, x, y, maxx, url ? url : "", (size_t)ulen,
                        text ? text : "", (size_t)tlen, fg);
      free(url);
      free(text);
    } else if (cid == CID_VIEW_SPN) {
      u64 tlen = 0;
      char *text = io_cstr(e, f[1], &tlen);
      x = birc_put_span(fr, x, y, maxx, text ? text : "", (size_t)tlen, fg,
                        (uint32_t)f[0], NULL);
      free(text);
    }
    spare_free(e, cls_fit(2), loc);
  }
  return x;
}
typedef struct {
  TimuiCellBuffer *buf;
  TimuiStyle border;
  TimuiRect root;
  uint32_t *click;
} BircLay;
static void rect_from(Term *f, TimuiRect *r) {
  r->x = (int)(uint32_t)f[0];
  r->y = (int)(uint32_t)f[1];
  r->w = (int)(uint32_t)f[2];
  r->h = (int)(uint32_t)f[3];
}
static void birc_draw_line(Env e, TimuiFrame *fr, int x, int y, int maxx,
                           uint32_t fg, Term ts_t, Term spans) {
  u64 tslen = 0;
  char *ts = io_cstr(e, ts_t, &tslen);
  if (fr && ts && tslen > 0) {
    int tw = 0;
    (void)birc_clip_cols(ts, (size_t)tslen, 0, 100000, &tw);
    timui_label(fr, x, y, (TimuiStr){ts, (size_t)tslen},
                timui_style_make(0xa0a0a0u, TIMUI_COLOR_DEFAULT, 0));
    x += tw + 1;
  }
  free(ts);
  (void)birc_draw_spans(e, fr, x, y, maxx, fg, spans);
}
static void birc_draw_op(Env e, TimuiFrame *fr, Term op, BircLay *ly) {
  u64 cid = term_aux(op);
  if (cid == CID_VIEW_OPBOX) {
    Term f[4];
    Loc loc = ctr_take(e, op, 4, f);
    TimuiRect r;
    rect_from(f, &r);
    if (ly && r.y + r.h > ly->root.y + ly->root.h)
      r.h = ly->root.y + ly->root.h - r.y;
    if (fr && ly && r.h > 0 && r.w > 2)
      timui_draw_box(ly->buf, r, TIMUI_BORDER_ROUND, ly->border);
    spare_free(e, cls_fit(4), loc);
  } else if (cid == CID_VIEW_OPTEXT) {
    Term f[6];
    Loc loc = ctr_take(e, op, 6, f);
    int x = (int)(uint32_t)f[0];
    int y = (int)(uint32_t)f[1];
    int w = (int)(uint32_t)f[2];
    u64 n = 0;
    char *s = io_cstr(e, f[5], &n);
    (void)birc_put_span(fr, x, y, x + w, s ? s : "", (size_t)n, (uint32_t)f[3],
                        (uint32_t)f[4], NULL);
    free(s);
    spare_free(e, cls_fit(6), loc);
  } else if (cid == CID_VIEW_OPTABS) {
    Term f[5];
    Loc loc = ctr_take(e, op, 5, f);
    TimuiRect r;
    char store[16][64];
    const char *labs[16];
    int ntabs, orig, sel;
    r.x = (int)(uint32_t)f[0];
    r.y = (int)(uint32_t)f[1];
    r.w = (int)(uint32_t)f[2];
    r.h = 1;
    ntabs = birc_str_list(e, f[4], store, labs, 16);
    orig = (int)(uint32_t)f[3];
    sel = orig < 0 ? 0 : orig;
    if (ntabs > 0 && sel >= ntabs)
      sel = ntabs - 1;
    orig = sel;
    if (fr && ntabs > 0)
      (void)timui_tabs(fr, TIMUI_ID("birc.bufs"), r, labs, ntabs, &sel);
    if (ly && sel != orig && sel >= 0 && sel < ntabs)
      *ly->click = (uint32_t)sel + 1u;
    spare_free(e, cls_fit(5), loc);
  } else if (cid == CID_VIEW_OPLINE) {
    Term f[6];
    Loc loc = ctr_take(e, op, 6, f);
    int x = (int)(uint32_t)f[0];
    int y = (int)(uint32_t)f[1];
    int w = (int)(uint32_t)f[2];
    birc_draw_line(e, fr, x, y, x + w, (uint32_t)f[3], f[4], f[5]);
    spare_free(e, cls_fit(6), loc);
  }
}
static void birc_draw_ops(Env e, TimuiFrame *fr, Term xs, BircLay *ly) {
  while (term_aux(xs) == CID_CON) {
    Term rest;
    Term op = birc_cons_head(e, xs, &rest);
    xs = rest;
    birc_draw_op(e, fr, op, ly);
  }
}
static void birc_drop_ops(Env e, Term xs) {
  birc_draw_ops(e, NULL, xs, NULL);
}
#endif /* CID_CON */
static int draw_composer(TimuiFrame *fr, int x, int y, int width, TimuiStyle st,
                         BircUi *stt, size_t *tlen) {
  TimuiId id;
  TimuiRect r;
  TimuiTextAreaResult res;
  int prompt_w;
  size_t n;
  (void)st;
  if (!fr || !stt)
    return 0;
  prompt_w = width > 2 ? 2 : 0;
  if (prompt_w > 0)
    timui_label(fr, x, y, (TimuiStr){"> ", 2}, st);
  id = TIMUI_ID("birc.composer");
  if (timui_focus(fr) != id)
    timui_set_focus(fr, id);
  r.x = x + prompt_w;
  r.y = y;
  r.w = width - prompt_w;
  if (r.w < 1)
    r.w = 1;
  r.h = 1;
  res = timui_text_area_mut(fr, id, r, &stt->st, TIMUI_TEXT_AREA_ENTER_SUBMITS);
  n = strlen(stt->composer);
  *tlen = birc_utf8_fit(stt->composer, n);
  return res.submitted ? 1 : 0;
}
static void birc_wait_fds(Timui *ui, uint32_t wait_ms, uint32_t wake_fd) {
  struct pollfd p[3];
  nfds_t n = 0;
  int r, wake_i = -1, poke_i = -1, tty, timeout;
  BircUi *bu = birc_state(ui);
  char dump;
  if (!ui)
    return;
  if (wake_fd == 0u && bu)
    bu->wake_dead = 0;
  tty = ui->fd.read_fd;
  if (tty >= 0) {
    p[n].fd = tty;
    p[n].events = POLLIN;
    p[n++].revents = 0;
  }
  if (wake_fd > 0u && (int)wake_fd != tty && (int)wake_fd >= 0 &&
      (!bu || !bu->wake_dead)) {
    wake_i = (int)n;
    p[n].fd = (int)wake_fd;
    p[n].events = POLLIN;
    p[n++].revents = 0;
  }
  if (bu && bu->poke_rd >= 0) {
    poke_i = (int)n;
    p[n].fd = bu->poke_rd;
    p[n].events = POLLIN;
    p[n++].revents = 0;
  }
  if (n == 0)
    return;
  timeout = wait_ms > 2147483647u ? -1 : (int)wait_ms;
  do {
    r = poll(p, n, timeout);
  } while (r == -1 && errno == EINTR);
  if (r > 0 && wake_i >= 0 &&
      (p[wake_i].revents & (POLLERR | POLLHUP | POLLNVAL))) {
    if (bu)
      bu->wake_dead = 1;
    if (!(p[wake_i].revents & POLLIN) && tty >= 0) {
      p[0].fd = tty;
      p[0].events = POLLIN;
      p[0].revents = 0;
      do {
        r = poll(p, 1, timeout);
      } while (r == -1 && errno == EINTR);
    }
  }
  if (r > 0 && poke_i >= 0 && (p[poke_i].revents & POLLIN))
    (void)read(bu->poke_rd, &dump, 1);
}
Term timui_frame_run(Env e, Term *f, IoWork *w) {
  Timui *ui = (Timui *)(uintptr_t)io_hand_v(f[0]);
  Term ops = f[1];
  uint64_t n_in = 0;
  char *input = io_cstr(e, f[2], &n_in);
  u32 seed = (u32)f[3];
  u32 page = (u32)f[4];
  u32 wait_ms = (u32)f[5];
  u32 wake_fd = (u32)f[6];
  TimuiFrame *fr = NULL;
  BircUi *bu = birc_state(ui);
  int quit = 0;
  int enter = 0;
  uint32_t rows = 24;
  uint32_t cols = 80;
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
#ifdef CID_CON
    birc_drop_ops(e, ops);
#endif
    return birc_frame_out(e, NULL, 1, 0, "", 0, 24, 80, 0, 0, 0, 0, 0);
  }
  birc_wait_fds(ui, wait_ms, wake_fd);
  if (!timui_begin(ui, &fr)) {
    free(input);
#ifdef CID_CON
    birc_drop_ops(e, ops);
#endif
    return birc_frame_out(e, ui, 1, 0, "", 0, 24, 80, 0, 0, 0, 0, 0);
  }
  {
    TimuiRect root = timui_root(fr);
    TimuiCellBuffer *buf = timui_frame_buffer(fr);
    TimuiStyle panel = timui_theme_style(&ui->theme, TIMUI_SLOT_PANEL);
    TimuiStyle text = timui_theme_style(&ui->theme, TIMUI_SLOT_TEXT);
    TimuiStyle border = timui_theme_style(&ui->theme, TIMUI_SLOT_BORDER);
    int input_y = root.h >= 1 ? root.y + root.h - 1 : root.y;
    BircLay ly;
    rows = root.h < 4 ? 4u : (uint32_t)root.h;
    cols = root.w < 1 ? 1u : (uint32_t)root.w;
    ly.buf = buf;
    ly.border = border;
    ly.root = root;
    ly.click = &click;
    timui_draw_fill(buf, root, panel);
#ifdef CID_CON
    birc_draw_ops(e, fr, ops, &ly);
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
    if (page < 1u)
      page = 1u;
    if (timui_key_pressed(fr, TIMUI_KEY_PAGE_UP))
      up = page;
    if (timui_key_pressed(fr, TIMUI_KEY_PAGE_DOWN))
      dn = page;
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
    out = birc_frame_out(e, ui, quit, enter, typed, tlen, rows, cols, tab, click,
                         up, dn, hist);
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
Term timui_close_run(Env e, Term *f, IoWork *w) {
  Timui *ui = (Timui *)(uintptr_t)io_hand_v(f[0]);
  BircUi *st = birc_state(ui);
  (void)e;
  (void)w;
  if (ui == birc_ui_live)
    birc_ui_live = NULL;
  if (st) {
    if (st->poke_rd >= 0)
      (void)close(st->poke_rd);
    if (st->poke_wr >= 0)
      (void)close(st->poke_wr);
  }
  if (ui)
    timui_close(ui);
  free(st);
  return term_pak(CID_UNIT, 0);
}
static void __attribute__((constructor)) timui_close_use(void) {
  io_eff(CID_TIMUI_CLOSE, timui_close_run, 0);
}
#ifdef CID_WAKE_POKE
Term wake_poke_run(Env e, Term *f, IoWork *w) {
  BircUi *bu = birc_ui_live ? birc_state(birc_ui_live) : NULL;
  char z = 0;
  (void)e;
  (void)f;
  (void)w;
  if (bu && bu->poke_wr >= 0)
    (void)write(bu->poke_wr, &z, 1);
  return term_pak(CID_UNIT, 0);
}
static void __attribute__((constructor)) wake_poke_use(void) {
  io_eff(CID_WAKE_POKE, wake_poke_run, 0);
}
#endif
#endif /* BIRC_TIMUI_FFI_C */
