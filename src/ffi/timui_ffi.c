/* Bend TimUI foreign effects — open, frame, close, tty watch, and winch.
 * TIMUI_IMPLEMENTATION once. Include-guarded for multi-import. */
#ifndef BIRC_TIMUI_FFI_C
#define BIRC_TIMUI_FFI_C
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#ifndef TIMUI_IMPLEMENTATION
#define TIMUI_IMPLEMENTATION
#endif
#include "timui.h"

#ifndef Loc
typedef uint64_t Loc;
#endif

#ifndef CID_UIKEYS
#define CID_UIKEYS CID(UiKeys)
#endif
#ifndef CID_TIMUI_OPEN
#define CID_TIMUI_OPEN CID(Timui.open)
#endif
#ifndef CID_TIMUI_FRAME
#define CID_TIMUI_FRAME CID(Timui.frame)
#endif
#ifndef CID_TIMUI_REDRAW_READY
#define CID_TIMUI_REDRAW_READY CID(Timui.redraw_ready)
#endif
#ifndef CID_TIMUI_CLOSE
#define CID_TIMUI_CLOSE CID(Timui.close)
#endif
#ifndef CID_TIMUI_ISATTY
#define CID_TIMUI_ISATTY CID(Timui.isatty)
#endif
#ifndef CID_TIMUI_TTY
#define CID_TIMUI_TTY CID(Timui.tty)
#endif
#ifndef CID_TTY_READY
#define CID_TTY_READY CID(Tty.ready)
#endif
#ifndef CID_TTY_CLOSE
#define CID_TTY_CLOSE CID(Tty.close)
#endif
#ifndef CID_WINCH_OPEN
#define CID_WINCH_OPEN CID(Winch.open)
#endif
#ifndef CID_WINCH_READY
#define CID_WINCH_READY CID(Winch.ready)
#endif
#ifndef CID_WINCH_CLOSE
#define CID_WINCH_CLOSE CID(Winch.close)
#endif
#ifndef CID_SYS_OPEN_PROGRAM
#define CID_SYS_OPEN_PROGRAM CID(Sys.open_program)
#endif
#ifndef CID_SYS_CLIPBOARD_PROGRAM
#define CID_SYS_CLIPBOARD_PROGRAM CID(Sys.clipboard_program)
#endif
#ifndef CID_SYS_EXIT_DONE
#define CID_SYS_EXIT_DONE CID(Sys.exit_done)
#endif
#ifndef CID_SYS_EXIT_FAIL
#define CID_SYS_EXIT_FAIL CID(Sys.exit_fail)
#endif

/* An IRC record is at most 512 octets, but Latin-1 fallback can expand
 * every octet to two UTF-8 bytes. Never truncate a decoded click target. */
enum { BIRC_URL_CAP = 1025 };

typedef struct {
  int active;       /* 1 if selection exists */
  int dragging;     /* 1 if left mouse button is pressed and held */
  int start_x, start_y;
  int cur_x, cur_y;
  TimuiRect pane;   /* bounds of pane where drag started */
} BircSel;

typedef struct {
  TimuiImage *image;
  char path[4096];
  size_t path_len;
} BircPreview;

typedef struct {
  char composer[512];
  TimuiTextAreaState st;
  int last_tab;
  uint32_t last_bell_seq;
  int bell_seen;
  int bell_pending;
  char link_url[BIRC_URL_CAP];
  char *clipboard;
  TimuiRect body_inner[2];
  int body_count;
  TimuiRect nicks_inner;
  BircSel sel;
  int profile_enabled;
  uint64_t profile_frames;
  uint64_t profile_prepare_ns;
  uint64_t profile_begin_ns;
  uint64_t profile_draw_ns;
  uint64_t profile_end_ns;
  BircPreview previews[2];
  int preview_count;
} BircUi;
static BircUi *birc_state(const Timui *ui) {
  return ui ? (BircUi *)timui_userdata(ui) : NULL;
}
#include "birc_utf8_fit.h"
static Timui *birc_ui_live;

/* Input and output can have separate descriptions. Make the write target
 * nonblocking for the whole budget, then restore exactly its saved flags. */
static void birc_write_bounded(TimuiFdCtx *ctx, int fd, const void *data, size_t size,
                               uint64_t deadline) {
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags >= 0 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0) {
    if (ctx)
      (void)timui_fd_write_(ctx, data, size, 1, deadline);
    else
      (void)timui_write_all_until_(fd, data, size, deadline);
    (void)fcntl(fd, F_SETFL, flags);
  }
}

static uint64_t birc_profile_now_ns(void) {
  struct timespec ts;
  if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
    return 0;
  return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static uint64_t birc_profile_us(uint64_t ns, uint64_t frames) {
  return frames > 0 ? ns / frames / 1000ULL : 0;
}

static TimuiImage *birc_preview_load(Timui *ui, const char *path) {
  unsigned char *data = NULL;
  TimuiImage *img = NULL;
  struct stat st;
  size_t size;
  size_t off = 0;
  int fd;
  if (!ui || !path || path[0] == '\0')
    return NULL;
  fd = open(path, O_RDONLY | O_NONBLOCK);
  if (fd < 0)
    return NULL;
  if (fcntl(fd, F_SETFD, FD_CLOEXEC) < 0 || fstat(fd, &st) < 0 ||
      !S_ISREG(st.st_mode) || st.st_size <= 0 ||
      (uintmax_t)st.st_size > (uintmax_t)TIMUI_IMAGE_PNG_MAX_BYTES) {
    (void)close(fd);
    return NULL;
  }
  size = (size_t)st.st_size;
  data = (unsigned char *)malloc(size);
  if (!data) {
    (void)close(fd);
    return NULL;
  }
  while (off < size) {
    ssize_t got = read(fd, data + off, size - off);
    if (got > 0) {
      off += (size_t)got;
    } else if (got < 0 && errno == EINTR) {
      continue;
    } else {
      break;
    }
  }
  (void)close(fd);
  if (off == size)
    img = timui_image_from_png(ui, data, size);
  free(data);
  return img;
}

static void birc_preview_set(BircPreview *preview, Timui *ui, const char *path,
                             size_t path_len) {
  if (!preview || !ui || !path || path_len == 0 ||
      path_len >= sizeof preview->path || memchr(path, '\0', path_len))
    return;
  if (preview->image && preview->path_len == path_len &&
      memcmp(preview->path, path, path_len) == 0)
    return;
  if (preview->image) {
    timui_image_free(ui, preview->image);
    preview->image = NULL;
  }
  memcpy(preview->path, path, path_len);
  preview->path[path_len] = '\0';
  preview->path_len = path_len;
  preview->image = birc_preview_load(ui, preview->path);
}

static int birc_winch_rd = -1;
static void birc_ui_atexit(void) {
  Timui *ui = birc_ui_live;
  birc_ui_live = NULL;
  if (ui) {
    if (ui->fd.write_fd >= 0)
      birc_write_bounded(&ui->fd, ui->fd.write_fd, "\x1b[?1002l", 8, timui_now_ms());
    timui_restore_terminal(ui);
  }
}
static Term birc_uikeys(Env e, Timui *ui, int enter, const char *typed,
                        size_t tlen, uint32_t rows, uint32_t cols,
                        uint32_t click, uint32_t key, uint32_t mods,
                        uint32_t codepoint, uint32_t wheel, uint32_t more,
                        const char *url, const char *clipboard) {
  Loc l = heap_alloc(e, cls_fit(12));
  e.mem[l + 0] = io_seal(e, (Term)(uint64_t)(enter ? 1u : 0u), CID_UIKEYS);
  e.mem[l + 1] = io_seal(e, io_str(e, typed, tlen), CID_UIKEYS);
  e.mem[l + 2] = io_seal(e, (Term)(uint64_t)rows, CID_UIKEYS);
  e.mem[l + 3] = io_seal(e, (Term)(uint64_t)cols, CID_UIKEYS);
  e.mem[l + 4] = io_seal(e, (Term)(uint64_t)click, CID_UIKEYS);
  e.mem[l + 5] = io_seal(e, (Term)(uint64_t)key, CID_UIKEYS);
  e.mem[l + 6] = io_seal(e, (Term)(uint64_t)mods, CID_UIKEYS);
  e.mem[l + 7] = io_seal(e, (Term)(uint64_t)codepoint, CID_UIKEYS);
  e.mem[l + 8] = io_seal(e, (Term)(uint64_t)wheel, CID_UIKEYS);
  e.mem[l + 9] = io_seal(e, (Term)(uint64_t)more, CID_UIKEYS);
  e.mem[l + 10] = io_seal(e, io_str(e, url, strlen(url)), CID_UIKEYS);
  e.mem[l + 11] = io_seal(e, io_str(e, clipboard, strlen(clipboard)), CID_UIKEYS);
  return io_tup(e, io_hand((uint64_t)(uintptr_t)ui), term_ctr(CID_UIKEYS, l));
}
Term timui_open_run(Env e, Term *f, IoWork *w) {
  TimuiConfig cfg = TIMUI_CONFIG_INIT;
  Timui *ui = NULL;
  BircUi *st;
  (void)f;
  (void)w;
  st = (BircUi *)calloc(1, sizeof(BircUi));
  if (!st) return io_fail(e, 1u, "timui_open failed");
  st->st.text = st->composer;
  st->st.cap = sizeof st->composer;
  st->last_tab = -1;
  st->profile_enabled = getenv("BIRC_FRAME_PROFILE") != NULL;
  cfg.title = "birc";
  cfg.flags = TIMUI_FLAG_ALT_SCREEN | TIMUI_FLAG_RESTORE_ON_EXIT |
              TIMUI_FLAG_BRACKETED_PASTE | TIMUI_FLAG_MOUSE;
  cfg.theme = TIMUI_THEME_MODERN_DARK;
  cfg.userdata = st;
  cfg.input_poll_ms = 0;
  TimuiResult tr = timui_open(&cfg, &ui);
  if (tr != TIMUI_OK) {
    free(st);
    return io_fail(e, (u32)tr, "timui_open failed");
  }
  if (getenv("BIRC_FORCE_IMAGE_PROTOCOL") &&
      strcmp(getenv("BIRC_FORCE_IMAGE_PROTOCOL"), "kitty") == 0)
    timui_force_image_protocol(ui, TIMUI_IMAGE_PROTOCOL_KITTY);
  if (ui && ui->fd.write_fd >= 0)
    birc_write_bounded(&ui->fd, ui->fd.write_fd, "\x1b[?1002h", 8, timui_now_ms() + 40u);
  for (int i = 0; i < TIMUI_SLOT_COUNT; i++) {
    if (i != TIMUI_SLOT_SELECTION && i != TIMUI_SLOT_BUTTON_ACTIVE) {
      ui->theme.slots[i].bg = TIMUI_COLOR_DEFAULT;
    }
  }
  timui_full_redraw(ui);
  birc_ui_live = ui;
  atexit(birc_ui_atexit);
  if (getenv("BIRC_DIE_AFTER_OPEN"))
    exit(1);
  return io_done(e, io_hand((uint64_t)(uintptr_t)ui));
}
static void __attribute__((constructor)) timui_open_use(void) {
  io_eff(CID_TIMUI_OPEN, timui_open_run, 0);
}
static size_t birc_clip_cols(const char *s, size_t n, int x, int maxx, int *out_w) {
  size_t i = 0;
  int cx = x;
  if (!s) n = 0;
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
  if (!fr || n == 0 || x >= maxx) return x;
  n = birc_clip_cols(p, n, x, maxx, &w);
  if (n == 0) return x;
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
  char uri[BIRC_URL_CAP];
  int end;
  if (!fr || tlen == 0 || x >= maxx) return x;
  if (ulen >= sizeof uri)
    return birc_put_span(fr, x, y, maxx, text, tlen, fg, 0, NULL);
  memcpy(uri, url, ulen);
  uri[ulen] = '\0';
  end = birc_put_span(fr, x, y, maxx, text, tlen, fg, TIMUI_ATTR_UNDERLINE, uri);
  if (fr->ui && fr->ui->ia.mouse_released && fr->ui->ia.mouse_y == y &&
      fr->ui->ia.mouse_x >= x && fr->ui->ia.mouse_x < end) {
    BircUi *bu = birc_state(fr->ui);
    if (bu)
      memcpy(bu->link_url, uri, ulen + 1);
  }
  return end;
}
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
    nlen = birc_utf8_fit(s, (size_t)len < 63 ? (size_t)len : (size_t)63);
    if (nlen > 0)
      memcpy(store[n], s, nlen);
    store[n][nlen] = '\0';
    labs[n] = store[n];
    free(s);
    n++;
  }
  term_sink(e, xs);
  return n;
}
static int birc_u32_list(Env e, Term xs, uint32_t *vals, int max) {
  int n = 0;
  while (n < max && term_aux(xs) == CID_CON) {
    Term tail;
    Term head = birc_cons_head(e, xs, &tail);
    xs = tail;
    vals[n++] = (uint32_t)head;
  }
  term_sink(e, xs);
  return n;
}
static void birc_bell_update(BircUi *bu, uint32_t enabled, uint32_t seq) {
  if (!bu) return;
  if (bu->bell_seen && enabled != 0 && seq != bu->last_bell_seq)
    bu->bell_pending = 1;
  bu->last_bell_seq = seq;
  bu->bell_seen = 1;
}
static void birc_draw_tab_alerts(TimuiFrame *fr, TimuiRect r,
                                 const char *const *labels, int ntabs,
                                 const uint32_t *alerts, int nalerts, int sel) {
  TimuiTabSpan spans[16];
  int i, scroll;
  if (!fr || !labels || !alerts || ntabs <= 0 || r.w <= 0)
    return;
  (void)timui_tabs_layout(labels, ntabs, 1, spans, 16);
  scroll = timui_tabs_scroll(spans, ntabs, sel, r.w, 0);
  timui_push_clip(fr, r);
  for (i = 0; i < ntabs && i < nalerts; i++) {
    TimuiStyle style;
    TimuiRect box;
    int sx;
    if (i == sel || alerts[i] == 0 || !timui_tab_visible(spans[i], scroll, r.w))
      continue;
    sx = r.x + spans[i].x - scroll;
    box = TIMUI_RECT(sx, r.y, spans[i].w, 1);
    if (alerts[i] >= 2)
      style = timui_style_make(0x1E1E2Eu, 0xFFD700u, TIMUI_ATTR_BOLD);
    else
      style = timui_style_make(TIMUI_COLOR_DEFAULT, TIMUI_COLOR_DEFAULT,
                               TIMUI_ATTR_REVERSE);
    timui_draw_fill(timui_frame_buffer(fr), box, style);
    timui_label(fr, sx + 1, r.y, timui_str_from_cstr(labels[i]), style);
  }
  timui_pop_clip(fr);
}
static int birc_draw_spans(Env e, TimuiFrame *fr, int x, int y, int maxx,
                           uint32_t fg, Term xs) {
  while (term_aux(xs) == CID_CON) {
    Term rest, f[3];
    Term sp = birc_cons_head(e, xs, &rest);
    u64 cid = term_aux(sp);
    xs = rest;
    if (cid == CID_VIEW_COL) {
      Loc loc = ctr_take(e, sp, 3, f);
      u64 tlen = 0;
      char *text = io_cstr(e, f[2], &tlen);
      x = birc_put_span(fr, x, y, maxx, text, (size_t)tlen, (uint32_t)f[1],
                        (uint32_t)f[0], NULL);
      free(text);
      spare_free(e, cls_fit(3), loc);
    } else {
      Loc loc = ctr_take(e, sp, 2, f);
      if (cid == CID_VIEW_LNK) {
        u64 ulen = 0, tlen = 0;
        char *url = io_cstr(e, f[0], &ulen);
        char *text = io_cstr(e, f[1], &tlen);
        x = birc_put_link(fr, x, y, maxx, url, (size_t)ulen, text, (size_t)tlen,
                          fg);
        free(url);
        free(text);
      } else if (cid == CID_VIEW_SPN) {
        u64 tlen = 0;
        char *text = io_cstr(e, f[1], &tlen);
        x = birc_put_span(fr, x, y, maxx, text, (size_t)tlen, fg,
                          (uint32_t)f[0], NULL);
        free(text);
      }
      spare_free(e, cls_fit(2), loc);
    }
  }
  return x;
}
typedef struct {
  TimuiCellBuffer *buf;
  TimuiStyle border;
  TimuiRect root;
  uint32_t *click;
  BircUi *bu;
  Timui *ui;
} BircLay;
static void birc_draw_op(Env e, TimuiFrame *fr, Term op, BircLay *ly) {
  u64 cid = term_aux(op);
  if (cid == CID_VIEW_OPBOX) {
    Term f[4];
    Loc loc = ctr_take(e, op, 4, f);
    TimuiRect r;
    r.x = (int)(uint32_t)f[0];
    r.y = (int)(uint32_t)f[1];
    r.w = (int)(uint32_t)f[2];
    r.h = (int)(uint32_t)f[3];
    if (ly && r.y + r.h > ly->root.y + ly->root.h)
      r.h = ly->root.y + ly->root.h - r.y;
    if (ly && ly->bu) {
      int i, body_box = 0;
      for (i = 0; i < ly->bu->body_count; i++) {
        TimuiRect in = ly->bu->body_inner[i];
        if (r.x == in.x - 1 && r.y == in.y - 1 &&
            r.w == in.w + 2 && r.h == in.h + 2)
          body_box = 1;
      }
      if (ly->bu->body_count == 0 && r.x == 0) {
        ly->bu->body_inner[0] = (TimuiRect){r.x + 1, r.y + 1,
          r.w > 2 ? r.w - 2 : 0, r.h > 2 ? r.h - 2 : 0};
        ly->bu->body_count = 1;
      } else if (!body_box) {
        ly->bu->nicks_inner = (TimuiRect){r.x + 1, r.y + 1,
          r.w > 2 ? r.w - 2 : 0, r.h > 2 ? r.h - 2 : 0};
      }
    }
    if (fr && ly && r.h > 0 && r.w > 2)
      timui_draw_box(ly->buf, r, TIMUI_BORDER_ROUND, ly->border);
    spare_free(e, cls_fit(4), loc);
  } else if (cid == CID_VIEW_OPSPLIT) {
    Term f[5];
    Loc loc = ctr_take(e, op, 5, f);
    TimuiRect area, panes[2];
    TimuiConstraint cons[2] = {TIMUI_FLEX(1), TIMUI_FLEX(1)};
    int axis = (int)(uint32_t)f[4];
    int made;
    area.x = (int)(uint32_t)f[0];
    area.y = (int)(uint32_t)f[1];
    area.w = (int)(uint32_t)f[2];
    area.h = (int)(uint32_t)f[3];
    made = axis == 0 ? timui_split_h(area, cons, 2, panes)
                     : timui_split_v(area, cons, 2, panes);
    if (ly && ly->bu && made == 2) {
      int i;
      ly->bu->body_count = 2;
      for (i = 0; i < 2; i++)
        ly->bu->body_inner[i] = (TimuiRect){panes[i].x + 1, panes[i].y + 1,
          panes[i].w > 2 ? panes[i].w - 2 : 0,
          panes[i].h > 2 ? panes[i].h - 2 : 0};
    }
    spare_free(e, cls_fit(5), loc);
  } else if (cid == CID_VIEW_OPTEXT) {
    Term f[6];
    Loc loc = ctr_take(e, op, 6, f);
    int x = (int)(uint32_t)f[0];
    int y = (int)(uint32_t)f[1];
    int w = (int)(uint32_t)f[2];
    u64 n = 0;
    char *s = io_cstr(e, f[5], &n);
    (void)birc_put_span(fr, x, y, x + w, s, (size_t)n, (uint32_t)f[3],
                        (uint32_t)f[4], NULL);
    free(s);
    spare_free(e, cls_fit(6), loc);
  } else if (cid == CID_VIEW_OPTABS) {
    Term f[8];
    Loc loc = ctr_take(e, op, 8, f);
    TimuiRect r;
    char store[16][64];
    const char *labs[16];
    uint32_t alerts[16] = {0};
    int ntabs, nalerts, orig, sel;
    r.x = (int)(uint32_t)f[0];
    r.y = (int)(uint32_t)f[1];
    r.w = (int)(uint32_t)f[2];
    r.h = 1;
    ntabs = birc_str_list(e, f[4], store, labs, 16);
    nalerts = birc_u32_list(e, f[5], alerts, 16);
    orig = (int)(uint32_t)f[3];
    sel = orig < 0 ? 0 : orig;
    if (ntabs > 0 && sel >= ntabs)
      sel = ntabs - 1;
    orig = sel;
    if (ly && ly->bu && ly->ui) {
      if (ly->bu->last_tab >= 0 && ly->bu->last_tab != orig) {
        timui_full_redraw(ly->ui);
      }
      ly->bu->last_tab = orig;
    }
    if (fr && ntabs > 0)
      (void)timui_tabs(fr, TIMUI_ID("birc.bufs"), r, labs, ntabs, &sel);
    birc_draw_tab_alerts(fr, r, labs, ntabs, alerts, nalerts, sel);
    if (ly && ly->bu)
      birc_bell_update(ly->bu, (uint32_t)f[6], (uint32_t)f[7]);
    if (ly && sel != orig && sel >= 0 && sel < ntabs)
      *ly->click = (uint32_t)sel + 1u;
    spare_free(e, cls_fit(8), loc);
  } else if (cid == CID_VIEW_OPLINE) {
    Term f[5];
    Loc loc = ctr_take(e, op, 5, f);
    int x = (int)(uint32_t)f[0];
    int y = (int)(uint32_t)f[1];
    int w = (int)(uint32_t)f[2];
    (void)birc_draw_spans(e, fr, x, y, x + w, (uint32_t)f[3], f[4]);
    spare_free(e, cls_fit(5), loc);
  } else if (cid == CID_VIEW_OPIMAGE) {
    Term f[5];
    Loc loc = ctr_take(e, op, 5, f);
    TimuiRect r;
    u64 n = 0;
    char *path = io_cstr(e, f[4], &n);
    BircPreview *preview = NULL;
    r.x = (int)(uint32_t)f[0];
    r.y = (int)(uint32_t)f[1];
    r.w = (int)(uint32_t)f[2];
    r.h = (int)(uint32_t)f[3];
    if (ly && ly->bu && ly->ui && ly->bu->preview_count < 2 &&
        n <= (u64)SIZE_MAX) {
      preview = &ly->bu->previews[ly->bu->preview_count++];
      birc_preview_set(preview, ly->ui, path, (size_t)n);
    }
    if (fr && preview && preview->image && r.w > 0 && r.h > 0)
      timui_image_draw_clipped(fr, preview->image, r, r);
    free(path);
    spare_free(e, cls_fit(5), loc);
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
/* A tty that stops reading must not park the only event-loop thread.
 * The first blocked frame waits a few ms; later frames fail at once
 * until a whole frame gets out. A dropped frame forces a full redraw. */
static uint64_t birc_frame_deadline;
static int birc_frame_short;
static int birc_tty_stalled;
static int birc_frame_disabled;

static int birc_output_ready(const Timui *ui) {
  struct pollfd pfd;
  if (!ui || ui->fd.write_fd < 0)
    return 0;
  pfd.fd = ui->fd.write_fd;
  pfd.events = POLLOUT;
  pfd.revents = 0;
  return poll(&pfd, 1, 0) > 0 && (pfd.revents & POLLOUT) != 0;
}

#if CID_TIMUI_REDRAW_READY
Term timui_redraw_ready_run(Env e, Term *f, IoWork *w) {
  Timui *ui = (Timui *)(uintptr_t)io_hand_v(f[0]);
  uint32_t ready = birc_tty_stalled && birc_output_ready(ui) ? 1u : 0u;
  (void)w;
  return io_tup(e, f[0], (Term)(uint64_t)ready);
}
static void __attribute__((constructor)) timui_redraw_ready_use(void) {
  io_eff(CID_TIMUI_REDRAW_READY, timui_redraw_ready_run, 0);
}
#endif

static int birc_frame_write(TimuiTransport *t, const void *data, size_t n) {
  TimuiFdCtx *c = (TimuiFdCtx *)t->ctx;
  int w;
  if (birc_frame_disabled || !c || n > 0x7fffffff) {
    birc_frame_short = 1;
    return -1;
  }
  w = timui_fd_write_(c, data, n, 1, birc_frame_deadline);
  if (w < 0 || (size_t)w < n || c->write_utf8_tail_len != 0)
    birc_frame_short = 1;
  return w;
}

/* One budget covers every write performed by a frame, including image
 * retirement, OSC 52, and BEL. A short write forces a later full redraw. */
static TimuiTransportWrite birc_output_begin(Timui *ui, int *saved_flags) {
  TimuiTransportWrite saved = ui->transport.write;
  int wait_ms = 40;
  birc_frame_short = 0;
  *saved_flags = fcntl(ui->fd.write_fd, F_GETFL, 0);
  birc_frame_disabled = *saved_flags < 0 ||
      fcntl(ui->fd.write_fd, F_SETFL, *saved_flags | O_NONBLOCK) < 0;
  /* Writable means some bytes fit, not that a complete repaint will fit.
   * A repair gets bounded headroom, never the former two-second UI stall. */
  if (birc_tty_stalled)
    wait_ms = birc_output_ready(ui) ? 200 : 0;
  birc_frame_deadline = timui_now_ms() + (uint64_t)wait_ms;
  ui->transport.write = birc_frame_write;
  return saved;
}

static void birc_output_end(Timui *ui, TimuiTransportWrite saved,
                           int saved_flags) {
  ui->transport.write = saved;
  if (saved_flags >= 0 && !birc_frame_disabled)
    (void)fcntl(ui->fd.write_fd, F_SETFL, saved_flags);
}

static inline int birc_pt_in_rect(int x, int y, TimuiRect r) {
  return x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h;
}

static inline int birc_clamp(int v, int min_v, int max_v) {
  if (v < min_v) return min_v;
  if (v > max_v) return max_v;
  return v;
}

static void birc_hold_ctrl_w(Timui *ui) {
  int ctrl_w;
  if (!ui) return;
  ctrl_w = ui->key_pressed == TIMUI_KEY_UNKNOWN &&
           (ui->key_mods & TIMUI_MOD_CTRL) != 0 &&
           (ui->key_codepoint == (uint32_t)'w' ||
            ui->key_codepoint == (uint32_t)'W');
  if (!ctrl_w) return;
  ui->key_in &= ~TIMUI_KEYIN_KILL_WORD;
  if (ui->edit_count > 0 &&
      ui->edit_ops[ui->edit_count - 1].kind == TIMUI_EDIT_KEY &&
      ui->edit_ops[ui->edit_count - 1].key == TIMUI_KEYIN_KILL_WORD)
    ui->edit_count--;
}

static void birc_copy_selection(Timui *ui, TimuiCellBuffer *buf, BircUi *bu) {
  int from_x, from_y, to_x, to_y;
  int min_x, max_x;
  size_t cap, len;
  char *out;
  if (!ui || !buf || !bu || !bu->sel.active) return;
  if (bu->sel.start_y < bu->sel.cur_y ||
      (bu->sel.start_y == bu->sel.cur_y && bu->sel.start_x <= bu->sel.cur_x)) {
    from_x = bu->sel.start_x; from_y = bu->sel.start_y;
    to_x = bu->sel.cur_x; to_y = bu->sel.cur_y;
  } else {
    from_x = bu->sel.cur_x; from_y = bu->sel.cur_y;
    to_x = bu->sel.start_x; to_y = bu->sel.start_y;
  }
  min_x = bu->sel.pane.x;
  max_x = bu->sel.pane.x + (bu->sel.pane.w > 0 ? bu->sel.pane.w - 1 : 0);
  cap = 4096;
  len = 0;
  out = (char *)malloc(cap);
  if (!out) return;

  for (int y = from_y; y <= to_y; y++) {
    int start_col = (y == from_y) ? from_x : min_x;
    int end_col = (y == to_y) ? to_x : max_x;
    char line[2048];
    size_t line_len = 0;
    for (int x = start_col; x <= end_col; x++) {
      TimuiCell *c;
      uint32_t cp;
      char utf8[8];
      int n;
      if (x < 0 || x >= buf->w || y < 0 || y >= buf->h) continue;
      c = &buf->cells[y * buf->w + x];
      if (c->flags & TIMUI_CELL_CONTINUATION) continue;
      cp = c->codepoint ? c->codepoint : (uint32_t)' ';
      n = timui_utf8_encode_(cp, utf8);
      if (n > 0 && line_len + (size_t)n < sizeof line) {
        memcpy(line + line_len, utf8, (size_t)n);
        line_len += (size_t)n;
      }
    }
    while (line_len > 0 && line[line_len - 1] == ' ')
      line_len--;
    if (y < to_y) {
      if (line_len + 1 < sizeof line) {
        line[line_len++] = '\n';
      }
    }
    if (line_len > 0) {
      if (len + line_len + 1 >= cap) {
        cap = (cap + line_len + 1) * 2;
        char *nout = (char *)realloc(out, cap);
        if (!nout) { free(out); return; }
        out = nout;
      }
      memcpy(out + len, line, line_len);
      len += line_len;
      out[len] = '\0';
    }
  }
  if (len > 0) {
    timui_clipboard_set(&ui->transport, (TimuiStr){out, len});
    /* Bend owns the external clipboard process outside this frame effect. */
    free(bu->clipboard);
    bu->clipboard = out;
    out = NULL;
  }
  free(out);
}

static void birc_render_selection(TimuiCellBuffer *buf, BircUi *bu) {
  int from_x, from_y, to_x, to_y;
  int min_x, max_x;
  if (!buf || !bu || !bu->sel.active) return;
  if (bu->sel.start_y < bu->sel.cur_y ||
      (bu->sel.start_y == bu->sel.cur_y && bu->sel.start_x <= bu->sel.cur_x)) {
    from_x = bu->sel.start_x; from_y = bu->sel.start_y;
    to_x = bu->sel.cur_x; to_y = bu->sel.cur_y;
  } else {
    from_x = bu->sel.cur_x; from_y = bu->sel.cur_y;
    to_x = bu->sel.start_x; to_y = bu->sel.start_y;
  }
  min_x = bu->sel.pane.x;
  max_x = bu->sel.pane.x + (bu->sel.pane.w > 0 ? bu->sel.pane.w - 1 : 0);
  for (int y = from_y; y <= to_y; y++) {
    int start_col = (y == from_y) ? from_x : min_x;
    int end_col = (y == to_y) ? to_x : max_x;
    for (int x = start_col; x <= end_col; x++) {
      if (x >= 0 && x < buf->w && y >= 0 && y < buf->h) {
        buf->cells[y * buf->w + x].attrs |= TIMUI_ATTR_REVERSE;
      }
    }
  }
}


static int draw_composer(TimuiFrame *fr, int x, int y, int width, TimuiStyle st,
                         BircUi *stt, size_t *tlen) {
  TimuiId id;
  TimuiRect r;
  TimuiTextAreaResult res;
  int prompt_w;
  size_t n;
  if (!fr || !stt) return 0;
  (void)st;
  prompt_w = width > 2 ? 2 : 0;
  if (prompt_w > 0) {
    TimuiStyle p_st = timui_style_make(0xFFD700, TIMUI_COLOR_DEFAULT, 0);
    timui_label(fr, x, y, (TimuiStr){"❯ ", 4}, p_st);
  }
  id = TIMUI_ID("birc.composer");
  if (timui_focus(fr) != id) timui_set_focus(fr, id);
  r.x = x + prompt_w;
  r.y = y;
  r.w = width - prompt_w;
  if (r.w < 1) r.w = 1;
  r.h = 1;
  res = timui_text_area_mut(fr, id, r, &stt->st, TIMUI_TEXT_AREA_ENTER_SUBMITS);
  n = strlen(stt->composer);
  *tlen = n;
  return res.submitted ? 1 : 0;
}
Term timui_frame_run(Env e, Term *f, IoWork *w) {
  Timui *ui = (Timui *)(uintptr_t)io_hand_v(f[0]);
  Term ops = f[1];
  uint64_t n_in = 0;
  char *input;
  u32 seed = (u32)f[3];
  TimuiFrame *fr = NULL;
  BircUi *bu = birc_state(ui);
  uint64_t profile_t0 = bu && bu->profile_enabled ? birc_profile_now_ns() : 0;
  uint64_t profile_t1 = 0;
  uint64_t profile_t2 = 0;
  uint64_t profile_t3 = 0;
  int enter = 0;
  uint32_t rows = 24;
  uint32_t cols = 80;
  uint32_t click = 0;
  size_t tlen = 0;
  TimuiTransportWrite saved_write;
  int saved_write_flags;
  (void)w;
  input = io_cstr(e, f[2], &n_in);
  if (!ui) {
    free(input);
    birc_drop_ops(e, ops);
    return birc_uikeys(e, NULL, 0, "", 0, 24, 80, 0, 1u, 0, 0, 0, 0, "", "");
  }
  {
    int check_fd = -1;
    if (ui->fd.write_fd >= 0 && isatty(ui->fd.write_fd))
      check_fd = ui->fd.write_fd;
    else if (ui->fd.read_fd >= 0 && isatty(ui->fd.read_fd))
      check_fd = ui->fd.read_fd;
    if (check_fd >= 0) {
      int tw = 0, th = 0, px_w = 0, px_h = 0;
      if (timui_term_size_pixels(check_fd, &tw, &th, &px_w, &px_h) == TIMUI_OK) {
        if (tw > 0 && th > 0 && (tw != ui->w || th != ui->h)) {
          if (timui_ui_resize_pixels(ui, tw, th, px_w, px_h) == TIMUI_OK)
            timui_full_redraw(ui);
        }
      }
    }
  }
  if (bu && bu->profile_enabled)
    profile_t1 = birc_profile_now_ns();
  saved_write = birc_output_begin(ui, &saved_write_flags);
  if (!timui_begin(ui, &fr)) {
    birc_output_end(ui, saved_write, saved_write_flags);
    free(input);
    birc_drop_ops(e, ops);
    return birc_uikeys(e, ui, 0, "", 0, 24, 80, 0, 1u, 0, 0, 0, 0, "", "");
  }
  if (bu && bu->profile_enabled)
    profile_t2 = birc_profile_now_ns();
  birc_hold_ctrl_w(ui);

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
    ly.bu = bu;
    ly.ui = ui;
    if (bu) {
      bu->body_count = 0;
      bu->preview_count = 0;
      bu->link_url[0] = '\0';
      memset(bu->body_inner, 0, sizeof bu->body_inner);
      memset(&bu->nicks_inner, 0, sizeof bu->nicks_inner);
    }
    timui_draw_fill(buf, root, panel);
    birc_draw_ops(e, fr, ops, &ly);
    if (seed != 0 && bu) {
      size_t ilen = (size_t)n_in;
      if (ilen >= sizeof bu->composer)
        ilen = birc_utf8_fit(input, sizeof bu->composer - 1);
      else
        ilen = birc_utf8_fit(input, ilen);
      if (ilen > 0)
        memcpy(bu->composer, input, ilen);
      bu->composer[ilen] = '\0';
      bu->st.cursor = ilen;
      bu->st.scroll_y = 0;
    }
    enter = draw_composer(fr, root.x, input_y, root.w, text, bu, &tlen);
    if (bu) {
      if (ui->ia.mouse_pressed) {
        int body_hit = -1;
        int i;
        for (i = 0; i < bu->body_count; i++)
          if (birc_pt_in_rect(ui->ia.mouse_x, ui->ia.mouse_y, bu->body_inner[i]))
            body_hit = i;
        if (body_hit >= 0) {
          bu->sel.active = 0;
          bu->sel.dragging = 1;
          bu->sel.start_x = bu->sel.cur_x = ui->ia.mouse_x;
          bu->sel.start_y = bu->sel.cur_y = ui->ia.mouse_y;
          bu->sel.pane = bu->body_inner[body_hit];
        } else if (birc_pt_in_rect(ui->ia.mouse_x, ui->ia.mouse_y, bu->nicks_inner)) {
          bu->sel.active = 0;
          bu->sel.dragging = 1;
          bu->sel.start_x = bu->sel.cur_x = ui->ia.mouse_x;
          bu->sel.start_y = bu->sel.cur_y = ui->ia.mouse_y;
          bu->sel.pane = bu->nicks_inner;
        } else {
          bu->sel.active = 0;
          bu->sel.dragging = 0;
        }
      } else if (bu->sel.dragging && ui->ia.mouse_down) {
        int min_x = bu->sel.pane.x;
        int max_x = bu->sel.pane.x + (bu->sel.pane.w > 0 ? bu->sel.pane.w - 1 : 0);
        int min_y = bu->sel.pane.y;
        int max_y = bu->sel.pane.y + (bu->sel.pane.h > 0 ? bu->sel.pane.h - 1 : 0);
        bu->sel.cur_x = birc_clamp(ui->ia.mouse_x, min_x, max_x);
        bu->sel.cur_y = birc_clamp(ui->ia.mouse_y, min_y, max_y);
        if (bu->sel.cur_x != bu->sel.start_x || bu->sel.cur_y != bu->sel.start_y) {
          bu->sel.active = 1;
        }
      }
      if (bu->sel.dragging && ui->ia.mouse_released) {
        int min_x = bu->sel.pane.x;
        int max_x = bu->sel.pane.x + (bu->sel.pane.w > 0 ? bu->sel.pane.w - 1 : 0);
        int min_y = bu->sel.pane.y;
        int max_y = bu->sel.pane.y + (bu->sel.pane.h > 0 ? bu->sel.pane.h - 1 : 0);
        bu->sel.dragging = 0;
        bu->sel.cur_x = birc_clamp(ui->ia.mouse_x, min_x, max_x);
        bu->sel.cur_y = birc_clamp(ui->ia.mouse_y, min_y, max_y);
        if (bu->sel.cur_x != bu->sel.start_x || bu->sel.cur_y != bu->sel.start_y) {
          bu->sel.active = 1;
          bu->link_url[0] = '\0';
          birc_copy_selection(ui, buf, bu);
        } else {
          bu->sel.active = 0;
        }
      }
    }
  }
  if (bu && bu->profile_enabled)
    profile_t3 = birc_profile_now_ns();
  {
    if (bu && bu->sel.active) {
      birc_render_selection(timui_frame_buffer(fr), bu);
    }
    timui_end(fr);
    if (bu && bu->bell_pending) {
      if (birc_frame_write(&ui->transport, "\a", 1) == 1)
        bu->bell_pending = 0;
    }
    birc_output_end(ui, saved_write, saved_write_flags);
    if (birc_frame_short) {
      birc_tty_stalled = 1;
      timui_full_redraw(ui);
    } else {
      birc_tty_stalled = 0;
    }
  }
  if (bu && bu->profile_enabled) {
    uint64_t profile_t4 = birc_profile_now_ns();
    bu->profile_frames += 1;
    bu->profile_prepare_ns += profile_t1 - profile_t0;
    bu->profile_begin_ns += profile_t2 - profile_t1;
    bu->profile_draw_ns += profile_t3 - profile_t2;
    bu->profile_end_ns += profile_t4 - profile_t3;
  }
  {
    const char *typed = bu ? bu->composer : "";
    uint32_t key = (uint32_t)ui->key_pressed;
    uint32_t mods = ui->key_mods;
    uint32_t codepoint = ui->key_codepoint;
    int wh = fr ? timui_mouse_wheel(fr) : 0;
    uint32_t more = (ui->event_count > 0 || ui->pending_in_len > 0 ||
                     ui->pending_enter_count > 0 || ui->pending_edit_count > 0) ? 1u : 0u;
    Term out;
    if (bu && bu->sel.active) {
      if (key == (uint32_t)TIMUI_KEY_ESCAPE) {
        bu->sel.active = 0;
        bu->sel.dragging = 0;
        key = 0;
        ui->key_pressed = (TimuiKey)0;
      } else if (key != 0 || enter || wh != 0) {
        bu->sel.active = 0;
        bu->sel.dragging = 0;
      }
    }
    if (timui_should_quit(ui) && key == 0)
      key = (uint32_t)TIMUI_KEY_ESCAPE;
    if (key == (uint32_t)TIMUI_KEY_ESCAPE || key == (uint32_t)TIMUI_KEY_F10)
      timui_quit(ui);
    out = birc_uikeys(e, ui, enter, typed, tlen, rows, cols, click, key, mods,
                         codepoint, (uint32_t)wh, more,
                         bu ? bu->link_url : "", bu && bu->clipboard ? bu->clipboard : "");
    if (bu) {
      free(bu->clipboard);
      bu->clipboard = NULL;
    }
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
  if (st && st->profile_enabled) {
    char report[256];
    uint64_t deadline = timui_now_ms() + 40u;
    int tty_report = isatty(STDERR_FILENO);
    int count = snprintf(report, sizeof report,
            "birc_profile frames=%llu prepare_us=%llu begin_us=%llu "
            "draw_us=%llu end_us=%llu\n",
            (unsigned long long)st->profile_frames,
            (unsigned long long)birc_profile_us(st->profile_prepare_ns,
                                                st->profile_frames),
            (unsigned long long)birc_profile_us(st->profile_begin_ns,
                                                st->profile_frames),
            (unsigned long long)birc_profile_us(st->profile_draw_ns,
                                                st->profile_frames),
            (unsigned long long)birc_profile_us(st->profile_end_ns,
                                                st->profile_frames));
    /* A tty stderr can alias the UI stream. Finish its accepted scalar before
     * this report, within the report's existing budget. Redirected stderr is
     * independent and does not need to wait for terminal output. */
    if (ui && tty_report && ui->fd.write_utf8_tail_len != 0)
      birc_write_bounded(&ui->fd, ui->fd.write_fd, "", 0, deadline);
    if (count > 0 && (size_t)count < sizeof report &&
        (!ui || !tty_report || ui->fd.write_utf8_tail_len == 0))
      birc_write_bounded(NULL, STDERR_FILENO, report, (size_t)count,
                         deadline);
  }
  if (ui) {
    if (ui->fd.write_fd >= 0)
      birc_write_bounded(&ui->fd, ui->fd.write_fd, "\x1b[?1002l", 8, timui_now_ms());
    /* TimUI retires and disowns image IDs under its one teardown budget.
     * Cached bitmaps can then be freed without further terminal IO. */
    timui_close(ui);
    if (st)
      for (int i = 0; i < 2; i++) {
        if (st->previews[i].image) {
          timui_image_free(NULL, st->previews[i].image);
          st->previews[i].image = NULL;
        }
      }
  }
  if (st)
    free(st->clipboard);
  free(st);
  return term_pak(CID_UNIT, 0);
}
static void __attribute__((constructor)) timui_close_use(void) {
  io_eff(CID_TIMUI_CLOSE, timui_close_run, 0);
}
#ifdef CID_TIMUI_ISATTY
Term timui_isatty_run(Env e, Term *f, IoWork *w) {
  (void)e;
  (void)f;
  (void)w;
  return (Term)(isatty(0) ? 1u : 0u);
}
static void __attribute__((constructor)) timui_isatty_use(void) {
  io_eff(CID_TIMUI_ISATTY, timui_isatty_run, 0);
}
#endif
#ifdef CID_TIMUI_TTY
Term timui_tty_run(Env e, Term *f, IoWork *w) {
  Timui *ui = (Timui *)(uintptr_t)io_hand_v(f[0]);
  (void)w;
  /* Same descriptor as the Ui. Do not dup: a close would be stdin. */
  if (!ui || ui->fd.read_fd < 0)
    return io_tup(e, f[0], io_fail(e, 1u, "no ui"));
  return io_tup(e, f[0], io_done(e, io_hand((u64)ui->fd.read_fd)));
}
static void __attribute__((constructor)) timui_tty_use(void) {
  io_eff(CID_TIMUI_TTY, timui_tty_run, 0);
}
#endif
#if defined(CID_TTY_READY) || defined(CID_WINCH_READY)
/* Shared park. Drain the winch pipe only; the frame reads the tty. */
static Term fd_ready_more(Env e, IoWork *w) {
  int fd = (int)w->hand;
  char dump;
  (void)e;
  if (w->made)
    while (read(fd, &dump, 1) > 0) {}
  return io_hand((u64)fd);
}
static Term fd_ready_run(Env e, Term *f, IoWork *w) {
  int fd = (int)io_hand_v(f[0]);
  int drain = fd >= 0 && fd == birc_winch_rd;
  char dump;
  (void)e;
  if (drain && read(fd, &dump, 1) > 0) {
    while (read(fd, &dump, 1) > 0) {}
    return f[0];
  }
  w->hand = (intptr_t)fd;
  w->made = drain;
  {
    u64 at = (!drain && birc_ui_live && birc_ui_live->input.state != 0)
                 ? io_tick() + 50000000ull
                 : 0;
    return io_wait_on(w, fd, POLLIN, at, fd_ready_more);
  }
}
#endif
#ifdef CID_TTY_READY
static void __attribute__((constructor)) tty_ready_use(void) {
  io_eff(CID_TTY_READY, fd_ready_run, 0);
}
#endif
#ifdef CID_TTY_CLOSE
Term tty_close_run(Env e, Term *f, IoWork *w) {
  (void)e;
  (void)f;
  (void)w;
  return term_pak(CID_UNIT, 0);
}
static void __attribute__((constructor)) tty_close_use(void) {
  io_eff(CID_TTY_CLOSE, tty_close_run, 0);
}
#endif
#if defined(CID_WINCH_OPEN) || defined(CID_WINCH_CLOSE)
static volatile sig_atomic_t birc_winch_wr = -1;
static struct sigaction birc_winch_old;
static int birc_winch_have;
#endif
#ifdef CID_WINCH_OPEN
static void birc_on_winch(int sig) {
  int save_errno = errno;
  char z = 1;
  int fd = (int)birc_winch_wr;
  (void)sig;
  if (fd >= 0) {
    ssize_t n = write(fd, &z, 1);
    (void)n;
  }
  errno = save_errno;
}
#endif
#ifdef CID_WINCH_OPEN
Term winch_open_run(Env e, Term *f, IoWork *w) {
  int pfd[2];
  struct sigaction sa;
  (void)f;
  (void)w;
  if (pipe(pfd) != 0) return io_fail(e, (u32)errno, "winch pipe");
  if (fcntl(pfd[0], F_SETFL, O_NONBLOCK) < 0 ||
      fcntl(pfd[1], F_SETFL, O_NONBLOCK) < 0) {
    int err = errno;
    (void)close(pfd[0]);
    (void)close(pfd[1]);
    return io_fail(e, (u32)err, "winch nonblock");
  }
  birc_winch_rd = pfd[0];
  birc_winch_wr = (sig_atomic_t)pfd[1];
  memset(&sa, 0, sizeof sa);
  sa.sa_handler = birc_on_winch;
  sa.sa_flags = SA_RESTART;
  sigemptyset(&sa.sa_mask);
  if (sigaction(SIGWINCH, &sa, &birc_winch_old) != 0) {
    int err = errno;
    (void)close(pfd[0]);
    (void)close(pfd[1]);
    birc_winch_rd = -1;
    birc_winch_wr = (sig_atomic_t)-1;
    return io_fail(e, (u32)err, "sigaction");
  }
  birc_winch_have = 1;
  return io_done(e, io_hand((u64)pfd[0]));
}
static void __attribute__((constructor)) winch_open_use(void) {
  io_eff(CID_WINCH_OPEN, winch_open_run, 0);
}
#endif
#ifdef CID_WINCH_READY
static void __attribute__((constructor)) winch_ready_use(void) {
  io_eff(CID_WINCH_READY, fd_ready_run, 0);
}
#endif
#ifdef CID_WINCH_CLOSE
Term winch_close_run(Env e, Term *f, IoWork *w) {
  int rd = (int)io_hand_v(f[0]);
  (void)e;
  (void)w;
  if (birc_winch_have) {
    (void)sigaction(SIGWINCH, &birc_winch_old, NULL);
    birc_winch_have = 0;
  }
  birc_winch_rd = -1;
  {
    int wr = (int)birc_winch_wr;
    birc_winch_wr = (sig_atomic_t)-1;
    if (wr >= 0)
      (void)close(wr);
  }
  if (rd >= 0) (void)close(rd);
  return term_pak(CID_UNIT, 0);
}
static void __attribute__((constructor)) winch_close_use(void) {
  io_eff(CID_WINCH_CLOSE, winch_close_run, 0);
}
#endif
#if CID_SYS_OPEN_PROGRAM
Term sys_open_program_run(Env e, Term *f, IoWork *w) {
  (void)f;
  (void)w;
#if defined(__APPLE__)
  return io_str(e, "open", 4);
#else
  return io_str(e, "xdg-open", 8);
#endif
}
static void __attribute__((constructor)) sys_open_program_use(void) {
  io_eff(CID_SYS_OPEN_PROGRAM, sys_open_program_run, 0);
}
#endif
#if CID_SYS_CLIPBOARD_PROGRAM
Term sys_clipboard_program_run(Env e, Term *f, IoWork *w) {
  (void)f;
  (void)w;
#ifdef __APPLE__
  return io_str(e, "pbcopy", 6);
#else
  return io_str(e, "", 0);
#endif
}
static void __attribute__((constructor)) sys_clipboard_program_use(void) {
  io_eff(CID_SYS_CLIPBOARD_PROGRAM, sys_clipboard_program_run, 0);
}
#endif
#if CID_SYS_EXIT_DONE
Term sys_exit_done_run(Env e, Term *f, IoWork *w) {
  (void)e;
  (void)f;
  (void)w;
  /* Timui.close restores blocking descriptor flags. Both IO.print and
   * IO.die (which always writes a stderr newline) can then hang. TimUI is
   * already closed; do not flush stdio or leave parked IO alive on success. */
  birc_write_bounded(NULL, STDOUT_FILENO, "birc=ok\n", 8, timui_now_ms() + 250u);
  _Exit(EXIT_SUCCESS);
}
static void __attribute__((constructor)) sys_exit_done_use(void) {
  io_eff(CID_SYS_EXIT_DONE, sys_exit_done_run, 0);
}
#endif
#if CID_SYS_EXIT_FAIL
Term sys_exit_fail_run(Env e, Term *f, IoWork *w) {
  u64 len = 0;
  char *msg = io_cstr(e, f[0], &len);
  uint64_t deadline = timui_now_ms() + 250u;
  (void)w;
  /* Like successful shutdown, a restored tty must not block on stderr. */
  if (msg)
    birc_write_bounded(NULL, STDERR_FILENO, msg, (size_t)len, deadline);
  birc_write_bounded(NULL, STDERR_FILENO, "\n", 1, deadline);
  free(msg);
  _Exit(EXIT_FAILURE);
}
static void __attribute__((constructor)) sys_exit_fail_use(void) {
  io_eff(CID_SYS_EXIT_FAIL, sys_exit_fail_run, 0);
}
#endif
#endif /* BIRC_TIMUI_FFI_C */
