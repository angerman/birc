/* Feed bytes through timui_begin + composer like birc; count what submits. */
#define TIMUI_IMPLEMENTATION
#include "timui.h"
#include <stdio.h>
#include <string.h>

typedef struct {
  const unsigned char *p;
  size_t n, off;
} Src;

static int t_write(TimuiTransport *t, const void *d, size_t n) {
  (void)t;
  (void)d;
  return (int)n;
}

static int t_read(TimuiTransport *t, void *buf, size_t cap) {
  Src *s = (Src *)t->ctx;
  size_t k = s->n - s->off;
  if (k > cap)
    k = cap;
  memcpy(buf, s->p + s->off, k);
  s->off += k;
  return (int)k;
}

static int t_flush(TimuiTransport *t) {
  (void)t;
  return 0;
}

static void t_close(TimuiTransport *t) { (void)t; }

static int run(const char *name, const unsigned char *in, size_t n,
               size_t expected_subs) {
  Src s = {in, n, 0};
  TimuiTransport tr = {t_write, t_read, t_flush, t_close, &s};
  TimuiAllocator al = timui_default_allocator();
  Timui *ui = NULL;
  char comp[4096] = {0};
  TimuiTextAreaState st = {comp, sizeof comp, 0, 0};
  size_t subs = 0, bytes = 0;
  int f;
  timui_open_for_test(&ui, tr, 80, 24, &al);
  for (f = 0; f < 4000; f++) {
    TimuiFrame *fr;
    TimuiTextAreaResult r;
    TimuiRect rc = {0, 23, 80, 1};
    if (!timui_begin(ui, &fr))
      break;
    timui_set_focus(fr, TIMUI_ID("c"));
    r = timui_text_area_mut(fr, TIMUI_ID("c"), rc, &st,
                            TIMUI_TEXT_AREA_ENTER_SUBMITS);
    timui_end(fr);
    if (r.submitted) {
      subs++;
      bytes += strlen(comp);
      comp[0] = 0;
      st.cursor = 0;
    }
  }
  int dropped = timui_events_dropped(ui);
  printf("%s: in=%zu submits=%zu submitted_bytes=%zu leftover=%zu dropped=%d\n",
         name, n, subs, bytes, strlen(comp), dropped);
  timui_close(ui);
  if (dropped != 0 || subs != expected_subs)
    return 1;
  return 0;
}

int main(void) {
  static unsigned char b[8192];
  size_t n = 0, i;
  int bad = 0;
  /* A: bracketed paste of 200 lines "lineNNN\r" */
  n = 0;
  memcpy(b, "\x1b[200~", 6);
  n = 6;
  for (i = 0; i < 200; i++)
    n += (size_t)sprintf((char *)b + n, "line%03zu\r", i);
  memcpy(b + n, "\x1b[201~", 6);
  n += 6;
  bad += run("A 200 lines paste", b, n, 200);

  /* B: 250 bytes of Latin-1 0xE9 then CR, in paste (expands to U+FFFD x3) */
  n = 0;
  memcpy(b, "\x1b[200~", 6);
  n = 6;
  for (i = 0; i < 250; i++)
    b[n++] = 0xE9;
  b[n++] = '\r';
  memcpy(b + n, "\x1b[201~", 6);
  n += 6;
  bad += run("B 250 x 0xE9 paste", b, n, 1);

  {
    size_t k;
    size_t ks[] = {50, 84, 86, 100, 170};
    for (k = 0; k < 5; k++) {
      char nm[64];
      n = 0;
      memcpy(b, "\x1b[200~", 6);
      n = 6;
      for (i = 0; i < ks[k]; i++)
        b[n++] = 0xE9;
      b[n++] = '\r';
      b[n++] = 'o';
      b[n++] = 'k';
      b[n++] = '\r';
      memcpy(b + n, "\x1b[201~", 6);
      n += 6;
      snprintf(nm, sizeof nm, "B%zu", ks[k]);
      bad += run(nm, b, n, 2);
    }
  }

  bad += run("D caf\\xe9\\r", (const unsigned char *)"\x1b[200~caf\xe9\r\x1b[201~",
             18, 1);
  bad += run("E caf\\xe9\\rx\\r",
             (const unsigned char *)"\x1b[200~caf\xe9\rx\r\x1b[201~", 20, 2);

  /* C: typed (unbracketed) 300 lines */
  n = 0;
  for (i = 0; i < 300; i++)
    n += (size_t)sprintf((char *)b + n, "l%03zu\r", i);
  bad += run("C 300 typed lines", b, n, 300);

  if (bad)
    return 1;
  printf("paste_harness=ok\n");
  return 0;
}
