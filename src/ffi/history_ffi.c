/* SPDX-License-Identifier: Apache-2.0
 * Scoped private history append. No global umask or path-based chmod. */
#ifndef BIRC_HISTORY_FFI_C
#define BIRC_HISTORY_FFI_C

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
/* Bend's `bend -o` paste has no -I. The #else text is birc_utf8_valid.h. */
#if __has_include("birc_utf8_valid.h")
#include "birc_utf8_valid.h"
#else
#ifndef BIRC_UTF8_VALID_H
#define BIRC_UTF8_VALID_H

#include <stddef.h>

static int birc_utf8_valid(const unsigned char *bytes, size_t size) {
  size_t at = 0;
  if (!bytes)
    return 0;
  while (at < size) {
    unsigned int lead = bytes[at++];
    unsigned int count;
    unsigned int low = 0x80u;
    unsigned int high = 0xbfu;
    if (lead < 0x80u)
      continue;
    if (lead >= 0xc2u && lead <= 0xdfu)
      count = 1u;
    else if (lead >= 0xe0u && lead <= 0xefu) {
      count = 2u;
      if (lead == 0xe0u)
        low = 0xa0u;
      if (lead == 0xedu)
        high = 0x9fu;
    } else if (lead >= 0xf0u && lead <= 0xf4u) {
      count = 3u;
      if (lead == 0xf0u)
        low = 0x90u;
      if (lead == 0xf4u)
        high = 0x8fu;
    } else
      return 0;
    if (size - at < count || bytes[at] < low || bytes[at] > high)
      return 0;
    ++at;
    while (--count > 0u) {
      if (bytes[at] < 0x80u || bytes[at] > 0xbfu)
        return 0;
      ++at;
    }
  }
  return 1;
}

#endif /* BIRC_UTF8_VALID_H */
#endif

typedef struct {
  uint32_t stage; /* 0 success, 1 open/policy, 2 write/close */
  uint32_t code;
} BircHistoryResult;

static BircHistoryResult birc_history_append(const char *path,
                                            const char *bytes, size_t size) {
  BircHistoryResult result = {1u, 0u};
  struct stat info;
  int fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC
                     | O_NOFOLLOW | O_NONBLOCK, 0600);
  if (fd < 0) {
    result.code = (uint32_t)errno;
    return result;
  }
  if (fstat(fd, &info) != 0) {
    result.code = (uint32_t)errno;
  } else if (!S_ISREG(info.st_mode) || info.st_uid != geteuid()) {
    result.code = (uint32_t)EPERM;
  } else if (fchmod(fd, 0600) != 0) {
    result.code = (uint32_t)errno;
  } else {
    size_t offset = 0;
    result.stage = 2u;
    while (offset < size) {
      ssize_t written = write(fd, bytes + offset, size - offset);
      if (written < 0) {
        if (errno == EINTR)
          continue;
        result.code = (uint32_t)errno;
        break;
      }
      if (written == 0) {
        result.code = (uint32_t)EIO;
        break;
      }
      offset += (size_t)written;
    }
  }
  if (close(fd) != 0 && result.code == 0)
    result.code = (uint32_t)errno;
  if (result.code == 0)
    result.stage = 0u;
  return result;
}

#ifndef BIRC_HISTORY_CORE_ONLY
#ifndef CID_APPEND_PRIVATE
#define CID_APPEND_PRIVATE CID(append_private)
#endif
#if CID_APPEND_PRIVATE
typedef struct {
  char *path;
  char *bytes;
  size_t size;
} BircHistoryAppend;

static void history_append_private_call(IoWork *w) {
  BircHistoryAppend *request = (BircHistoryAppend *)w->data;
  BircHistoryResult result = birc_history_append(request->path, request->bytes,
                                                request->size);
  w->word = result.stage;
  w->code = result.code;
}

static Term history_append_private_pack(Env e, IoWork *w) {
  BircHistoryAppend *request = (BircHistoryAppend *)w->data;
  if (request) {
    free(request->path);
    free(request->bytes);
    free(request);
  }
  w->data = NULL;
  return io_tup(e, (Term)w->word, (Term)(uint32_t)w->code);
}

Term history_append_private_run(Env e, Term *f, IoWork *w) {
  uint64_t path_size = 0, data_size = 0;
  BircHistoryAppend *request = (BircHistoryAppend *)calloc(1, sizeof *request);
  w->data = (char *)request;
  w->word = 1u;
  if (!request) {
    term_sink(e, f[0]);
    term_sink(e, f[1]);
    w->code = ENOMEM;
    return history_append_private_pack(e, w);
  }
  request->path = io_cstr(e, f[0], &path_size);
  request->bytes = io_cstr(e, f[1], &data_size);
  if (!request->path || !request->bytes) {
    w->code = ENOMEM;
    return history_append_private_pack(e, w);
  }
  if (data_size > SIZE_MAX || io_nul(request->path, path_size)) {
    w->code = data_size > SIZE_MAX ? EOVERFLOW : EILSEQ;
    return history_append_private_pack(e, w);
  }
  request->size = (size_t)data_size;
  return io_work(w, history_append_private_call, history_append_private_pack);
}

static void __attribute__((constructor)) history_append_private_use(void) {
  io_eff(CID_APPEND_PRIVATE, history_append_private_run);
}
#endif

/* Kept-line handoff. C frames newlines, drops an invalid or overlong
 * record, and retains the last min(cap, 1024) lines per target. Record
 * acceptance still runs in Bend on the returned fields. The ring simulates
 * an empty client (one server buffer): at most 14 channels stay alive, and
 * the oldest channel is dropped when another would be created. Display
 * names are that empty client's final buffer order so Bend can plant the
 * buffers before applying lines. A session that already holds channel
 * buffers is not passed in. */
#ifndef CID_READ_KEPT
#define CID_READ_KEPT CID(read_kept)
#endif
#if CID_READ_KEPT
#define BIRC_HIST_LINE_MAX 8192u
#define BIRC_HIST_CHUNK 65536u
#define BIRC_HIST_KEEP_MAX 1024u
#define BIRC_HIST_ALIVE_MAX 14u

typedef struct {
  uint32_t off;
  uint32_t len;
  uint32_t seq;
} BircHistSpan;

typedef struct {
  char *key;
  uint32_t key_len;
  char *display;
  uint32_t display_len;
  int alive;
  uint32_t last_seq;
  BircHistSpan *ring;
  uint32_t count;
  uint32_t next;
} BircHistSlot;

typedef struct {
  uint32_t off;
  uint32_t len;
} BircHistName;

typedef struct {
  char *arena;
  size_t arena_len;
  size_t arena_cap;
  BircHistSlot *slots;
  uint32_t slot_n;
  uint32_t slot_cap;
  uint32_t *hash;
  uint32_t hash_mask;
  uint32_t alive[BIRC_HIST_ALIVE_MAX];
  uint32_t alive_n;
  BircHistSpan *server;
  uint32_t server_n;
  uint32_t server_next;
  uint32_t keep;
  uint32_t seq;
  const unsigned char *ep;
  uint32_t ep_len;
  uint32_t stage;
  uint32_t err;
} BircHistScan;

typedef struct {
  char *path;
  char *endpoint;
  uint32_t cap;
  uint32_t stage;
  uint32_t err;
  char *arena;
  size_t arena_len;
  BircHistSpan *out;
  uint32_t out_n;
  char *names_arena;
  BircHistName *names;
  uint32_t name_n;
} BircHistRead;

static void birc_hist_release(void *p) {
  (free)(p);
}

static unsigned char birc_hist_fold(unsigned char c) {
  if (c >= 'a' && c <= 'z')
    c = (unsigned char)(c - (unsigned char)('a' - 'A'));
  if (c == '[')
    return '{';
  if (c == '\\')
    return '|';
  if (c == ']')
    return '}';
  if (c == '~')
    return '^';
  return c;
}

static int birc_hist_kind(const unsigned char *s, uint32_t n) {
  static const char *const kinds[] = {
    "MSG", "SELF", "SYS", "ACT", "NOT", "ERR", "HL", "PRS", "NCK"
  };
  uint32_t i;
  for (i = 0; i < 9u; i++) {
    size_t kn = strlen(kinds[i]);
    if ((size_t)n == kn && memcmp(s, kinds[i], kn) == 0)
      return 1;
  }
  return 0;
}

static int birc_hist_split7(const unsigned char *s, uint32_t n, uint32_t *off) {
  uint32_t i;
  uint32_t tabs = 0;
  off[0] = 0;
  for (i = 0; i < n; i++) {
    if (s[i] != '\t')
      continue;
    tabs++;
    if (tabs > 6u)
      return 0;
    off[tabs] = i + 1u;
  }
  if (tabs != 6u)
    return 0;
  off[7] = n;
  return 1;
}

static uint32_t birc_hist_field_at(const uint32_t *off, uint32_t i, uint32_t *begin) {
  uint32_t end = off[i + 1u];
  *begin = off[i];
  if (i < 6u)
    end -= 1u;
  return end;
}

static int birc_hist_eq_fold(const unsigned char *s, uint32_t n,
                             const unsigned char *ep, uint32_t ep_len) {
  uint32_t i;
  if (n != ep_len)
    return 0;
  for (i = 0; i < n; i++) {
    if (birc_hist_fold(s[i]) != ep[i])
      return 0;
  }
  return 1;
}

/* Unfolded buffer spelling: drop C0/DEL, strip one leading '@' when the
 * rest is a channel. '+' is a channel type and stays. Folding is only for
 * the hash key. */
static uint32_t birc_hist_norm(const unsigned char *s, uint32_t n, unsigned char *out) {
  uint32_t i;
  uint32_t m = 0;
  for (i = 0; i < n; i++) {
    unsigned char c = s[i];
    if (c < 32u || c == 127u)
      continue;
    out[m++] = c;
  }
  if (m >= 2u && out[0] == '@' &&
      (out[1] == '#' || out[1] == '&' || out[1] == '+' || out[1] == '!')) {
    memmove(out, out + 1, (size_t)m - 1u);
    m -= 1u;
  }
  return m;
}

static void birc_hist_fold_buf(unsigned char *s, uint32_t n) {
  uint32_t i;
  for (i = 0; i < n; i++)
    s[i] = birc_hist_fold(s[i]);
}

static uint32_t birc_hist_hash(const unsigned char *key, uint32_t n) {
  uint32_t h = 2166136261u;
  uint32_t i;
  for (i = 0; i < n; i++) {
    h ^= (uint32_t)key[i];
    h *= 16777619u;
  }
  return h;
}

static void birc_hist_scan_clear(BircHistScan *sc) {
  uint32_t i;
  for (i = 0; i < sc->slot_n; i++) {
    birc_hist_release(sc->slots[i].key);
    birc_hist_release(sc->slots[i].display);
    birc_hist_release(sc->slots[i].ring);
  }
  birc_hist_release(sc->slots);
  birc_hist_release(sc->hash);
  birc_hist_release(sc->server);
  sc->slots = NULL;
  sc->hash = NULL;
  sc->server = NULL;
}

static int birc_hist_rehash(BircHistScan *sc, uint32_t mask) {
  uint32_t *next = (uint32_t *)malloc(((size_t)mask + 1u) * sizeof *next);
  uint32_t i;
  if (!next)
    return 0;
  memset(next, 0, ((size_t)mask + 1u) * sizeof *next);
  for (i = 0; i < sc->slot_n; i++) {
    uint32_t at = birc_hist_hash((const unsigned char *)sc->slots[i].key,
                                 sc->slots[i].key_len) & mask;
    while (next[at] != 0u)
      at = (at + 1u) & mask;
    next[at] = i + 1u;
  }
  birc_hist_release(sc->hash);
  sc->hash = next;
  sc->hash_mask = mask;
  return 1;
}

static int birc_hist_lookup(const BircHistScan *sc, const unsigned char *key,
                            uint32_t key_len, uint32_t *slot) {
  uint32_t mask;
  uint32_t at;
  uint32_t n;
  if (sc->hash == NULL)
    return 0;
  mask = sc->hash_mask;
  at = birc_hist_hash(key, key_len) & mask;
  for (n = 0; n <= mask; n++) {
    uint32_t ent = sc->hash[at];
    BircHistSlot *got;
    if (ent == 0u)
      return 0;
    got = &sc->slots[ent - 1u];
    if (got->key_len == key_len &&
        memcmp(got->key, key, (size_t)key_len) == 0) {
      *slot = ent - 1u;
      return 1;
    }
    at = (at + 1u) & mask;
  }
  return 0;
}

static int birc_hist_insert(BircHistScan *sc, const unsigned char *key,
                            uint32_t key_len, uint32_t *slot) {
  uint32_t at;
  char *copy;
  if (sc->hash == NULL || sc->slot_n * 2u >= sc->hash_mask) {
    uint32_t mask = sc->hash == NULL ? 31u : (sc->hash_mask << 1) | 1u;
    if (!birc_hist_rehash(sc, mask))
      return 0;
  }
  if (sc->slot_n == sc->slot_cap) {
    uint32_t cap = sc->slot_cap == 0u ? 16u : sc->slot_cap * 2u;
    BircHistSlot *next = (BircHistSlot *)realloc(sc->slots, (size_t)cap * sizeof *next);
    if (!next)
      return 0;
    sc->slots = next;
    sc->slot_cap = cap;
  }
  copy = (char *)malloc((size_t)key_len + 1u);
  if (!copy)
    return 0;
  memcpy(copy, key, (size_t)key_len);
  copy[key_len] = '\0';
  memset(&sc->slots[sc->slot_n], 0, sizeof sc->slots[sc->slot_n]);
  sc->slots[sc->slot_n].key = copy;
  sc->slots[sc->slot_n].key_len = key_len;
  at = birc_hist_hash(key, key_len) & sc->hash_mask;
  while (sc->hash[at] != 0u)
    at = (at + 1u) & sc->hash_mask;
  sc->hash[at] = sc->slot_n + 1u;
  *slot = sc->slot_n;
  sc->slot_n++;
  return 1;
}

static void birc_hist_evict(BircHistScan *sc) {
  uint32_t best = 0;
  uint32_t i;
  uint32_t slot;
  if (sc->alive_n == 0u)
    return;
  for (i = 1; i < sc->alive_n; i++) {
    if (sc->slots[sc->alive[i]].last_seq < sc->slots[sc->alive[best]].last_seq)
      best = i;
  }
  slot = sc->alive[best];
  birc_hist_release(sc->slots[slot].ring);
  sc->slots[slot].ring = NULL;
  sc->slots[slot].count = 0;
  sc->slots[slot].next = 0;
  sc->slots[slot].alive = 0;
  sc->slots[slot].last_seq = 0;
  memmove(&sc->alive[best], &sc->alive[best + 1u],
          (size_t)(sc->alive_n - best - 1u) * sizeof sc->alive[0]);
  sc->alive_n--;
}

static int birc_hist_ring_push(BircHistScan *sc, BircHistSpan **ring, uint32_t *count,
                               uint32_t *next, uint32_t *last, uint32_t off, uint32_t len) {
  BircHistSpan span;
  span.off = off;
  span.len = len;
  span.seq = sc->seq;
  if (*ring == NULL) {
    *ring = (BircHistSpan *)malloc((size_t)sc->keep * sizeof **ring);
    if (*ring == NULL)
      return 0;
    memset(*ring, 0, (size_t)sc->keep * sizeof **ring);
  }
  if (*count < sc->keep) {
    (*ring)[*count] = span;
    (*count)++;
  } else {
    (*ring)[*next] = span;
    *next = (*next + 1u) % sc->keep;
  }
  if (last)
    *last = sc->seq;
  sc->seq++;
  return 1;
}

static int birc_hist_arena(BircHistScan *sc, const unsigned char *s, uint32_t n, uint32_t *off) {
  size_t need;
  if (n == 0u) {
    *off = (uint32_t)sc->arena_len;
    return 1;
  }
  need = sc->arena_len + (size_t)n;
  if (need > sc->arena_cap) {
    size_t cap = sc->arena_cap == 0u ? 4096u : sc->arena_cap;
    char *next;
    while (cap < need) {
      if (cap > SIZE_MAX / 2u)
        return 0;
      cap *= 2u;
    }
    next = (char *)realloc(sc->arena, cap);
    if (!next)
      return 0;
    sc->arena = next;
    sc->arena_cap = cap;
  }
  memcpy(sc->arena + sc->arena_len, s, (size_t)n);
  *off = (uint32_t)sc->arena_len;
  sc->arena_len = need;
  return 1;
}

static int birc_hist_set_display(BircHistSlot *slot, const unsigned char *s, uint32_t n) {
  char *copy = (char *)malloc((size_t)n + 1u);
  if (!copy)
    return 0;
  if (n != 0u)
    memcpy(copy, s, (size_t)n);
  copy[n] = '\0';
  birc_hist_release(slot->display);
  slot->display = copy;
  slot->display_len = n;
  return 1;
}

static int birc_hist_take(BircHistScan *sc, const unsigned char *s, uint32_t n) {
  uint32_t off7[8];
  uint32_t begin;
  uint32_t end;
  uint32_t stored;
  unsigned char norm[BIRC_HIST_LINE_MAX];
  unsigned char folded[BIRC_HIST_LINE_MAX];
  uint32_t key_len;
  uint32_t slot;
  const unsigned char *target;
  uint32_t target_n;
  if (sc->keep == 0u || n == 0u)
    return 1;
  if (!birc_utf8_valid(s, (size_t)n) || !birc_hist_split7(s, n, off7))
    return 1;
  end = birc_hist_field_at(off7, 0u, &begin);
  if (end - begin != 5u || memcmp(s + begin, "BIRC2", 5) != 0)
    return 1;
  end = birc_hist_field_at(off7, 1u, &begin);
  if (!birc_hist_eq_fold(s + begin, end - begin, sc->ep, sc->ep_len))
    return 1;
  end = birc_hist_field_at(off7, 3u, &begin);
  if (!birc_hist_kind(s + begin, end - begin))
    return 1;
  end = birc_hist_field_at(off7, 2u, &begin);
  if (end == begin)
    return 1;
  target = s + begin;
  target_n = end - begin;
  if (target_n == 8u && memcmp(target, "*server*", 8) == 0) {
    if (!birc_hist_arena(sc, s, n, &stored))
      return 0;
    return birc_hist_ring_push(sc, &sc->server, &sc->server_n, &sc->server_next,
                               NULL, stored, n);
  }
  key_len = birc_hist_norm(target, target_n, norm);
  if (key_len == 0u || norm[0] == '*')
    return 1;
  memcpy(folded, norm, (size_t)key_len);
  birc_hist_fold_buf(folded, key_len);
  if (!birc_hist_lookup(sc, folded, key_len, &slot)) {
    if (sc->alive_n >= BIRC_HIST_ALIVE_MAX)
      birc_hist_evict(sc);
    if (sc->alive_n >= BIRC_HIST_ALIVE_MAX ||
        !birc_hist_insert(sc, folded, key_len, &slot) ||
        !birc_hist_set_display(&sc->slots[slot], norm, key_len))
      return 0;
    sc->slots[slot].alive = 1;
    sc->alive[sc->alive_n++] = slot;
  } else if (!sc->slots[slot].alive) {
    if (sc->alive_n >= BIRC_HIST_ALIVE_MAX)
      birc_hist_evict(sc);
    if (sc->alive_n >= BIRC_HIST_ALIVE_MAX ||
        !birc_hist_set_display(&sc->slots[slot], norm, key_len))
      return 0;
    birc_hist_release(sc->slots[slot].ring);
    sc->slots[slot].ring = NULL;
    sc->slots[slot].count = 0;
    sc->slots[slot].next = 0;
    sc->slots[slot].alive = 1;
    sc->alive[sc->alive_n++] = slot;
  }
  if (!birc_hist_arena(sc, s, n, &stored))
    return 0;
  return birc_hist_ring_push(sc, &sc->slots[slot].ring, &sc->slots[slot].count,
                             &sc->slots[slot].next, &sc->slots[slot].last_seq,
                             stored, n);
}

static void birc_hist_copy_ring(BircHistSpan *dst, const BircHistSpan *ring,
                                uint32_t count, uint32_t next, uint32_t keep) {
  uint32_t i;
  if (count < keep || next == 0u) {
    for (i = 0; i < count; i++)
      dst[i] = ring[i];
    return;
  }
  for (i = 0; i < count; i++)
    dst[i] = ring[(next + i) % keep];
}

static int birc_hist_span_cmp(const void *left, const void *right) {
  const BircHistSpan *a = left;
  const BircHistSpan *b = right;
  if (a->seq < b->seq)
    return -1;
  if (a->seq > b->seq)
    return 1;
  return 0;
}

static int birc_hist_collect(BircHistScan *sc, BircHistRead *req) {
  uint32_t n = sc->server_n;
  uint32_t i;
  uint32_t at = 0;
  for (i = 0; i < sc->alive_n; i++)
    n += sc->slots[sc->alive[i]].count;
  req->out = NULL;
  req->out_n = 0;
  if (n == 0u)
    return 1;
  req->out = (BircHistSpan *)malloc((size_t)n * sizeof *req->out);
  if (!req->out)
    return 0;
  if (sc->server_n != 0u) {
    birc_hist_copy_ring(req->out, sc->server, sc->server_n, sc->server_next, sc->keep);
    at = sc->server_n;
  }
  for (i = 0; i < sc->alive_n; i++) {
    BircHistSlot *slot = &sc->slots[sc->alive[i]];
    birc_hist_copy_ring(req->out + at, slot->ring, slot->count, slot->next, sc->keep);
    at += slot->count;
  }
  qsort(req->out, (size_t)n, sizeof *req->out, birc_hist_span_cmp);
  req->out_n = n;
  return 1;
}

static void birc_hist_copy_names(BircHistScan *sc, BircHistRead *req) {
  size_t bytes = 1u;
  size_t at = 0;
  uint32_t i;
  char *arena;
  BircHistName *names;
  if (sc->alive_n == 0u)
    return;
  names = (BircHistName *)malloc((size_t)sc->alive_n * sizeof *names);
  if (!names)
    return;
  for (i = 0; i < sc->alive_n; i++)
    bytes += sc->slots[sc->alive[i]].display_len;
  arena = (char *)malloc(bytes);
  if (!arena) {
    birc_hist_release(names);
    return;
  }
  for (i = 0; i < sc->alive_n; i++) {
    BircHistSlot *slot = &sc->slots[sc->alive[i]];
    names[i].off = (uint32_t)at;
    names[i].len = slot->display_len;
    if (slot->display_len != 0u && slot->display != NULL)
      memcpy(arena + at, slot->display, (size_t)slot->display_len);
    at += slot->display_len;
  }
  req->names = names;
  req->names_arena = arena;
  req->name_n = sc->alive_n;
}

static void birc_hist_read(BircHistScan *sc, int fd, uint32_t remaining) {
  unsigned char carry[BIRC_HIST_LINE_MAX];
  unsigned char chunk[BIRC_HIST_CHUNK];
  uint32_t carry_n = 0;
  int dropping = 0;
  while (remaining > 0u && sc->stage == 0u) {
    uint32_t want = remaining > BIRC_HIST_CHUNK ? BIRC_HIST_CHUNK : remaining;
    ssize_t got = (read)(fd, chunk, (size_t)want);
    uint32_t n;
    uint32_t i;
    if (got < 0) {
      if (errno == EINTR)
        continue;
      sc->stage = 4u;
      sc->err = (uint32_t)errno;
      break;
    }
    if (got == 0)
      break;
    n = (uint32_t)got;
    if (n > remaining)
      n = remaining;
    remaining -= n;
    for (i = 0; i < n; i++) {
      unsigned char byte = chunk[i];
      if (byte == '\n') {
        if (!dropping && !birc_hist_take(sc, carry, carry_n)) {
          sc->stage = 4u;
          sc->err = (uint32_t)ENOMEM;
          return;
        }
        carry_n = 0;
        dropping = 0;
      } else if (dropping || carry_n >= BIRC_HIST_LINE_MAX) {
        dropping = 1;
      } else {
        carry[carry_n++] = byte;
      }
    }
  }
}

static void birc_hist_scan(BircHistScan *sc, int fd, uint32_t size,
                           const unsigned char *ep, uint32_t ep_len, uint32_t keep) {
  memset(sc, 0, sizeof *sc);
  sc->ep = ep;
  sc->ep_len = ep_len;
  sc->keep = keep > BIRC_HIST_KEEP_MAX ? BIRC_HIST_KEEP_MAX : keep;
  birc_hist_read(sc, fd, size);
}

static Term birc_hist_fields(Env e, const char *arena, BircHistSpan span) {
  const unsigned char *s = (const unsigned char *)arena + span.off;
  uint32_t off[8];
  Term fields = term_pak(CID(Nil), 0);
  uint32_t i;
  if (!birc_hist_split7(s, span.len, off))
    return fields;
  for (i = 7u; i > 0u; i--) {
    uint32_t begin = 0;
    uint32_t end = birc_hist_field_at(off, i - 1u, &begin);
    const char *p = (const char *)s + begin;
    fields = io_node(e, CID(Con), io_str(e, end == begin ? "" : p, (u64)(end - begin)), fields);
  }
  return fields;
}

static void history_read_kept_free(BircHistRead *req) {
  if (!req)
    return;
  birc_hist_release(req->path);
  birc_hist_release(req->endpoint);
  birc_hist_release(req->arena);
  birc_hist_release(req->out);
  birc_hist_release(req->names_arena);
  birc_hist_release(req->names);
  birc_hist_release(req);
}

static void history_read_kept_call(IoWork *w) {
  BircHistRead *req = (BircHistRead *)w->data;
  BircHistScan sc;
  struct stat info;
  int fd;
  unsigned char *ep;
  uint32_t i;
  if (!req)
    return;
  req->stage = 2u;
  req->err = (uint32_t)EINVAL;
  do {
    fd = open(req->path, O_RDONLY | O_CLOEXEC, 0);
  } while (fd < 0 && errno == EINTR);
  if (fd < 0) {
    req->stage = errno == ENOENT ? 1u : 2u;
    req->err = (uint32_t)errno;
    return;
  }
  if ((fstat)(fd, &info) != 0) {
    req->stage = 3u;
    req->err = (uint32_t)errno;
    (close)(fd);
    return;
  }
  if (info.st_size < 0 || (uint64_t)info.st_size > (uint64_t)UINT32_MAX) {
    req->stage = 3u;
    req->err = (uint32_t)EOVERFLOW;
    (close)(fd);
    return;
  }
  ep = (unsigned char *)malloc((size_t)strlen(req->endpoint) + 1u);
  if (!ep) {
    req->stage = 4u;
    req->err = (uint32_t)ENOMEM;
    (close)(fd);
    return;
  }
  for (i = 0; req->endpoint[i] != '\0'; i++)
    ep[i] = birc_hist_fold((unsigned char)req->endpoint[i]);
  ep[i] = '\0';
  birc_hist_scan(&sc, fd, (uint32_t)info.st_size, ep, i, req->cap);
  birc_hist_release(ep);
  (close)(fd);
  if (!birc_hist_collect(&sc, req)) {
    req->stage = 4u;
    req->err = (uint32_t)ENOMEM;
    birc_hist_release(req->out);
    req->out = NULL;
    req->out_n = 0;
    birc_hist_release(sc.arena);
    sc.arena = NULL;
  } else {
    req->stage = sc.stage;
    req->err = sc.err;
    req->arena = sc.arena;
    req->arena_len = sc.arena_len;
    sc.arena = NULL;
    birc_hist_copy_names(&sc, req);
  }
  birc_hist_scan_clear(&sc);
}

static Term birc_hist_name_at(Env e, const BircHistRead *req, uint32_t i) {
  BircHistName name = req->names[i];
  const char *p = req->names_arena + name.off;
  if (name.len == 0u)
    return io_str(e, "", 0);
  return io_str(e, p, (u64)name.len);
}

static Term history_read_kept_pack(Env e, IoWork *w) {
  BircHistRead *req = (BircHistRead *)w->data;
  Term names = term_pak(CID(Nil), 0);
  Term lines = term_pak(CID(Nil), 0);
  uint32_t stage = 2u;
  uint32_t err = (uint32_t)ENOMEM;
  if (req) {
    uint32_t i;
    stage = req->stage;
    err = req->err;
    if (req->names_arena && req->names) {
      for (i = req->name_n; i > 0u; i--)
        names = io_node(e, CID(Con), birc_hist_name_at(e, req, i - 1u), names);
    }
    if (req->arena && req->out) {
      for (i = req->out_n; i > 0u; i--)
        lines = io_node(e, CID(Con), birc_hist_fields(e, req->arena, req->out[i - 1u]), lines);
    }
  }
  history_read_kept_free(req);
  w->data = NULL;
  return io_tup(e, (Term)stage, io_tup(e, (Term)err, io_tup(e, names, lines)));
}

Term history_read_kept_run(Env e, Term *f, IoWork *w) {
  uint64_t path_size = 0;
  uint64_t ep_size = 0;
  BircHistRead *req = (BircHistRead *)calloc(1, sizeof *req);
  w->data = (char *)req;
  w->word = 0u;
  w->code = 0;
  if (!req) {
    term_sink(e, f[0]);
    term_sink(e, f[1]);
    term_sink(e, f[2]);
    return history_read_kept_pack(e, w);
  }
  req->path = io_cstr(e, f[0], &path_size);
  req->endpoint = io_cstr(e, f[1], &ep_size);
  req->cap = (uint32_t)f[2];
  term_sink(e, f[2]);
  req->stage = 2u;
  req->err = (uint32_t)ENOMEM;
  if (!req->path || !req->endpoint)
    return history_read_kept_pack(e, w);
  if (io_nul(req->path, path_size) || io_nul(req->endpoint, ep_size)) {
    req->err = (uint32_t)EILSEQ;
    return history_read_kept_pack(e, w);
  }
  return io_work(w, history_read_kept_call, history_read_kept_pack);
}

static void __attribute__((constructor)) history_read_kept_use(void) {
  io_eff(CID_READ_KEPT, history_read_kept_run);
}
#endif
#endif /* BIRC_HISTORY_CORE_ONLY */
#endif /* BIRC_HISTORY_FFI_C */
