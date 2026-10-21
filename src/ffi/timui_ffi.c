/* Bend TimUI foreign effects — open, frame, close, tty watch, and winch.
 * TIMUI_IMPLEMENTATION once. Include-guarded for multi-import.
 *
 * Duplicated caps (no single source of truth; do not "fix" one side here):
 *   recv clamp 65536 — dns_ffi.c max clamp, tls_ffi.c bytes[65536],
 *     actor.bend Tr.recv_octets(..., 65536)
 *   history scan 8 MiB — history_search_ffi.c BIRC_SEARCH_SCAN_MAX,
 *     history_search_io.bend SCAN_NATIVE_CAP (8388608)
 *   TLS setup 5s — unnamed literal 5000 at transport.bend Tls.open_for;
 *     tls_ffi.c reads that deadline as f[2] milliseconds
 *   tab/buffer slots 16 — BIRC_TAB_SLOTS below (spans, store, alerts) and
 *     drafts.bend ENTRY_CAP. birc_str_list drops names past the cap with
 *     no error (the remainder is sunk). That silent truncation is the
 *     dangerous pair: Bend can hold 16 drafts while paint shows fewer tabs.
 *   composer bytes — BIRC_COMPOSER_CAP (512) is only this buffer. drafts.bend
 *     TEXT_BYTES is 4096, not 512. A longer reseed is clipped here.
 *   media — birc_media.h CAP 8 / FRAME_CAP 24 / LIMIT 2 MiB vs media.bend
 *     CAP() 8 (pending and ready). Frame cap, byte limit, 320px, and
 *     1536000 pixel-frames exist only in C.
 *   OSC8 — single-sourced: timui.h TIMUI_HYPERLINK_MAX_BYTES 1024, so
 *     BIRC_URL_CAP is 1025 and a URL of length >= 1025 is a plain span.
 *     1024-byte targets are kept. Do not reintroduce a second cap.
 */
#ifndef BIRC_TIMUI_FFI_C
#define BIRC_TIMUI_FFI_C
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stddef.h>
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
#include "birc_output.h"
#include "birc_media.h"
#include "bend_cid.h"

#ifndef Loc
typedef uint64_t Loc;
#endif

#ifndef CID_UIKEYS
#define CID_UIKEYS CID(UiKeys)
#endif
#ifndef CID_TIMUI_OPEN
#define CID_TIMUI_OPEN CID(Timui.open)
#endif
#ifndef CID_TIMUI_IMAGE_SUPPORTED
#define CID_TIMUI_IMAGE_SUPPORTED CID(Timui.image_supported)
#endif
#ifndef CID_TIMUI_MEASURE
#define CID_TIMUI_MEASURE CID(Timui.measure)
#endif
#ifndef CID_TIMUI_VIEW_BEGIN
#define CID_TIMUI_VIEW_BEGIN CID(Timui.view_begin)
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
#ifndef CID_SYS_PLATFORM
#define CID_SYS_PLATFORM CID(Sys.platform)
#endif
#ifndef CID_SYS_MEDIA_PROGRAM
#define CID_SYS_MEDIA_PROGRAM CID(Sys.media_program)
#endif
#ifndef CID_TIMUI_MEDIA_ADD
#define CID_TIMUI_MEDIA_ADD CID(Timui.media_add)
#endif
#ifndef CID_TIMUI_MEDIA_CLEAR
#define CID_TIMUI_MEDIA_CLEAR CID(Timui.media_clear)
#endif
#ifndef CID_SYS_EXIT_DONE
#define CID_SYS_EXIT_DONE CID(Sys.exit_done)
#endif
#ifndef CID_SYS_EXIT_FAIL
#define CID_SYS_EXIT_FAIL CID(Sys.exit_fail)
#endif

/* An IRC record is at most 512 octets, but Latin-1 fallback can expand
 * every octet to two UTF-8 bytes. Never truncate a decoded click target.
 * Decline when ulen >= BIRC_URL_CAP (1025). A 1024-byte target still fits
 * with its NUL. docs/FFI.md's "255 bytes" figure is stale. */
enum { BIRC_URL_CAP = TIMUI_HYPERLINK_MAX_BYTES + 1 };
enum { BIRC_PREVIEW_CAP = BIRC_MEDIA_CAP };
/* drafts.bend ENTRY_CAP is 16. Label storage is 64 bytes with a 63-byte
 * cluster clip. The composer array is not TEXT_BYTES (4096). */
enum { BIRC_TAB_SLOTS = 16, BIRC_TAB_LABEL = 64, BIRC_COMPOSER_CAP = 512 };
/* Historic dark mention chip (0x1E1E2E / 0xFFD700). Theme.tab_mention_bg/fg
 * own the palette. OpTabs does not carry those words yet, so paint still
 * passes these constants. Activity stays reverse video, not a colour. */
enum { BIRC_TAB_MENTION_BG = 0x1E1E2Eu, BIRC_TAB_MENTION_FG = 0xFFD700u };

typedef struct {
  int active;       /* 1 if selection exists */
  int dragging;     /* 1 if left mouse button is pressed and held */
  int start_x, start_y;
  int cur_x, cur_y;
  TimuiRect pane;   /* bounds of pane where drag started */
} BircSel;

typedef struct {
  TimuiImage *image;
  TimuiImage *retiring;
  char path[4096];
  size_t path_len;
  uint32_t token; /* 0 names the existing local-PNG preview path */
} BircPreview;

typedef struct {
  char composer[BIRC_COMPOSER_CAP];
  TimuiTextAreaState st;
  int last_tab;
  uint32_t last_bell_seq;
  int bell_seen;
  int bell_pending;
  char link_url[BIRC_URL_CAP];
  char *clipboard;
  TimuiRect body_inner[2];
  int body_count;
  /* Index into body_inner for the composer host; -1 until a
   * PANE_COMPOSER OpBox (or the sole body pane) registers. */
  int composer_pane;
  TimuiRect nicks_inner;
  BircSel sel;
  int profile_enabled;
  uint64_t profile_frames;
  uint64_t profile_view_start_ns;
  uint64_t profile_view_ns;
  uint64_t profile_prepare_ns;
  uint64_t profile_begin_ns;
  uint64_t profile_draw_ns;
  uint64_t profile_end_ns;
  BircPreview previews[BIRC_PREVIEW_CAP];
  int preview_count;
  BircOutput output;
  BircMediaCache media;
  /* Attrs 8: drawn after the composer widget so it is not cleared. */
  char ghost[128];
  int ghost_x;
  int ghost_y;
  int ghost_w; /* Bend OpGhost.w columns; paint maxx is gx + ghost_w. */
  int ghost_on;
  uint32_t ghost_fg;
  /* Reused UTF-8 encode buffer for OpText / span paint (no per-op malloc). */
  char *paint_buf;
  size_t paint_cap;
} BircUi;
static BircUi *birc_state(const Timui *ui) {
  return ui ? (BircUi *)timui_userdata(ui) : NULL;
}
#include "birc_utf8_fit.h"
static Timui *birc_ui_live;
/* Capture failure follows mandatory shutdown, then nonzero status. */
static int birc_output_failure;
/* Only the single controlling UI's accepted output debt can outlive close. Keep
 * its stream open independently of borrowed stdout/stderr descriptor numbers. */
static TimuiClosedOutput birc_final_output;
static struct stat birc_final_stream;
static int birc_final_pending;
static Timui *birc_final_retained_ui;
static BircUi *birc_final_retained_state;

static void birc_state_destroy(BircUi *state) {
  if (!state)
    return;
  free(state->paint_buf);
  state->paint_buf = NULL;
  state->paint_cap = 0;
  for (int i = 0; i < BIRC_PREVIEW_CAP; i++) {
    if (state->previews[i].image)
      timui_image_free(NULL, state->previews[i].image);
    if (state->previews[i].retiring)
      timui_image_free(NULL, state->previews[i].retiring);
  }
  free(state->clipboard);
  birc_output_destroy(&state->output);
  birc_media_clear(&state->media);
  free(state);
}

static int birc_same_stream(const struct stat *a, const struct stat *b) {
  return a->st_dev == b->st_dev && a->st_ino == b->st_ino &&
         a->st_rdev == b->st_rdev && (a->st_mode & S_IFMT) == (b->st_mode & S_IFMT);
}

static int birc_fd_same_stream(int a, int b) {
  struct stat sa, sb;
  return fstat(a, &sa) == 0 && fstat(b, &sb) == 0 && birc_same_stream(&sa, &sb);
}

static void birc_final_disown(void) {
  if (birc_final_pending && birc_final_output.fd.write_fd >= 0)
    (void)close(birc_final_output.fd.write_fd);
  birc_final_pending = 0;
}

static void birc_final_take(TimuiClosedOutput *pending) {
  birc_final_disown();
  birc_final_retained_ui = pending->retained_ui;
  birc_final_retained_state = birc_state(pending->retained_ui);
  if (pending->fd.write_utf8_tail_len == 0 && !pending->framing_debt &&
      !pending->sync_open && !pending->retained_ui) {
    if (pending->owned_fd)
      (void)close(pending->fd.write_fd);
    return;
  }
  birc_final_output = *pending;
  if (fstat(pending->fd.write_fd, &birc_final_stream) != 0) {
    /* Identity is unknown: suppress final output rather than bypass debt. */
    if (pending->owned_fd)
      (void)close(pending->fd.write_fd);
    memset(&birc_final_stream, 0, sizeof birc_final_stream);
    birc_final_output.fd.write_fd = -1;
    birc_final_pending = 2;
  } else {
    birc_final_output.fd.write_fd = pending->owned_fd ? pending->fd.write_fd
        : fcntl(pending->fd.write_fd, F_DUPFD_CLOEXEC, 3);
    birc_final_pending = 1;
  }
}

/* At most one complete Ui/BircUi owner is retained for an already-entered
 * handler. Never wait for it; a final exit gets only its existing deadline. */
static int birc_final_reap(uint64_t deadline) {
  Timui *ui = birc_final_retained_ui;
  BircUi *state = birc_final_retained_state;
  TimuiClosedOutput pending;
  if (!ui)
    return 1;
  if (!timui_close_prepare_(ui))
    return 0;
  birc_final_retained_ui = NULL;
  birc_final_retained_state = NULL;
  timui_close_prepared_(ui, &pending, 1, deadline);
  birc_state_destroy(state);
  birc_final_take(&pending);
  return 1;
}

static void birc_final_before_exit(void) {
  if (birc_final_retained_ui)
    timui_signal_host_restore_(birc_final_retained_ui);
  birc_final_disown();
}

/* Input and output can have separate descriptions. Make the write target
 * nonblocking for the whole budget, then return the borrow's saved flags. */
static void birc_write_bounded(TimuiFdCtx *ctx, int fd, const void *data, size_t size,
                               uint64_t deadline) {
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags >= 0 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0) {
    if (ctx)
      (void)timui_fd_write_(ctx, data, size, 1, deadline);
    else
      (void)timui_write_all_until_(fd, data, size, deadline);
    timui_fd_flags_restore_(fd, flags);
  }
}

static int birc_settle_debt(TimuiFdCtx *ctx, int *framing_debt,
                            volatile sig_atomic_t *sync_open, uint64_t deadline) {
  int flags = fcntl(ctx->write_fd, F_GETFL, 0);
  int settled;
  if (flags < 0 || fcntl(ctx->write_fd, F_SETFL, flags | O_NONBLOCK) != 0)
    return 0;
  settled = timui_fd_settle_debt_(ctx, framing_debt, sync_open, deadline);
  timui_fd_flags_restore_(ctx->write_fd, flags);
  return settled;
}

static void birc_write_final(TimuiFdCtx *output, const void *data, size_t size,
                             uint64_t deadline) {
  struct stat stream;
  int fd = output->write_fd;
  if (!birc_final_reap(deadline) &&
      (fstat(fd, &stream) != 0 || birc_final_pending == 2 ||
       birc_same_stream(&stream, &birc_final_stream)))
    return;
  if (birc_final_pending &&
      (birc_final_output.fd.write_utf8_tail_len != 0 ||
       birc_final_output.framing_debt || birc_final_output.sync_open) &&
      (fstat(fd, &stream) != 0 || birc_final_pending == 2 ||
       birc_same_stream(&stream, &birc_final_stream))) {
    if (birc_final_output.fd.write_fd < 0)
      return;
    if (!birc_settle_debt(&birc_final_output.fd, &birc_final_output.framing_debt,
                         &birc_final_output.sync_open, deadline))
      return;
  }
  birc_write_bounded(output, fd, data, size, deadline);
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

/* Consume a mark once at frame entry, before the native preparation phase. */
static void birc_profile_view_end(BircUi *bu, uint64_t now) {
  if (!bu)
    return;
  if (bu->profile_enabled && bu->profile_view_start_ns != 0 &&
      now >= bu->profile_view_start_ns)
    bu->profile_view_ns += now - bu->profile_view_start_ns;
  bu->profile_view_start_ns = 0;
}

/* Start of Bend's pure-View phase. Default-off: unless BIRC_FRAME_PROFILE=1
 * this returns the handle unchanged. It is not profile_t0 at frame entry;
 * that mark ends the View phase. The call site is unconditional and lives
 * in net.bend; gate it there. Keep this seam. */
Term timui_view_begin_run(Env e, Term *f, IoWork *w) {
  Timui *ui = (Timui *)(uintptr_t)io_hand_v(f[0]);
  BircUi *bu = birc_state(ui);
  (void)e;
  (void)w;
  if (bu && bu->profile_enabled)
    bu->profile_view_start_ns = birc_profile_now_ns();
  return f[0];
}
static void __attribute__((constructor)) timui_view_begin_use(void) {
  io_eff(CID_TIMUI_VIEW_BEGIN, timui_view_begin_run);
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
  fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW);
  if (fd < 0)
    return NULL;
  if (fstat(fd, &st) < 0 || !S_ISREG(st.st_mode) || st.st_size <= 0 ||
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

static int birc_preview_retire(BircPreview *preview, Timui *ui) {
  BircUi *bu = birc_state(ui);
  if (!bu || !bu->output.capturing)
    return 0;
  if (preview->image) {
    if (preview->retiring)
      return 0;
    if (timui_image_retire_capture_(ui, preview->image) != TIMUI_FRAME_DONE)
      return 0;
    preview->retiring = preview->image;
    preview->image = NULL;
  }
  preview->path_len = 0;
  preview->token = 0;
  return 1;
}

static void birc_preview_set(BircPreview *preview, Timui *ui, const char *path,
                             size_t path_len) {
  if (!preview || !ui || !path || path_len == 0 ||
      path_len >= sizeof preview->path || memchr(path, '\0', path_len))
    return;
  if (preview->image && preview->token == 0 && preview->path_len == path_len &&
      memcmp(preview->path, path, path_len) == 0)
    return;
  if (!birc_preview_retire(preview, ui))
    return;
  memcpy(preview->path, path, path_len);
  preview->path[path_len] = '\0';
  preview->path_len = path_len;
  preview->image = birc_preview_load(ui, preview->path);
}

static TimuiImage *birc_media_image(Timui *ui, const BircMedia *media) {
  TimuiImage *image;
  TimuiImageFrame frames[BIRC_MEDIA_FRAME_CAP];
  uint32_t i;
  if (!media)
    return NULL;
  image = timui_image_from_png_rgba(ui, media->frames[0].png,
      media->frames[0].png_len, media->rgba, (int)media->width,
      (int)media->height, (int)media->width * 4);
  if (!image)
    return NULL;
  if (media->count > 1) {
    for (i = 0; i < media->count; i++) {
      frames[i].png = media->frames[i].png;
      frames[i].len = media->frames[i].png_len;
      frames[i].duration_ms = media->frames[i].duration;
    }
    if (timui_image_set_animation(image, frames, media->count, media->iterations,
                                  media->gif, media->gif_len) != TIMUI_OK) {
      timui_image_free(NULL, image);
      return NULL;
    }
  }
  return image;
}

static TimuiImage *birc_preview_media(BircPreview *preview, Timui *ui,
                                      uint32_t token) {
  BircUi *bu = birc_state(ui);
  const BircMedia *media = bu ? birc_media_find(&bu->media, token) : NULL;
  if (!bu || !bu->output.capturing || !media)
    return NULL;
  if (preview->token == token && preview->image)
    return preview->image;
  if (!birc_preview_retire(preview, ui))
    return NULL;
  preview->token = token;
  preview->image = birc_media_image(ui, media);
  return preview->image;
}

/* Clearing/evicting payload bytes is immediate. Native ids remain owned until
 * a later accepted frame deletes them, or ordinary close settles that debt. */
static void birc_media_prune(Timui *ui, BircUi *bu) {
  int i;
  if (!bu || !bu->output.capturing)
    return;
  for (i = 0; i < BIRC_PREVIEW_CAP; i++)
    if (bu->previews[i].token &&
        !birc_media_find(&bu->media, bu->previews[i].token))
      (void)birc_preview_retire(&bu->previews[i], ui);
}

static void birc_draw_media(TimuiFrame *frame, BircUi *bu, Timui *ui,
                            uint32_t x, uint32_t y, uint32_t width,
                            uint32_t height, uint32_t clip_y,
                            uint32_t clip_h, uint32_t token) {
  TimuiRect full, visible;
  TimuiImage *image = NULL;
  BircPreview *preview = NULL;
  BircPreview *reusable = NULL;
  int i;
  int64_t top = (int64_t)y - clip_y;
  if (!frame || !bu || !ui || x > INT_MAX || y > INT_MAX ||
      width > INT_MAX || height > INT_MAX || clip_h > INT_MAX ||
      !width || !height || !clip_h || clip_y > height || clip_h > height - clip_y ||
      top < INT_MIN || top > INT_MAX)
    return;
  full = (TimuiRect){(int)x, (int)top, (int)width, (int)height};
  visible = (TimuiRect){(int)x, (int)y, (int)width, (int)clip_h};
  /* Split panes may emit OpMedia twice for one ready token. Reuse that slot
   * so a duplicate never burns a second of the eight preview slots. */
  for (i = 0; i < BIRC_PREVIEW_CAP; i++) {
    if (bu->previews[i].token != token)
      continue;
    if (bu->previews[i].image) {
      preview = &bu->previews[i];
      break;
    }
    if (!reusable)
      reusable = &bu->previews[i];
  }
  if (!preview)
    preview = reusable;
  if (!preview) {
    if (bu->preview_count < BIRC_PREVIEW_CAP)
      preview = &bu->previews[bu->preview_count++];
  } else {
    int idx = (int)(preview - bu->previews);
    if (idx >= bu->preview_count)
      bu->preview_count = idx + 1;
  }
  if (preview)
    image = birc_preview_media(preview, ui, token);
  if (image)
    timui_image_draw_clipped(frame, image, full, visible);
  else
    image_placeholder_(ui, timui_intersect_rect_(visible, timui_root(frame)));
}

#if CID_TIMUI_IMAGE_SUPPORTED
Term timui_image_supported_run(Env e, Term *f, IoWork *w) {
  Timui *ui = (Timui *)(uintptr_t)io_hand_v(f[0]);
  (void)w;
  return io_tup(e, f[0],
      (Term)(timui_image_protocol(ui) != TIMUI_IMAGE_PROTOCOL_NONE ? 1u : 0u));
}
static void __attribute__((constructor)) timui_image_supported_use(void) {
  io_eff(CID_TIMUI_IMAGE_SUPPORTED, timui_image_supported_run);
}
#endif

/* Same floors as the UiKeys rows/cols taken from timui_root after begin.
 * Returns 1 when the native grid changed, so the frame can full-redraw. */
static void birc_floor_grid(int w, int h, uint32_t *rows, uint32_t *cols) {
  if (h < 4)
    h = 4;
  if (w < 1)
    w = 1;
  *rows = (uint32_t)h;
  *cols = (uint32_t)w;
}

static int birc_sync_term_size(Timui *ui, uint32_t *rows, uint32_t *cols) {
  int check_fd = -1;
  int tw = 0;
  int th = 0;
  int px_w = 0;
  int px_h = 0;
  int resized = 0;
  *rows = 24;
  *cols = 80;
  if (!ui)
    return 0;
  if (ui->w > 0 && ui->h > 0)
    birc_floor_grid(ui->w, ui->h, rows, cols);
  if (ui->fd.write_fd >= 0 && isatty(ui->fd.write_fd))
    check_fd = ui->fd.write_fd;
  else if (ui->fd.read_fd >= 0 && isatty(ui->fd.read_fd))
    check_fd = ui->fd.read_fd;
  if (check_fd < 0)
    return 0;
  if (timui_term_size_pixels(check_fd, &tw, &th, &px_w, &px_h) != TIMUI_OK)
    return 0;
  if (tw <= 0 || th <= 0)
    return 0;
  if (tw != ui->w || th != ui->h) {
    if (timui_ui_resize_pixels(ui, tw, th, px_w, px_h) == TIMUI_OK)
      resized = 1;
  }
  if (ui->w > 0 && ui->h > 0)
    birc_floor_grid(ui->w, ui->h, rows, cols);
  else
    birc_floor_grid(tw, th, rows, cols);
  return resized;
}

#if CID_TIMUI_MEASURE
Term timui_measure_run(Env e, Term *f, IoWork *w) {
  Timui *ui = (Timui *)(uintptr_t)io_hand_v(f[0]);
  uint32_t rows = 24;
  uint32_t cols = 80;
  (void)w;
  (void)birc_sync_term_size(ui, &rows, &cols);
  return io_tup(e, f[0], io_tup(e, (Term)(uint64_t)rows, (Term)(uint64_t)cols));
}
static void __attribute__((constructor)) timui_measure_use(void) {
  io_eff(CID_TIMUI_MEASURE, timui_measure_run);
}
#endif

static int birc_u32_list(Env e, Term xs, uint32_t *vals, int max);
#if CID_TIMUI_MEDIA_ADD
Term timui_media_add_run(Env e, Term *f, IoWork *w) {
  Timui *ui = (Timui *)(uintptr_t)io_hand_v(f[0]);
  BircUi *bu = birc_state(ui);
  u64 length = 0;
  uint32_t retained[BIRC_MEDIA_CAP];
  int count = birc_u32_list(e, f[2], retained, BIRC_MEDIA_CAP);
  char *text = io_cstr(e, f[1], &length);
  if (bu) birc_media_retain(&bu->media, retained, (size_t)count);
  uint32_t token = bu && text && length <= (u64)SIZE_MAX
      ? birc_media_add(&bu->media, text, (size_t)length) : 0;
  (void)w;
  free(text);
  return io_tup(e, f[0], (Term)(uint64_t)token);
}
static void __attribute__((constructor)) timui_media_add_use(void) {
  io_eff(CID_TIMUI_MEDIA_ADD, timui_media_add_run);
}
#endif
#if CID_TIMUI_MEDIA_CLEAR
Term timui_media_clear_run(Env e, Term *f, IoWork *w) {
  Timui *ui = (Timui *)(uintptr_t)io_hand_v(f[0]);
  BircUi *bu = birc_state(ui);
  (void)e; (void)w;
  if (bu) birc_media_clear(&bu->media);
  return f[0];
}
static void __attribute__((constructor)) timui_media_clear_use(void) {
  io_eff(CID_TIMUI_MEDIA_CLEAR, timui_media_clear_run);
}
#endif

static int birc_winch_rd = -1;
static void birc_ui_atexit(void) {
  Timui *ui = birc_ui_live;
  birc_ui_live = NULL;
  if (ui) {
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
  st->composer_pane = -1;
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
  io_eff(CID_TIMUI_OPEN, timui_open_run);
}
/* One grapheme advance that also returns width (no second width table).
 * Bend already sized OpText/spans via columns.bend; this only defends maxx. */
static size_t birc_clip_cols(const char *s, size_t n, int x, int maxx, int *out_w) {
  size_t i = 0;
  int64_t cx = x;
  if (!s) n = 0;
  while (i < n) {
    int w = 0;
    size_t next = timui_grapheme_next_w_(s, n, i, &w);
    if (next <= i) break;
    if (w == 0 && timui_utf8_decode(s + i, n - i, NULL) <= 0)
      w = 1;
    if (w > 0 && (cx + w > maxx || cx + w - x > INT_MAX))
      break;
    if (w > 0)
      cx += w;
    i = next;
  }
  if (out_w)
    *out_w = (int)(cx - x);
  return i;
}
#ifndef CID_SCON
#define CID_SCON 0u /* test stub: fall back to io_cstr */
#endif
#ifndef CID_SNIL
#define CID_SNIL 0u
#endif
/* Encode a Bend String into bu->paint_buf (length-bounded). Returns 1 and
 * sets *out / *out_n on success. Falls back to io_cstr when the term is not
 * an SCon chain (unit-test stubs) — caller frees only in that path. On any
 * allocation failure: *out="", *out_n=0, return 0 so callers that ignore the
 * status still pass a zero-length span. */
static int birc_draw_str(Env e, Term s, BircUi *bu, const char **out, size_t *out_n,
                         char **owned) {
  size_t n = 0;
  u64 aux;
  *owned = NULL;
  *out = "";
  *out_n = 0;
  if (!bu) {
    u64 len = 0;
    char *heap = io_cstr(e, s, &len);
    if (!heap) {
      /* Empty source may omit an allocation; nonzero len without bytes is OOM. */
      return len == 0;
    }
    if (len > (u64)SIZE_MAX) {
      free(heap);
      return 0;
    }
    *owned = heap;
    *out = heap;
    *out_n = (size_t)len;
    return 1;
  }
  aux = term_aux(s);
  if (CID_SCON != 0u && (aux == CID_SCON || aux == CID_SNIL)) {
    Term cur = s;
    while (term_aux(cur) == CID_SCON) {
      Term fb[2];
      Loc sp = ctr_take(e, cur, 2, fb);
      char enc[4];
      int k = timui_utf8_encode_((uint32_t)fb[0], enc);
      if (n + (size_t)k + 1 > bu->paint_cap) {
        size_t need = bu->paint_cap ? bu->paint_cap * 2 : 128;
        char *next;
        while (need < n + (size_t)k + 1)
          need *= 2;
        next = (char *)realloc(bu->paint_buf, need);
        if (!next) {
          spare_free(e, cls_fit(2), sp);
          *out = "";
          *out_n = 0;
          return 0;
        }
        bu->paint_buf = next;
        bu->paint_cap = need;
      }
      memcpy(bu->paint_buf + n, enc, (size_t)k);
      n += (size_t)k;
      cur = fb[1];
      spare_free(e, cls_fit(2), sp);
    }
    if (bu->paint_cap == 0) {
      bu->paint_buf = (char *)malloc(1);
      if (!bu->paint_buf) {
        *out = "";
        *out_n = 0;
        return 0;
      }
      bu->paint_cap = 1;
    }
    bu->paint_buf[n] = '\0';
    *out = bu->paint_buf;
    *out_n = n;
    return 1;
  }
  {
    u64 len = 0;
    char *heap = io_cstr(e, s, &len);
    if (!heap) {
      *owned = NULL;
      *out = "";
      *out_n = 0;
      return len == 0;
    }
    if (len > (u64)SIZE_MAX) {
      free(heap);
      *owned = NULL;
      *out = "";
      *out_n = 0;
      return 0;
    }
    *owned = heap;
    *out = heap;
    *out_n = (size_t)len;
    return 1;
  }
}
static int birc_put_span(TimuiFrame *fr, int x, int y, int maxx, const char *p,
                         size_t n, uint32_t fg, uint32_t attrs, const char *uri) {
  int w = 0;
  TimuiStyle st;
  if (!fr || n == 0 || x >= maxx) return x;
  /* Bend owns column clipping (columns.bend). Defensive fit only. */
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
/* Byte-capped labels must inspect the complete source cluster, including any
 * attachment beyond the cap. The composer keeps its separate code-point clip.
 * Names past BIRC_TAB_SLOTS are discarded with no error: the unread tail is
 * sunk, not drawn. That is silent truncation against drafts.bend ENTRY_CAP. */
static size_t birc_cluster_fit(const char *text, size_t length, size_t cap) {
  size_t kept = 0;
  if (!text) return 0;
  while (kept < length) {
    size_t next = timui_grapheme_next(text, length, kept);
    if (next <= kept || next > cap) break;
    kept = next;
  }
  return kept;
}
static int birc_str_list(Env e, Term xs, char store[][BIRC_TAB_LABEL],
                         const char **labs, int max) {
  int n = 0;
  while (n < max && term_aux(xs) == CID_CON) {
    Term t;
    u64 len = 0;
    char *s;
    size_t nlen;
    Term h = birc_cons_head(e, xs, &t);
    xs = t;
    s = io_cstr(e, h, &len);
    /* Keep the byte/code-point cap, then back up past a partial cluster.
     * 63 is BIRC_TAB_LABEL-1. test-utf8-fit greps this expression; the
     * Makefile owns that check, so the spelling stays literal. */
    nlen = birc_utf8_fit(s, (size_t)len < 63 ? (size_t)len : (size_t)63);
    nlen = birc_cluster_fit(s, (size_t)len, nlen);
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
                                 const uint32_t *alerts, int nalerts, int sel,
                                 uint32_t mention_bg, uint32_t mention_fg) {
  TimuiTabSpan spans[BIRC_TAB_SLOTS];
  int i, scroll;
  if (!fr || !labels || !alerts || ntabs <= 0 || r.w <= 0)
    return;
  (void)timui_tabs_layout(labels, ntabs, 1, spans, BIRC_TAB_SLOTS);
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
      style = timui_style_make(mention_bg, mention_fg, TIMUI_ATTR_BOLD);
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
      const char *text = "";
      size_t tlen = 0;
      char *owned = NULL;
      BircUi *bu = (fr && fr->ui) ? birc_state(fr->ui) : NULL;
      (void)birc_draw_str(e, f[2], bu, &text, &tlen, &owned);
      x = birc_put_span(fr, x, y, maxx, text, tlen, (uint32_t)f[1],
                        (uint32_t)f[0], NULL);
      free(owned);
      spare_free(e, cls_fit(3), loc);
    } else {
      Loc loc = ctr_take(e, sp, 2, f);
      if (cid == CID_VIEW_LNK) {
        u64 ulen = 0;
        char *url = io_cstr(e, f[0], &ulen);
        const char *text = "";
        size_t tlen = 0;
        char *owned = NULL;
        BircUi *bu = (fr && fr->ui) ? birc_state(fr->ui) : NULL;
        (void)birc_draw_str(e, f[1], bu, &text, &tlen, &owned);
        x = birc_put_link(fr, x, y, maxx, url, (size_t)ulen, text, tlen, fg);
        free(url);
        free(owned);
      } else if (cid == CID_VIEW_SPN) {
        const char *text = "";
        size_t tlen = 0;
        char *owned = NULL;
        BircUi *bu = (fr && fr->ui) ? birc_state(fr->ui) : NULL;
        (void)birc_draw_str(e, f[1], bu, &text, &tlen, &owned);
        x = birc_put_span(fr, x, y, maxx, text, tlen, fg, (uint32_t)f[0], NULL);
        free(owned);
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
    /* role: 0 unknown, 1 body, 2 nicks, 3 composer (body host). */
    Term f[5];
    Loc loc = ctr_take(e, op, 5, f);
    TimuiRect r;
    uint32_t role;
    r.x = (int)(uint32_t)f[0];
    r.y = (int)(uint32_t)f[1];
    r.w = (int)(uint32_t)f[2];
    r.h = (int)(uint32_t)f[3];
    role = (uint32_t)f[4];
    if (ly && r.y + r.h > ly->root.y + ly->root.h)
      r.h = ly->root.y + ly->root.h - r.y;
    if (ly && ly->bu) {
      TimuiRect inner = (TimuiRect){r.x + 1, r.y + 1,
        r.w > 2 ? r.w - 2 : 0, r.h > 2 ? r.h - 2 : 0};
      if (role == 1u || role == 3u) {
        int i, found = -1;
        for (i = 0; i < ly->bu->body_count; i++) {
          TimuiRect in = ly->bu->body_inner[i];
          if (r.x == in.x - 1 && r.y == in.y - 1 &&
              r.w == in.w + 2 && r.h == in.h + 2)
            found = i;
        }
        if (found < 0 && ly->bu->body_count < 2) {
          found = ly->bu->body_count;
          ly->bu->body_inner[found] = inner;
          ly->bu->body_count++;
        }
        if (role == 3u && found >= 0)
          ly->bu->composer_pane = found;
      } else if (role == 2u) {
        ly->bu->nicks_inner = inner;
      }
      /* role 0 (unknown): draw only; tests may emit bare OpBox. */
    }
    if (fr && ly && r.h > 0 && r.w > 2)
      timui_draw_box(ly->buf, r, TIMUI_BORDER_ROUND, ly->border);
    spare_free(e, cls_fit(5), loc);
  } else if (cid == CID_VIEW_OPSPLIT) {
    Term f[6];
    Loc loc = ctr_take(e, op, 6, f);
    TimuiRect area, panes[2];
    TimuiConstraint cons[2] = {TIMUI_FLEX(1), TIMUI_FLEX(1)};
    int axis = (int)(uint32_t)f[4];
    int made;
    area.x = (int)(uint32_t)f[0];
    area.y = (int)(uint32_t)f[1];
    area.w = (int)(uint32_t)f[2];
    area.h = (int)(uint32_t)f[3];
    /* f[5] is pane role (Body); split always seeds both body inners. */
    (void)(uint32_t)f[5];
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
    spare_free(e, cls_fit(6), loc);
  } else if (cid == CID_VIEW_OPTEXT) {
    Term f[6];
    Loc loc = ctr_take(e, op, 6, f);
    int x = (int)(uint32_t)f[0];
    int y = (int)(uint32_t)f[1];
    int w = (int)(uint32_t)f[2];
    const char *s = "";
    size_t n = 0;
    char *owned = NULL;
    BircUi *bu = ly ? ly->bu : NULL;
    (void)birc_draw_str(e, f[5], bu, &s, &n, &owned);
    /* Underline (TIMUI_ATTR_UNDERLINE == 8) paints like any other Attrs;
     * deferred composer text uses OpGhost, not an in-band attrs marker. */
    (void)birc_put_span(fr, x, y, x + w, s, n, (uint32_t)f[3],
                        (uint32_t)f[4], NULL);
    free(owned);
    spare_free(e, cls_fit(6), loc);
#ifdef CID_VIEW_OPGHOST
  } else if (cid == CID_VIEW_OPGHOST) {
    Term f[5];
    Loc loc = ctr_take(e, op, 5, f);
    int x = (int)(uint32_t)f[0];
    int y = (int)(uint32_t)f[1];
    int w = (int)(uint32_t)f[2];
    const char *s = "";
    size_t n = 0;
    char *owned = NULL;
    BircUi *bu = ly ? ly->bu : NULL;
    (void)birc_draw_str(e, f[4], bu, &s, &n, &owned);
    /* Composer-row text that the widget would wipe. Keep it and paint after
     * the text area. Bend owns column width (f[2]); do not infer maxx from
     * strlen. */
    if (bu) {
      size_t gn = n;
      if (gn >= sizeof bu->ghost)
        gn = sizeof bu->ghost - 1;
      gn = birc_cluster_fit(s, n, gn);
      if (gn > 0)
        memcpy(bu->ghost, s, gn);
      bu->ghost[gn] = '\0';
      bu->ghost_x = x;
      bu->ghost_y = y;
      bu->ghost_w = w;
      bu->ghost_fg = (uint32_t)f[3];
      bu->ghost_on = 1;
    }
    free(owned);
    spare_free(e, cls_fit(5), loc);
#endif
  } else if (cid == CID_VIEW_OPTABS) {
    Term f[8];
    Loc loc = ctr_take(e, op, 8, f);
    TimuiRect r;
    char store[BIRC_TAB_SLOTS][BIRC_TAB_LABEL];
    const char *labs[BIRC_TAB_SLOTS];
    uint32_t alerts[BIRC_TAB_SLOTS] = {0};
    int ntabs, nalerts, orig, sel;
    r.x = (int)(uint32_t)f[0];
    r.y = (int)(uint32_t)f[1];
    r.w = (int)(uint32_t)f[2];
    r.h = 1;
    ntabs = birc_str_list(e, f[4], store, labs, BIRC_TAB_SLOTS);
    nalerts = birc_u32_list(e, f[5], alerts, BIRC_TAB_SLOTS);
    orig = (int)(uint32_t)f[3];
    sel = orig < 0 ? 0 : orig;
    if (ntabs > 0 && sel >= ntabs)
      sel = ntabs - 1;
    orig = sel;
    /* Tab index changes repaint via the cell diff; full_redraw is reserved
     * for grid size changes (timui_ui_resize_pixels above). */
    if (ly && ly->bu)
      ly->bu->last_tab = orig;
    if (fr && ntabs > 0)
      (void)timui_tabs(fr, TIMUI_ID("birc.bufs"), r, labs, ntabs, &sel);
    /* f[0..7] are OpTabs as declared in view.bend. Mention colours belong
     * in f[8] (bg) and f[9] (fg) once that constructor grows; until then
     * the historic dark pair is the only pair C can paint. */
    birc_draw_tab_alerts(fr, r, labs, ntabs, alerts, nalerts, sel,
                         BIRC_TAB_MENTION_BG, BIRC_TAB_MENTION_FG);
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
    if (ly && ly->bu && ly->ui && ly->bu->preview_count < BIRC_PREVIEW_CAP &&
        n <= (u64)SIZE_MAX) {
      preview = &ly->bu->previews[ly->bu->preview_count++];
      birc_preview_set(preview, ly->ui, path, (size_t)n);
    }
    if (fr && preview && preview->image && r.w > 0 && r.h > 0)
      timui_image_draw_clipped(fr, preview->image, r, r);
    free(path);
    spare_free(e, cls_fit(5), loc);
#ifdef CID_VIEW_OPMEDIA
  } else if (cid == CID_VIEW_OPMEDIA) {
    Term f[7];
    Loc loc = ctr_take(e, op, 7, f);
    if (ly)
      birc_draw_media(fr, ly->bu, ly->ui, (uint32_t)f[0], (uint32_t)f[1],
          (uint32_t)f[2], (uint32_t)f[3], (uint32_t)f[4], (uint32_t)f[5],
          (uint32_t)f[6]);
    spare_free(e, cls_fit(7), loc);
#endif
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
 * Own exactly one serialized frame and its accepted-byte offset. TimUI's
 * baseline describes that frame; it cannot advance again until bytes drain. */
static uint64_t birc_frame_deadline;
static int birc_frame_disabled;
static int birc_frame_attempted;

static int birc_output_pending(const Timui *ui) {
  BircUi *bu = birc_state(ui);
  return bu && (bu->output.size > 0 || bu->output.repaint ||
                ui->fd.write_utf8_tail_len != 0);
}

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
  /* A resize/network paint can read input before the parked tty watcher sees
   * readability. Its old wait may have no deadline, so the maintenance tick
   * must also expire timed parser states, independently of output readiness.
   * Partial UTF-8 (state 4) has no idle expiry and must not cause idle paints. */
  int timed_input = ui && ((ui->input.state >= 1 && ui->input.state <= 3) ||
                          ui->input.state == 5 || ui->input.state == 6 ||
                          ui->input.state == 7 || ui->input.pasting);
  uint32_t ready = timed_input || (birc_output_pending(ui) && birc_output_ready(ui)) ? 1u : 0u;
  (void)w;
  return io_tup(e, f[0], (Term)(uint64_t)ready);
}
static void __attribute__((constructor)) timui_redraw_ready_use(void) {
  io_eff(CID_TIMUI_REDRAW_READY, timui_redraw_ready_run);
}
#endif

static int birc_frame_write(TimuiTransport *t, const void *data, size_t n) {
  BircUi *bu = birc_state(birc_ui_live);
  int w;
  (void)t;
  if (birc_frame_disabled || !bu) {
    return -1;
  }
  w = birc_output_capture(&bu->output, data, n);
  return w;
}

static int birc_physical_write(TimuiTransport *t, const void *data, size_t n) {
  return timui_fd_write_((TimuiFdCtx *)t->ctx, data, n, 1,
                         birc_frame_deadline);
}

static void birc_frame_drain(Timui *ui, BircUi *bu) {
  TimuiTransport sink;
  int owned_frame;
  if (!bu || birc_frame_disabled || bu->output.capturing)
    return;
  sink = ui->transport;
  sink.write = birc_physical_write;
  owned_frame = bu->output.size > 0 || ui->fd.write_utf8_tail_len != 0;
  if (bu->output.size > 0) {
    if (birc_frame_attempted && timui_now_ms() >= birc_frame_deadline)
      return;
    birc_frame_attempted = 1;
    /* A serialized closing sequence is not a physically accepted close.
     * Signal/quit can abandon this frame; conservatively owe resync and a
     * synchronized-output end until every queued byte and scalar is out. */
    ui->framing_debt = 1;
    ui->sync_open = 1;
  }
  (void)birc_output_drain(&bu->output, &sink, birc_frame_deadline);
  if (bu->output.size == 0 && ui->fd.write_utf8_tail_len != 0) {
    if (birc_frame_attempted && timui_now_ms() >= birc_frame_deadline)
      return;
    birc_frame_attempted = 1;
  }
  if (bu->output.size == 0 &&
      timui_fd_write_(&ui->fd, "", 0, 1, birc_frame_deadline) == 0) {
    int i;
    if (owned_frame) {
      ui->framing_debt = 0;
      ui->sync_open = 0;
    }
    if (!birc_output_failure)
      for (i = 0; i < BIRC_PREVIEW_CAP; i++)
        if (bu->previews[i].retiring) {
          timui_image_retire_done_(ui, bu->previews[i].retiring);
          bu->previews[i].retiring = NULL;
        }
  }
}

/* One budget covers physical frame output, including image retirement,
 * OSC 52 and BEL. Short writes retain their byte offset, not a redraw request. */
static TimuiTransportWrite birc_output_begin(Timui *ui, int *saved_flags) {
  TimuiTransportWrite saved = ui->transport.write;
  BircUi *bu = birc_state(ui);
  int wait_ms = 40;
  *saved_flags = fcntl(ui->fd.write_fd, F_GETFL, 0);
  birc_frame_disabled = *saved_flags < 0 ||
      fcntl(ui->fd.write_fd, F_SETFL, *saved_flags | O_NONBLOCK) < 0;
  /* Writable means some bytes fit, not that a complete repaint will fit.
   * A repair gets bounded headroom, never the former two-second UI stall. */
  if (birc_output_pending(ui))
    wait_ms = birc_output_ready(ui) ? 200 : 0;
  birc_frame_deadline = timui_now_ms() + (uint64_t)wait_ms;
  birc_frame_attempted = 0;
  birc_frame_drain(ui, bu);
  if (bu)
    (void)birc_output_start(&bu->output);
  ui->transport.write = birc_frame_write;
  if (bu && bu->output.capturing)
    (void)timui_framing_settle_(ui);
  return saved;
}

static void birc_output_end(Timui *ui, TimuiTransportWrite saved,
                           int saved_flags) {
  BircUi *bu = birc_state(ui);
  if (bu && !birc_output_finish(&bu->output)) {
    birc_output_failure = 1;
    /* Captured settling bytes were discarded too. Memory acceptance cannot
     * discharge any physical debt from startup or the preceding frame. */
    ui->framing_debt = 1;
    ui->sync_open = 1;
    /* Failed capture never touched the physical output. Restore its diff
     * baseline in case a renderer callback already completed in memory. */
    timui_full_redraw(ui);
  }
  birc_frame_drain(ui, bu);
  ui->transport.write = saved;
  if (saved_flags >= 0 && !birc_frame_disabled)
    timui_fd_flags_restore_(ui->fd.write_fd, saved_flags);
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

static int birc_selection_append(char **out, size_t *cap, size_t *len,
                                  const char *text, size_t size) {
  size_t need, grown;
  char *next;
  if (size > SIZE_MAX - *len - 1)
    return 0;
  need = *len + size + 1;
  if (need > *cap) {
    grown = *cap;
    while (grown < need) {
      if (grown > SIZE_MAX / 2) { grown = need; break; }
      grown *= 2;
    }
    next = (char *)realloc(*out, grown);
    if (!next)
      return 0;
    *out = next;
    *cap = grown;
  }
  memcpy(*out + *len, text, size);
  *len += size;
  (*out)[*len] = '\0';
  return 1;
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
    size_t row_end = len;
    for (int x = start_col; x <= end_col; x++) {
      TimuiCell *c;
      uint32_t cp;
      char utf8[8];
      TimuiStr glyph;
      if (x < 0 || x >= buf->w || y < 0 || y >= buf->h) continue;
      c = &buf->cells[y * buf->w + x];
      if (c->flags & TIMUI_CELL_CONTINUATION) continue;
      cp = c->codepoint ? c->codepoint : (uint32_t)' ';
      glyph = timui_cell_grapheme(buf, c);
      if (!glyph.len) {
        glyph.ptr = utf8;
        glyph.len = (size_t)timui_utf8_encode_(cp, utf8);
      }
      if (glyph.len && !birc_selection_append(&out, &cap, &len, glyph.ptr, glyph.len)) {
        free(out);
        return;
      }
      /* Padding is a separate one-byte space cell. A space attached by ZWJ
       * belongs to its complete glyph and must not be trimmed from its bytes. */
      if (glyph.len != 1 || glyph.ptr[0] != ' ')
        row_end = len;
    }
    len = row_end;
    out[len] = '\0';
    if (y < to_y && !birc_selection_append(&out, &cap, &len, "\n", 1)) {
      free(out);
      return;
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


static int draw_composer(TimuiFrame *fr, int x, int y, int width,
                         BircUi *stt, size_t *tlen) {
  TimuiId id;
  TimuiRect r;
  TimuiTextAreaResult res;
  size_t n;
  int at_end;
  if (!fr || !stt) return 0;
  id = TIMUI_ID("birc.composer");
  if (timui_focus(fr) != id) timui_set_focus(fr, id);
  r.x = x;
  r.y = y;
  r.w = width;
  if (r.w < 1) r.w = 1;
  r.h = 1;
  /* Unmodified Right moves the cursor unless it is already at the end.
   * Only an at-end unmodified Right is reported, so Bend can accept the
   * ghost suffix. Shift+Right (tab switch) must still reach Bend. */
  at_end = stt->st.cursor >= strlen(stt->composer);
  res = timui_text_area_mut(fr, id, r, &stt->st, TIMUI_TEXT_AREA_ENTER_SUBMITS);
  if (!at_end && fr->ui && fr->ui->key_pressed == TIMUI_KEY_RIGHT &&
      fr->ui->key_mods == TIMUI_MOD_NONE)
    fr->ui->key_pressed = TIMUI_KEY_UNKNOWN;
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
  u32 compose_x = (u32)f[4];
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
  birc_profile_view_end(bu, profile_t0);
  input = io_cstr(e, f[2], &n_in);
  if (!ui) {
    free(input);
    birc_drop_ops(e, ops);
    return birc_uikeys(e, NULL, 0, "", 0, 24, 80, 0, (uint32_t)TIMUI_KEY_F10, 0, 0, 0, 0, "", "");
  }
  if (birc_sync_term_size(ui, &rows, &cols))
    timui_full_redraw(ui);
  if (bu && bu->profile_enabled)
    profile_t1 = birc_profile_now_ns();
  saved_write = birc_output_begin(ui, &saved_write_flags);
  if (!timui_begin(ui, &fr)) {
    birc_output_end(ui, saved_write, saved_write_flags);
    free(input);
    birc_drop_ops(e, ops);
    return birc_uikeys(e, ui, 0, "", 0, 24, 80, 0, (uint32_t)TIMUI_KEY_F10, 0, 0, 0, 0, "", "");
  }
  if (bu && bu->profile_enabled)
    profile_t2 = birc_profile_now_ns();
  birc_hold_ctrl_w(ui);

  {
    TimuiRect root = timui_root(fr);
    TimuiCellBuffer *buf = timui_frame_buffer(fr);
    TimuiStyle panel = timui_theme_style(&ui->theme, TIMUI_SLOT_PANEL);
    TimuiStyle border = timui_theme_style(&ui->theme, TIMUI_SLOT_BORDER);
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
      birc_media_prune(ui, bu);
      bu->link_url[0] = '\0';
      bu->ghost_on = 0;
      bu->ghost_w = 0;
      bu->ghost[0] = '\0';
      memset(bu->body_inner, 0, sizeof bu->body_inner);
      bu->composer_pane = -1;
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
    /* Inline composer: the widget sits on the last inner body row after
     * Bend's <nick> prefix. Bend tags the host OpBox PANE_COMPOSER (or
     * the sole body pane when only one is registered). compose_x is the
     * nick-prefix column from Bend. */
    if (bu) {
      int chosen = -1;
      if (bu->composer_pane >= 0 && bu->composer_pane < bu->body_count)
        chosen = bu->composer_pane;
      else if (bu->body_count == 1)
        chosen = 0;
      if (chosen >= 0) {
        TimuiRect in = bu->body_inner[chosen];
        int cy = in.y + in.h - 1;
        int64_t cx = (int64_t)compose_x;
        int cxx;
        int cw;
        if (cx < 0)
          cx = 0;
        if (cx > in.w)
          cx = in.w;
        cxx = in.x + (int)cx;
        cw = in.w - (int)cx;
        enter = draw_composer(fr, cxx, cy, cw, bu, &tlen);
        if (bu->ghost_on) {
          int gx = bu->ghost_x;
          int gw = bu->ghost_w;
          size_t gn = strlen(bu->ghost);
          /* A suffix is compose_x plus the draft width. A panel line saved
           * in the same slot is already a screen column, left of that. */
          if (gx >= (int)compose_x)
            gx += in.x;
          if (gw < 0)
            gw = 0;
          /* maxx from Bend OpGhost.w; birc_put_span / birc_clip_cols defend. */
          (void)birc_put_span(fr, gx, bu->ghost_y, gx + gw,
                              bu->ghost, gn, bu->ghost_fg, 0, NULL);
        }
      } else {
        enter = 0;
        tlen = 0;
      }
    }
    if (bu) {
      if (ui->ia.mouse_pressed) {
        int body_hit = -1;
        int i;
        for (i = 0; i < bu->body_count; i++) {
          TimuiRect in = bu->body_inner[i];
          /* The draft row is not selectable chat history. */
          if (in.h > 0 && ui->ia.mouse_y >= in.y + in.h - 1)
            continue;
          if (birc_pt_in_rect(ui->ia.mouse_x, ui->ia.mouse_y, in))
            body_hit = i;
        }
        if (body_hit >= 0) {
          bu->sel.active = 0;
          bu->sel.dragging = 1;
          bu->sel.start_x = bu->sel.cur_x = ui->ia.mouse_x;
          bu->sel.start_y = bu->sel.cur_y = ui->ia.mouse_y;
          bu->sel.pane = bu->body_inner[body_hit];
          if (bu->sel.pane.h > 0)
            bu->sel.pane.h -= 1;
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
    /* Clear selection before the overlay is painted. Esc that dismisses a
     * selection must not reach Bend (Bend maps Esc to quit). Upload-cancel
     * Esc is a separate path: with no selection, Esc is returned below and
     * Bend cancels a pending upload when one exists. */
    if (bu && bu->sel.active) {
      if (ui->key_pressed == TIMUI_KEY_ESCAPE) {
        bu->sel.active = 0;
        bu->sel.dragging = 0;
        ui->key_pressed = (TimuiKey)0;
      } else if (ui->key_pressed != 0 || enter || timui_mouse_wheel(fr) != 0) {
        bu->sel.active = 0;
        bu->sel.dragging = 0;
      }
    }
    if (bu && bu->sel.active) {
      birc_render_selection(timui_frame_buffer(fr), bu);
    }
    timui_end(fr);
    if (bu && bu->bell_pending) {
      if (birc_frame_write(&ui->transport, "\a", 1) == 1)
        bu->bell_pending = 0;
    }
    birc_output_end(ui, saved_write, saved_write_flags);
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
    /* Bend owns Escape/F10 policy: Escape may cancel a pending upload.
     * Fatal transport shutdown must bypass that cancelable action. */
    if (birc_output_failure || (timui_should_quit(ui) && key == 0))
      key = (uint32_t)TIMUI_KEY_F10;
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
  io_eff(CID_TIMUI_FRAME, timui_frame_run);
}
Term timui_close_run(Env e, Term *f, IoWork *w) {
  Timui *ui = (Timui *)(uintptr_t)io_hand_v(f[0]);
  BircUi *st = birc_state(ui);
  (void)e;
  (void)w;
  if (ui == birc_ui_live)
    birc_ui_live = NULL;
  if (ui && !timui_close_prepare_(ui)) {
    TimuiClosedOutput pending = {0};
    pending.fd.write_fd = ui->signal_host.write_fd;
    pending.retained_ui = ui;
    birc_final_take(&pending);
    return term_pak(CID_UNIT, 0);
  }
  if (st && st->profile_enabled) {
    char report[256];
    uint64_t deadline = timui_now_ms() + 40u;
    int same_report_stream = ui && birc_fd_same_stream(ui->fd.write_fd, STDERR_FILENO);
    int count = snprintf(report, sizeof report,
            "birc_profile frames=%llu prepare_us=%llu begin_us=%llu "
            "draw_us=%llu end_us=%llu view_us=%llu\n",
            (unsigned long long)st->profile_frames,
            (unsigned long long)birc_profile_us(st->profile_prepare_ns,
                                                st->profile_frames),
            (unsigned long long)birc_profile_us(st->profile_begin_ns,
                                                st->profile_frames),
            (unsigned long long)birc_profile_us(st->profile_draw_ns,
                                                st->profile_frames),
            (unsigned long long)birc_profile_us(st->profile_end_ns,
                                                st->profile_frames),
            (unsigned long long)birc_profile_us(st->profile_view_ns,
                                                st->profile_frames));
    /* stderr can alias the UI stream, including a redirected pipe. Finish
     * its accepted scalar before the report within the existing budget.
     * Unrelated stderr remains independent of terminal output. */
    int report_ready = !same_report_stream ||
        birc_settle_debt(&ui->fd, &ui->framing_debt, &ui->sync_open, deadline);
    if (count > 0 && (size_t)count < sizeof report &&
        report_ready)
      birc_write_bounded(NULL, STDERR_FILENO, report, (size_t)count,
                         deadline);
  }
  if (ui) {
    TimuiClosedOutput pending;
    /* TimUI retires and disowns image IDs under its one teardown budget.
     * Cached bitmaps can then be freed without further terminal IO. */
    timui_close_prepared_(ui, &pending, 0, 0);
    birc_final_take(&pending);
  }
  birc_state_destroy(st);
  return term_pak(CID_UNIT, 0);
}
static void __attribute__((constructor)) timui_close_use(void) {
  io_eff(CID_TIMUI_CLOSE, timui_close_run);
}
#ifdef CID_TIMUI_ISATTY
Term timui_isatty_run(Env e, Term *f, IoWork *w) {
  (void)e;
  (void)f;
  (void)w;
  return (Term)(isatty(0) ? 1u : 0u);
}
static void __attribute__((constructor)) timui_isatty_use(void) {
  io_eff(CID_TIMUI_ISATTY, timui_isatty_run);
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
  io_eff(CID_TIMUI_TTY, timui_tty_run);
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
  io_eff(CID_TTY_READY, fd_ready_run);
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
  io_eff(CID_TTY_CLOSE, tty_close_run);
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
  /* Linux: pipe2 sets CLOEXEC+NONBLOCK atomically. Darwin has neither
   * pipe2 nor SOCK_CLOEXEC in the SDK; fall back to pipe + F_SETFD/FL. */
#if defined(__linux__)
  if (pipe2(pfd, O_CLOEXEC | O_NONBLOCK) != 0)
    return io_fail(e, (u32)errno, "winch pipe");
#else
  if (pipe(pfd) != 0) return io_fail(e, (u32)errno, "winch pipe");
  if (fcntl(pfd[0], F_SETFD, FD_CLOEXEC) < 0 ||
      fcntl(pfd[1], F_SETFD, FD_CLOEXEC) < 0 ||
      fcntl(pfd[0], F_SETFL, O_NONBLOCK) < 0 ||
      fcntl(pfd[1], F_SETFL, O_NONBLOCK) < 0) {
    int err = errno;
    (void)close(pfd[0]);
    (void)close(pfd[1]);
    return io_fail(e, (u32)err, "winch cloexec");
  }
#endif
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
  io_eff(CID_WINCH_OPEN, winch_open_run);
}
#endif
#ifdef CID_WINCH_READY
static void __attribute__((constructor)) winch_ready_use(void) {
  io_eff(CID_WINCH_READY, fd_ready_run);
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
  io_eff(CID_WINCH_CLOSE, winch_close_run);
}
#endif
#if CID_SYS_PLATFORM
/* 1 = Apple, 0 = every other host. Program names are Bend policy. */
Term sys_platform_run(Env e, Term *f, IoWork *w) {
  (void)e;
  (void)f;
  (void)w;
#if defined(__APPLE__)
  return (Term)1u;
#else
  return (Term)0u;
#endif
}
static void __attribute__((constructor)) sys_platform_use(void) {
  io_eff(CID_SYS_PLATFORM, sys_platform_run);
}
#endif
#if CID_SYS_MEDIA_PROGRAM
Term sys_media_program_run(Env e, Term *f, IoWork *w) {
  const char *program = getenv("BIRC_MEDIA_HELPER");
  (void)f; (void)w;
  if (!program || !*program) program = "native";
  return io_str(e, program, strlen(program));
}
static void __attribute__((constructor)) sys_media_program_use(void) {
  io_eff(CID_SYS_MEDIA_PROGRAM, sys_media_program_run);
}
#endif
#if CID_SYS_EXIT_DONE
Term sys_exit_done_run(Env e, Term *f, IoWork *w) {
  TimuiFdCtx output = {0};
  output.write_fd = STDOUT_FILENO;
  (void)e;
  (void)f;
  (void)w;
  /* Timui.close restores blocking descriptor flags. Both IO.print and
   * IO.die (which always writes a stderr newline) can then hang. TimUI is
   * already closed; do not flush stdio or leave parked IO alive on success. */
  const char *status = birc_output_failure ? "birc=failed\n" : "birc=ok\n";
  birc_write_final(&output, status, strlen(status), timui_now_ms() + 250u);
  birc_final_before_exit();
  _Exit(birc_output_failure ? EXIT_FAILURE : EXIT_SUCCESS);
}
static void __attribute__((constructor)) sys_exit_done_use(void) {
  io_eff(CID_SYS_EXIT_DONE, sys_exit_done_run);
}
#endif
#if CID_SYS_EXIT_FAIL
Term sys_exit_fail_run(Env e, Term *f, IoWork *w) {
  TimuiFdCtx output = {0};
  u64 len = 0;
  char *msg = io_cstr(e, f[0], &len);
  uint64_t deadline = timui_now_ms() + 250u;
  output.write_fd = STDERR_FILENO;
  (void)w;
  /* Like successful shutdown, a restored tty must not block on stderr. */
  if (msg)
    birc_write_final(&output, msg, (size_t)len, deadline);
  birc_write_final(&output, "\n", 1, deadline);
  birc_final_before_exit();
  free(msg);
  _Exit(EXIT_FAILURE);
}
static void __attribute__((constructor)) sys_exit_fail_use(void) {
  io_eff(CID_SYS_EXIT_FAIL, sys_exit_fail_run);
}
#endif
#endif /* BIRC_TIMUI_FFI_C */
