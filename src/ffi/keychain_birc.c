/* SPDX-License-Identifier: Apache-2.0
 * macOS Keychain launcher. Profiles are public TOML; secrets stay in Keychain
 * or one inherited EOF pipe. C admits the file and talks to /usr/bin/security;
 * Bend owns authentication once birc is running. */
#ifndef BIRC_KEYCHAIN_BIRC_C
#define BIRC_KEYCHAIN_BIRC_C

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
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#define BIRC_KC_MAX_SECRET 1024u
#define BIRC_KC_MAX_CONFIG (64u * 1024u)
#define BIRC_KC_MAX_CHANS 14u
#define BIRC_KC_CHAN_MAX 505u
#define BIRC_KC_CSV_MAX 7083u
#define BIRC_KC_NAME_MAX 64u
#define BIRC_KC_HOST_MAX 260u
#define BIRC_KC_ACCOUNT_MAX 128u
#define BIRC_KC_NICK_MAX 64u
#define BIRC_KC_PREFIX_MAX 255u
#define BIRC_KC_CONFIRM_MAX 512u
#define BIRC_KC_SERVICE_MAX 512u
#define BIRC_KC_SUCCESS "BIRC_AUTH_OK\n"
#define BIRC_KC_ENVELOPE "birc-v1:"
#define BIRC_KC_SECURITY "/usr/bin/security"

typedef struct {
  char host[BIRC_KC_HOST_MAX + 1u];
  uint32_t port;
  char account[BIRC_KC_ACCOUNT_MAX + 1u];
  char nick[BIRC_KC_NICK_MAX + 1u];
  char auth[16];
  char prefix[BIRC_KC_PREFIX_MAX + 1u];
  char confirmation[BIRC_KC_CONFIRM_MAX + 1u];
  int relay;
  char service[BIRC_KC_SERVICE_MAX];
  int tls;
  char channels[BIRC_KC_MAX_CHANS][BIRC_KC_CHAN_MAX + 1u];
  size_t channel_n;
  int has_channels;
} BircKcProfile;

typedef struct {
  char name[BIRC_KC_NAME_MAX + 1u];
  BircKcProfile profile;
  unsigned seen;
  int used;
} BircKcRow;

typedef struct {
  BircKcRow rows[32];
  size_t n;
} BircKcDoc;

static const char *birc_kc_why = "";

static void birc_kc_fail(const char *why) {
  birc_kc_why = why;
}

static int birc_kc_trusted(const struct stat *info, int file, mode_t mask) {
  if (file && !S_ISREG(info->st_mode))
    return 0;
  return info->st_uid == getuid() && (info->st_mode & mask) == 0;
}

static int birc_kc_utf8_space(unsigned cp) {
  return cp == 0x00a0u || cp == 0x1680u || (cp >= 0x2000u && cp <= 0x200au)
      || cp == 0x2028u || cp == 0x2029u || cp == 0x202fu || cp == 0x205fu
      || cp == 0x3000u;
}

static int birc_kc_next_cp(const char *s, size_t *i, unsigned *cp) {
  unsigned char c = (unsigned char)s[*i];
  if (c < 0x80u) {
    *cp = c;
    *i += 1u;
    return 1;
  }
  if ((c & 0xe0u) == 0xc0u && s[*i + 1u] != 0) {
    unsigned char d = (unsigned char)s[*i + 1u];
    if ((d & 0xc0u) != 0x80u)
      return 0;
    *cp = ((unsigned)c & 0x1fu) << 6 | ((unsigned)d & 0x3fu);
    *i += 2u;
    return *cp >= 0x80u;
  }
  if ((c & 0xf0u) == 0xe0u && s[*i + 1u] != 0 && s[*i + 2u] != 0) {
    unsigned char d = (unsigned char)s[*i + 1u];
    unsigned char e = (unsigned char)s[*i + 2u];
    if ((d & 0xc0u) != 0x80u || (e & 0xc0u) != 0x80u)
      return 0;
    *cp = ((unsigned)c & 0x0fu) << 12 | ((unsigned)d & 0x3fu) << 6
        | ((unsigned)e & 0x3fu);
    *i += 3u;
    return *cp >= 0x800u;
  }
  if ((c & 0xf8u) == 0xf0u && s[*i + 1u] != 0 && s[*i + 2u] != 0 && s[*i + 3u] != 0) {
    unsigned char d = (unsigned char)s[*i + 1u];
    unsigned char e = (unsigned char)s[*i + 2u];
    unsigned char f = (unsigned char)s[*i + 3u];
    if ((d & 0xc0u) != 0x80u || (e & 0xc0u) != 0x80u || (f & 0xc0u) != 0x80u)
      return 0;
    *cp = ((unsigned)c & 0x07u) << 18 | ((unsigned)d & 0x3fu) << 12
        | ((unsigned)e & 0x3fu) << 6 | ((unsigned)f & 0x3fu);
    *i += 4u;
    return *cp >= 0x10000u && *cp <= 0x10ffffu;
  }
  return 0;
}

static int birc_kc_public_text(const char *value, size_t limit, int spaces,
                               char *out, size_t out_n) {
  size_t n;
  size_t i = 0;
  if (value == NULL || value[0] == 0)
    return 0;
  n = strlen(value);
  if (n > limit || n + 1u > out_n)
    return 0;
  while (value[i] != 0) {
    unsigned cp = 0;
    if (!birc_kc_next_cp(value, &i, &cp))
      return 0;
    if (cp < 32u || cp == 127u)
      return 0;
    if (!spaces && (cp == 32u || birc_kc_utf8_space(cp)))
      return 0;
  }
  memcpy(out, value, n + 1u);
  return 1;
}

static int birc_kc_name_ok(const char *name) {
  size_t n = strlen(name);
  size_t i;
  if (n == 0 || n > BIRC_KC_NAME_MAX)
    return 0;
  for (i = 0; i < n; i++) {
    char c = name[i];
    if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
          || (c >= '0' && c <= '9') || c == '_' || c == '.' || c == '-'))
      return 0;
  }
  return 1;
}

static void birc_kc_bare_host(const char *host, char *out, size_t out_n) {
  size_t n = strlen(host);
  if (n > 0 && host[n - 1u] == '.')
    n--;
  if (n + 1u > out_n)
    n = out_n - 1u;
  memcpy(out, host, n);
  out[n] = 0;
}

static int birc_kc_host_ok(const char *host) {
  char canonical[256];
  const char *p;
  size_t part = 0;
  size_t n = strlen(host);
  if (n == 0 || n > BIRC_KC_HOST_MAX)
    return 0;
  birc_kc_bare_host(host, canonical, sizeof canonical);
  if (canonical[0] == 0 || strlen(canonical) > 253u)
    return 0;
  for (p = host; *p; p++) {
    char ch = *p;
    if (!((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z')
          || (ch >= '0' && ch <= '9') || ch == '.' || ch == '-'))
      return 0;
  }
  for (p = canonical; ; p++) {
    if (*p == 0 || *p == '.') {
      if (part == 0 || part > 63u)
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

static int birc_kc_endpoint(const char *value, int have_port, uint32_t separate,
                            int tls, char *host, size_t host_n, uint32_t *port) {
  char raw[BIRC_KC_HOST_MAX + 1u];
  const char *colon;
  uint32_t inline_port = 0;
  int have_inline = 0;
  if (!birc_kc_public_text(value, BIRC_KC_HOST_MAX, 0, raw, sizeof raw)) {
    birc_kc_fail("invalid profile metadata");
    return 0;
  }
  colon = strchr(raw, ':');
  if (colon) {
    const char *digits = colon + 1;
    uint32_t v = 0;
    if (digits[0] == 0) {
      birc_kc_fail("invalid profile endpoint");
      return 0;
    }
    while (*digits) {
      if (*digits < '0' || *digits > '9') {
        birc_kc_fail("invalid profile endpoint");
        return 0;
      }
      v = v * 10u + (uint32_t)(*digits - '0');
      if (v > 65535u) {
        birc_kc_fail("invalid profile endpoint");
        return 0;
      }
      digits++;
    }
    if (v < 1u) {
      birc_kc_fail("invalid profile endpoint");
      return 0;
    }
    inline_port = v;
    have_inline = 1;
    {
      size_t hlen = (size_t)(colon - raw);
      if (hlen >= host_n) {
        birc_kc_fail("invalid profile endpoint");
        return 0;
      }
      memcpy(host, raw, hlen);
      host[hlen] = 0;
    }
  } else if (strlen(raw) >= host_n) {
    birc_kc_fail("invalid profile endpoint");
    return 0;
  } else {
    memcpy(host, raw, strlen(raw) + 1u);
  }
  if (!birc_kc_host_ok(host)) {
    birc_kc_fail("invalid profile endpoint");
    return 0;
  }
  if (have_port && (separate < 1u || separate > 65535u)) {
    birc_kc_fail("invalid profile metadata");
    return 0;
  }
  if (have_inline && have_port && inline_port != separate) {
    birc_kc_fail("conflicting profile ports");
    return 0;
  }
  if (have_port)
    *port = separate;
  else if (have_inline)
    *port = inline_port;
  else
    *port = tls ? 6697u : 6667u;
  return 1;
}

static int birc_kc_channel_one(const char *name, char *out, size_t out_n) {
  char text[BIRC_KC_CHAN_MAX + 1u];
  unsigned char first;
  if (!birc_kc_public_text(name, BIRC_KC_CHAN_MAX, 0, text, sizeof text))
    return 0;
  first = (unsigned char)text[0];
  if (strlen(text) <= 1u || strchr("#&+!", (int)first) == NULL || strchr(text, ',') != NULL)
    return 0;
  if (strlen(text) + 1u > out_n)
    return 0;
  memcpy(out, text, strlen(text) + 1u);
  return 1;
}

static int birc_kc_channels(const char *const *names, size_t n, BircKcProfile *p) {
  size_t i, j;
  if (n > BIRC_KC_MAX_CHANS)
    return 0;
  for (i = 0; i < n; i++) {
    if (!birc_kc_channel_one(names[i], p->channels[i], sizeof p->channels[i]))
      return 0;
    for (j = 0; j < i; j++) {
      if (strcmp(p->channels[i], p->channels[j]) == 0)
        return 0;
    }
  }
  p->channel_n = n;
  p->has_channels = 1;
  return 1;
}

static int birc_kc_channel_csv(const char *value, char *out, size_t out_n) {
  char copy[BIRC_KC_CSV_MAX + 1u];
  char *names[BIRC_KC_MAX_CHANS];
  BircKcProfile tmp;
  size_t n = 0;
  char *p;
  if (value[0] == 0) {
    if (out_n == 0)
      return 0;
    out[0] = 0;
    return 1;
  }
  if (!birc_kc_public_text(value, BIRC_KC_CSV_MAX, 0, copy, sizeof copy))
    return 0;
  p = copy;
  while (1) {
    if (n >= BIRC_KC_MAX_CHANS)
      return 0;
    names[n++] = p;
    p = strchr(p, ',');
    if (!p)
      break;
    *p++ = 0;
  }
  memset(&tmp, 0, sizeof tmp);
  if (!birc_kc_channels((const char *const *)names, n, &tmp))
    return 0;
  if (strlen(value) + 1u > out_n)
    return 0;
  memcpy(out, value, strlen(value) + 1u);
  return 1;
}

static int birc_kc_valid_prefix(const char *prefix) {
  const char *bang = strchr(prefix, '!');
  const char *at;
  size_t i;
  char nick[256];
  if (!bang || bang == prefix)
    return 0;
  at = strchr(bang + 1, '@');
  if (!at || at == bang + 1 || at[1] == 0)
    return 0;
  if (strchr(at + 1, '!') || strchr(at + 1, '@'))
    return 0;
  for (i = 0; prefix[i]; i++) {
    char c = prefix[i];
    if (c == ' ' || c == '*' || c == '?')
      return 0;
  }
  if ((size_t)(bang - prefix) >= sizeof nick)
    return 0;
  memcpy(nick, prefix, (size_t)(bang - prefix));
  nick[bang - prefix] = 0;
  if (nick[0] == '#' || nick[0] == '&' || nick[0] == '+' || nick[0] == '!'
      || nick[0] == ':' || strchr(nick, ',') != NULL)
    return 0;
  return 1;
}

static int birc_kc_loopback(const char *host) {
  unsigned a = 0, b = 0, c = 0, d = 0;
  char extra;
  if (sscanf(host, "%u.%u.%u.%u%c", &a, &b, &c, &d, &extra) != 4)
    return 0;
  return a == 127u && b <= 255u && c <= 255u && d <= 255u;
}

static int birc_kc_json_string(const char *s, char *out, size_t out_n) {
  size_t n = 0;
  if (n + 1u >= out_n)
    return 0;
  out[n++] = '"';
  while (*s) {
    unsigned char c = (unsigned char)*s++;
    if (c == '"' || c == '\\') {
      if (n + 3u >= out_n)
        return 0;
      out[n++] = '\\';
      out[n++] = (char)c;
    } else if (c < 32u) {
      if (n + 7u >= out_n)
        return 0;
      if (snprintf(out + n, out_n - n, "\\u%04x", c) != 6)
        return 0;
      n += 6u;
    } else {
      if (n + 2u >= out_n)
        return 0;
      out[n++] = (char)c;
    }
  }
  if (n + 2u > out_n)
    return 0;
  out[n++] = '"';
  out[n] = 0;
  return 1;
}

static int birc_kc_service(const char *name, const char *host, uint32_t port,
                           char *out, size_t out_n) {
  char a[128], b[300];
  if (!birc_kc_json_string(name, a, sizeof a) || !birc_kc_json_string(host, b, sizeof b))
    return 0;
  if (snprintf(out, out_n, "birc.auth.v1:[%s,%s,%u]", a, b, port) < 0
      || out[0] == 0)
    return 0;
  return 1;
}

static int birc_kc_hex(char c) {
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'a' && c <= 'f')
    return c - 'a' + 10;
  if (c >= 'A' && c <= 'F')
    return c - 'A' + 10;
  return -1;
}

static void birc_kc_skip(const char **pp, const char *end) {
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
}

static int birc_kc_take(const char **pp, const char *end, const char *lit) {
  size_t n = strlen(lit);
  birc_kc_skip(pp, end);
  if ((size_t)(end - *pp) < n || memcmp(*pp, lit, n) != 0)
    return 0;
  *pp += n;
  return 1;
}

static int birc_kc_string(const char **pp, const char *end, char *out, size_t out_n) {
  const char *p;
  size_t n = 0;
  birc_kc_skip(pp, end);
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
      } else if (*p == 't') {
        ch = '\t';
        p++;
      } else if (*p == 'u' && p + 5 <= end) {
        int a = birc_kc_hex(p[1]);
        int b = birc_kc_hex(p[2]);
        int c = birc_kc_hex(p[3]);
        int d = birc_kc_hex(p[4]);
        unsigned cp;
        if (a < 0 || b < 0 || c < 0 || d < 0)
          return 0;
        cp = (unsigned)((a << 12) | (b << 8) | (c << 4) | d);
        p += 5;
        if (cp < 0x80u) {
          ch = (unsigned char)cp;
        } else if (cp < 0x800u) {
          if (n + 2u >= out_n)
            return 0;
          out[n++] = (char)(0xc0u | (cp >> 6));
          ch = (unsigned char)(0x80u | (cp & 0x3fu));
        } else {
          if (n + 3u >= out_n)
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
    if (n + 1u >= out_n)
      return 0;
    out[n++] = (char)ch;
  }
  if (p >= end || *p != '"')
    return 0;
  out[n] = 0;
  *pp = p + 1;
  return 1;
}

static int birc_kc_bool(const char **pp, const char *end, int *out) {
  if (birc_kc_take(pp, end, "true")) {
    *out = 1;
    return 1;
  }
  if (birc_kc_take(pp, end, "false")) {
    *out = 0;
    return 1;
  }
  return 0;
}

static int birc_kc_u32(const char **pp, const char *end, uint32_t *out) {
  const char *p;
  uint64_t v = 0;
  int digits = 0;
  birc_kc_skip(pp, end);
  p = *pp;
  while (p < end && *p >= '0' && *p <= '9') {
    v = v * 10u + (uint64_t)(*p - '0');
    if (v > 4294967295ull)
      return 0;
    digits++;
    p++;
  }
  if (digits == 0 || (digits > 1 && (*pp)[0] == '0'))
    return 0;
  *out = (uint32_t)v;
  *pp = p;
  return 1;
}

static int birc_kc_ident(const char **pp, const char *end, char *out, size_t out_n) {
  const char *p;
  size_t n = 0;
  birc_kc_skip(pp, end);
  p = *pp;
  if (p >= end)
    return 0;
  if (!((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z') || (*p >= '0' && *p <= '9')
        || *p == '_' || *p == '-'))
    return 0;
  while (p < end && ((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z')
                     || (*p >= '0' && *p <= '9') || *p == '_' || *p == '-')) {
    if (n + 1u >= out_n)
      return 0;
    out[n++] = *p++;
  }
  out[n] = 0;
  *pp = p;
  return 1;
}

static int birc_kc_strings(const char **pp, const char *end, BircKcProfile *prof) {
  char *ptrs[BIRC_KC_MAX_CHANS];
  size_t n = 0;
  if (!birc_kc_take(pp, end, "["))
    return 0;
  birc_kc_skip(pp, end);
  if (birc_kc_take(pp, end, "]"))
    return birc_kc_channels((const char *const *)ptrs, 0, prof);
  while (1) {
    if (n >= BIRC_KC_MAX_CHANS)
      return 0;
    if (!birc_kc_string(pp, end, prof->channels[n], sizeof prof->channels[n]))
      return 0;
    ptrs[n] = prof->channels[n];
    n++;
    birc_kc_skip(pp, end);
    if (birc_kc_take(pp, end, "]"))
      break;
    if (!birc_kc_take(pp, end, ","))
      return 0;
  }
  return birc_kc_channels((const char *const *)ptrs, n, prof);
}

static int birc_kc_parse_header(const char **pp, const char *end, char *name,
                               size_t name_n) {
  birc_kc_skip(pp, end);
  if (!birc_kc_take(pp, end, "[") || !birc_kc_take(pp, end, "profiles"))
    return 0;
  birc_kc_skip(pp, end);
  if (*pp < end && **pp == ']') {
    name[0] = 0;
    *pp += 1;
    return 1;
  }
  if (!birc_kc_take(pp, end, "."))
    return 0;
  birc_kc_skip(pp, end);
  if (*pp < end && **pp == '"') {
    if (!birc_kc_string(pp, end, name, name_n))
      return 0;
  } else if (!birc_kc_ident(pp, end, name, name_n)) {
    return 0;
  }
  birc_kc_skip(pp, end);
  if (*pp >= end || **pp != ']')
    return 0;
  *pp += 1;
  return 1;
}

static BircKcRow *birc_kc_row(BircKcDoc *doc, const char *name) {
  size_t i;
  if (name[0] == 0)
    return NULL;
  for (i = 0; i < doc->n; i++) {
    if (strcmp(doc->rows[i].name, name) == 0)
      return &doc->rows[i];
  }
  if (doc->n >= 32u)
    return NULL;
  memset(&doc->rows[doc->n], 0, sizeof doc->rows[doc->n]);
  if (strlen(name) >= sizeof doc->rows[doc->n].name)
    return NULL;
  memcpy(doc->rows[doc->n].name, name, strlen(name) + 1u);
  return &doc->rows[doc->n++];
}

static int birc_kc_parse_toml(const char *raw, size_t n, BircKcDoc *doc) {
  const char *p = raw;
  const char *end = raw + n;
  BircKcRow *cur = NULL;
  memset(doc, 0, sizeof *doc);
  while (p < end) {
    char key[32];
    birc_kc_skip(&p, end);
    if (p >= end)
      break;
    if (*p == '[') {
      char name[BIRC_KC_NAME_MAX + 1u];
      if (!birc_kc_parse_header(&p, end, name, sizeof name))
        return 0;
      if (name[0] == 0) {
        cur = NULL;
        continue;
      }
      cur = birc_kc_row(doc, name);
      if (!cur)
        return 0;
      continue;
    }
    if (!cur || !birc_kc_ident(&p, end, key, sizeof key) || !birc_kc_take(&p, end, "="))
      return 0;
    if (strcmp(key, "host") == 0 && !(cur->seen & 1u)) {
      char host[BIRC_KC_HOST_MAX + 1u];
      cur->seen |= 1u;
      if (!birc_kc_string(&p, end, host, sizeof host)
          || strlen(host) >= sizeof cur->profile.host)
        return 0;
      memcpy(cur->profile.host, host, strlen(host) + 1u);
    } else if (strcmp(key, "port") == 0 && !(cur->seen & 2u)) {
      cur->seen |= 2u;
      if (!birc_kc_u32(&p, end, &cur->profile.port))
        return 0;
    } else if (strcmp(key, "account") == 0 && !(cur->seen & 4u)) {
      cur->seen |= 4u;
      if (!birc_kc_string(&p, end, cur->profile.account, sizeof cur->profile.account))
        return 0;
    } else if (strcmp(key, "nick") == 0 && !(cur->seen & 8u)) {
      cur->seen |= 8u;
      if (!birc_kc_string(&p, end, cur->profile.nick, sizeof cur->profile.nick))
        return 0;
    } else if (strcmp(key, "auth") == 0 && !(cur->seen & 16u)) {
      cur->seen |= 16u;
      if (!birc_kc_string(&p, end, cur->profile.auth, sizeof cur->profile.auth))
        return 0;
    } else if (strcmp(key, "nickserv_prefix") == 0 && !(cur->seen & 32u)) {
      cur->seen |= 32u;
      if (!birc_kc_string(&p, end, cur->profile.prefix, sizeof cur->profile.prefix))
        return 0;
    } else if (strcmp(key, "nickserv_success") == 0 && !(cur->seen & 64u)) {
      cur->seen |= 64u;
      if (!birc_kc_string(&p, end, cur->profile.confirmation,
                          sizeof cur->profile.confirmation))
        return 0;
    } else if (strcmp(key, "trusted_relay") == 0 && !(cur->seen & 128u)) {
      cur->seen |= 128u;
      if (!birc_kc_bool(&p, end, &cur->profile.relay))
        return 0;
    } else if (strcmp(key, "tls") == 0 && !(cur->seen & 256u)) {
      cur->seen |= 256u;
      if (!birc_kc_bool(&p, end, &cur->profile.tls))
        return 0;
    } else if (strcmp(key, "channels") == 0 && !(cur->seen & 512u)) {
      cur->seen |= 512u;
      if (!birc_kc_strings(&p, end, &cur->profile))
        return 0;
    } else {
      return 0;
    }
  }
  return 1;
}

static int birc_kc_load_raw(const char *path, char *raw, size_t raw_n, size_t *used) {
  int fd;
  struct stat info;
  ssize_t got;
  fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
  if (fd < 0) {
    if (errno == ENOENT) {
      birc_kc_fail("no profile file; use --create HOST --nick NICK");
      return -1;
    }
    birc_kc_fail("cannot read profile file");
    return 0;
  }
  if (fstat(fd, &info) != 0 || !birc_kc_trusted(&info, 1, (mode_t)0022)
      || (uint64_t)info.st_size > BIRC_KC_MAX_CONFIG) {
    (void)close(fd);
    birc_kc_fail("unsafe profile file");
    return 0;
  }
  if (raw_n < BIRC_KC_MAX_CONFIG + 2u) {
    (void)close(fd);
    birc_kc_fail("cannot read profile file");
    return 0;
  }
  got = read(fd, raw, BIRC_KC_MAX_CONFIG + 1u);
  (void)close(fd);
  if (got < 0) {
    birc_kc_fail("cannot read profile file");
    return 0;
  }
  if ((size_t)got > BIRC_KC_MAX_CONFIG) {
    birc_kc_fail("profile file exceeds bound");
    return 0;
  }
  raw[got] = 0;
  *used = (size_t)got;
  return 1;
}

static int birc_kc_finish_row(BircKcRow *row, int have_tls, int tls,
                              int have_port, uint32_t port, BircKcProfile *out) {
  BircKcProfile p;
  char host[BIRC_KC_HOST_MAX + 1u];
  uint32_t resolved;
  int use_tls;
  memset(&p, 0, sizeof p);
  if (!birc_kc_name_ok(row->name)) {
    birc_kc_fail("invalid profile name");
    return 0;
  }
  if (!(row->seen & 1u) || !(row->seen & 4u)) {
    birc_kc_fail("invalid profile metadata");
    return 0;
  }
  use_tls = (row->seen & 256u) ? row->profile.tls : 1;
  if (have_tls)
    use_tls = tls;
  if (!birc_kc_public_text(row->profile.account, BIRC_KC_ACCOUNT_MAX, 0,
                           p.account, sizeof p.account)) {
    birc_kc_fail("invalid profile metadata");
    return 0;
  }
  if (!birc_kc_endpoint(row->profile.host, have_port || (row->seen & 2u),
                        have_port ? port : row->profile.port, use_tls,
                        host, sizeof host, &resolved))
    return 0;
  memcpy(p.host, host, strlen(host) + 1u);
  p.port = resolved;
  p.tls = use_tls;
  p.relay = (row->seen & 128u) ? row->profile.relay : 0;
  if (row->seen & 8u) {
    if (!birc_kc_public_text(row->profile.nick, BIRC_KC_NICK_MAX, 0, p.nick,
                             sizeof p.nick)) {
      birc_kc_fail("invalid profile metadata");
      return 0;
    }
  }
  if (row->seen & 16u) {
    if (strcmp(row->profile.auth, "sasl") != 0
        && strcmp(row->profile.auth, "nickserv") != 0
        && strcmp(row->profile.auth, "sasl-nickserv") != 0) {
      birc_kc_fail("invalid authentication mode");
      return 0;
    }
    memcpy(p.auth, row->profile.auth, strlen(row->profile.auth) + 1u);
  } else {
    memcpy(p.auth, "sasl", 5);
  }
  if (strcmp(p.auth, "sasl") != 0) {
    if (!(row->seen & 32u) || !(row->seen & 64u)
        || !birc_kc_public_text(row->profile.prefix, BIRC_KC_PREFIX_MAX, 0,
                                p.prefix, sizeof p.prefix)
        || !birc_kc_public_text(row->profile.confirmation, BIRC_KC_CONFIRM_MAX, 1,
                                p.confirmation, sizeof p.confirmation)) {
      birc_kc_fail("invalid profile metadata");
      return 0;
    }
    if (!birc_kc_valid_prefix(p.prefix)) {
      birc_kc_fail("NickServ requires an exact full prefix");
      return 0;
    }
  } else if ((row->seen & 32u) || (row->seen & 64u)) {
    birc_kc_fail("NickServ trust requires an explicit authentication mode");
    return 0;
  }
  if (row->seen & 512u) {
    size_t i;
    const char *names[BIRC_KC_MAX_CHANS];
    for (i = 0; i < row->profile.channel_n; i++)
      names[i] = row->profile.channels[i];
    if (!birc_kc_channels(names, row->profile.channel_n, &p)) {
      birc_kc_fail("invalid profile channels");
      return 0;
    }
  }
  if (!birc_kc_service(row->name, p.host, p.port, p.service, sizeof p.service)) {
    birc_kc_fail("invalid profile metadata");
    return 0;
  }
  *out = p;
  return 1;
}

static int birc_kc_read_profile(const char *path, const char *name, int have_tls,
                                int tls, int have_port, uint32_t port,
                                BircKcProfile *out) {
  char raw[BIRC_KC_MAX_CONFIG + 2u];
  size_t n = 0;
  BircKcDoc doc;
  size_t i;
  int load;
  if (!birc_kc_name_ok(name)) {
    birc_kc_fail("invalid profile name");
    return 0;
  }
  load = birc_kc_load_raw(path, raw, sizeof raw, &n);
  if (load <= 0)
    return load;
  if (!birc_kc_parse_toml(raw, n, &doc)) {
    birc_kc_fail("cannot read profile file");
    return 0;
  }
  for (i = 0; i < doc.n; i++) {
    if (strcmp(doc.rows[i].name, name) == 0)
      return birc_kc_finish_row(&doc.rows[i], have_tls, tls, have_port, port, out);
  }
  birc_kc_fail("unknown profile");
  return -1;
}

static int birc_kc_mkdir_p(const char *dir) {
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

static int birc_kc_ensure_dir(const char *path) {
  char dir[4096];
  const char *slash = strrchr(path, '/');
  struct stat info;
  if (!slash || slash == path) {
    birc_kc_fail("unsafe profile directory");
    return 0;
  }
  if ((size_t)(slash - path) >= sizeof dir) {
    birc_kc_fail("unsafe profile directory");
    return 0;
  }
  memcpy(dir, path, (size_t)(slash - path));
  dir[slash - path] = 0;
  if (stat(dir, &info) != 0) {
    if (errno != ENOENT || birc_kc_mkdir_p(dir) != 0 || chmod(dir, 0700) != 0
        || stat(dir, &info) != 0) {
      birc_kc_fail("unsafe profile directory");
      return 0;
    }
  }
  if (!birc_kc_trusted(&info, 0, (mode_t)0077)) {
    birc_kc_fail("unsafe profile directory");
    return 0;
  }
  return 1;
}

static int birc_kc_toml_string(const char *s, char *out, size_t out_n) {
  return birc_kc_json_string(s, out, out_n);
}

static int birc_kc_create_profile(const char *path, const char *name, const char *host,
                                 int have_port, uint32_t port, const char *nick,
                                 const char *channels, int have_tls, int tls,
                                 BircKcProfile *out) {
  char body[2048];
  char hjson[300], njson[200], ajson[200], namej[160];
  char resolved_host[BIRC_KC_HOST_MAX + 1u];
  uint32_t resolved = 0;
  int use_tls = have_tls ? tls : 1;
  size_t n = 0;
  int existed;
  if (!birc_kc_name_ok(name)) {
    birc_kc_fail("invalid profile name");
    return 0;
  }
  if (strchr(host, ':') != NULL) {
    birc_kc_fail("--create takes a bare host; use --port");
    return 0;
  }
  if (have_port && (port < 1u || port > 65535u)) {
    birc_kc_fail("invalid port override");
    return 0;
  }
  if (!birc_kc_endpoint(host, have_port, port, use_tls, resolved_host,
                        sizeof resolved_host, &resolved))
    return 0;
  if (!birc_kc_public_text(nick, BIRC_KC_NICK_MAX, 0, ajson, sizeof ajson)) {
    birc_kc_fail("invalid profile metadata");
    return 0;
  }
  if (!birc_kc_toml_string(name, namej, sizeof namej)
      || !birc_kc_toml_string(resolved_host, hjson, sizeof hjson)
      || !birc_kc_toml_string(nick, njson, sizeof njson)) {
    birc_kc_fail("invalid profile metadata");
    return 0;
  }
  n = (size_t)snprintf(body, sizeof body, "[profiles.%s]\nhost = %s\n", namej, hjson);
  if (n >= sizeof body)
    return 0;
  if (have_port) {
    int add = snprintf(body + n, sizeof body - n, "port = %u\n", resolved);
    if (add < 0 || n + (size_t)add >= sizeof body)
      return 0;
    n += (size_t)add;
  }
  {
    int add = snprintf(body + n, sizeof body - n, "account = %s\nnick = %s\n", njson, njson);
    if (add < 0 || n + (size_t)add >= sizeof body)
      return 0;
    n += (size_t)add;
  }
  if (!use_tls) {
    int add = snprintf(body + n, sizeof body - n, "tls = false\n");
    if (add < 0 || n + (size_t)add >= sizeof body)
      return 0;
    n += (size_t)add;
  }
  if (channels && channels[0]) {
    char csv[BIRC_KC_CSV_MAX + 1u];
    char copy[BIRC_KC_CSV_MAX + 1u];
    char *names[BIRC_KC_MAX_CHANS];
    BircKcProfile tmp;
    size_t cn = 0;
    char *walk;
    size_t i;
    if (!birc_kc_channel_csv(channels, csv, sizeof csv)) {
      birc_kc_fail("invalid profile channels");
      return 0;
    }
    memcpy(copy, csv, strlen(csv) + 1u);
    walk = copy;
    while (1) {
      names[cn++] = walk;
      walk = strchr(walk, ',');
      if (!walk)
        break;
      *walk++ = 0;
    }
    memset(&tmp, 0, sizeof tmp);
    if (!birc_kc_channels((const char *const *)names, cn, &tmp)) {
      birc_kc_fail("invalid profile channels");
      return 0;
    }
    {
      int add = snprintf(body + n, sizeof body - n, "channels = [");
      if (add < 0 || n + (size_t)add >= sizeof body)
        return 0;
      n += (size_t)add;
    }
    for (i = 0; i < tmp.channel_n; i++) {
      char item[BIRC_KC_CHAN_MAX + 8u];
      int add;
      if (!birc_kc_toml_string(tmp.channels[i], item, sizeof item))
        return 0;
      add = snprintf(body + n, sizeof body - n, "%s%s", i ? ", " : "", item);
      if (add < 0 || n + (size_t)add >= sizeof body)
        return 0;
      n += (size_t)add;
    }
    {
      int add = snprintf(body + n, sizeof body - n, "]\n");
      if (add < 0 || n + (size_t)add >= sizeof body)
        return 0;
      n += (size_t)add;
    }
  }
  if (!birc_kc_ensure_dir(path))
    return 0;
  existed = access(path, F_OK) == 0;
  if (!existed) {
    int fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    ssize_t w;
    if (fd < 0) {
      birc_kc_fail("profile file changed during creation");
      return 0;
    }
    w = write(fd, body, n);
    (void)close(fd);
    if (w != (ssize_t)n) {
      birc_kc_fail("cannot read profile file");
      return 0;
    }
  } else {
    char raw[BIRC_KC_MAX_CONFIG + 2u];
    size_t used = 0;
    BircKcDoc doc;
    size_t i;
    int fd;
    char prefix[2048];
    size_t pn;
    struct stat info;
    if (birc_kc_load_raw(path, raw, sizeof raw, &used) <= 0)
      return 0;
    if (!birc_kc_parse_toml(raw, used, &doc)) {
      birc_kc_fail("cannot read profile file");
      return 0;
    }
    for (i = 0; i < doc.n; i++) {
      if (strcmp(doc.rows[i].name, name) == 0) {
        birc_kc_fail("profile file changed during creation");
        return 0;
      }
    }
    pn = (size_t)snprintf(prefix, sizeof prefix, "\n%s", body);
    if (pn >= sizeof prefix) {
      birc_kc_fail("cannot read profile file");
      return 0;
    }
    fd = open(path, O_WRONLY | O_APPEND | O_NOFOLLOW);
    if (fd < 0) {
      birc_kc_fail("cannot read profile file");
      return 0;
    }
    if (fstat(fd, &info) != 0 || !birc_kc_trusted(&info, 1, (mode_t)0022)
        || (uint64_t)info.st_size + (uint64_t)pn > BIRC_KC_MAX_CONFIG) {
      (void)close(fd);
      birc_kc_fail("unsafe profile file");
      return 0;
    }
    if (write(fd, prefix, pn) != (ssize_t)pn) {
      (void)close(fd);
      birc_kc_fail("cannot read profile file");
      return 0;
    }
    (void)close(fd);
  }
  return birc_kc_read_profile(path, name, have_tls, tls, have_port, port, out) > 0;
}

static int birc_kc_secret_bytes(const char *value, unsigned char *out, size_t *n) {
  size_t len;
  size_t i;
  if (value == NULL) {
    birc_kc_fail("invalid password");
    return 0;
  }
  len = strlen(value);
  if (len == 0 || len > BIRC_KC_MAX_SECRET) {
    birc_kc_fail("password must be 1..1024 UTF-8 bytes without NUL, CR or LF");
    return 0;
  }
  for (i = 0; i < len; i++) {
    unsigned char c = (unsigned char)value[i];
    if (c == 0 || c == 10 || c == 13) {
      birc_kc_fail("password must be 1..1024 UTF-8 bytes without NUL, CR or LF");
      return 0;
    }
  }
  memcpy(out, value, len);
  *n = len;
  return 1;
}

#ifndef BIRC_KEYCHAIN_CORE_ONLY
static const char birc_kc_b64[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static int birc_kc_b64_enc(const unsigned char *in, size_t n, char *out, size_t out_n) {
  size_t i = 0, o = 0;
  while (i < n) {
    unsigned remain = (unsigned)(n - i);
    unsigned a = in[i++];
    unsigned b = remain > 1u ? in[i++] : 0;
    unsigned c = remain > 2u ? in[i++] : 0;
    unsigned triple = (a << 16) | (b << 8) | c;
    if (o + 5u > out_n)
      return 0;
    out[o++] = birc_kc_b64[(triple >> 18) & 63u];
    out[o++] = birc_kc_b64[(triple >> 12) & 63u];
    out[o++] = remain > 1u ? birc_kc_b64[(triple >> 6) & 63u] : '=';
    out[o++] = remain > 2u ? birc_kc_b64[triple & 63u] : '=';
  }
  if (o >= out_n)
    return 0;
  out[o] = 0;
  return 1;
}

static int birc_kc_b64_val(int c) {
  if (c >= 'A' && c <= 'Z')
    return c - 'A';
  if (c >= 'a' && c <= 'z')
    return c - 'a' + 26;
  if (c >= '0' && c <= '9')
    return c - '0' + 52;
  if (c == '+')
    return 62;
  if (c == '/')
    return 63;
  return -1;
}

static int birc_kc_b64_dec(const char *in, unsigned char *out, size_t out_n, size_t *used) {
  size_t len = strlen(in);
  size_t i = 0, o = 0;
  if (len % 4u != 0)
    return 0;
  while (i < len) {
    int a = birc_kc_b64_val((unsigned char)in[i]);
    int b = birc_kc_b64_val((unsigned char)in[i + 1u]);
    int c = in[i + 2u] == '=' ? 0 : birc_kc_b64_val((unsigned char)in[i + 2u]);
    int d = in[i + 3u] == '=' ? 0 : birc_kc_b64_val((unsigned char)in[i + 3u]);
    unsigned triple;
    if (a < 0 || b < 0 || (in[i + 2u] != '=' && c < 0) || (in[i + 3u] != '=' && d < 0))
      return 0;
    if (in[i + 2u] == '=' && in[i + 3u] != '=')
      return 0;
    if (in[i + 3u] == '=' && i + 4u != len)
      return 0;
    triple = ((unsigned)a << 18) | ((unsigned)b << 12) | ((unsigned)c << 6) | (unsigned)d;
    if (o < out_n)
      out[o++] = (unsigned char)((triple >> 16) & 0xffu);
    if (in[i + 2u] != '=' && o < out_n)
      out[o++] = (unsigned char)((triple >> 8) & 0xffu);
    if (in[i + 3u] != '=' && o < out_n)
      out[o++] = (unsigned char)(triple & 0xffu);
    i += 4u;
  }
  *used = o;
  return 1;
}

static int birc_kc_quote(const char *value, char *out, size_t out_n) {
  size_t n = 0;
  if (n + 1u >= out_n)
    return 0;
  out[n++] = '"';
  while (*value) {
    if (*value == '\\' || *value == '"') {
      if (n + 3u >= out_n)
        return 0;
      out[n++] = '\\';
    }
    if (n + 2u >= out_n)
      return 0;
    out[n++] = *value++;
  }
  if (n + 2u > out_n)
    return 0;
  out[n++] = '"';
  out[n] = 0;
  return 1;
}

static void birc_kc_hex_encode(const unsigned char *in, size_t n, char *out) {
  static const char hex[] = "0123456789abcdef";
  size_t i;
  for (i = 0; i < n; i++) {
    out[i * 2u] = hex[(in[i] >> 4) & 0xfu];
    out[i * 2u + 1u] = hex[in[i] & 0xfu];
  }
  out[n * 2u] = 0;
}

static int birc_kc_skip_env(const char *entry) {
  static const char *drop[] = {
    "BIRC_SASL_USER=", "BIRC_SASL_PASS=", "BIRC_AUTH_SECRET_FD=", "BIRC_AUTH_EVENT_FD=",
#if defined(BIRC_KEYCHAIN_TEST)
    "BIRC_KEYCHAIN_PASSWORD=", "BIRC_SECURITY=", "BIRC_KEYCHAIN_PLATFORM=",
#endif
    NULL
  };
  size_t i;
  for (i = 0; drop[i]; i++) {
    if (strncmp(entry, drop[i], strlen(drop[i])) == 0)
      return 1;
  }
  return 0;
}

extern char **environ;

static char *birc_kc_unconst(const char *s) {
  char *p;
  memcpy(&p, &s, sizeof p);
  return p;
}

static char **birc_kc_env(const char *secret_fd, const char *event_fd, const char *lc_all) {
  size_t n = 0, i, o = 0;
  char **env;
  while (environ[n])
    n++;
  env = calloc(n + 6u, sizeof *env);
  if (!env)
    return NULL;
  for (i = 0; environ[i]; i++) {
    if (!birc_kc_skip_env(environ[i]))
      env[o++] = environ[i];
  }
  if (secret_fd)
    env[o++] = birc_kc_unconst(secret_fd);
  if (event_fd)
    env[o++] = birc_kc_unconst(event_fd);
  if (lc_all)
    env[o++] = birc_kc_unconst(lc_all);
  env[o] = NULL;
  return env;
}

static double birc_kc_now(void) {
  struct timespec ts;
  if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
    return 0;
  return (double)ts.tv_sec + (double)ts.tv_nsec / 1000000000.0;
}

static void birc_kc_close_extra(int keep_a, int keep_b) {
  int fd;
  int maxfd = (int)sysconf(_SC_OPEN_MAX);
  if (maxfd < 8)
    maxfd = 256;
  for (fd = 3; fd < maxfd; fd++) {
    if (fd != keep_a && fd != keep_b)
      (void)close(fd);
  }
}

static int birc_kc_bounded(char *const argv[], const unsigned char *data, size_t data_n,
                           size_t limit, double timeout, int *code, unsigned char *out,
                           size_t *out_n) {
  int in_p[2] = {-1, -1};
  int out_p[2] = {-1, -1};
  pid_t pid;
  size_t wrote = 0;
  size_t got = 0;
  char **env;
  double deadline = birc_kc_now() + timeout;
  env = birc_kc_env(NULL, NULL, "LC_ALL=C");
  if (!env) {
    birc_kc_fail("Keychain helper failed");
    return 0;
  }
  if (pipe(in_p) != 0 || pipe(out_p) != 0) {
    free(env);
    birc_kc_fail("Keychain helper failed");
    return 0;
  }
  pid = fork();
  if (pid < 0) {
    (void)close(in_p[0]);
    (void)close(in_p[1]);
    (void)close(out_p[0]);
    (void)close(out_p[1]);
    free(env);
    birc_kc_fail("Keychain helper failed");
    return 0;
  }
  if (pid == 0) {
    if (dup2(in_p[0], 0) < 0 || dup2(out_p[1], 1) < 0) {
      _exit(127);
    }
    {
      int nullfd = open("/dev/null", O_WRONLY);
      if (nullfd >= 0) {
        (void)dup2(nullfd, 2);
        if (nullfd != 2)
          (void)close(nullfd);
      }
    }
    birc_kc_close_extra(-1, -1);
    execve(argv[0], argv, env);
    _exit(127);
  }
  (void)close(in_p[0]);
  (void)close(out_p[1]);
  free(env);
  if (data_n == 0) {
    (void)close(in_p[1]);
    in_p[1] = -1;
  } else {
    (void)fcntl(in_p[1], F_SETFL, O_NONBLOCK);
  }
  (void)fcntl(out_p[0], F_SETFL, O_NONBLOCK);
  while (1) {
    struct pollfd pfd[2];
    nfds_t nfds = 0;
    double remain = deadline - birc_kc_now();
    int ms;
    int pr;
    if (remain <= 0) {
      birc_kc_fail("Keychain helper timed out");
      goto fail;
    }
    if (in_p[1] >= 0) {
      pfd[nfds].fd = in_p[1];
      pfd[nfds].events = POLLOUT;
      nfds++;
    }
    pfd[nfds].fd = out_p[0];
    pfd[nfds].events = POLLIN;
    nfds++;
    ms = remain > 2147483.0 ? 2147483647 : (int)(remain * 1000.0);
    if (ms < 1)
      ms = 1;
    pr = poll(pfd, nfds, ms);
    if (pr < 0) {
      if (errno == EINTR)
        continue;
      birc_kc_fail("Keychain helper failed");
      goto fail;
    }
    if (pr == 0)
      continue;
    if (in_p[1] >= 0 && (pfd[0].revents & (POLLOUT | POLLERR | POLLHUP))) {
      ssize_t w = write(in_p[1], data + wrote, data_n - wrote);
      if (w < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
        birc_kc_fail("Keychain helper failed");
        goto fail;
      }
      if (w > 0)
        wrote += (size_t)w;
      if (wrote == data_n) {
        (void)close(in_p[1]);
        in_p[1] = -1;
      }
    }
    {
      struct pollfd *rd = in_p[1] >= 0 ? &pfd[1] : &pfd[0];
      if (rd->revents & (POLLIN | POLLHUP | POLLERR)) {
        unsigned char buf[4096];
        size_t want = limit + 1u - got;
        ssize_t r;
        if (want > sizeof buf)
          want = sizeof buf;
        r = read(out_p[0], buf, want);
        if (r < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
          birc_kc_fail("Keychain helper failed");
          goto fail;
        }
        if (r == 0)
          break;
        if (r > 0) {
          if (got + (size_t)r > limit) {
            birc_kc_fail("Keychain helper output exceeds bound");
            goto fail;
          }
          memcpy(out + got, buf, (size_t)r);
          got += (size_t)r;
        }
      }
    }
  }
  {
    int status = 0;
    double remain = deadline - birc_kc_now();
    if (remain <= 0) {
      birc_kc_fail("Keychain helper timed out");
      goto fail;
    }
    if (waitpid(pid, &status, 0) < 0) {
      birc_kc_fail("Keychain helper failed");
      goto fail;
    }
    *code = WIFEXITED(status) ? WEXITSTATUS(status) : 1;
    *out_n = got;
    if (in_p[1] >= 0)
      (void)close(in_p[1]);
    (void)close(out_p[0]);
    return 1;
  }
fail:
  if (in_p[1] >= 0)
    (void)close(in_p[1]);
  (void)close(out_p[0]);
  (void)kill(pid, SIGKILL);
  (void)waitpid(pid, NULL, 0);
  return 0;
}

static int birc_kc_load_secret(const char *security, const BircKcProfile *profile,
                               unsigned char *out, size_t *n, int *missing) {
  char *argv[8];
  unsigned char buf[4096];
  size_t got = 0;
  int code = 0;
  argv[0] = birc_kc_unconst(security);
  argv[1] = "find-generic-password";
  argv[2] = "-s";
  argv[3] = birc_kc_unconst(profile->service);
  argv[4] = "-a";
  argv[5] = birc_kc_unconst(profile->account);
  argv[6] = "-w";
  argv[7] = NULL;
  *missing = 0;
  if (!birc_kc_bounded(argv, NULL, 0, 2048, 30.0, &code, buf, &got))
    return 0;
  if (code == 44 && got == 0) {
    *missing = 1;
    return 1;
  }
  if (code != 0) {
    char why[80];
    if (snprintf(why, sizeof why, "Keychain lookup failed (status %d)", code) < 0)
      birc_kc_fail("Keychain lookup failed");
    else {
      static char hold[80];
      memcpy(hold, why, strlen(why) + 1u);
      birc_kc_fail(hold);
    }
    return 0;
  }
  if (got == 0 || buf[got - 1u] != '\n' || memchr(buf, '\n', got - 1u) != NULL
      || got < sizeof BIRC_KC_ENVELOPE || memcmp(buf, BIRC_KC_ENVELOPE, 8) != 0) {
    birc_kc_fail("unsupported Keychain credential format");
    return 0;
  }
  buf[got - 1u] = 0;
  {
    unsigned char raw[BIRC_KC_MAX_SECRET + 4u];
    size_t raw_n = 0;
    char text[BIRC_KC_MAX_SECRET + 1u];
    if (!birc_kc_b64_dec((char *)buf + 8, raw, sizeof raw, &raw_n) || raw_n == 0
        || raw_n > BIRC_KC_MAX_SECRET) {
      birc_kc_fail("invalid Keychain credential format");
      return 0;
    }
    memcpy(text, raw, raw_n);
    text[raw_n] = 0;
    if (strlen(text) != raw_n || !birc_kc_secret_bytes(text, out, n)) {
      birc_kc_fail("invalid Keychain credential format");
      return 0;
    }
  }
  return 1;
}

static int birc_kc_save_secret(const char *security, const BircKcProfile *profile,
                               const unsigned char *secret, size_t n, int *code) {
  char b64[2048];
  char envelope[2100];
  char acct[512];
  char svc[1024];
  char hex[4200];
  unsigned char command[4096];
  size_t cmd_n;
  char *argv[3];
  unsigned char ignored[8];
  size_t ign = 0;
  if (!birc_kc_b64_enc(secret, n, b64, sizeof b64)) {
    birc_kc_fail("invalid password");
    return 0;
  }
  if (snprintf(envelope, sizeof envelope, "%s%s", BIRC_KC_ENVELOPE, b64) < 0) {
    birc_kc_fail("Keychain command exceeds bound");
    return 0;
  }
  if (!birc_kc_quote(profile->account, acct, sizeof acct)
      || !birc_kc_quote(profile->service, svc, sizeof svc)) {
    birc_kc_fail("Keychain command exceeds bound");
    return 0;
  }
  birc_kc_hex_encode((const unsigned char *)envelope, strlen(envelope), hex);
  cmd_n = (size_t)snprintf((char *)command, sizeof command,
                           "add-generic-password -a %s -s %s -X %s\n", acct, svc, hex);
  if (cmd_n >= 4096u) {
    birc_kc_fail("Keychain command exceeds bound");
    return 0;
  }
  argv[0] = birc_kc_unconst(security);
  argv[1] = "-i";
  argv[2] = NULL;
  return birc_kc_bounded(argv, command, cmd_n, 2048, 30.0, code, ignored, &ign);
}

static int birc_kc_write_secret(int fd, const unsigned char *secret, size_t n) {
  size_t off = 0;
  while (off < n) {
    ssize_t w = write(fd, secret + off, n - off);
    if (w <= 0) {
      birc_kc_fail("credential pipe failed");
      return 0;
    }
    off += (size_t)w;
  }
  return 1;
}

static int birc_kc_auth_ok(pid_t child, int fd, int *reaped, int *status) {
  unsigned char out[sizeof BIRC_KC_SUCCESS + 1u];
  size_t n = 0;
  (void)fcntl(fd, F_SETFL, O_NONBLOCK);
  *reaped = 0;
  while (1) {
    struct pollfd pfd;
    int exited = 0;
    ssize_t r;
    int st = 0;
    pfd.fd = fd;
    pfd.events = POLLIN;
    (void)poll(&pfd, 1, 250);
    if (waitpid(child, &st, WNOHANG) == child) {
      *reaped = 1;
      *status = WIFEXITED(st) ? WEXITSTATUS(st) : 1;
      exited = 1;
    }
    r = read(fd, out + n, sizeof out - n);
    if (r < 0) {
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        if (exited)
          return 0;
        continue;
      }
      return 0;
    }
    if (r == 0)
      return n == sizeof BIRC_KC_SUCCESS - 1u
          && memcmp(out, BIRC_KC_SUCCESS, n) == 0;
    n += (size_t)r;
    if (n > sizeof BIRC_KC_SUCCESS - 1u)
      return 0;
  }
}

static int birc_kc_join_channels(const BircKcProfile *p, char *out, size_t out_n) {
  size_t i, n = 0;
  for (i = 0; i < p->channel_n; i++) {
    size_t add = strlen(p->channels[i]);
    if (n + add + (i ? 1u : 0u) + 1u > out_n)
      return 0;
    if (i)
      out[n++] = ',';
    memcpy(out + n, p->channels[i], add);
    n += add;
  }
  out[n] = 0;
  return 1;
}

static int birc_kc_launch(const char *program, const BircKcProfile *profile,
                          const unsigned char *secret, size_t secret_n,
                          char *const extra[], const char *security, int save) {
  int secret_p[2] = {-1, -1};
  int event_p[2] = {-1, -1};
  pid_t child = -1;
  int status = 1;
  char secret_env[64];
  char event_env[64];
  char port[8];
  char chan[BIRC_KC_CSV_MAX + 1u];
  char *argv[48];
  size_t argc = 0;
  char **env = NULL;
  int has_channel = 0;
  size_t i;
  if (pipe(secret_p) != 0)
    return -1;
  if (pipe(event_p) != 0) {
    (void)close(secret_p[0]);
    (void)close(secret_p[1]);
    return -1;
  }
  if (!birc_kc_write_secret(secret_p[1], secret, secret_n))
    goto done;
  (void)close(secret_p[1]);
  secret_p[1] = -1;
  if (snprintf(secret_env, sizeof secret_env, "BIRC_AUTH_SECRET_FD=%d", secret_p[0]) < 0
      || snprintf(event_env, sizeof event_env, "BIRC_AUTH_EVENT_FD=%d", event_p[1]) < 0
      || snprintf(port, sizeof port, "%u", profile->port) < 0)
    goto done;
  env = birc_kc_env(secret_env, event_env, NULL);
  if (!env)
    goto done;
  argv[argc++] = birc_kc_unconst(program);
  argv[argc++] = "--connect";
  argv[argc++] = birc_kc_unconst(profile->host);
  argv[argc++] = "--port";
  argv[argc++] = port;
  argv[argc++] = "--sasl-user";
  argv[argc++] = birc_kc_unconst(profile->account);
  argv[argc++] = "--auth";
  argv[argc++] = birc_kc_unconst(profile->auth);
  argv[argc++] = profile->tls ? "--tls" : "--plain";
  if (profile->nick[0]) {
    argv[argc++] = "--nick";
    argv[argc++] = birc_kc_unconst(profile->nick);
  }
  if (profile->prefix[0]) {
    argv[argc++] = "--nickserv-prefix";
    argv[argc++] = birc_kc_unconst(profile->prefix);
    argv[argc++] = "--nickserv-success";
    argv[argc++] = birc_kc_unconst(profile->confirmation);
  }
  if (extra) {
    for (i = 0; extra[i]; i++) {
      if (strcmp(extra[i], "--channel") == 0)
        has_channel = 1;
    }
  }
  if (profile->has_channels && !has_channel) {
    if (!birc_kc_join_channels(profile, chan, sizeof chan))
      goto done;
    argv[argc++] = "--channel";
    argv[argc++] = chan;
  }
  if (extra) {
    for (i = 0; extra[i] && argc + 2u < 48u; i++)
      argv[argc++] = extra[i];
  }
  argv[argc] = NULL;
  child = fork();
  if (child < 0)
    goto done;
  if (child == 0) {
    if (secret_p[1] >= 0)
      (void)close(secret_p[1]);
    (void)close(event_p[0]);
    birc_kc_close_extra(secret_p[0], event_p[1]);
    execve(program, argv, env);
    _exit(127);
  }
  (void)close(secret_p[0]);
  secret_p[0] = -1;
  (void)close(event_p[1]);
  event_p[1] = -1;
  {
    int reaped = 0;
    int child_status = 1;
    if (birc_kc_auth_ok(child, event_p[0], &reaped, &child_status) && save) {
      int code = 0;
      if (!birc_kc_save_secret(security, profile, secret, secret_n, &code) || code != 0) {
        if (code != 0)
          fprintf(stderr, "keychain-birc: password not saved (status %d)\n", code);
        else
          fprintf(stderr, "keychain-birc: %s\n", birc_kc_why);
      }
    }
    if (reaped) {
      status = child_status;
    } else if (waitpid(child, &status, 0) < 0) {
      status = 1;
    } else {
      status = WIFEXITED(status) ? WEXITSTATUS(status) : 1;
    }
    child = -1;
  }
done:
  if (secret_p[0] >= 0)
    (void)close(secret_p[0]);
  if (secret_p[1] >= 0)
    (void)close(secret_p[1]);
  if (event_p[0] >= 0)
    (void)close(event_p[0]);
  if (event_p[1] >= 0)
    (void)close(event_p[1]);
  free(env);
  if (child > 0) {
    (void)kill(child, SIGTERM);
    {
      double deadline = birc_kc_now() + 2.0;
      int st = 0;
      while (birc_kc_now() < deadline) {
        if (waitpid(child, &st, WNOHANG) != 0)
          break;
        (void)poll(NULL, 0, 50);
      }
      if (waitpid(child, &st, WNOHANG) == 0) {
        (void)kill(child, SIGKILL);
        (void)waitpid(child, &st, 0);
      }
    }
  }
  return status;
}

static int birc_kc_prompt(char *out, size_t out_n) {
#if defined(BIRC_KEYCHAIN_TEST)
  {
    const char *forced = getenv("BIRC_KEYCHAIN_PASSWORD");
    if (forced) {
      if (strlen(forced) + 1u > out_n)
        return 0;
      memcpy(out, forced, strlen(forced) + 1u);
      return 1;
    }
  }
#endif
  {
    int fd = open("/dev/tty", O_RDWR | O_NOCTTY);
    struct termios oldt, newt;
    size_t n = 0;
    if (fd < 0)
      return 0;
    if (tcgetattr(fd, &oldt) != 0) {
      (void)close(fd);
      return 0;
    }
    newt = oldt;
    newt.c_lflag &= (tcflag_t)~ECHO;
    if (tcsetattr(fd, TCSAFLUSH, &newt) != 0) {
      (void)close(fd);
      return 0;
    }
    if (write(fd, "IRC password: ", 14) < 0) {
      (void)tcsetattr(fd, TCSAFLUSH, &oldt);
      (void)close(fd);
      return 0;
    }
    while (n + 1u < out_n) {
      unsigned char c = 0;
      ssize_t r = read(fd, &c, 1);
      if (r <= 0)
        break;
      if (c == '\n' || c == '\r')
        break;
      out[n++] = (char)c;
    }
    out[n] = 0;
    (void)write(fd, "\n", 1);
    (void)tcsetattr(fd, TCSAFLUSH, &oldt);
    (void)close(fd);
    return n > 0;
  }
}

static void birc_kc_help(void) {
  fputs(
      "usage: keychain-birc --profile NAME [options]\n"
      "\n"
      "Launch a macOS Keychain-backed IRC account profile.\n"
      "\n"
      "  --profile NAME            name in [profiles.NAME]\n"
      "  --config PATH             metadata TOML; contains no passwords\n"
      "  --allow-insecure-auth     allow plaintext credentials for this launch only\n"
      "  --tls                     use verified TLS (default); keep an explicit profile port\n"
      "  --plain                   use plaintext IRC; keep an explicit profile port\n"
      "  --frames N                forward birc frame cap\n"
      "  --channel LIST            forward initial IRC channel\n"
      "  --port N                  override profile port (endpoint-bound credential scope)\n"
      "  --create HOST             create the profile with this host if missing (requires --nick)\n"
      "  --nick NICK               seed the nick for --create (refused when the profile exists)\n",
      stdout);
}

static int birc_kc_darwin(void) {
#if defined(BIRC_KEYCHAIN_TEST)
  {
    const char *forced = getenv("BIRC_KEYCHAIN_PLATFORM");
    if (forced)
      return strcmp(forced, "darwin") == 0;
  }
#endif
#if defined(__APPLE__)
  return 1;
#else
  return 0;
#endif
}

static void birc_kc_sibling(const char *argv0, char *out, size_t out_n) {
  const char *slash = strrchr(argv0, '/');
  if (slash) {
    size_t n = (size_t)(slash - argv0);
    if (n + 6u < out_n) {
      memcpy(out, argv0, n);
      memcpy(out + n, "/birc", 6);
      return;
    }
  }
  if (out_n >= 5u)
    memcpy(out, "birc", 5);
  else
    out[0] = 0;
}

int main(int argc, char **argv) {
  const char *profile = NULL;
  const char *config = NULL;
  const char *create = NULL;
  const char *nick = NULL;
  const char *channel = NULL;
  int have_tls = 0;
  int tls = 1;
  int have_port = 0;
  int64_t port = 0;
  int have_frames = 0;
  int64_t frames = 0;
  int allow_insecure = 0;
  int i;
  char config_buf[4096];
  char program_buf[4096];
  const char *program;
  const char *security;
  BircKcProfile p;
  unsigned char secret[BIRC_KC_MAX_SECRET];
  size_t secret_n = 0;
  int missing = 0;
  int save = 0;
  char extra_frames[16];
  char extra_chan[BIRC_KC_CSV_MAX + 1u];
  char *extra[8];
  size_t extra_n = 0;
  int rc;

  (void)signal(SIGPIPE, SIG_IGN);
  for (i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
      birc_kc_help();
      return 0;
    }
    if (strcmp(argv[i], "--profile") == 0 && i + 1 < argc && !profile)
      profile = argv[++i];
    else if (strcmp(argv[i], "--config") == 0 && i + 1 < argc && !config)
      config = argv[++i];
    else if (strcmp(argv[i], "--create") == 0 && i + 1 < argc && !create)
      create = argv[++i];
    else if (strcmp(argv[i], "--nick") == 0 && i + 1 < argc && !nick)
      nick = argv[++i];
    else if (strcmp(argv[i], "--channel") == 0 && i + 1 < argc && !channel)
      channel = argv[++i];
    else if (strcmp(argv[i], "--allow-insecure-auth") == 0)
      allow_insecure = 1;
    else if (strcmp(argv[i], "--tls") == 0) {
      if (have_tls && !tls) {
        fputs("keychain-birc: invalid arguments; use --help\n", stderr);
        return 2;
      }
      have_tls = 1;
      tls = 1;
    } else if (strcmp(argv[i], "--plain") == 0) {
      if (have_tls && tls) {
        fputs("keychain-birc: invalid arguments; use --help\n", stderr);
        return 2;
      }
      have_tls = 1;
      tls = 0;
    } else if (strcmp(argv[i], "--port") == 0 && i + 1 < argc && !have_port) {
      int64_t v = 0;
      char *end = NULL;
      errno = 0;
      v = strtoll(argv[++i], &end, 10);
      if (errno || !end || *end || end == argv[i]) {
        fputs("keychain-birc: invalid arguments; use --help\n", stderr);
        return 2;
      }
      have_port = 1;
      port = v;
    } else if (strcmp(argv[i], "--frames") == 0 && i + 1 < argc && !have_frames) {
      char *end = NULL;
      errno = 0;
      frames = strtoll(argv[++i], &end, 10);
      if (errno || !end || *end || end == argv[i]) {
        fputs("keychain-birc: invalid arguments; use --help\n", stderr);
        return 2;
      }
      have_frames = 1;
    } else {
      fputs("keychain-birc: invalid arguments; use --help\n", stderr);
      return 2;
    }
  }
  if (!profile) {
    fputs("keychain-birc: invalid arguments; use --help\n", stderr);
    return 2;
  }

  if (!birc_kc_darwin()) {
    fputs("keychain-birc: macOS is required for Keychain authentication\n", stderr);
    return 1;
  }

  if (!config) {
    const char *xdg = getenv("XDG_CONFIG_HOME");
    const char *home = getenv("HOME");
    if (xdg && xdg[0]) {
      if (snprintf(config_buf, sizeof config_buf, "%s/birc/config.toml", xdg) < 0
          || config_buf[0] == 0) {
        fputs("keychain-birc: cannot locate profile config\n", stderr);
        return 1;
      }
    } else if (home && home[0]) {
      if (snprintf(config_buf, sizeof config_buf, "%s/.config/birc/config.toml", home) < 0
          || config_buf[0] == 0) {
        fputs("keychain-birc: cannot locate profile config\n", stderr);
        return 1;
      }
    } else {
      fputs("keychain-birc: cannot locate profile config\n", stderr);
      return 1;
    }
    config = config_buf;
  }

  if (have_port && (port < 1 || port > 65535)) {
    fputs("keychain-birc: invalid port override\n", stderr);
    return 1;
  }
  rc = birc_kc_read_profile(config, profile, have_tls, tls, have_port, (uint32_t)port, &p);
  if (rc < 0) {
    if (!create) {
      fprintf(stderr,
              "keychain-birc: unknown profile '%s' (use --create HOST --nick NICK to create it)\n",
              profile);
      return 1;
    }
    if (!nick) {
      fputs("keychain-birc: --create requires --nick to seed the profile\n", stderr);
      return 1;
    }
    if (!birc_kc_create_profile(config, profile, create, have_port, (uint32_t)port, nick,
                                channel, have_tls, tls, &p)) {
      fprintf(stderr, "keychain-birc: %s\n", birc_kc_why);
      return 1;
    }
    fprintf(stderr, "keychain-birc: created profile '%s' in %s\n", profile, config);
  } else if (rc == 0) {
    fprintf(stderr, "keychain-birc: %s\n", birc_kc_why);
    return 1;
  } else {
    if (nick) {
      fputs("keychain-birc: identity overrides are refused; the profile owns the nick\n",
            stderr);
      return 1;
    }
    if (create) {
      char want[BIRC_KC_HOST_MAX + 1u];
      char a[256], b[256];
      uint32_t ignored = 0;
      if (strchr(create, ':') != NULL) {
        fputs("keychain-birc: --create takes a bare host; use --port\n", stderr);
        return 1;
      }
      if (!birc_kc_endpoint(create, 0, 0, p.tls, want, sizeof want, &ignored)) {
        fprintf(stderr, "keychain-birc: %s\n", birc_kc_why);
        return 1;
      }
      birc_kc_bare_host(want, a, sizeof a);
      birc_kc_bare_host(p.host, b, sizeof b);
      if (strcmp(a, b) != 0) {
        fprintf(stderr, "keychain-birc: profile '%s' points at a different host\n",
                profile);
        return 1;
      }
    }
  }

  if (!p.tls && allow_insecure) {
    fputs("keychain-birc: WARNING: plaintext IRC authentication can expose your password.\n",
          stderr);
  } else if (!(p.tls || (p.relay && birc_kc_loopback(p.host)))) {
    fputs("keychain-birc: authentication requires TLS or a trusted loopback relay; "
          "use --allow-insecure-auth to accept plaintext risk\n",
          stderr);
    return 1;
  }

  if (have_frames) {
    if (frames < 0 || frames > 65535) {
      fputs("keychain-birc: invalid frame cap\n", stderr);
      return 1;
    }
    if (snprintf(extra_frames, sizeof extra_frames, "%lld", (long long)frames) < 0) {
      fputs("keychain-birc: invalid frame cap\n", stderr);
      return 1;
    }
    extra[extra_n++] = "--frames";
    extra[extra_n++] = extra_frames;
  }
  if (channel) {
    if (!birc_kc_channel_csv(channel, extra_chan, sizeof extra_chan)) {
      fputs("keychain-birc: invalid profile channels\n", stderr);
      return 1;
    }
    extra[extra_n++] = "--channel";
    extra[extra_n++] = extra_chan;
  }
  extra[extra_n] = NULL;

  program = getenv("BIRC_PROGRAM");
  if (!program || !program[0]) {
    birc_kc_sibling(argv[0], program_buf, sizeof program_buf);
    program = program_buf;
  }
#if defined(BIRC_KEYCHAIN_TEST)
  security = getenv("BIRC_SECURITY");
  if (!security || !security[0])
    security = BIRC_KC_SECURITY;
#else
  security = BIRC_KC_SECURITY;
#endif

  if (!birc_kc_load_secret(security, &p, secret, &secret_n, &missing)) {
    fprintf(stderr, "keychain-birc: %s\n", birc_kc_why);
    return 1;
  }
  save = missing;
  if (save) {
    char prompted[BIRC_KC_MAX_SECRET + 2u];
    if (!birc_kc_prompt(prompted, sizeof prompted)
        || !birc_kc_secret_bytes(prompted, secret, &secret_n)) {
      if (birc_kc_why[0] && strstr(birc_kc_why, "password") != NULL)
        fprintf(stderr, "keychain-birc: %s\n", birc_kc_why);
      else
        fputs("keychain-birc: password prompt requires a terminal with echo disabled\n",
              stderr);
      return 1;
    }
  }

  rc = birc_kc_launch(program, &p, secret, secret_n, extra, security, save);
  if (rc < 0) {
    fputs("keychain-birc: launch cancelled or unavailable\n", stderr);
    return 1;
  }
  return rc;
}
#endif /* BIRC_KEYCHAIN_CORE_ONLY */

#endif /* BIRC_KEYCHAIN_BIRC_C */
