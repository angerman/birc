/* M0.5 TimUI hello foreign effect.
 * CID_TIMUI_HELLO — runs a short alt-screen loop and returns Unit.
 * Built via: bend … -o build/timui_hello.c && cc -Isrc/ui … */
#include <stdio.h>
#include <string.h>

#define TIMUI_IMPLEMENTATION
#include "timui.h"

Term timui_hello_run(Env e, Term *f, IoWork *w) {
  u32 max_frames = (u32)f[0];
  TimuiConfig cfg = TIMUI_CONFIG_INIT;
  Timui *ui = 0;
  u32 frames = 0;

  (void)w;
  cfg.title = "birc ffi hello";
  cfg.flags = TIMUI_FLAG_ALT_SCREEN | TIMUI_FLAG_RESTORE_ON_EXIT;
  cfg.theme = TIMUI_THEME_DOS_BLUE;

  if (timui_open(&cfg, &ui) != TIMUI_OK) {
    return io_fail(e, 1u, "timui_open failed");
  }

  while (!timui_should_quit(ui)) {
    TimuiFrame *fr = 0;
    TimuiRect root;
    if (!timui_begin(ui, &fr))
      break;
    root = timui_root(fr);
    timui_label(fr, root.x + 2, root.y + 2,
                TIMUI_STR_LIT("birc Timui.hello — Escape or frame budget"),
                timui_style_make(0x59ee3f, TIMUI_COLOR_DEFAULT, 0));
    if (timui_key_pressed(fr, TIMUI_KEY_ESCAPE))
      timui_quit(ui);
    timui_end(fr);
    frames += 1;
    if (max_frames > 0 && frames >= max_frames)
      timui_quit(ui);
  }

  timui_close(ui);
  return term_pak(CID_UNIT, 0);
}

static void __attribute__((constructor)) timui_hello_use(void) {
  io_eff(CID_TIMUI_HELLO, timui_hello_run, 0);
}
