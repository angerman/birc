/* SPDX-License-Identifier: Apache-2.0
 * Private preferences file IO. Bend owns the wire and settings policy.
 * This effect admits the parent directory and file, locks, and stages. */
#ifndef BIRC_PREFERENCES_FFI_C
#define BIRC_PREFERENCES_FFI_C

#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE
#endif
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE
#endif

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#if defined(__APPLE__)
int getentropy(void *buffer, size_t size);
#else
#include <sys/random.h>
#endif

#define BIRC_PREFS_MAX_CONFIG 65536u
#define BIRC_PREFS_MAX_WIRE 40960u
#define BIRC_PREFS_MAX_MUTES 64u
#define BIRC_PREFS_MAX_CHANNELS 14u
#define BIRC_PREFS_MAX_SERVERS 16u
#define BIRC_PREFS_HOST_MAX 254u
#define BIRC_PREFS_MUTE_MAX 512u
#define BIRC_PREFS_CHAN_MAX 505u

typedef struct {
  uint64_t dev;
  uint64_t ino;
  uint64_t size;
  uint64_t mtime_ns;
  uint64_t ctime_ns;
} BircPrefsId;

typedef struct {
  int present;
  BircPrefsId id;
} BircPrefsPrev;

typedef struct {
  int joins, ts, motd, history, autoreconn, bell, images, nicks;
  uint32_t hist_cap;
  int theme; /* 0 dark, 1 light, 2 mono */
  char mutes[BIRC_PREFS_MAX_MUTES][BIRC_PREFS_MUTE_MAX + 1u];
  size_t mute_n;
  struct {
    char host[BIRC_PREFS_HOST_MAX + 1u];
    uint32_t port;
    char channels[BIRC_PREFS_MAX_CHANNELS][BIRC_PREFS_CHAN_MAX + 1u];
    size_t channel_n;
  } servers[BIRC_PREFS_MAX_SERVERS];
  size_t server_n;
} BircPrefsDoc;

static uint64_t birc_prefs_ns(const struct timespec *ts) {
  return (uint64_t)ts->tv_sec * 1000000000ull + (uint64_t)ts->tv_nsec;
}

static BircPrefsId birc_prefs_id(const struct stat *info) {
  BircPrefsId id;
#if defined(__APPLE__)
  id.dev = (uint64_t)info->st_dev;
  id.ino = (uint64_t)info->st_ino;
  id.size = (uint64_t)info->st_size;
  id.mtime_ns = birc_prefs_ns(&info->st_mtimespec);
  id.ctime_ns = birc_prefs_ns(&info->st_ctimespec);
#else
  id.dev = (uint64_t)info->st_dev;
  id.ino = (uint64_t)info->st_ino;
  id.size = (uint64_t)info->st_size;
  id.mtime_ns = birc_prefs_ns(&info->st_mtim);
  id.ctime_ns = birc_prefs_ns(&info->st_ctim);
#endif
  return id;
}

static int birc_prefs_id_eq(BircPrefsId a, BircPrefsId b) {
  return a.dev == b.dev && a.ino == b.ino && a.size == b.size
      && a.mtime_ns == b.mtime_ns && a.ctime_ns == b.ctime_ns;
}

static int birc_prefs_owned(const struct stat *info, int directory) {
  mode_t mask = directory ? (mode_t)0022 : (mode_t)0077;
  if (directory) {
    if (!S_ISDIR(info->st_mode))
      return 0;
  } else if (!S_ISREG(info->st_mode) || info->st_nlink != 1) {
    return 0;
  }
  return info->st_uid == geteuid() && (info->st_mode & mask) == 0;
}

static int birc_prefs_mkdir_p(const char *dir) {
  char buf[4096];
  size_t n = strlen(dir);
  size_t i;
  if (n == 0 || n >= sizeof buf)
    return -1;
  memcpy(buf, dir, n + 1u);
  for (i = 1; i <= n; i++) {
    if (i == n || buf[i] == '/') {
      char saved = buf[i];
      buf[i] = 0;
      if (buf[0] != 0 && !(buf[0] == '/' && buf[1] == 0)) {
        if (mkdir(buf, 0700) != 0 && errno != EEXIST)
          return -1;
      }
      buf[i] = saved;
    }
  }
  return 0;
}

static int birc_prefs_split(const char *path, char *dir, size_t dir_n,
                            char *name, size_t name_n) {
  const char *slash = strrchr(path, '/');
  if (path[0] == 0)
    return -1;
  if (!slash) {
    if (strlen(path) >= name_n || dir_n < 2)
      return -1;
    memcpy(name, path, strlen(path) + 1u);
    dir[0] = '.';
    dir[1] = 0;
    return 0;
  }
  {
    size_t dlen = (size_t)(slash - path);
    if (slash[1] == 0 || strlen(slash + 1) >= name_n)
      return -1;
    if (dlen == 0) {
      if (dir_n < 2)
        return -1;
      dir[0] = '/';
      dir[1] = 0;
    } else if (dlen >= dir_n) {
      return -1;
    } else {
      memcpy(dir, path, dlen);
      dir[dlen] = 0;
    }
    memcpy(name, slash + 1, strlen(slash + 1) + 1u);
    return 0;
  }
}

static int birc_prefs_open_parent(const char *dir, int create) {
  int fd;
  struct stat listed;
  struct stat opened;
  if (create && birc_prefs_mkdir_p(dir) != 0)
    return -1;
  if (lstat(dir, &listed) != 0)
    return -1;
  if (S_ISLNK(listed.st_mode)) {
    errno = ELOOP;
    return -1;
  }
  fd = open(dir, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0)
    return -1;
  if (fstat(fd, &opened) != 0 || !birc_prefs_owned(&opened, 1)
      || listed.st_dev != opened.st_dev || listed.st_ino != opened.st_ino) {
    (void)close(fd);
    errno = EPERM;
    return -1;
  }
  return fd;
}

static int birc_prefs_verify_parent(int dirfd, const char *dir) {
  struct stat opened;
  struct stat listed;
  if (fstat(dirfd, &opened) != 0 || !birc_prefs_owned(&opened, 1))
    return 4;
  if (lstat(dir, &listed) != 0)
    return 4;
  if (listed.st_dev != opened.st_dev || listed.st_ino != opened.st_ino)
    return 4;
  return 0;
}

static int birc_prefs_text(const char *s, size_t bound, int channel) {
  size_t n = strlen(s);
  size_t i;
  unsigned char c;
  if (n == 0 || n > bound)
    return 0;
  for (i = 0; s[i] != 0; i++) {
    c = (unsigned char)s[i];
    if (c < 33u || c == 127u)
      return 0;
  }
  if (!channel)
    return 1;
  c = (unsigned char)s[0];
  if (n <= 1 || c < 33u || c > 126u)
    return 0;
  if ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
      || c == ',' || c == ':')
    return 0;
  for (i = 1; s[i] != 0; i++) {
    if (s[i] == ',')
      return 0;
  }
  return 1;
}

static int birc_prefs_host_ok(const char *host) {
  size_t n = strlen(host);
  char canonical[256];
  const char *p;
  size_t part = 0;
  if (!birc_prefs_text(host, BIRC_PREFS_HOST_MAX, 0))
    return 0;
  if (n > 0 && host[n - 1] == '.') {
    if (n - 1 >= sizeof canonical)
      return 0;
    memcpy(canonical, host, n - 1);
    canonical[n - 1] = 0;
  } else {
    memcpy(canonical, host, n + 1u);
  }
  if (canonical[0] == 0 || strlen(canonical) > 253)
    return 0;
  for (p = host; *p; p++) {
    char ch = *p;
    if (!((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z')
          || (ch >= '0' && ch <= '9') || ch == '.' || ch == '-'))
      return 0;
  }
  for (p = canonical; ; p++) {
    if (*p == 0 || *p == '.') {
      if (part == 0 || part > 63)
        return 0;
      part = 0;
      if (*p == 0)
        break;
    } else {
      part++;
    }
  }
  return 1;
}

static int birc_prefs_scope(const char *host, uint32_t port) {
  if (host[0] == 0 && port == 0)
    return 0;
  if (!birc_prefs_host_ok(host) || port < 1u || port > 65535u)
    return -1;
  return 1;
}

static int birc_prefs_unique(const char *const *xs, size_t n) {
  size_t i, j;
  for (i = 0; i < n; i++) {
    for (j = i + 1; j < n; j++) {
      if (strcmp(xs[i], xs[j]) == 0)
        return 0;
    }
  }
  return 1;
}

static void birc_prefs_doc_init(BircPrefsDoc *doc) {
  memset(doc, 0, sizeof *doc);
  doc->nicks = 1;
}

static int birc_prefs_skip(const char **pp, const char *end) {
  const char *p = *pp;
  while (p < end) {
    if (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') {
      p++;
      continue;
    }
    if (*p == '#') {
      while (p < end && *p != '\n')
        p++;
      continue;
    }
    break;
  }
  *pp = p;
  return 0;
}

static int birc_prefs_take(const char **pp, const char *end, const char *lit) {
  size_t n = strlen(lit);
  birc_prefs_skip(pp, end);
  if ((size_t)(end - *pp) < n || memcmp(*pp, lit, n) != 0)
    return 0;
  *pp += n;
  return 1;
}

static int birc_prefs_ident(const char **pp, const char *end, char *out, size_t out_n) {
  const char *p;
  size_t n = 0;
  birc_prefs_skip(pp, end);
  p = *pp;
  if (p >= end)
    return 0;
  if (!((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z') || *p == '_'))
    return 0;
  while (p < end && ((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z')
                     || (*p >= '0' && *p <= '9') || *p == '_')) {
    if (n + 1 >= out_n)
      return 0;
    out[n++] = *p++;
  }
  out[n] = 0;
  *pp = p;
  return 1;
}

static int birc_prefs_hex(char c) {
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'a' && c <= 'f')
    return c - 'a' + 10;
  if (c >= 'A' && c <= 'F')
    return c - 'A' + 10;
  return -1;
}

static int birc_prefs_string(const char **pp, const char *end, char *out, size_t out_n) {
  const char *p;
  size_t n = 0;
  birc_prefs_skip(pp, end);
  p = *pp;
  if (p >= end || *p != '"')
    return 0;
  p++;
  while (p < end && *p != '"') {
    unsigned char ch;
    if (*p == '\\') {
      p++;
      if (p >= end)
        return 0;
      if (*p == '"' || *p == '\\' || *p == '/')
        ch = (unsigned char)*p++;
      else if (*p == 'n') {
        ch = '\n';
        p++;
      } else if (*p == 'u' && p + 5 <= end) {
        int a = birc_prefs_hex(p[1]);
        int b = birc_prefs_hex(p[2]);
        int c = birc_prefs_hex(p[3]);
        int d = birc_prefs_hex(p[4]);
        unsigned cp;
        if (a < 0 || b < 0 || c < 0 || d < 0)
          return 0;
        cp = (unsigned)((a << 12) | (b << 8) | (c << 4) | d);
        p += 5;
        if (cp < 0x80u) {
          ch = (unsigned char)cp;
        } else if (cp < 0x800u) {
          if (n + 2 >= out_n)
            return 0;
          out[n++] = (char)(0xc0u | (cp >> 6));
          ch = (unsigned char)(0x80u | (cp & 0x3fu));
        } else {
          if (n + 3 >= out_n)
            return 0;
          out[n++] = (char)(0xe0u | (cp >> 12));
          out[n++] = (char)(0x80u | ((cp >> 6) & 0x3fu));
          ch = (unsigned char)(0x80u | (cp & 0x3fu));
        }
      } else {
        return 0;
      }
    } else {
      ch = (unsigned char)*p++;
    }
    if (n + 1 >= out_n)
      return 0;
    out[n++] = (char)ch;
  }
  if (p >= end || *p != '"')
    return 0;
  out[n] = 0;
  *pp = p + 1;
  return 1;
}

static int birc_prefs_bool(const char **pp, const char *end, int *out) {
  if (birc_prefs_take(pp, end, "true")) {
    *out = 1;
    return 1;
  }
  if (birc_prefs_take(pp, end, "false")) {
    *out = 0;
    return 1;
  }
  return 0;
}

static int birc_prefs_u32(const char **pp, const char *end, uint32_t *out) {
  const char *p;
  uint64_t v = 0;
  int digits = 0;
  birc_prefs_skip(pp, end);
  p = *pp;
  while (p < end && *p >= '0' && *p <= '9') {
    v = v * 10u + (uint64_t)(*p - '0');
    if (v > 4294967295ull)
      return 0;
    digits++;
    p++;
  }
  if (digits == 0)
    return 0;
  *out = (uint32_t)v;
  *pp = p;
  return 1;
}

static int birc_prefs_strings(const char **pp, const char *end, char *xs, size_t stride,
                              size_t cap, size_t *n, size_t bound, int channel) {
  const char *ptrs[BIRC_PREFS_MAX_MUTES];
  size_t i;
  *n = 0;
  if (!birc_prefs_take(pp, end, "["))
    return 0;
  birc_prefs_skip(pp, end);
  if (birc_prefs_take(pp, end, "]"))
    return 1;
  for (;;) {
    char *slot;
    if (*n >= cap)
      return 0;
    slot = xs + (*n) * stride;
    if (!birc_prefs_string(pp, end, slot, bound + 1u))
      return 0;
    if (!birc_prefs_text(slot, bound, channel))
      return 0;
    (*n)++;
    birc_prefs_skip(pp, end);
    if (birc_prefs_take(pp, end, "]"))
      break;
    if (!birc_prefs_take(pp, end, ","))
      return 0;
  }
  for (i = 0; i < *n; i++)
    ptrs[i] = xs + i * stride;
  return birc_prefs_unique(ptrs, *n);
}

static int birc_prefs_set_key(BircPrefsDoc *doc, const char *key, const char **pp,
                              const char *end, unsigned *seen) {
  if (strcmp(key, "joins") == 0 && !(*seen & 1u)) {
    *seen |= 1u;
    return birc_prefs_bool(pp, end, &doc->joins);
  }
  if (strcmp(key, "ts") == 0 && !(*seen & 2u)) {
    *seen |= 2u;
    return birc_prefs_bool(pp, end, &doc->ts);
  }
  if (strcmp(key, "motd") == 0 && !(*seen & 4u)) {
    *seen |= 4u;
    return birc_prefs_bool(pp, end, &doc->motd);
  }
  if (strcmp(key, "history") == 0 && !(*seen & 8u)) {
    *seen |= 8u;
    return birc_prefs_bool(pp, end, &doc->history);
  }
  if (strcmp(key, "hist_cap") == 0 && !(*seen & 16u)) {
    *seen |= 16u;
    return birc_prefs_u32(pp, end, &doc->hist_cap);
  }
  if (strcmp(key, "autoreconn") == 0 && !(*seen & 32u)) {
    *seen |= 32u;
    return birc_prefs_bool(pp, end, &doc->autoreconn);
  }
  if (strcmp(key, "bell") == 0 && !(*seen & 64u)) {
    *seen |= 64u;
    return birc_prefs_bool(pp, end, &doc->bell);
  }
  if (strcmp(key, "images") == 0 && !(*seen & 128u)) {
    *seen |= 128u;
    return birc_prefs_bool(pp, end, &doc->images);
  }
  if (strcmp(key, "nicks") == 0 && !(*seen & 256u)) {
    *seen |= 256u;
    return birc_prefs_bool(pp, end, &doc->nicks);
  }
  if (strcmp(key, "theme") == 0 && !(*seen & 512u)) {
    char theme[8];
    *seen |= 512u;
    if (!birc_prefs_string(pp, end, theme, sizeof theme))
      return 0;
    if (strcmp(theme, "dark") == 0)
      doc->theme = 0;
    else if (strcmp(theme, "light") == 0)
      doc->theme = 1;
    else if (strcmp(theme, "mono") == 0)
      doc->theme = 2;
    else
      return 0;
    return 1;
  }
  if (strcmp(key, "mutes") == 0 && !(*seen & 1024u)) {
    *seen |= 1024u;
    return birc_prefs_strings(pp, end, (char *)doc->mutes, sizeof doc->mutes[0],
                              BIRC_PREFS_MAX_MUTES, &doc->mute_n, BIRC_PREFS_MUTE_MAX, 0);
  }
  return 0;
}

static int birc_prefs_parse_toml(const char *raw, size_t n, BircPrefsDoc *doc) {
  const char *p = raw;
  const char *end = raw + n;
  char key[32];
  unsigned seen = 0;
  int have_version = 0;
  int have_servers = 0;
  int have_settings = 0;
  birc_prefs_doc_init(doc);
  while (p < end) {
    birc_prefs_skip(&p, end);
    if (p >= end)
      break;
    if (birc_prefs_take(&p, end, "[[servers]]")) {
      size_t i;
      unsigned sseen = 0;
      if (doc->server_n >= BIRC_PREFS_MAX_SERVERS)
        return 0;
      have_servers = 1;
      i = doc->server_n++;
      while (p < end) {
        const char *save = p;
        birc_prefs_skip(&p, end);
        if (p >= end || *p == '[') {
          p = save;
          break;
        }
        if (!birc_prefs_ident(&p, end, key, sizeof key) || !birc_prefs_take(&p, end, "="))
          return 0;
        if (strcmp(key, "host") == 0 && !(sseen & 1u)) {
          sseen |= 1u;
          if (!birc_prefs_string(&p, end, doc->servers[i].host, sizeof doc->servers[i].host)
              || !birc_prefs_host_ok(doc->servers[i].host))
            return 0;
        } else if (strcmp(key, "port") == 0 && !(sseen & 2u)) {
          sseen |= 2u;
          if (!birc_prefs_u32(&p, end, &doc->servers[i].port)
              || doc->servers[i].port < 1u || doc->servers[i].port > 65535u)
            return 0;
        } else if (strcmp(key, "channels") == 0 && !(sseen & 4u)) {
          sseen |= 4u;
          if (!birc_prefs_strings(&p, end, (char *)doc->servers[i].channels,
                                  sizeof doc->servers[i].channels[0],
                                  BIRC_PREFS_MAX_CHANNELS, &doc->servers[i].channel_n,
                                  BIRC_PREFS_CHAN_MAX, 1))
            return 0;
        } else {
          return 0;
        }
      }
      if (sseen != 7u)
        return 0;
      continue;
    }
    if (birc_prefs_take(&p, end, "[settings]")) {
      have_settings = 1;
      continue;
    }
    if (!birc_prefs_ident(&p, end, key, sizeof key) || !birc_prefs_take(&p, end, "="))
      return 0;
    if (strcmp(key, "version") == 0) {
      uint32_t ver = 0;
      if (have_version || !birc_prefs_u32(&p, end, &ver) || ver != 1u)
        return 0;
      have_version = 1;
    } else if (strcmp(key, "servers") == 0) {
      if (have_servers || !birc_prefs_take(&p, end, "[") || !birc_prefs_take(&p, end, "]"))
        return 0;
      have_servers = 1;
    } else if (!have_settings || !birc_prefs_set_key(doc, key, &p, end, &seen)) {
      return 0;
    }
  }
  if (!have_version || !have_settings || !have_servers)
    return 0;
  /* Required settings omit optional nicks (256) and theme (512). */
  if ((seen & 1279u) != 1279u)
    return 0;
  {
    size_t i, j;
    for (i = 0; i < doc->server_n; i++) {
      for (j = i + 1; j < doc->server_n; j++) {
        if (strcmp(doc->servers[i].host, doc->servers[j].host) == 0
            && doc->servers[i].port == doc->servers[j].port)
          return 0;
      }
    }
  }
  return 1;
}

static int birc_prefs_json_escape(const char *s, char *out, size_t out_n) {
  size_t n = 0;
  if (n + 1 >= out_n)
    return 0;
  out[n++] = '"';
  while (*s) {
    unsigned char c = (unsigned char)*s++;
    if (c == '"' || c == '\\') {
      if (n + 3 >= out_n)
        return 0;
      out[n++] = '\\';
      out[n++] = (char)c;
    } else if (c < 32u) {
      return 0;
    } else {
      if (n + 2 >= out_n)
        return 0;
      out[n++] = (char)c;
    }
  }
  if (n + 2 > out_n)
    return 0;
  out[n++] = '"';
  out[n] = 0;
  return 1;
}

static int birc_prefs_put(char *out, size_t out_n, size_t *n, const char *s) {
  size_t add = strlen(s);
  if (*n + add >= out_n)
    return 0;
  memcpy(out + *n, s, add);
  *n += add;
  out[*n] = 0;
  return 1;
}

static int birc_prefs_encode(const BircPrefsDoc *doc, char *out, size_t out_n, size_t *used) {
  static const char *keys[] = {
    "joins", "ts", "motd", "history", "hist_cap", "autoreconn", "bell", "images", "nicks"
  };
  const int bits[] = {
    doc->joins, doc->ts, doc->motd, doc->history, -1, doc->autoreconn, doc->bell,
    doc->images, doc->nicks
  };
  char line[4096];
  char item[1024];
  size_t n = 0;
  size_t i, k;
  if (!birc_prefs_put(out, out_n, &n, "version = 1\n"))
    return 0;
  if (doc->server_n == 0 && !birc_prefs_put(out, out_n, &n, "servers = []\n"))
    return 0;
  if (!birc_prefs_put(out, out_n, &n, "\n[settings]\n"))
    return 0;
  for (k = 0; k < 9; k++) {
    if (k == 4) {
      if (snprintf(line, sizeof line, "hist_cap = %u\n", doc->hist_cap) < 0
          || !birc_prefs_put(out, out_n, &n, line))
        return 0;
    } else if (snprintf(line, sizeof line, "%s = %s\n", keys[k], bits[k] ? "true" : "false") < 0
               || !birc_prefs_put(out, out_n, &n, line)) {
      return 0;
    }
  }
  if (doc->theme == 1 && !birc_prefs_put(out, out_n, &n, "theme = \"light\"\n"))
    return 0;
  if (doc->theme == 2 && !birc_prefs_put(out, out_n, &n, "theme = \"mono\"\n"))
    return 0;
  if (!birc_prefs_put(out, out_n, &n, "mutes = ["))
    return 0;
  for (i = 0; i < doc->mute_n; i++) {
    if (i && !birc_prefs_put(out, out_n, &n, ", "))
      return 0;
    if (!birc_prefs_json_escape(doc->mutes[i], item, sizeof item)
        || !birc_prefs_put(out, out_n, &n, item))
      return 0;
  }
  if (!birc_prefs_put(out, out_n, &n, "]\n"))
    return 0;
  for (i = 0; i < doc->server_n; i++) {
    size_t c;
    if (!birc_prefs_json_escape(doc->servers[i].host, item, sizeof item))
      return 0;
    if (snprintf(line, sizeof line, "\n[[servers]]\nhost = %s\nport = %u\nchannels = [",
                 item, doc->servers[i].port) < 0
        || !birc_prefs_put(out, out_n, &n, line))
      return 0;
    for (c = 0; c < doc->servers[i].channel_n; c++) {
      if (c && !birc_prefs_put(out, out_n, &n, ", "))
        return 0;
      if (!birc_prefs_json_escape(doc->servers[i].channels[c], item, sizeof item)
          || !birc_prefs_put(out, out_n, &n, item))
        return 0;
    }
    if (!birc_prefs_put(out, out_n, &n, "]\n"))
      return 0;
  }
  if (n > BIRC_PREFS_MAX_CONFIG)
    return 0;
  *used = n;
  return 1;
}

static int birc_prefs_parse_wire(const char *body, size_t n, BircPrefsDoc *stg, int *known) {
  char copy[BIRC_PREFS_MAX_WIRE + 1u];
  char *lines[BIRC_PREFS_MAX_MUTES + BIRC_PREFS_MAX_CHANNELS + 8u];
  size_t line_n = 0;
  char *p;
  char *fields[12];
  size_t field_n = 0;
  size_t i;
  if (n > BIRC_PREFS_MAX_WIRE || n == 0 || body[n - 1] != '\n')
    return 0;
  memcpy(copy, body, n);
  copy[n] = 0;
  p = copy;
  while (*p) {
    if (line_n >= sizeof lines / sizeof lines[0])
      return 0;
    lines[line_n++] = p;
    p = strchr(p, '\n');
    if (!p)
      return 0;
    *p++ = 0;
  }
  if (line_n < 2 || strcmp(lines[0], "BIRC_PREFS1") != 0)
    return 0;
  p = lines[1];
  while (p) {
    if (field_n >= 12)
      return 0;
    fields[field_n++] = p;
    p = strchr(p, '\t');
    if (p)
      *p++ = 0;
  }
  if ((field_n != 9 && field_n != 10) || strcmp(fields[0], "settings") != 0)
    return 0;
  birc_prefs_doc_init(stg);
  *known = 1;
  for (i = 1; i <= 4; i++) {
    if (strcmp(fields[i], "0") != 0 && strcmp(fields[i], "1") != 0)
      return 0;
  }
  for (i = 6; i <= 8; i++) {
    if (strcmp(fields[i], "0") != 0 && strcmp(fields[i], "1") != 0)
      return 0;
  }
  if (field_n == 10 && strcmp(fields[9], "0") != 0 && strcmp(fields[9], "1") != 0)
    return 0;
  {
    size_t cap_n = strlen(fields[5]);
    uint32_t cap = 0;
    const char *c = fields[5];
    if (cap_n == 0 || cap_n > 10)
      return 0;
    while (*c) {
      if (*c < '0' || *c > '9')
        return 0;
      cap = cap * 10u + (uint32_t)(*c - '0');
      c++;
    }
    stg->hist_cap = cap;
  }
  stg->joins = fields[1][0] == '1';
  stg->ts = fields[2][0] == '1';
  stg->motd = fields[3][0] == '1';
  stg->history = fields[4][0] == '1';
  stg->autoreconn = fields[6][0] == '1';
  stg->bell = fields[7][0] == '1';
  stg->images = fields[8][0] == '1';
  stg->nicks = field_n == 9 ? 1 : fields[9][0] == '1';
  for (i = 2; i < line_n; i++) {
    char *tab = strchr(lines[i], '\t');
    char *kind;
    char *value;
    if (!tab || strchr(tab + 1, '\t'))
      return 0;
    *tab = 0;
    kind = lines[i];
    value = tab + 1;
    if (strcmp(kind, "mute") == 0) {
      if (stg->mute_n >= BIRC_PREFS_MAX_MUTES || !birc_prefs_text(value, BIRC_PREFS_MUTE_MAX, 0))
        return 0;
      memcpy(stg->mutes[stg->mute_n], value, strlen(value) + 1u);
      stg->mute_n++;
    } else if (strcmp(kind, "channel") == 0) {
      if (stg->server_n == 0)
        stg->server_n = 1;
      if (stg->servers[0].channel_n >= BIRC_PREFS_MAX_CHANNELS
          || !birc_prefs_text(value, BIRC_PREFS_CHAN_MAX, 1))
        return 0;
      memcpy(stg->servers[0].channels[stg->servers[0].channel_n], value, strlen(value) + 1u);
      stg->servers[0].channel_n++;
    } else if (strcmp(kind, "theme") == 0) {
      if (stg->theme != 0)
        return 0;
      if (strcmp(value, "light") == 0)
        stg->theme = 1;
      else if (strcmp(value, "mono") == 0)
        stg->theme = 2;
      else
        return 0;
    } else if (strcmp(kind, "scope") == 0 && strcmp(value, "0") == 0) {
      *known = 0;
    } else {
      return 0;
    }
  }
  {
    const char *ptrs[BIRC_PREFS_MAX_MUTES];
    size_t m;
    for (m = 0; m < stg->mute_n; m++)
      ptrs[m] = stg->mutes[m];
    if (!birc_prefs_unique(ptrs, stg->mute_n))
      return 0;
    for (m = 0; m < stg->servers[0].channel_n; m++)
      ptrs[m] = stg->servers[0].channels[m];
    if (!birc_prefs_unique(ptrs, stg->servers[0].channel_n))
      return 0;
  }
  return 1;
}

static int birc_prefs_show_wire(const BircPrefsDoc *doc, size_t server, int known,
                                char *out, size_t out_n, size_t *used) {
  const int bits[] = {
    doc->joins, doc->ts, doc->motd, doc->history, -1, doc->autoreconn, doc->bell,
    doc->images, doc->nicks
  };
  size_t n = 0;
  size_t i;
  char line[1024];
  if (!birc_prefs_put(out, out_n, &n, "BIRC_PREFS1\nsettings"))
    return 0;
  for (i = 1; i <= 9; i++) {
    if (i == 5) {
      if (snprintf(line, sizeof line, "\t%u", doc->hist_cap) < 0
          || !birc_prefs_put(out, out_n, &n, line))
        return 0;
    } else if (snprintf(line, sizeof line, "\t%d", bits[i - 1]) < 0
               || !birc_prefs_put(out, out_n, &n, line)) {
      return 0;
    }
  }
  if (!birc_prefs_put(out, out_n, &n, "\n"))
    return 0;
  if (doc->theme == 1 && !birc_prefs_put(out, out_n, &n, "theme\tlight\n"))
    return 0;
  if (doc->theme == 2 && !birc_prefs_put(out, out_n, &n, "theme\tmono\n"))
    return 0;
  for (i = 0; i < doc->mute_n; i++) {
    if (snprintf(line, sizeof line, "mute\t%s\n", doc->mutes[i]) < 0
        || !birc_prefs_put(out, out_n, &n, line))
      return 0;
  }
  if (known && server < doc->server_n) {
    for (i = 0; i < doc->servers[server].channel_n; i++) {
      if (snprintf(line, sizeof line, "channel\t%s\n", doc->servers[server].channels[i]) < 0
          || !birc_prefs_put(out, out_n, &n, line))
        return 0;
    }
  }
  if (!known && !birc_prefs_put(out, out_n, &n, "scope\t0\n"))
    return 0;
  *used = n;
  return 1;
}

static int birc_prefs_read_fd(int fd, const struct stat *info, char *buf, size_t buf_n, size_t *got) {
  size_t need;
  size_t n = 0;
  if ((uint64_t)info->st_size > BIRC_PREFS_MAX_CONFIG)
    return 2;
  need = (size_t)info->st_size;
  if (need >= buf_n)
    return 2;
  while (n < need) {
    ssize_t r = read(fd, buf + n, need - n);
    if (r < 0) {
      if (errno == EINTR)
        continue;
      return 3;
    }
    if (r == 0)
      return 4;
    n += (size_t)r;
  }
  buf[n] = 0;
  *got = n;
  return 0;
}

static int birc_prefs_snapshot(int dirfd, const char *name, BircPrefsDoc *doc, BircPrefsPrev *prev) {
  int fd;
  struct stat info;
  struct stat listed;
  char buf[BIRC_PREFS_MAX_CONFIG + 1u];
  size_t n = 0;
  int rc;
  prev->present = 0;
  fd = openat(dirfd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
  if (fd < 0) {
    if (errno == ENOENT)
      return 0;
    if (errno == ELOOP)
      return 3;
    return 3;
  }
  if (fstat(fd, &info) != 0) {
    (void)close(fd);
    return 3;
  }
  if (!birc_prefs_owned(&info, 0)) {
    (void)close(fd);
    return 3;
  }
  {
    BircPrefsId opened = birc_prefs_id(&info);
    rc = birc_prefs_read_fd(fd, &info, buf, sizeof buf, &n);
    if (rc != 0) {
      (void)close(fd);
      return rc;
    }
    if (fstat(fd, &info) != 0 || !birc_prefs_id_eq(opened, birc_prefs_id(&info))) {
      (void)close(fd);
      return 4;
    }
    if (fstatat(dirfd, name, &listed, AT_SYMLINK_NOFOLLOW) != 0
        || !birc_prefs_id_eq(opened, birc_prefs_id(&listed))) {
      (void)close(fd);
      return 4;
    }
  }
  (void)close(fd);
  if (!birc_prefs_parse_toml(buf, n, doc))
    return 2;
  prev->present = 1;
  prev->id = birc_prefs_id(&listed);
  return 0;
}

static int birc_prefs_lock(int dirfd, const char *name) {
  char lock[260];
  int fd;
  struct stat info;
  if (snprintf(lock, sizeof lock, "%s.lock", name) < 0)
    return -1;
  fd = openat(dirfd, lock, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0600);
  if (fd < 0)
    return -1;
  if (fstat(fd, &info) != 0 || !birc_prefs_owned(&info, 0) || fchmod(fd, 0600) != 0
      || flock(fd, LOCK_EX | LOCK_NB) != 0) {
    (void)close(fd);
    return -1;
  }
  return fd;
}

static int birc_prefs_token(char hex[25]) {
  unsigned char raw[12];
  static const char *digits = "0123456789abcdef";
  size_t i;
#if defined(__APPLE__)
  if (getentropy(raw, sizeof raw) != 0)
    return -1;
#else
  if (getentropy(raw, sizeof raw) != 0)
    return -1;
#endif
  for (i = 0; i < 12; i++) {
    hex[i * 2] = digits[raw[i] >> 4];
    hex[i * 2 + 1] = digits[raw[i] & 15u];
  }
  hex[24] = 0;
  return 0;
}

static int birc_prefs_commit(int dirfd, const char *dir, const char *name,
                             const char *data, size_t n, BircPrefsPrev prev) {
  char token[25];
  char staging[48];
  int fd = -1;
  int rc = 3;
  struct stat current;
  int have_current;
  if (birc_prefs_token(token) != 0)
    return 3;
  if (snprintf(staging, sizeof staging, ".preferences-%s.tmp", token) < 0)
    return 3;
  fd = openat(dirfd, staging, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
  if (fd < 0)
    return 3;
  if (fchmod(fd, 0600) != 0)
    goto done;
  {
    size_t off = 0;
    while (off < n) {
      ssize_t w = write(fd, data + off, n - off);
      if (w < 0) {
        if (errno == EINTR)
          continue;
        rc = 4;
        goto done;
      }
      if (w == 0) {
        rc = 4;
        goto done;
      }
      off += (size_t)w;
    }
  }
  if (fsync(fd) != 0)
    goto done;
  rc = birc_prefs_verify_parent(dirfd, dir);
  if (rc != 0)
    goto done;
  have_current = fstatat(dirfd, name, &current, AT_SYMLINK_NOFOLLOW) == 0;
  if (have_current == 0 && errno != ENOENT) {
    rc = 3;
    goto done;
  }
  if (prev.present != have_current
      || (have_current && !birc_prefs_id_eq(prev.id, birc_prefs_id(&current)))) {
    rc = 4;
    goto done;
  }
  if (renameat(dirfd, staging, dirfd, name) != 0) {
    rc = 3;
    goto done;
  }
  staging[0] = 0;
  if (fsync(dirfd) != 0) {
    rc = 3;
    goto done;
  }
  rc = 0;
done:
  if (staging[0] != 0)
    (void)unlinkat(dirfd, staging, 0);
  if (fd >= 0)
    (void)close(fd);
  return rc;
}

static int birc_prefs_find(const BircPrefsDoc *doc, const char *host, uint32_t port) {
  size_t i;
  for (i = 0; i < doc->server_n; i++) {
    if (strcmp(doc->servers[i].host, host) == 0 && doc->servers[i].port == port)
      return (int)i;
  }
  return -1;
}

static void birc_prefs_apply_settings(BircPrefsDoc *doc, const BircPrefsDoc *stg) {
  doc->joins = stg->joins;
  doc->ts = stg->ts;
  doc->motd = stg->motd;
  doc->history = stg->history;
  doc->hist_cap = stg->hist_cap;
  doc->autoreconn = stg->autoreconn;
  doc->bell = stg->bell;
  doc->images = stg->images;
  doc->nicks = stg->nicks;
  doc->theme = stg->theme;
  doc->mute_n = stg->mute_n;
  memcpy(doc->mutes, stg->mutes, sizeof doc->mutes);
}

uint32_t birc_prefs_read(const char *path, const char *host, uint32_t port,
                         char *out, size_t out_n, size_t *used) {
  char dir[4096];
  char name[256];
  int dirfd;
  int scope;
  BircPrefsDoc doc;
  BircPrefsPrev prev;
  int rc;
  int idx;
  *used = 0;
  if (!path || !host || path[0] == 0)
    return 0;
  scope = birc_prefs_scope(host, port);
  if (scope < 0)
    return 2;
  if (birc_prefs_split(path, dir, sizeof dir, name, sizeof name) != 0)
    return 2;
  dirfd = birc_prefs_open_parent(dir, 0);
  if (dirfd < 0)
    return errno == ENOENT ? 0 : 3;
  rc = birc_prefs_snapshot(dirfd, name, &doc, &prev);
  if (rc == 0)
    rc = birc_prefs_verify_parent(dirfd, dir) == 0 ? 0 : 4;
  (void)close(dirfd);
  if (rc != 0)
    return (uint32_t)rc;
  if (!prev.present)
    return 0;
  idx = scope ? birc_prefs_find(&doc, host, port) : -1;
  if (!birc_prefs_show_wire(&doc, idx < 0 ? doc.server_n : (size_t)idx, idx >= 0, out, out_n, used))
    return 2;
  return 0;
}

uint32_t birc_prefs_write(const char *path, const char *host, uint32_t port,
                          const char *wire, size_t wire_n) {
  char dir[4096];
  char name[256];
  char encoded[BIRC_PREFS_MAX_CONFIG + 1u];
  size_t encoded_n = 0;
  int dirfd = -1;
  int lockfd = -1;
  int scope;
  int known = 1;
  BircPrefsDoc stg;
  BircPrefsDoc doc;
  BircPrefsPrev prev;
  uint32_t rc = 3;
  if (!path || !host || !wire || path[0] == 0)
    return 0;
  scope = birc_prefs_scope(host, port);
  if (scope < 0)
    return 2;
  if (!birc_prefs_parse_wire(wire, wire_n, &stg, &known))
    return 2;
  if (scope == 0 && stg.servers[0].channel_n != 0)
    return 2;
  if (birc_prefs_split(path, dir, sizeof dir, name, sizeof name) != 0)
    return 2;
  dirfd = birc_prefs_open_parent(dir, 1);
  if (dirfd < 0)
    return 3;
  lockfd = birc_prefs_lock(dirfd, name);
  if (lockfd < 0)
    goto done;
  rc = (uint32_t)birc_prefs_snapshot(dirfd, name, &doc, &prev);
  if (rc != 0)
    goto done;
  if (!prev.present)
    birc_prefs_doc_init(&doc);
  birc_prefs_apply_settings(&doc, &stg);
  if (scope) {
    int idx = birc_prefs_find(&doc, host, port);
    if (idx < 0) {
      if (doc.server_n >= BIRC_PREFS_MAX_SERVERS) {
        rc = 2;
        goto done;
      }
      idx = (int)doc.server_n++;
      memcpy(doc.servers[idx].host, host, strlen(host) + 1u);
      doc.servers[idx].port = port;
    }
    doc.servers[idx].channel_n = stg.servers[0].channel_n;
    memcpy(doc.servers[idx].channels, stg.servers[0].channels, sizeof doc.servers[idx].channels);
  }
  if (!birc_prefs_encode(&doc, encoded, sizeof encoded, &encoded_n)) {
    rc = 2;
    goto done;
  }
  rc = (uint32_t)birc_prefs_commit(dirfd, dir, name, encoded, encoded_n, prev);
done:
  if (lockfd >= 0)
    (void)close(lockfd);
  if (dirfd >= 0)
    (void)close(dirfd);
  return rc;
}

#ifndef BIRC_PREFS_CORE_ONLY
#ifndef CID_PREFS_LOAD
#define CID_PREFS_LOAD CID(prefs_load)
#endif
#ifndef CID_PREFS_SAVE
#define CID_PREFS_SAVE CID(prefs_save)
#endif

#if CID_PREFS_LOAD
typedef struct {
  char *path;
  char *host;
  uint32_t port;
  uint32_t code;
  char *out;
  size_t out_n;
} BircPrefsLoad;

static void prefs_load_call(IoWork *w) {
  BircPrefsLoad *req = (BircPrefsLoad *)w->data;
  char buf[BIRC_PREFS_MAX_WIRE + 1u];
  size_t n = 0;
  req->code = birc_prefs_read(req->path, req->host, req->port, buf, sizeof buf, &n);
  req->out = NULL;
  req->out_n = 0;
  if (req->code == 0 && n > 0) {
    req->out = (char *)malloc(n + 1u);
    if (!req->out) {
      req->code = 3;
      return;
    }
    memcpy(req->out, buf, n);
    req->out[n] = 0;
    req->out_n = n;
  }
}

static Term prefs_load_pack(Env e, IoWork *w) {
  BircPrefsLoad *req = (BircPrefsLoad *)w->data;
  Term packed;
  const char *data = "";
  uint64_t len = 0;
  uint32_t code = 3;
  if (req) {
    code = req->code;
    if (req->out) {
      data = req->out;
      len = (uint64_t)req->out_n;
    }
  }
  packed = io_tup(e, (Term)code, io_str(e, data, len));
  if (req) {
    free(req->path);
    free(req->host);
    free(req->out);
    free(req);
  }
  w->data = NULL;
  return packed;
}

Term prefs_load_run(Env e, Term *f, IoWork *w) {
  uint64_t path_n = 0;
  uint64_t host_n = 0;
  BircPrefsLoad *req = (BircPrefsLoad *)calloc(1, sizeof *req);
  w->data = (char *)req;
  if (!req) {
    term_sink(e, f[0]);
    term_sink(e, f[1]);
    term_sink(e, f[2]);
    return prefs_load_pack(e, w);
  }
  req->path = io_cstr(e, f[0], &path_n);
  req->host = io_cstr(e, f[1], &host_n);
  req->port = (uint32_t)f[2];
  term_sink(e, f[2]);
  if (!req->path || !req->host || io_nul(req->path, path_n) || io_nul(req->host, host_n)) {
    req->code = 2;
    return prefs_load_pack(e, w);
  }
  return io_work(w, prefs_load_call, prefs_load_pack);
}

static void __attribute__((constructor)) prefs_load_use(void) {
  io_eff(CID_PREFS_LOAD, prefs_load_run);
}
#endif

#if CID_PREFS_SAVE
typedef struct {
  char *path;
  char *host;
  uint32_t port;
  char *wire;
  size_t wire_n;
  uint32_t code;
} BircPrefsSave;

static void prefs_save_call(IoWork *w) {
  BircPrefsSave *req = (BircPrefsSave *)w->data;
  req->code = birc_prefs_write(req->path, req->host, req->port, req->wire, req->wire_n);
}

static Term prefs_save_pack(Env e, IoWork *w) {
  BircPrefsSave *req = (BircPrefsSave *)w->data;
  uint32_t code = 3;
  (void)e;
  if (req) {
    code = req->code;
    free(req->path);
    free(req->host);
    free(req->wire);
    free(req);
  }
  w->data = NULL;
  return (Term)code;
}

Term prefs_save_run(Env e, Term *f, IoWork *w) {
  uint64_t path_n = 0;
  uint64_t host_n = 0;
  uint64_t wire_n = 0;
  BircPrefsSave *req = (BircPrefsSave *)calloc(1, sizeof *req);
  w->data = (char *)req;
  if (!req) {
    term_sink(e, f[0]);
    term_sink(e, f[1]);
    term_sink(e, f[2]);
    term_sink(e, f[3]);
    return prefs_save_pack(e, w);
  }
  req->path = io_cstr(e, f[0], &path_n);
  req->host = io_cstr(e, f[1], &host_n);
  req->port = (uint32_t)f[2];
  term_sink(e, f[2]);
  req->wire = io_cstr(e, f[3], &wire_n);
  if (!req->path || !req->host || !req->wire
      || io_nul(req->path, path_n) || io_nul(req->host, host_n)) {
    req->code = 2;
    return prefs_save_pack(e, w);
  }
  req->wire_n = (size_t)wire_n;
  return io_work(w, prefs_save_call, prefs_save_pack);
}

static void __attribute__((constructor)) prefs_save_use(void) {
  io_eff(CID_PREFS_SAVE, prefs_save_run);
}
#endif
#endif /* BIRC_PREFS_CORE_ONLY */
#endif /* BIRC_PREFERENCES_FFI_C */
