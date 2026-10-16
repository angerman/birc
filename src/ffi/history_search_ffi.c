/* SPDX-License-Identifier: Apache-2.0
 * Retained-fd search scan: lstat plus one O_NOFOLLOW open plus fstat
 * evidence, then the scan reads via that same checked descriptor and
 * closes it exactly once. Reads refuse; they never repair and never
 * reopen by pathname. */
#ifndef BIRC_HISTORY_SEARCH_FFI_C
#define BIRC_HISTORY_SEARCH_FFI_C

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
/* Makefile links pass -I src/ffi, and a direct include of this file
 * searches src/ffi for the sibling header. Bend's `bend -o` paste
 * compiles a temporary translation unit with no -I, so that include
 * is invisible there; the #else text is birc_utf8_valid.h unchanged. */
#if __has_include("birc_utf8_valid.h")
#include "birc_utf8_valid.h"
#else
/* Strict UTF-8 (RFC 3629). Rejects overlong encodings, UTF-16 surrogates
 * (U+D800..U+DFFF), truncated sequences, and lead bytes outside
 * 0x00..0x7F / 0xC2..0xF4. U+0000, CR, and LF are valid UTF-8; callers
 * that forbid them apply that policy themselves. Empty input is valid.
 * A null pointer is not. */
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

/* Evidence bits: regular file, euid-owned, final symlink, mode 0600, missing. */
#define BIRC_SEARCH_REGULAR ((uint32_t)1u)
#define BIRC_SEARCH_OWNED ((uint32_t)2u)
#define BIRC_SEARCH_SYMLINK ((uint32_t)4u)
#define BIRC_SEARCH_PRIVATE ((uint32_t)8u)
#define BIRC_SEARCH_MISSING ((uint32_t)16u)
/* Scan status past the five file-evidence bits: early EOF against the
 * fstat snapshot (the file shrank mid-scan). Partial bytes are
 * discarded; Bend fails closed with the exact affine diagnostic. */
#define BIRC_SEARCH_TRUNCATED ((uint32_t)32u)

/* Bytes the retained scan reads via one descriptor; past the cap the scan
 * refuses closed (EFBIG) instead of truncating silently. */
#define BIRC_SEARCH_SCAN_MAX ((size_t)(8u * 1024u * 1024u))

typedef struct {
  uint32_t bits;
  uint32_t err;
} BircSearchEvidence;

typedef struct {
  uint32_t bits;
  uint32_t err;
  char *data;
  size_t len;
} BircSearchScan;

static void birc_history_search_scan_free(BircSearchScan *scan) {
  if (scan) {
    free(scan->data);
    scan->data = NULL;
    scan->len = 0;
  }
}

/* One checked open: lstat, then O_NOFOLLOW open. Returns the caller-owned
 * fd, or -1 with refused/missing bits (err 0) or err set. No fd escapes. */
static int birc_history_search_checked_open(const char *path, BircSearchEvidence *evidence) {
  struct stat listed;
  int fd = 0;
  evidence->bits = 0u;
  evidence->err = 0u;
  if (lstat(path, &listed) != 0) {
    if (errno == ENOENT) {
      evidence->bits |= BIRC_SEARCH_MISSING;
    } else {
      evidence->err = (uint32_t)errno;
    }
    return -1;
  }
  if (S_ISLNK(listed.st_mode)) {
    evidence->bits |= BIRC_SEARCH_SYMLINK;
    return -1;
  }
  fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
  if (fd < 0) {
    if (errno == ELOOP) {
      evidence->bits |= BIRC_SEARCH_SYMLINK;
    } else if (errno == ENOENT) {
      evidence->bits |= BIRC_SEARCH_MISSING;
    } else {
      evidence->err = (uint32_t)errno;
    }
    return -1;
  }
  return fd;
}

static uint32_t birc_history_search_fstat_bits(int fd, BircSearchEvidence *evidence, size_t *size) {
  struct stat info;
  if (fstat(fd, &info) != 0) {
    evidence->err = (uint32_t)errno;
    return 0u;
  }
  if (size) {
    *size = (size_t)info.st_size;
  }
  if (S_ISREG(info.st_mode)) {
    evidence->bits |= BIRC_SEARCH_REGULAR;
  }
  if (info.st_uid == geteuid()) {
    evidence->bits |= BIRC_SEARCH_OWNED;
  }
  if ((info.st_mode & (mode_t)0777) == (mode_t)0600) {
    evidence->bits |= BIRC_SEARCH_PRIVATE;
  }
  return 1u;
}

static int birc_history_search_admitted(uint32_t bits) {
  return (bits & BIRC_SEARCH_REGULAR) != 0u && (bits & BIRC_SEARCH_OWNED) != 0u
      && (bits & BIRC_SEARCH_PRIVATE) != 0u;
}

/* Strict UTF-8: the scan hands Bend exact bytes, so undecodable content
 * refuses closed (EILSEQ) instead of corrupting cursor offsets. */
static int birc_history_search_utf8_ok(const unsigned char *data, size_t len) {
  return birc_utf8_valid(data, len);
}

/* Snapshot-cutoff read core: reads EXACTLY snapshot bytes via the
 * checked fd. Post-snapshot appends are never read (cutoff); early EOF
 * (shrink) sets TRUNCATED with no content (partial bytes discarded);
 * a snapshot past cap refuses EFBIG before reading. Never closes: the
 * caller owns the fd exactly once. */
static BircSearchScan birc_history_search_scan_snapshot(int fd, uint32_t bits, size_t snapshot, size_t cap) {
  BircSearchScan scan = {0u, 0u, NULL, 0};
  size_t total = 0;
  char *data = NULL;
  scan.bits = bits;
  if (cap == 0 || cap > BIRC_SEARCH_SCAN_MAX) {
    cap = BIRC_SEARCH_SCAN_MAX;
  }
  if (snapshot > cap) {
    scan.err = (uint32_t)EFBIG;
    return scan;
  }
  data = (char *)malloc(snapshot + 1u);
  if (!data) {
    scan.err = (uint32_t)ENOMEM;
    return scan;
  }
  while (total < snapshot) {
    size_t want = snapshot - total;
    ssize_t got = 0;
    if (want > 65536u) {
      want = 65536u;
    }
    got = read(fd, data + total, want);
    if (got < 0) {
      if (errno == EINTR) {
        continue;
      }
      scan.err = (uint32_t)errno;
      free(data);
      return scan;
    }
    if (got == 0) {
      scan.bits |= BIRC_SEARCH_TRUNCATED;
      free(data);
      return scan;
    }
    total += (size_t)got;
  }
  if (!birc_history_search_utf8_ok((const unsigned char *)data, total)) {
    scan.err = (uint32_t)EILSEQ;
    free(data);
    return scan;
  }
  data[total] = '\0';
  scan.data = data;
  scan.len = total;
  return scan;
}

/* Retained scan: evidence plus the exact snapshot bytes read via the one
 * checked descriptor. The fd closes exactly once on success,
 * refusal-after-open, oversize, shrink, decode failure, and read error
 * alike. */
static BircSearchScan birc_history_search_scan(const char *path, size_t cap) {
  BircSearchScan scan = {0u, 0u, NULL, 0};
  BircSearchEvidence evidence = {0u, 0u};
  int fd = birc_history_search_checked_open(path, &evidence);
  size_t snapshot = 0;
  if (fd < 0) {
    scan.bits = evidence.bits;
    scan.err = evidence.err;
    return scan;
  }
  if (!birc_history_search_fstat_bits(fd, &evidence, &snapshot)) {
    scan.bits = evidence.bits;
    scan.err = evidence.err;
    (void)close(fd);
    return scan;
  }
  scan.bits = evidence.bits;
  if (!birc_history_search_admitted(evidence.bits)) {
    (void)close(fd);
    return scan;
  }
  scan = birc_history_search_scan_snapshot(fd, evidence.bits, snapshot, cap);
  (void)close(fd);
  return scan;
}

/* Checked private open for the affine-FD seam: one lstat plus O_NOFOLLOW
 * open plus fstat admission (regular, euid-owned, mode 0600). Returns the
 * caller-owned retained fd with *code 0, or -1 with *code ENOENT (missing),
 * EACCES (refused: symlink, non-regular, foreign, or non-private), or the
 * underlying errno. Descriptors from refused opens close here; only the
 * admitted fd escapes. */
static int birc_history_search_open_private(const char *path, uint32_t *code) {
  BircSearchEvidence evidence = {0u, 0u};
  int fd = birc_history_search_checked_open(path, &evidence);
  *code = 0u;
  if (fd < 0) {
    if ((evidence.bits & BIRC_SEARCH_MISSING) != 0u) {
      *code = (uint32_t)ENOENT;
    } else if (evidence.err != 0u) {
      *code = evidence.err;
    } else {
      *code = (uint32_t)EACCES;
    }
    return -1;
  }
  if (!birc_history_search_fstat_bits(fd, &evidence, NULL)) {
    *code = evidence.err;
    (void)close(fd);
    return -1;
  }
  if (!birc_history_search_admitted(evidence.bits)) {
    *code = (uint32_t)EACCES;
    (void)close(fd);
    return -1;
  }
  return fd;
}

#ifndef BIRC_HISTORY_SEARCH_CORE_ONLY
#ifndef CID_SEARCH_SCAN
#define CID_SEARCH_SCAN CID(search_scan)
#endif
#if CID_SEARCH_SCAN
typedef struct {
  char *path;
  uint32_t cap;
  BircSearchScan done;
  int scanned;
} BircSearchScanReq;

static void search_scan_req_free(BircSearchScanReq *request) {
  if (request) {
    free(request->path);
    birc_history_search_scan_free(&request->done);
    free(request);
  }
}

static void search_scan_call(IoWork *w) {
  BircSearchScanReq *request = (BircSearchScanReq *)w->data;
  request->done = birc_history_search_scan(request->path, (size_t)request->cap);
  request->scanned = 1;
}

static Term search_scan_pack(Env e, IoWork *w) {
  BircSearchScanReq *request = (BircSearchScanReq *)w->data;
  Term packed;
  const char *data = "";
  uint64_t len = 0;
  uint32_t bits = 0u;
  uint32_t err = (uint32_t)ENOMEM;
  if (request && request->scanned) {
    bits = request->done.bits;
    err = request->done.err;
    if (request->done.data) {
      data = request->done.data;
      len = (uint64_t)request->done.len;
    }
  } else if (request) {
    err = (uint32_t)w->code;
  }
  packed = io_tup(e, (Term)bits, io_tup(e, (Term)err, io_str(e, data, len)));
  search_scan_req_free(request);
  w->data = NULL;
  return packed;
}

Term search_scan_run(Env e, Term *f, IoWork *w) {
  uint64_t path_size = 0;
  BircSearchScanReq *request = (BircSearchScanReq *)calloc(1, sizeof *request);
  w->data = (char *)request;
  w->word = 0u;
  w->code = 0;
  if (!request) {
    term_sink(e, f[0]);
    term_sink(e, f[1]);
    w->code = ENOMEM;
    return search_scan_pack(e, w);
  }
  request->path = io_cstr(e, f[0], &path_size);
  request->cap = (u32)f[1];
  term_sink(e, f[1]);
  if (!request->path) {
    w->code = ENOMEM;
    return search_scan_pack(e, w);
  }
  if (io_nul(request->path, path_size)) {
    w->code = EILSEQ;
    return search_scan_pack(e, w);
  }
  return io_work(w, search_scan_call, search_scan_pack);
}

static void __attribute__((constructor)) search_scan_use(void) {
  io_eff(CID_SEARCH_SCAN, search_scan_run);
}
#endif
#ifndef CID_HISTORY_SEARCH_OPEN
#define CID_HISTORY_SEARCH_OPEN CID(open_private)
#endif
#if CID_HISTORY_SEARCH_OPEN
/* Retained-fd open effect, mirroring effs/file_open.c: the helper-thread
 * call runs the checked private open and the pack hands the retained fd
 * out as an affine File (refusals arrive as Fail and already closed). */
static void history_search_open_call(IoWork *w) {
  uint32_t code = 0u;
  int fd = birc_history_search_open_private(w->data, &code);
  w->code = code;
  w->made = (intptr_t)(fd < 0 ? 0 : fd);
}

static Term history_search_open_pack(Env e, IoWork *w) {
  free(w->data);
  return io_res(e, w, io_hand(w->made));
}

Term history_search_open_run(Env e, Term *f, IoWork *w) {
  w->data = io_cstr(e, f[0], &w->size);
  w->word = 0u;
  if (io_nul(w->data, w->size)) {
    w->code = EILSEQ;
    return history_search_open_pack(e, w);
  }
  return io_work(w, history_search_open_call, history_search_open_pack);
}

static void __attribute__((constructor)) history_search_open_use(void) {
  io_eff(CID_HISTORY_SEARCH_OPEN, history_search_open_run);
}
#endif
#endif /* BIRC_HISTORY_SEARCH_CORE_ONLY */
#endif /* BIRC_HISTORY_SEARCH_FFI_C */
