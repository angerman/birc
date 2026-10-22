/* SPDX-License-Identifier: Apache-2.0
 * Image and card fetch/decode. Bend owns request identity and queues.
 * This effect admits files, talks HTTP/1.1 over OpenSSL, and decodes. */
#ifndef BIRC_MEDIA_FETCH_FFI_C
#define BIRC_MEDIA_FETCH_FFI_C

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE
#endif
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE
#endif

#include <arpa/inet.h>
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <openssl/err.h>
#include <openssl/pem.h>
#include <openssl/sha.h>
#include <openssl/ssl.h>
#include <openssl/x509v3.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>
#if defined(__APPLE__)
int getentropy(void *buffer, size_t size);
#else
#include <sys/random.h>
#endif

#ifndef STBI_INCLUDE_STB_IMAGE_H
#ifdef __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Weverything"
#endif
#ifdef __GNUC__
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wall"
#pragma GCC diagnostic ignored "-Wextra"
#pragma GCC diagnostic ignored "-Wpedantic"
#endif
#define STB_IMAGE_STATIC
#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_STDIO
#define STBI_NO_HDR
#define STBI_NO_PSD
#define STBI_NO_TGA
#define STBI_NO_PIC
#define STBI_NO_PNM
#define STBI_MAX_DIMENSIONS 4096
#include "stb_image.h"
#ifdef __GNUC__
#pragma GCC diagnostic pop
#endif
#ifdef __clang__
#pragma clang diagnostic pop
#endif
#endif

#define BIRC_MF_MAX_URL 4096u
#define BIRC_MF_MAX_HOST 253u
#define BIRC_MF_MAX_PATH 4096u
#define BIRC_MF_MAX_DOWNLOAD (8u * 1024u * 1024u)
#define BIRC_MF_MAX_LOCAL (16u * 1024u * 1024u)
#define BIRC_MF_MAX_HTML (256u * 1024u)
#define BIRC_MF_MAX_PAYLOAD (2u * 1024u * 1024u)
#define BIRC_MF_MAX_PIXELS (16u * 1024u * 1024u)
#define BIRC_MF_MAX_SIDE 320u
#define BIRC_MF_MAX_CACHE_ENTRIES 64u
#define BIRC_MF_MAX_CACHE_BYTES (64u * 1024u * 1024u)
#define BIRC_MF_MAX_CACHE_SCAN 256u
#define BIRC_MF_MAX_TITLE 128u
#define BIRC_MF_MAX_DESC 256u
#define BIRC_MF_MAX_IMAGE 1024u
#define BIRC_MF_MAX_META 200u
#define BIRC_MF_MAX_TAG 2048u
#define BIRC_MF_MAX_BASE (4u * 4096u)
#define BIRC_MF_REDIRECTS 3u
#define BIRC_MF_DEADLINE_MS 8000u

typedef struct {
  uint64_t dev, ino, size, mtime_ns, ctime_ns;
} BircMfId;

typedef struct {
  char scheme[8];
  char host[BIRC_MF_MAX_HOST + 1u];
  uint32_t port;
  char path[BIRC_MF_MAX_PATH + 1u];
} BircMfUrl;

static uint64_t birc_mf_now_ms(void) {
  struct timespec ts;
  if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
    return 0;
  return (uint64_t)ts.tv_sec * 1000ull + (uint64_t)ts.tv_nsec / 1000000ull;
}

static uint64_t birc_mf_ns(const struct timespec *ts) {
  return (uint64_t)ts->tv_sec * 1000000000ull + (uint64_t)ts->tv_nsec;
}

static BircMfId birc_mf_id(const struct stat *info) {
  BircMfId id;
  id.dev = (uint64_t)info->st_dev;
  id.ino = (uint64_t)info->st_ino;
  id.size = (uint64_t)info->st_size;
#if defined(__APPLE__)
  id.mtime_ns = birc_mf_ns(&info->st_mtimespec);
  id.ctime_ns = birc_mf_ns(&info->st_ctimespec);
#else
  id.mtime_ns = birc_mf_ns(&info->st_mtim);
  id.ctime_ns = birc_mf_ns(&info->st_ctim);
#endif
  return id;
}

static int birc_mf_id_eq(BircMfId a, BircMfId b) {
  return a.dev == b.dev && a.ino == b.ino && a.size == b.size
      && a.mtime_ns == b.mtime_ns && a.ctime_ns == b.ctime_ns;
}

static int birc_mf_dir_ok(const struct stat *info) {
  return S_ISDIR(info->st_mode) && info->st_uid == geteuid()
      && (info->st_mode & (mode_t)0077) == 0;
}

static int birc_mf_file_owned(const struct stat *info) {
  return S_ISREG(info->st_mode) && info->st_uid == geteuid()
      && info->st_nlink == 1;
}

static int birc_mf_hex(unsigned char c) {
  if (c >= '0' && c <= '9') return 1;
  if (c >= 'a' && c <= 'f') return 1;
  return 0;
}

static int birc_mf_payload_name(const char *name, const char *suffix) {
  size_t n = strlen(name);
  size_t s = strlen(suffix);
  size_t i;
  if (n != 64u + s || memcmp(name + 64, suffix, s) != 0)
    return 0;
  for (i = 0; i < 64u; i++) {
    if (!birc_mf_hex((unsigned char)name[i]))
      return 0;
  }
  return 1;
}

static int birc_mf_staging_name(const char *name) {
  size_t i;
  if (strlen(name) != 35u || memcmp(name, ".write-", 7) != 0
      || memcmp(name + 31, ".tmp", 4) != 0)
    return 0;
  for (i = 7; i < 31u; i++) {
    if (!birc_mf_hex((unsigned char)name[i]))
      return 0;
  }
  return 1;
}

static void birc_mf_sha_name(const char *url, const char *suffix, char *out, size_t n) {
  unsigned char dig[SHA256_DIGEST_LENGTH];
  static const char hex[] = "0123456789abcdef";
  size_t i;
  SHA256((const unsigned char *)url, strlen(url), dig);
  if (n < 65u + strlen(suffix)) {
    out[0] = 0;
    return;
  }
  for (i = 0; i < 32u; i++) {
    out[i * 2u] = hex[dig[i] >> 4];
    out[i * 2u + 1u] = hex[dig[i] & 15u];
  }
  memcpy(out + 64, suffix, strlen(suffix) + 1u);
}

static int birc_mf_public_v4(uint32_t a) {
  if (a <= 0x00ffffffu)
    return 0;
  if ((a & 0xff000000u) == 0x0a000000u)
    return 0;
  if ((a & 0xff000000u) == 0x7f000000u)
    return 0;
  if ((a & 0xffff0000u) == 0xa9fe0000u)
    return 0;
  if ((a & 0xfff00000u) == 0xac100000u)
    return 0;
  if ((a & 0xffff0000u) == 0xc0a80000u)
    return 0;
  if ((a & 0xffc00000u) == 0x64400000u)
    return 0;
  if ((a & 0xf0000000u) >= 0xe0000000u)
    return 0;
  return 1;
}

int birc_media_public_address(const char *value) {
  char host[128];
  const char *pct;
  struct in_addr a4;
  struct in6_addr a6;
  size_t n;
  if (!value || !value[0])
    return 0;
  pct = strchr(value, '%');
  n = pct ? (size_t)(pct - value) : strlen(value);
  if (n == 0 || n >= sizeof host)
    return 0;
  memcpy(host, value, n);
  host[n] = 0;
  if (strchr(host, ':')) {
    if (inet_pton(AF_INET6, host, &a6) != 1)
      return 0;
    if (IN6_IS_ADDR_V4MAPPED(&a6)) {
      memcpy(&a4, a6.s6_addr + 12, 4);
      return birc_mf_public_v4(ntohl(a4.s_addr));
    }
    if (a6.s6_addr[0] == 0x20 && a6.s6_addr[1] == 0x02)
      return 0;
    if (a6.s6_addr[0] == 0x20 && a6.s6_addr[1] == 0x01
        && a6.s6_addr[2] == 0 && a6.s6_addr[3] == 0)
      return 0;
    if ((a6.s6_addr[0] & 0xe0) != 0x20)
      return 0;
    if (IN6_IS_ADDR_MULTICAST(&a6))
      return 0;
    return 1;
  }
  if (inet_pton(AF_INET, host, &a4) != 1)
    return 0;
  return birc_mf_public_v4(ntohl(a4.s_addr));
}

static int birc_mf_host_ok(const char *host) {
  size_t n = strlen(host);
  size_t i, label = 0;
  if (n == 0 || n > BIRC_MF_MAX_HOST)
    return 0;
  for (i = 0; i < n; i++) {
    unsigned char c = (unsigned char)host[i];
    if (c == '.') {
      if (label == 0 || label > 63)
        return 0;
      label = 0;
    } else if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
               || (c >= '0' && c <= '9') || c == '-') {
      label++;
    } else {
      return 0;
    }
  }
  return label != 0 && label <= 63;
}

static int birc_mf_pct_ok(unsigned char c) {
  return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
      || (c >= '0' && c <= '9') || c == '/' || c == '%' || c == ':'
      || c == '@' || c == '!' || c == '$' || c == '&' || c == '\''
      || c == '(' || c == ')' || c == '*' || c == '+' || c == ','
      || c == ';' || c == '=' || c == '-' || c == '.' || c == '_'
      || c == '~';
}

static int birc_mf_quote(const char *in, int query, char *out, size_t out_n) {
  static const char hex[] = "0123456789ABCDEF";
  size_t used = 0;
  size_t i;
  for (i = 0; in[i]; i++) {
    unsigned char c = (unsigned char)in[i];
    int safe = birc_mf_pct_ok(c) || (query && c == '?');
    if (safe) {
      if (used + 1 >= out_n)
        return 0;
      out[used++] = (char)c;
    } else {
      if (used + 3 >= out_n)
        return 0;
      out[used++] = '%';
      out[used++] = hex[c >> 4];
      out[used++] = hex[c & 15u];
    }
  }
  out[used] = 0;
  return 1;
}

int birc_media_parse_url(const char *url, int https_only, BircMfUrl *out) {
  const char *p;
  const char *host_b;
  const char *path_b;
  char host[BIRC_MF_MAX_HOST + 8u];
  char path_raw[BIRC_MF_MAX_PATH + 1u];
  char query_raw[BIRC_MF_MAX_PATH + 1u];
  size_t i, n, hlen, plen;
  uint32_t port = 0;
  int has_port = 0;
  if (!url || !out)
    return 0;
  n = strlen(url);
  if (n == 0 || n > BIRC_MF_MAX_URL)
    return 0;
  for (i = 0; i < n; i++) {
    unsigned char c = (unsigned char)url[i];
    if (c <= 32u || c == 127u)
      return 0;
  }
  memset(out, 0, sizeof *out);
  if (n >= 8 && memcmp(url, "https://", 8) == 0) {
    memcpy(out->scheme, "https", 6);
    p = url + 8;
    port = 443;
  } else if (!https_only && n >= 7 && memcmp(url, "http://", 7) == 0) {
    memcpy(out->scheme, "http", 5);
    p = url + 7;
    port = 80;
  } else {
    return 0;
  }
  if (memchr(p, '@', strcspn(p, "/?#")))
    return 0;
  host_b = p;
  while (*p && *p != '/' && *p != '?' && *p != '#' && *p != ':')
    p++;
  hlen = (size_t)(p - host_b);
  if (hlen == 0 || hlen >= sizeof host)
    return 0;
  memcpy(host, host_b, hlen);
  host[hlen] = 0;
  if (*p == ':') {
    char *end = NULL;
    unsigned long parsed;
    p++;
    if (!isdigit((unsigned char)*p))
      return 0;
    errno = 0;
    parsed = strtoul(p, &end, 10);
    if (errno || end == p || parsed > 65535ul)
      return 0;
    has_port = 1;
    port = (uint32_t)parsed;
    p = end;
  }
  if (strcmp(out->scheme, "https") == 0) {
    if (has_port && port != 443)
      return 0;
    port = 443;
  } else {
    if (has_port && port != 80)
      return 0;
    port = 80;
  }
  if (*p && *p != '/' && *p != '?' && *p != '#')
    return 0;
  path_raw[0] = '/';
  path_raw[1] = 0;
  query_raw[0] = 0;
  if (*p == '/') {
    path_b = p;
    while (*p && *p != '?' && *p != '#')
      p++;
    plen = (size_t)(p - path_b);
    if (plen >= sizeof path_raw)
      return 0;
    memcpy(path_raw, path_b, plen);
    path_raw[plen] = 0;
  }
  if (*p == '?') {
    const char *q = p + 1;
    p++;
    while (*p && *p != '#')
      p++;
    plen = (size_t)(p - q);
    if (plen >= sizeof query_raw)
      return 0;
    memcpy(query_raw, q, plen);
    query_raw[plen] = 0;
  }
  for (i = 0; host[i]; i++) {
    if (host[i] >= 'A' && host[i] <= 'Z')
      host[i] = (char)(host[i] - 'A' + 'a');
  }
  if (!birc_mf_host_ok(host))
    return 0;
  memcpy(out->host, host, strlen(host) + 1u);
  out->port = port;
  if (!birc_mf_quote(path_raw, 0, out->path, sizeof out->path))
    return 0;
  if (query_raw[0]) {
    char qenc[BIRC_MF_MAX_PATH + 1u];
    size_t used = strlen(out->path);
    if (!birc_mf_quote(query_raw, 1, qenc, sizeof qenc))
      return 0;
    if (used + 1u + strlen(qenc) >= sizeof out->path)
      return 0;
    out->path[used] = '?';
    memcpy(out->path + used + 1u, qenc, strlen(qenc) + 1u);
  }
  return 1;
}

static int birc_mf_url_text(const BircMfUrl *u, char *out, size_t n) {
  int need_port = (strcmp(u->scheme, "https") == 0 && u->port != 443)
      || (strcmp(u->scheme, "http") == 0 && u->port != 80);
  int rc;
  if (need_port)
    rc = snprintf(out, n, "%s://%s:%u%s", u->scheme, u->host, u->port, u->path);
  else
    rc = snprintf(out, n, "%s://%s%s", u->scheme, u->host, u->path);
  return rc > 0 && (size_t)rc < n;
}

static int birc_mf_urljoin(const char *base, const char *loc, int https_only,
                           char *out, size_t n) {
  BircMfUrl bu;
  char built[BIRC_MF_MAX_URL + 1u];
  char merged[BIRC_MF_MAX_PATH + 1u];
  if (!loc || !loc[0] || strlen(loc) > BIRC_MF_MAX_URL)
    return 0;
  if (strstr(loc, "://"))
    return birc_media_parse_url(loc, https_only, &bu) && birc_mf_url_text(&bu, out, n);
  if (!birc_media_parse_url(base, https_only, &bu))
    return 0;
  if (loc[0] == '/' && loc[1] == '/') {
    if (snprintf(built, sizeof built, "%s:%s", bu.scheme, loc) >= (int)sizeof built)
      return 0;
    return birc_media_parse_url(built, https_only, &bu) && birc_mf_url_text(&bu, out, n);
  }
  if (loc[0] == '/') {
    memcpy(merged, loc, strlen(loc) + 1u);
  } else {
    char dir[BIRC_MF_MAX_PATH + 1u];
    char *slash;
    size_t dlen;
    memcpy(dir, bu.path, strlen(bu.path) + 1u);
    slash = strrchr(dir, '/');
    if (!slash)
      return 0;
    slash[1] = 0;
    dlen = strlen(dir);
    if (dlen + strlen(loc) >= sizeof merged)
      return 0;
    memcpy(merged, dir, dlen);
    memcpy(merged + dlen, loc, strlen(loc) + 1u);
  }
  {
    char *hash = strchr(merged, '#');
    if (hash)
      *hash = 0;
  }
  if (strlen(merged) >= sizeof bu.path)
    return 0;
  memcpy(bu.path, merged, strlen(merged) + 1u);
  return birc_mf_url_text(&bu, out, n) && birc_media_parse_url(out, https_only, &bu)
      && birc_mf_url_text(&bu, out, n);
}

static int birc_mf_poll(int fd, short ev, uint64_t deadline) {
  struct pollfd p;
  uint64_t now = birc_mf_now_ms();
  int wait;
  if (now >= deadline)
    return -1;
  wait = (int)(deadline - now);
  p.fd = fd;
  p.events = ev;
  p.revents = 0;
  if (poll(&p, 1, wait) <= 0)
    return -1;
  return 0;
}

static int birc_mf_no_password(char *bytes, int size, int writing, void *data) {
  (void)bytes;
  (void)size;
  (void)writing;
  (void)data;
  return 0;
}

static int birc_mf_ca_file(SSL_CTX *ctx, const char *path) {
  const size_t cap = 8u * 1024u * 1024u;
  struct stat info;
  unsigned char *bytes = NULL;
  BIO *bio = NULL;
  STACK_OF(X509_INFO) *items = NULL;
  X509_STORE *store;
  size_t size, used = 0;
  int fd = -1, count = 0, good = 0;
  if (!ctx || !path)
    return 0;
  store = SSL_CTX_get_cert_store(ctx);
  if (!store)
    return 0;
  fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
  if (fd < 0 || fstat(fd, &info) != 0 || !S_ISREG(info.st_mode)
      || info.st_size <= 0 || (uintmax_t)info.st_size > (uintmax_t)cap)
    goto done;
  size = (size_t)info.st_size;
  bytes = (unsigned char *)malloc(size);
  if (!bytes)
    goto done;
  while (used < size) {
    ssize_t got = read(fd, bytes + used, size - used < 65536u ? size - used : 65536u);
    if (got <= 0)
      goto done;
    used += (size_t)got;
  }
  if (close(fd) != 0) {
    fd = -1;
    goto done;
  }
  fd = -1;
  bio = BIO_new_mem_buf(bytes, (int)size);
  if (!bio)
    goto done;
  items = PEM_X509_INFO_read_bio(bio, NULL, birc_mf_no_password, NULL);
  if (!items)
    goto done;
  for (int i = 0; i < sk_X509_INFO_num(items); i++) {
    X509_INFO *item = sk_X509_INFO_value(items, i);
    if (!item)
      goto done;
    if (item->x509) {
      if (X509_STORE_add_cert(store, item->x509) != 1)
        goto done;
      count++;
    }
    if (item->crl) {
      if (X509_STORE_add_crl(store, item->crl) != 1)
        goto done;
      count++;
    }
  }
  good = count != 0;
done:
  if (fd >= 0)
    (void)close(fd);
  sk_X509_INFO_pop_free(items, X509_INFO_free);
  BIO_free(bio);
  free(bytes);
  return good;
}

static int birc_mf_trust(SSL_CTX *ctx) {
  const char *file = getenv("SSL_CERT_FILE");
  const char *directory = getenv("SSL_CERT_DIR");
  if (!ctx)
    return 0;
  if (file || directory) {
    if ((file && file[0] == 0) || (directory && directory[0] == 0))
      return 0;
    if (file && !birc_mf_ca_file(ctx, file))
      return 0;
    return directory == NULL || SSL_CTX_load_verify_locations(ctx, NULL, directory) == 1;
  }
  return SSL_CTX_set_default_verify_paths(ctx) == 1;
}

static int birc_mf_connect(const struct addrinfo *list, uint64_t deadline) {
  const struct addrinfo *it;
  for (it = list; it; it = it->ai_next) {
    int fd, flags;
    if (it->ai_addr->sa_family == AF_INET) {
      const struct sockaddr_in *sa = (const struct sockaddr_in *)it->ai_addr;
      char ip[INET_ADDRSTRLEN];
      inet_ntop(AF_INET, &sa->sin_addr, ip, sizeof ip);
      if (!birc_media_public_address(ip))
        return -1;
    } else if (it->ai_addr->sa_family == AF_INET6) {
      const struct sockaddr_in6 *sa = (const struct sockaddr_in6 *)it->ai_addr;
      char ip[INET6_ADDRSTRLEN];
      inet_ntop(AF_INET6, &sa->sin6_addr, ip, sizeof ip);
      if (!birc_media_public_address(ip))
        return -1;
    } else {
      continue;
    }
    fd = socket(it->ai_family, it->ai_socktype, it->ai_protocol);
    if (fd < 0)
      continue;
    flags = fcntl(fd, F_GETFL);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) != 0) {
      (void)close(fd);
      continue;
    }
    if (connect(fd, it->ai_addr, it->ai_addrlen) != 0 && errno != EINPROGRESS) {
      (void)close(fd);
      continue;
    }
    if (birc_mf_poll(fd, POLLOUT, deadline) == 0) {
      int err = 0;
      socklen_t n = sizeof err;
      if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &n) == 0 && err == 0)
        return fd;
    }
    (void)close(fd);
  }
  return -1;
}

static int birc_mf_ssl_wait(SSL *ssl, int fd, int why, uint64_t deadline) {
  if (why == SSL_ERROR_WANT_READ)
    return birc_mf_poll(fd, POLLIN, deadline);
  if (why == SSL_ERROR_WANT_WRITE)
    return birc_mf_poll(fd, POLLOUT, deadline);
  (void)ssl;
  return -1;
}

static int birc_mf_write(int fd, SSL *ssl, const char *buf, size_t n, uint64_t deadline) {
  size_t sent = 0;
  while (sent < n) {
    if (ssl) {
      int got;
      ERR_clear_error();
      got = SSL_write(ssl, buf + sent, (int)(n - sent));
      if (got > 0) {
        sent += (size_t)got;
        continue;
      }
      if (birc_mf_ssl_wait(ssl, fd, SSL_get_error(ssl, got), deadline) != 0)
        return -1;
    } else {
      ssize_t got;
      if (birc_mf_poll(fd, POLLOUT, deadline) != 0)
        return -1;
      got = send(fd, buf + sent, n - sent, 0);
      if (got <= 0)
        return -1;
      sent += (size_t)got;
    }
  }
  return 0;
}

static ssize_t birc_mf_read(int fd, SSL *ssl, void *buf, size_t n, uint64_t deadline) {
  if (ssl) {
    int got;
    for (;;) {
      ERR_clear_error();
      got = SSL_read(ssl, buf, (int)n);
      if (got > 0)
        return got;
      if (got == 0)
        return 0;
      if (birc_mf_ssl_wait(ssl, fd, SSL_get_error(ssl, got), deadline) != 0)
        return -1;
    }
  }
  if (birc_mf_poll(fd, POLLIN, deadline) != 0)
    return -1;
  return recv(fd, buf, n, 0);
}

static int birc_mf_header(const char *headers, const char *name, char *out, size_t n) {
  const char *p = headers;
  size_t nlen = strlen(name);
  while (*p) {
    const char *eol = strstr(p, "\r\n");
    size_t line = eol ? (size_t)(eol - p) : strlen(p);
    if (line >= nlen + 1u && strncasecmp(p, name, nlen) == 0 && p[nlen] == ':') {
      const char *v = p + nlen + 1;
      while (v < p + line && (*v == ' ' || *v == '\t'))
        v++;
      if ((size_t)(p + line - v) >= n)
        return 0;
      memcpy(out, v, (size_t)(p + line - v));
      out[p + line - v] = 0;
      return 1;
    }
    if (!eol)
      break;
    p = eol + 2;
  }
  return 0;
}

static int birc_mf_fetch(const char *url, int cards, uint64_t deadline,
                         unsigned char **body, size_t *body_n, char *final, size_t final_n) {
  char current[BIRC_MF_MAX_URL + 1u];
  unsigned redirect;
  if (!url || strlen(url) >= sizeof current)
    return 0;
  memcpy(current, url, strlen(url) + 1u);
  for (redirect = 0; redirect <= BIRC_MF_REDIRECTS; redirect++) {
    BircMfUrl parts;
    struct addrinfo hints;
    struct addrinfo *list = NULL;
    int fd = -1;
    SSL_CTX *ctx = NULL;
    SSL *ssl = NULL;
    char req[BIRC_MF_MAX_PATH + 512u];
    char hdr[65536];
    size_t hdr_n = 0;
    int status = 0;
    char location[BIRC_MF_MAX_URL + 1u];
    char encoding[64];
    char ctype[128];
    char clen[32];
    unsigned char *data = NULL;
    size_t data_n = 0;
    size_t maxb = cards ? BIRC_MF_MAX_HTML : BIRC_MF_MAX_DOWNLOAD;
    int ok = 0;
    if (birc_mf_now_ms() >= deadline)
      return 0;
    if (!birc_media_parse_url(current, cards, &parts))
      return 0;
    memset(&hints, 0, sizeof hints);
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_family = AF_UNSPEC;
    if (getaddrinfo(parts.host, NULL, &hints, &list) != 0 || !list)
      return 0;
    {
      struct addrinfo *it;
      for (it = list; it; it = it->ai_next) {
        if (it->ai_family == AF_INET)
          ((struct sockaddr_in *)it->ai_addr)->sin_port = htons((uint16_t)parts.port);
        else if (it->ai_family == AF_INET6)
          ((struct sockaddr_in6 *)it->ai_addr)->sin6_port = htons((uint16_t)parts.port);
      }
    }
    fd = birc_mf_connect(list, deadline);
    freeaddrinfo(list);
    if (fd < 0)
      return 0;
    if (strcmp(parts.scheme, "https") == 0) {
      int ip = 0;
      unsigned char addr[16];
      ctx = SSL_CTX_new(TLS_client_method());
      if (!ctx)
        goto hop_fail;
      SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);
      if (SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION) != 1 || !birc_mf_trust(ctx))
        goto hop_fail;
      (void)SSL_CTX_set_options(ctx, SSL_OP_NO_RENEGOTIATION);
      ssl = SSL_new(ctx);
      if (!ssl)
        goto hop_fail;
      ip = inet_pton(AF_INET, parts.host, addr) == 1
          || inet_pton(AF_INET6, parts.host, addr) == 1;
      SSL_set_hostflags(ssl, X509_CHECK_FLAG_NEVER_CHECK_SUBJECT
                           | X509_CHECK_FLAG_NO_PARTIAL_WILDCARDS);
      if ((ip && X509_VERIFY_PARAM_set1_ip_asc(SSL_get0_param(ssl), parts.host) != 1)
          || (!ip && (SSL_set1_host(ssl, parts.host) != 1
                      || SSL_set_tlsext_host_name(ssl, parts.host) != 1))
          || SSL_set_fd(ssl, fd) != 1)
        goto hop_fail;
      SSL_set_connect_state(ssl);
      for (;;) {
        int rc, why;
        ERR_clear_error();
        rc = SSL_connect(ssl);
        if (rc == 1 && SSL_get_verify_result(ssl) == X509_V_OK)
          break;
        why = SSL_get_error(ssl, rc);
        if (birc_mf_ssl_wait(ssl, fd, why, deadline) != 0)
          goto hop_fail;
      }
    }
    if (snprintf(req, sizeof req,
                 "GET %s HTTP/1.1\r\nHost: %s\r\nUser-Agent: %s\r\n"
                 "Accept: %s\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n",
                 parts.path, parts.host,
                 cards ? "birc-cards/1" : "birc-image/1",
                 cards ? "text/html" : "image/*") >= (int)sizeof req)
      goto hop_fail;
    if (birc_mf_write(fd, ssl, req, strlen(req), deadline) != 0)
      goto hop_fail;
    while (hdr_n + 1u < sizeof hdr) {
      ssize_t got = birc_mf_read(fd, ssl, hdr + hdr_n, sizeof hdr - 1u - hdr_n, deadline);
      if (got <= 0)
        goto hop_fail;
      hdr_n += (size_t)got;
      hdr[hdr_n] = 0;
      if (strstr(hdr, "\r\n\r\n"))
        break;
    }
    {
      char *sep = strstr(hdr, "\r\n\r\n");
      char *line_end;
      size_t preface;
      if (!sep || sscanf(hdr, "HTTP/%*s %d", &status) != 1)
        goto hop_fail;
      line_end = strstr(hdr, "\r\n");
      if (!line_end)
        goto hop_fail;
      preface = (size_t)(sep + 4 - hdr);
      data_n = hdr_n - preface;
      data = (unsigned char *)malloc(maxb + 1u);
      if (!data)
        goto hop_fail;
      if (data_n)
        memcpy(data, hdr + preface, data_n);
      if (status == 301 || status == 302 || status == 303 || status == 307 || status == 308) {
        if (redirect == BIRC_MF_REDIRECTS || !birc_mf_header(line_end + 2, "Location", location, sizeof location)
            || !birc_mf_urljoin(current, location, cards, current, sizeof current))
          goto hop_fail;
        if (cards && strncmp(current, "https://", 8) != 0)
          goto hop_fail;
        if (!cards && strcmp(parts.scheme, "https") == 0 && strncmp(current, "https://", 8) != 0)
          goto hop_fail;
        free(data);
        if (ssl)
          SSL_free(ssl);
        if (ctx)
          SSL_CTX_free(ctx);
        (void)close(fd);
        continue;
      }
      if (status != 200)
        goto hop_fail;
      encoding[0] = 0;
      if (birc_mf_header(line_end + 2, "Content-Encoding", encoding, sizeof encoding)
          && strcasecmp(encoding, "identity") != 0)
        goto hop_fail;
      if (birc_mf_header(line_end + 2, "Transfer-Encoding", encoding, sizeof encoding)
          && encoding[0] && strcasecmp(encoding, "identity") != 0)
        goto hop_fail;
      if (cards) {
        ctype[0] = 0;
        if (birc_mf_header(line_end + 2, "Content-Type", ctype, sizeof ctype)) {
          char *semi = strchr(ctype, ';');
          if (semi)
            *semi = 0;
          while (semi != ctype && ctype[0] && (ctype[strlen(ctype) - 1] == ' ' || ctype[strlen(ctype) - 1] == '\t'))
            ctype[strlen(ctype) - 1] = 0;
          if (strcasecmp(ctype, "text/html") != 0)
            goto hop_fail;
        }
      }
      clen[0] = 0;
      if (birc_mf_header(line_end + 2, "Content-Length", clen, sizeof clen)) {
        char *end = NULL;
        unsigned long want;
        size_t i;
        if (!clen[0])
          goto hop_fail;
        for (i = 0; clen[i]; i++) {
          if (!isdigit((unsigned char)clen[i]))
            goto hop_fail;
        }
        errno = 0;
        want = strtoul(clen, &end, 10);
        if (errno || !end || *end || want > maxb)
          goto hop_fail;
      }
      while (data_n <= maxb) {
        ssize_t got = birc_mf_read(fd, ssl, data + data_n, maxb + 1u - data_n, deadline);
        if (got < 0)
          goto hop_fail;
        if (got == 0)
          break;
        data_n += (size_t)got;
      }
      if (data_n > maxb)
        goto hop_fail;
      if (clen[0] && data_n != strtoul(clen, NULL, 10))
        goto hop_fail;
      if (final && !birc_mf_url_text(&parts, final, final_n))
        goto hop_fail;
      *body = data;
      *body_n = data_n;
      data = NULL;
      ok = 1;
    }
hop_fail:
    free(data);
    if (ssl)
      SSL_free(ssl);
    if (ctx)
      SSL_CTX_free(ctx);
    if (fd >= 0)
      (void)close(fd);
    ERR_clear_error();
    return ok;
  }
  return 0;
}

static int birc_mf_mkdir_walk(int *dirfd, const char *path, int create) {
  char buf[4096];
  size_t n = strlen(path);
  size_t i;
  int fd;
  if (n == 0 || n >= sizeof buf || path[0] != '/')
    return -1;
  memcpy(buf, path, n + 1u);
  fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0)
    return -1;
  for (i = 1; i <= n; i++) {
    if (i == n || buf[i] == '/') {
      char saved = buf[i];
      int next;
      buf[i] = 0;
      if (buf[0] != 0 && !(buf[0] == '/' && buf[1] == 0)) {
        const char *name = strrchr(buf, '/');
        name = name ? name + 1 : buf;
        if (create)
          (void)mkdirat(fd, name, 0700);
        next = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (next < 0) {
          (void)close(fd);
          return -1;
        }
        (void)close(fd);
        fd = next;
      }
      buf[i] = saved;
    }
  }
  {
    struct stat info;
    if (fstat(fd, &info) != 0 || !birc_mf_dir_ok(&info)) {
      (void)close(fd);
      return -1;
    }
  }
  *dirfd = fd;
  return 0;
}

static int birc_mf_cache_root(int create, int *dirfd) {
  const char *explicit = getenv("BIRC_IMAGE_CACHE");
  char path[4096];
  const char *base;
  if (explicit && (explicit[0] == 0 || strcmp(explicit, "none") == 0))
    return -1;
  if (explicit) {
    if (explicit[0] != '/' || strlen(explicit) >= sizeof path)
      return -1;
    memcpy(path, explicit, strlen(explicit) + 1u);
  } else {
    base = getenv("XDG_CACHE_HOME");
    if (base && base[0] == '/') {
      if (snprintf(path, sizeof path, "%s/birc/images", base) >= (int)sizeof path)
        return -1;
    } else {
      base = getenv("HOME");
      if (!base || base[0] != '/')
        return -1;
      if (snprintf(path, sizeof path, "%s/.cache/birc/images", base) >= (int)sizeof path)
        return -1;
    }
  }
  return birc_mf_mkdir_walk(dirfd, path, create);
}

static int birc_mf_open_cards(int parent, int create, int *out) {
  int fd;
  struct stat info;
  if (create)
    (void)mkdirat(parent, "cards", 0700);
  fd = openat(parent, "cards", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0)
    return -1;
  if (fstat(fd, &info) != 0 || !birc_mf_dir_ok(&info)) {
    (void)close(fd);
    return -1;
  }
  *out = fd;
  return 0;
}

static int birc_mf_usage(int dirfd, const char *suffix, uint32_t *count, uint64_t *bytes) {
  int scanfd = dup(dirfd);
  DIR *dir;
  struct dirent *ent;
  uint32_t seen = 0;
  uint64_t total = 0;
  uint32_t n = 0;
  if (scanfd < 0)
    return -1;
  dir = fdopendir(scanfd);
  if (!dir) {
    (void)close(scanfd);
    return -1;
  }
  while ((ent = readdir(dir))) {
    struct stat info;
    if (seen >= BIRC_MF_MAX_CACHE_SCAN) {
      (void)closedir(dir);
      return -1;
    }
    seen++;
    if (!birc_mf_payload_name(ent->d_name, suffix) && !birc_mf_staging_name(ent->d_name))
      continue;
    if (fstatat(dirfd, ent->d_name, &info, AT_SYMLINK_NOFOLLOW) != 0
        || !birc_mf_file_owned(&info)) {
      (void)closedir(dir);
      return -1;
    }
    n++;
    total += (uint64_t)info.st_size;
  }
  (void)closedir(dir);
  *count = n;
  *bytes = total;
  return 0;
}

static int birc_mf_read_cached(int dirfd, const char *name, size_t limit,
                               unsigned char **out, size_t *out_n) {
  int fd = openat(dirfd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
  struct stat info, cur, after;
  unsigned char *data;
  size_t used = 0;
  if (fd < 0)
    return 0;
  if (fstat(fd, &info) != 0 || !birc_mf_file_owned(&info)
      || info.st_size <= 0 || (size_t)info.st_size > limit) {
    (void)close(fd);
    return 0;
  }
  (void)fchmod(fd, 0600);
  if (fstat(fd, &info) != 0) {
    (void)close(fd);
    return 0;
  }
  data = (unsigned char *)malloc((size_t)info.st_size);
  if (!data) {
    (void)close(fd);
    return 0;
  }
  while (used < (size_t)info.st_size) {
    ssize_t got = read(fd, data + used, (size_t)info.st_size - used);
    if (got <= 0) {
      free(data);
      (void)close(fd);
      return 0;
    }
    used += (size_t)got;
  }
  if (fstat(fd, &after) != 0 || fstatat(dirfd, name, &cur, AT_SYMLINK_NOFOLLOW) != 0
      || !birc_mf_id_eq(birc_mf_id(&info), birc_mf_id(&after))
      || !birc_mf_id_eq(birc_mf_id(&info), birc_mf_id(&cur))) {
    free(data);
    (void)close(fd);
    return 0;
  }
  (void)close(fd);
  *out = data;
  *out_n = used;
  return 1;
}

static int birc_mf_lock(int dirfd) {
  int fd = openat(dirfd, ".lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0600);
  struct stat info;
  if (fd < 0)
    return -1;
  if (fstat(fd, &info) != 0 || !birc_mf_file_owned(&info) || fchmod(fd, 0600) != 0
      || flock(fd, LOCK_EX | LOCK_NB) != 0) {
    (void)close(fd);
    return -1;
  }
  return fd;
}

typedef struct {
  uint64_t mtime_ns;
  off_t size;
  char name[80];
} BircMfEnt;

static int birc_mf_commit(int dirfd, const char *target, const unsigned char *data, size_t n,
                          const struct stat *previous) {
  unsigned char rnd[12];
  char tmp[40];
  static const char hex[] = "0123456789abcdef";
  int fd = -1;
  size_t i, used = 0;
  struct stat cur;
  int have_cur;
  if (getentropy(rnd, sizeof rnd) != 0)
    return -1;
  memcpy(tmp, ".write-", 7);
  for (i = 0; i < 12u; i++) {
    tmp[7 + i * 2u] = hex[rnd[i] >> 4];
    tmp[8 + i * 2u] = hex[rnd[i] & 15u];
  }
  memcpy(tmp + 31, ".tmp", 5);
  fd = openat(dirfd, tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
  if (fd < 0)
    return -1;
  (void)fchmod(fd, 0600);
  while (used < n) {
    ssize_t got = write(fd, data + used, n - used);
    if (got <= 0) {
      (void)close(fd);
      (void)unlinkat(dirfd, tmp, 0);
      return -1;
    }
    used += (size_t)got;
  }
  have_cur = fstatat(dirfd, target, &cur, AT_SYMLINK_NOFOLLOW) == 0;
  if ((previous == NULL) != (!have_cur)
      || (have_cur && previous && !birc_mf_id_eq(birc_mf_id(previous), birc_mf_id(&cur)))) {
    (void)close(fd);
    (void)unlinkat(dirfd, tmp, 0);
    return -1;
  }
  if (renameat(dirfd, tmp, dirfd, target) != 0) {
    (void)close(fd);
    (void)unlinkat(dirfd, tmp, 0);
    return -1;
  }
  (void)close(fd);
  return 0;
}

static void birc_mf_cache_write(int parent, int cards, const char *url,
                                const unsigned char *data, size_t n, const char *final) {
  char name[80];
  const char *suffix = cards ? ".card" : ".img";
  int dirfd = -1, lock = -1, otherfd = -1;
  uint32_t other_n = 0;
  uint64_t other_b = 0;
  unsigned char *stored = NULL;
  size_t stored_n = n;
  struct stat prev;
  int have_prev;
  BircMfEnt ents[BIRC_MF_MAX_CACHE_SCAN];
  size_t ent_n = 0;
  uint32_t seen = 0;
  if (!data || n == 0 || n > (cards ? BIRC_MF_MAX_HTML : BIRC_MF_MAX_DOWNLOAD)
      || n > BIRC_MF_MAX_CACHE_BYTES)
    return;
  if (cards) {
    size_t flen = strlen(final ? final : url);
    stored_n = flen + 1u + n;
    if (stored_n > BIRC_MF_MAX_CACHE_BYTES)
      return;
    stored = (unsigned char *)malloc(stored_n);
    if (!stored)
      return;
    memcpy(stored, final ? final : url, flen);
    stored[flen] = '\n';
    memcpy(stored + flen + 1u, data, n);
    data = stored;
    n = stored_n;
  }
  birc_mf_sha_name(url, suffix, name, sizeof name);
  if (cards) {
    if (birc_mf_open_cards(parent, 1, &dirfd) != 0)
      goto done;
  } else {
    dirfd = parent;
  }
  lock = birc_mf_lock(parent);
  if (lock < 0)
    goto done;
  /* Images are .img files beside the parent; cards are .card files under cards/. Both caps count the other tree. */
  if (cards) {
    otherfd = parent;
  } else {
    struct stat cards_st;
    if (fstatat(parent, "cards", &cards_st, AT_SYMLINK_NOFOLLOW) != 0) {
      if (errno != ENOENT)
        goto done;
    } else if (!S_ISDIR(cards_st.st_mode)
               || birc_mf_open_cards(parent, 0, &otherfd) != 0) {
      goto done;
    }
  }
  if (otherfd >= 0
      && birc_mf_usage(otherfd, cards ? ".img" : ".card", &other_n, &other_b) != 0)
    goto done;
  if (other_n + 1u > BIRC_MF_MAX_CACHE_ENTRIES || other_b + n > BIRC_MF_MAX_CACHE_BYTES)
    goto done;
  have_prev = fstatat(dirfd, name, &prev, AT_SYMLINK_NOFOLLOW) == 0;
  if (have_prev && !birc_mf_file_owned(&prev))
    goto done;
  {
    int scanfd = dup(dirfd);
    DIR *dir;
    struct dirent *ent;
    if (scanfd < 0)
      goto done;
    dir = fdopendir(scanfd);
    if (!dir) {
      (void)close(scanfd);
      goto done;
    }
    while ((ent = readdir(dir))) {
      struct stat info;
      if (seen >= BIRC_MF_MAX_CACHE_SCAN) {
        (void)closedir(dir);
        goto done;
      }
      seen++;
      if (!birc_mf_payload_name(ent->d_name, suffix) && !birc_mf_staging_name(ent->d_name))
        continue;
      if (fstatat(dirfd, ent->d_name, &info, AT_SYMLINK_NOFOLLOW) != 0
          || !birc_mf_file_owned(&info)) {
        (void)closedir(dir);
        goto done;
      }
      if (strcmp(ent->d_name, name) == 0)
        continue;
      if (ent_n >= BIRC_MF_MAX_CACHE_SCAN) {
        (void)closedir(dir);
        goto done;
      }
      ents[ent_n].mtime_ns = birc_mf_id(&info).mtime_ns;
      ents[ent_n].size = info.st_size;
      memcpy(ents[ent_n].name, ent->d_name, strlen(ent->d_name) + 1u);
      ent_n++;
    }
    (void)closedir(dir);
  }
  {
    size_t a, b;
    for (a = 0; a < ent_n; a++) {
      for (b = a + 1; b < ent_n; b++) {
        if (ents[b].mtime_ns < ents[a].mtime_ns
            || (ents[b].mtime_ns == ents[a].mtime_ns && strcmp(ents[b].name, ents[a].name) < 0)) {
          BircMfEnt tmp = ents[a];
          ents[a] = ents[b];
          ents[b] = tmp;
        }
      }
    }
  }
  {
    uint64_t total = 0;
    size_t i;
    for (i = 0; i < ent_n; i++)
      total += (uint64_t)ents[i].size;
    i = 0;
    while (i < ent_n && (other_n + (uint32_t)(ent_n - i) + 1u > BIRC_MF_MAX_CACHE_ENTRIES
                         || other_b + total + n > BIRC_MF_MAX_CACHE_BYTES)) {
      struct stat now;
      if (fstatat(dirfd, ents[i].name, &now, AT_SYMLINK_NOFOLLOW) != 0
          || birc_mf_id(&now).mtime_ns != ents[i].mtime_ns) {
        goto done;
      }
      if (unlinkat(dirfd, ents[i].name, 0) != 0)
        goto done;
      total -= (uint64_t)ents[i].size;
      i++;
    }
  }
  (void)birc_mf_commit(dirfd, name, data, n, have_prev ? &prev : NULL);
done:
  if (lock >= 0)
    (void)close(lock);
  if (cards && dirfd >= 0)
    (void)close(dirfd);
  if (!cards && otherfd >= 0)
    (void)close(otherfd);
  free(stored);
}

static unsigned char *birc_mf_read_regular(const char *path, size_t limit, size_t *out_n) {
  int fd;
  struct stat info;
  unsigned char *data;
  size_t used = 0;
  if (!path || !path[0])
    return NULL;
  fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
  if (fd < 0)
    return NULL;
  if (fstat(fd, &info) != 0 || !S_ISREG(info.st_mode)
      || info.st_size <= 0 || (size_t)info.st_size > limit) {
    (void)close(fd);
    return NULL;
  }
  data = (unsigned char *)malloc((size_t)info.st_size + 1u);
  if (!data) {
    (void)close(fd);
    return NULL;
  }
  while (used <= (size_t)info.st_size) {
    size_t want = (size_t)info.st_size + 1u - used;
    ssize_t got = read(fd, data + used, want > 65536u ? 65536u : want);
    if (got < 0) {
      free(data);
      (void)close(fd);
      return NULL;
    }
    if (got == 0)
      break;
    used += (size_t)got;
  }
  (void)close(fd);
  if (used != (size_t)info.st_size) {
    free(data);
    return NULL;
  }
  *out_n = used;
  return data;
}

static uint32_t birc_mf_crc32(const unsigned char *p, size_t n) {
  static uint32_t table[256];
  static int ready;
  uint32_t c = 0xffffffffu;
  size_t i;
  if (!ready) {
    uint32_t k, b;
    for (k = 0; k < 256u; k++) {
      uint32_t v = k;
      for (b = 0; b < 8u; b++)
        v = (v & 1u) ? (0xedb88320u ^ (v >> 1)) : (v >> 1);
      table[k] = v;
    }
    ready = 1;
  }
  for (i = 0; i < n; i++)
    c = table[(c ^ p[i]) & 255u] ^ (c >> 8);
  return c ^ 0xffffffffu;
}

static uint32_t birc_mf_adler(const unsigned char *p, size_t n) {
  uint32_t s1 = 1, s2 = 0;
  size_t i;
  for (i = 0; i < n; i++) {
    s1 = (s1 + p[i]) % 65521u;
    s2 = (s2 + s1) % 65521u;
  }
  return (s2 << 16) | s1;
}

static void birc_mf_be32(unsigned char *p, uint32_t v) {
  p[0] = (unsigned char)(v >> 24);
  p[1] = (unsigned char)(v >> 16);
  p[2] = (unsigned char)(v >> 8);
  p[3] = (unsigned char)v;
}

static int birc_mf_png_chunk(unsigned char **cur, unsigned char *end, const char *type,
                             const unsigned char *data, uint32_t n) {
  unsigned char head[8];
  unsigned char crcbuf[8];
  unsigned char *crc_src;
  uint32_t crc;
  if (*cur + 12u + n > end)
    return 0;
  birc_mf_be32(head, n);
  memcpy(head + 4, type, 4);
  memcpy(*cur, head, 8);
  *cur += 8;
  if (n) {
    memcpy(*cur, data, n);
    *cur += n;
  }
  crc_src = (unsigned char *)malloc(4u + n);
  if (!crc_src)
    return 0;
  memcpy(crc_src, type, 4);
  if (n)
    memcpy(crc_src + 4, data, n);
  crc = birc_mf_crc32(crc_src, 4u + n);
  free(crc_src);
  birc_mf_be32(crcbuf, crc);
  memcpy(*cur, crcbuf, 4);
  *cur += 4;
  return 1;
}

static int birc_mf_write_png(const unsigned char *rgba, uint32_t w, uint32_t h,
                             unsigned char **out, size_t *out_n) {
  size_t raw_n = (size_t)h * ((size_t)w * 4u + 1u);
  unsigned char *raw = (unsigned char *)malloc(raw_n);
  unsigned char *z;
  size_t z_n, pos = 0, left;
  unsigned char *png;
  unsigned char *cur;
  unsigned char ihdr[13];
  size_t png_cap;
  uint32_t y;
  uint32_t adler;
  if (!raw)
    return 0;
  for (y = 0; y < h; y++) {
    raw[(size_t)y * ((size_t)w * 4u + 1u)] = 0;
    memcpy(raw + (size_t)y * ((size_t)w * 4u + 1u) + 1u,
           rgba + (size_t)y * (size_t)w * 4u, (size_t)w * 4u);
  }
  z_n = 2u + ((raw_n + 65535u) / 65535u) * 5u + raw_n + 4u;
  z = (unsigned char *)malloc(z_n);
  if (!z) {
    free(raw);
    return 0;
  }
  z[0] = 0x78;
  z[1] = 0x01;
  pos = 2;
  left = raw_n;
  while (left) {
    uint32_t chunk = left > 65535u ? 65535u : (uint32_t)left;
    z[pos] = left == chunk ? 1 : 0;
    z[pos + 1] = (unsigned char)(chunk & 255u);
    z[pos + 2] = (unsigned char)(chunk >> 8);
    z[pos + 3] = (unsigned char)((~chunk) & 255u);
    z[pos + 4] = (unsigned char)((~chunk) >> 8);
    memcpy(z + pos + 5, raw + (raw_n - left), chunk);
    pos += 5u + chunk;
    left -= chunk;
  }
  adler = birc_mf_adler(raw, raw_n);
  birc_mf_be32(z + pos, adler);
  pos += 4;
  free(raw);
  png_cap = 8u + 12u + 13u + 12u + pos + 12u;
  png = (unsigned char *)malloc(png_cap);
  if (!png) {
    free(z);
    return 0;
  }
  memcpy(png, "\x89PNG\r\n\x1a\n", 8);
  cur = png + 8;
  birc_mf_be32(ihdr, w);
  birc_mf_be32(ihdr + 4, h);
  ihdr[8] = 8;
  ihdr[9] = 6;
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;
  if (!birc_mf_png_chunk(&cur, png + png_cap, "IHDR", ihdr, 13)
      || !birc_mf_png_chunk(&cur, png + png_cap, "IDAT", z, (uint32_t)pos)
      || !birc_mf_png_chunk(&cur, png + png_cap, "IEND", NULL, 0)) {
    free(z);
    free(png);
    return 0;
  }
  free(z);
  *out = png;
  *out_n = (size_t)(cur - png);
  return 1;
}

static void birc_mf_thumb(const unsigned char *src, int sw, int sh,
                          unsigned char *dst, int dw, int dh) {
  int y, x;
  for (y = 0; y < dh; y++) {
    int sy = (int)(((int64_t)y * sh) / dh);
    for (x = 0; x < dw; x++) {
      int sx = (int)(((int64_t)x * sw) / dw);
      memcpy(dst + ((size_t)y * (size_t)dw + (size_t)x) * 4u,
             src + ((size_t)sy * (size_t)sw + (size_t)sx) * 4u, 4);
    }
  }
}

static size_t birc_mf_b64(const unsigned char *in, size_t n, char *out, size_t out_n) {
  static const char tab[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  size_t i, used = 0;
  for (i = 0; i < n; i += 3) {
    unsigned int a = in[i];
    unsigned int b = i + 1 < n ? in[i + 1] : 0;
    unsigned int c = i + 2 < n ? in[i + 2] : 0;
    unsigned int v = (a << 16) | (b << 8) | c;
    if (used + 4 >= out_n)
      return 0;
    out[used++] = tab[(v >> 18) & 63u];
    out[used++] = tab[(v >> 12) & 63u];
    out[used++] = (i + 1 < n) ? tab[(v >> 6) & 63u] : '=';
    out[used++] = (i + 2 < n) ? tab[v & 63u] : '=';
  }
  out[used] = 0;
  return used;
}

uint32_t birc_media_encode(const unsigned char *data, size_t n, char **out, size_t *out_n) {
  int w = 0, h = 0, comp = 0;
  unsigned char *rgba;
  unsigned char *scaled = NULL;
  unsigned char *png = NULL;
  unsigned char *payload = NULL;
  char *b64 = NULL;
  size_t png_n = 0, payload_n, b64_n, rgba_n;
  uint32_t dw, dh;
  uint32_t rc = 1;
  if (!data || n == 0 || n > BIRC_MF_MAX_LOCAL)
    return 1;
  rgba = stbi_load_from_memory(data, (int)n, &w, &h, &comp, 4);
  if (!rgba || w <= 0 || h <= 0 || w > 4096 || h > 4096
      || (uint64_t)w * (uint64_t)h > BIRC_MF_MAX_PIXELS)
    goto done;
  dw = (uint32_t)w;
  dh = (uint32_t)h;
  if (dw > BIRC_MF_MAX_SIDE || dh > BIRC_MF_MAX_SIDE) {
    if (dw >= dh) {
      dh = dh * BIRC_MF_MAX_SIDE / dw;
      dw = BIRC_MF_MAX_SIDE;
    } else {
      dw = dw * BIRC_MF_MAX_SIDE / dh;
      dh = BIRC_MF_MAX_SIDE;
    }
    if (dw == 0)
      dw = 1;
    if (dh == 0)
      dh = 1;
  }
  if (dw != (uint32_t)w || dh != (uint32_t)h) {
    scaled = (unsigned char *)malloc((size_t)dw * dh * 4u);
    if (!scaled)
      goto done;
    birc_mf_thumb(rgba, w, h, scaled, (int)dw, (int)dh);
  } else {
    scaled = rgba;
    rgba = NULL;
  }
  if (!birc_mf_write_png(scaled, dw, dh, &png, &png_n))
    goto done;
  rgba_n = (size_t)dw * dh * 4u;
  payload_n = 32u + rgba_n + 8u + png_n;
  if (payload_n > BIRC_MF_MAX_PAYLOAD)
    goto done;
  payload = (unsigned char *)malloc(payload_n);
  if (!payload)
    goto done;
  memcpy(payload, "BIRCIMG1", 8);
  birc_mf_be32(payload + 8, dw);
  birc_mf_be32(payload + 12, dh);
  birc_mf_be32(payload + 16, 1);
  birc_mf_be32(payload + 20, 1);
  birc_mf_be32(payload + 24, (uint32_t)rgba_n);
  birc_mf_be32(payload + 28, 0);
  memcpy(payload + 32, scaled, rgba_n);
  birc_mf_be32(payload + 32 + rgba_n, 100);
  birc_mf_be32(payload + 36 + rgba_n, (uint32_t)png_n);
  memcpy(payload + 40 + rgba_n, png, png_n);
  b64 = (char *)malloc(((payload_n + 2u) / 3u) * 4u + 2u);
  if (!b64)
    goto done;
  b64_n = birc_mf_b64(payload, payload_n, b64, ((payload_n + 2u) / 3u) * 4u + 2u);
  if (!b64_n)
    goto done;
  *out = b64;
  *out_n = b64_n;
  b64 = NULL;
  rc = 0;
done:
  if (rgba)
    stbi_image_free(rgba);
  if (scaled && scaled != rgba)
    free(scaled);
  free(png);
  free(payload);
  free(b64);
  return rc;
}

static int birc_mf_utf8_take(const char *in, size_t max_cp, char *out, size_t out_n) {
  size_t i = 0, o = 0, cps = 0;
  while (in[i] && cps < max_cp) {
    unsigned char c = (unsigned char)in[i];
    size_t need = 1;
    if (c >= 0x80) {
      if ((c & 0xe0) == 0xc0) need = 2;
      else if ((c & 0xf0) == 0xe0) need = 3;
      else if ((c & 0xf8) == 0xf0) need = 4;
      else { i++; continue; }
    }
    if (o + need >= out_n)
      break;
    memcpy(out + o, in + i, need);
    o += need;
    i += need;
    cps++;
  }
  out[o] = 0;
  return 1;
}

static void birc_mf_unescape(const char *in, char *out, size_t out_n) {
  size_t i = 0, o = 0;
  while (in[i] && o + 1 < out_n) {
    if (in[i] == '&') {
      if (strncmp(in + i, "&amp;", 5) == 0) { out[o++] = '&'; i += 5; continue; }
      if (strncmp(in + i, "&lt;", 4) == 0) { out[o++] = '<'; i += 4; continue; }
      if (strncmp(in + i, "&gt;", 4) == 0) { out[o++] = '>'; i += 4; continue; }
      if (strncmp(in + i, "&quot;", 6) == 0) { out[o++] = '"'; i += 6; continue; }
      if (strncmp(in + i, "&apos;", 6) == 0) { out[o++] = '\''; i += 6; continue; }
      if (in[i + 1] == '#') {
        char *end = NULL;
        unsigned long v;
        if (in[i + 2] == 'x' || in[i + 2] == 'X')
          v = strtoul(in + i + 3, &end, 16);
        else
          v = strtoul(in + i + 2, &end, 10);
        /* U+D800..U+DFFF are not scalar values; leave that reference text. */
        if (end && *end == ';' && v > 0 && v <= 0x10fffful
            && (v < 0xd800ul || v > 0xdffful)) {
          if (v < 0x80) {
            out[o++] = (char)v;
          } else if (v < 0x800 && o + 2 < out_n) {
            out[o++] = (char)(0xc0 | (v >> 6));
            out[o++] = (char)(0x80 | (v & 0x3f));
          } else if (v < 0x10000 && o + 3 < out_n) {
            out[o++] = (char)(0xe0 | (v >> 12));
            out[o++] = (char)(0x80 | ((v >> 6) & 0x3f));
            out[o++] = (char)(0x80 | (v & 0x3f));
          } else if (v >= 0x10000ul && o + 4 < out_n) {
            out[o++] = (char)(0xf0 | (v >> 18));
            out[o++] = (char)(0x80 | ((v >> 12) & 0x3f));
            out[o++] = (char)(0x80 | ((v >> 6) & 0x3f));
            out[o++] = (char)(0x80 | (v & 0x3f));
          }
          i = (size_t)(end - in) + 1u;
          continue;
        }
      }
    }
    out[o++] = in[i++];
  }
  out[o] = 0;
}

static void birc_mf_clean(const char *in, size_t limit, char *out, size_t out_n) {
  char unesc[8192];
  char spaced[8192];
  size_t i, o = 0, start = 0;
  birc_mf_unescape(in, unesc, sizeof unesc);
  for (i = 0; unesc[i] && o + 1 < sizeof spaced; i++) {
    unsigned char c = (unsigned char)unesc[i];
    spaced[o++] = (c < 32u || c == 127u) ? ' ' : (char)c;
  }
  spaced[o] = 0;
  o = 0;
  while (spaced[start] == ' ')
    start++;
  i = start;
  while (spaced[i] && o + 1 < sizeof unesc) {
    if (spaced[i] == ' ') {
      while (spaced[i] == ' ')
        i++;
      if (spaced[i] && o)
        unesc[o++] = ' ';
      continue;
    }
    unesc[o++] = spaced[i++];
  }
  unesc[o] = 0;
  birc_mf_utf8_take(unesc, limit, out, out_n);
}

static int birc_mf_attr(const char *tag, const char *key, char *out, size_t n) {
  const char *p = tag;
  size_t klen = strlen(key);
  while (*p) {
    while (*p && !(((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z') || *p == ':' || *p == '-')))
      p++;
    if (!*p)
      return 0;
    if (strncasecmp(p, key, klen) == 0 && (p[klen] == '=' || p[klen] == ' ' || p[klen] == '\t')) {
      const char *eq = strchr(p + klen, '=');
      char q;
      const char *v;
      size_t i = 0;
      if (!eq)
        return 0;
      v = eq + 1;
      while (*v == ' ' || *v == '\t')
        v++;
      if (*v != '"' && *v != '\'')
        return 0;
      q = *v++;
      while (v[i] && v[i] != q && i + 1 < n)
        i++;
      if (v[i] != q)
        return 0;
      memcpy(out, v, i);
      out[i] = 0;
      return 1;
    }
    while (*p && *p != '=' && *p != ' ' && *p != '>')
      p++;
    if (*p == '=') {
      p++;
      while (*p == ' ' || *p == '\t')
        p++;
      if (*p == '"' || *p == '\'') {
        char q = *p++;
        while (*p && *p != q)
          p++;
        if (*p == q)
          p++;
      }
    }
  }
  return 0;
}

static void birc_mf_lower(char *s) {
  size_t i;
  for (i = 0; s[i]; i++) {
    if (s[i] >= 'A' && s[i] <= 'Z')
      s[i] = (char)(s[i] - 'A' + 'a');
  }
}

static int birc_mf_card_image(const char *raw, const char *base, char *out, size_t n) {
  char joined[BIRC_MF_MAX_URL + 1u];
  BircMfUrl url;
  char cleaned[BIRC_MF_MAX_IMAGE + 8u];
  if (!raw || !raw[0] || strlen(raw) > BIRC_MF_MAX_IMAGE)
    return 0;
  birc_mf_clean(raw, BIRC_MF_MAX_IMAGE, cleaned, sizeof cleaned);
  if (!cleaned[0] || !birc_mf_urljoin(base, cleaned, 1, joined, sizeof joined)
      || !birc_media_parse_url(joined, 1, &url) || strlen(joined) > BIRC_MF_MAX_IMAGE)
    return 0;
  if (strlen(joined) >= n)
    return 0;
  memcpy(out, joined, strlen(joined) + 1u);
  return 1;
}

uint32_t birc_cards_parse(const unsigned char *data, size_t n, const char *base,
                          char **out, size_t *out_n) {
  char *doc;
  char title[BIRC_MF_MAX_TITLE * 4u + 8u];
  char desc[BIRC_MF_MAX_DESC * 4u + 8u];
  char image[BIRC_MF_MAX_IMAGE + 8u];
  char og_title[4096], og_desc[4096], og_image[4096], plain_desc[4096];
  unsigned metas = 0;
  const char *p;
  size_t i;
  int utf8 = 1;
  title[0] = desc[0] = image[0] = 0;
  og_title[0] = og_desc[0] = og_image[0] = plain_desc[0] = 0;
  if (!data)
    return 1;
  for (i = 0; i < n; i++) {
    if ((data[i] & 0xc0) == 0x80)
      continue;
    if (data[i] < 0x80)
      continue;
    if ((data[i] & 0xe0) == 0xc0 && i + 1 < n && (data[i + 1] & 0xc0) == 0x80)
      continue;
    if ((data[i] & 0xf0) == 0xe0 && i + 2 < n && (data[i + 1] & 0xc0) == 0x80
        && (data[i + 2] & 0xc0) == 0x80)
      continue;
    if ((data[i] & 0xf8) == 0xf0 && i + 3 < n && (data[i + 1] & 0xc0) == 0x80
        && (data[i + 2] & 0xc0) == 0x80 && (data[i + 3] & 0xc0) == 0x80)
      continue;
    utf8 = 0;
    break;
  }
  doc = (char *)malloc(n * 4u + 1u);
  if (!doc)
    return 1;
  if (utf8) {
    memcpy(doc, data, n);
    doc[n] = 0;
  } else {
    size_t o = 0;
    for (i = 0; i < n; i++) {
      unsigned char c = data[i];
      if (c < 0x80)
        doc[o++] = (char)c;
      else {
        doc[o++] = (char)(0xc0 | (c >> 6));
        doc[o++] = (char)(0x80 | (c & 0x3f));
      }
    }
    doc[o] = 0;
  }
  p = doc;
  while ((p = strcasestr(p, "<meta")) && metas < BIRC_MF_MAX_META) {
    const char *end = strchr(p, '>');
    char tag[BIRC_MF_MAX_TAG + 8u];
    char key[80], content[4096];
    size_t tlen;
    if (!end)
      break;
    tlen = (size_t)(end + 1 - p);
    if (tlen > BIRC_MF_MAX_TAG) {
      p = end + 1;
      continue;
    }
    memcpy(tag, p, tlen);
    tag[tlen] = 0;
    metas++;
    key[0] = content[0] = 0;
    if (!birc_mf_attr(tag, "property", key, sizeof key))
      (void)birc_mf_attr(tag, "name", key, sizeof key);
    (void)birc_mf_attr(tag, "content", content, sizeof content);
    birc_mf_lower(key);
    if (strcmp(key, "og:title") == 0 && !og_title[0])
      memcpy(og_title, content, strlen(content) + 1u);
    else if (strcmp(key, "og:description") == 0 && !og_desc[0])
      memcpy(og_desc, content, strlen(content) + 1u);
    else if (strcmp(key, "og:image") == 0 && !og_image[0])
      memcpy(og_image, content, strlen(content) + 1u);
    else if (strcmp(key, "description") == 0 && !og_desc[0] && !plain_desc[0])
      memcpy(plain_desc, content, strlen(content) + 1u);
    p = end + 1;
  }
  if (!og_title[0]) {
    const char *t = strcasestr(doc, "<title");
    if (t) {
      const char *gt = strchr(t, '>');
      const char *end = gt ? strcasestr(gt, "</title") : NULL;
      if (gt && end && (size_t)(end - (gt + 1)) <= 512u) {
        char raw[513];
        size_t tlen = (size_t)(end - (gt + 1));
        memcpy(raw, gt + 1, tlen);
        raw[tlen] = 0;
        memcpy(og_title, raw, tlen + 1u);
      }
    }
  }
  birc_mf_clean(og_title, BIRC_MF_MAX_TITLE, title, sizeof title);
  birc_mf_clean(og_desc[0] ? og_desc : plain_desc, BIRC_MF_MAX_DESC, desc, sizeof desc);
  if (strlen(og_image) > BIRC_MF_MAX_IMAGE)
    image[0] = 0;
  else
    (void)birc_mf_card_image(og_image, base ? base : "https://local.invalid/", image, sizeof image);
  {
    size_t need = strlen(title) + strlen(desc) + strlen(image) + 4u;
    char *text = (char *)malloc(need);
    if (!text) {
      free(doc);
      return 1;
    }
    snprintf(text, need, "%s\n%s\n%s\n", title, desc, image);
    *out = text;
    *out_n = strlen(text);
  }
  free(doc);
  return 0;
}

static uint32_t birc_mf_remote(int cards, const char *url, char **out, size_t *out_n) {
  BircMfUrl parts;
  unsigned char *body = NULL;
  size_t body_n = 0;
  char final[BIRC_MF_MAX_URL + 1u];
  int parent = -1, dirfd = -1;
  unsigned char *cached = NULL;
  size_t cached_n = 0;
  char name[80];
  uint32_t rc = 1;
  uint64_t deadline = birc_mf_now_ms() + BIRC_MF_DEADLINE_MS;
  const char *base = url;
  if (!birc_media_parse_url(url, cards, &parts))
    return 2;
  if (birc_mf_cache_root(0, &parent) == 0) {
    if (cards) {
      if (birc_mf_open_cards(parent, 0, &dirfd) == 0) {
        birc_mf_sha_name(url, ".card", name, sizeof name);
        if (birc_mf_read_cached(dirfd, name, BIRC_MF_MAX_HTML + BIRC_MF_MAX_BASE + 1u,
                                &cached, &cached_n)) {
          const unsigned char *sep = memchr(cached, '\n', cached_n);
          if (sep && (size_t)(sep - cached) <= BIRC_MF_MAX_BASE) {
            char head[BIRC_MF_MAX_URL + 1u];
            size_t hlen = (size_t)(sep - cached);
            if (hlen < sizeof head) {
              memcpy(head, cached, hlen);
              head[hlen] = 0;
              if (birc_media_parse_url(head, 1, &parts)) {
                rc = birc_cards_parse(sep + 1, cached_n - hlen - 1u, head, out, out_n);
                free(cached);
                (void)close(dirfd);
                (void)close(parent);
                return rc;
              }
            }
          }
          rc = birc_cards_parse(cached, cached_n, url, out, out_n);
          free(cached);
          (void)close(dirfd);
          (void)close(parent);
          return rc;
        }
        (void)close(dirfd);
      }
    } else {
      birc_mf_sha_name(url, ".img", name, sizeof name);
      if (birc_mf_read_cached(parent, name, BIRC_MF_MAX_DOWNLOAD, &cached, &cached_n)) {
        rc = birc_media_encode(cached, cached_n, out, out_n);
        free(cached);
        (void)close(parent);
        return rc;
      }
    }
    (void)close(parent);
    parent = -1;
  }
  if (!birc_mf_fetch(url, cards, deadline, &body, &body_n, final, sizeof final))
    return 1;
  if (cards)
    rc = birc_cards_parse(body, body_n, final[0] ? final : url, out, out_n);
  else
    rc = birc_media_encode(body, body_n, out, out_n);
  if (rc == 0 && birc_mf_cache_root(1, &parent) == 0) {
    birc_mf_cache_write(parent, cards, url, body, body_n, final[0] ? final : url);
    (void)close(parent);
  }
  free(body);
  (void)base;
  return rc;
}

uint32_t birc_media_run(int local, const char *source, char **out, size_t *out_n) {
  unsigned char *data;
  size_t n = 0;
  uint32_t rc;
  *out = NULL;
  *out_n = 0;
  if (!source || !source[0])
    return 2;
  if (local) {
    data = birc_mf_read_regular(source, BIRC_MF_MAX_LOCAL, &n);
    if (!data)
      return 1;
    rc = birc_media_encode(data, n, out, out_n);
    free(data);
    return rc;
  }
  return birc_mf_remote(0, source, out, out_n);
}

uint32_t birc_cards_run(int local, const char *source, char **out, size_t *out_n) {
  unsigned char *data;
  size_t n = 0;
  uint32_t rc;
  *out = NULL;
  *out_n = 0;
  if (!source || !source[0])
    return 2;
  if (local) {
    data = birc_mf_read_regular(source, BIRC_MF_MAX_HTML, &n);
    if (!data)
      return 1;
    rc = birc_cards_parse(data, n, "https://local.invalid/", out, out_n);
    free(data);
    return rc;
  }
  return birc_mf_remote(1, source, out, out_n);
}

#ifndef BIRC_MEDIA_CORE_ONLY
#ifndef CID_MEDIA_LOAD
#define CID_MEDIA_LOAD CID(media_load)
#endif
#ifndef CID_CARDS_LOAD
#define CID_CARDS_LOAD CID(cards_load)
#endif

typedef struct {
  uint32_t local;
  char *source;
  uint32_t code;
  char *out;
  size_t out_n;
  int cards;
} BircMfReq;

static void media_load_call(IoWork *w) {
  BircMfReq *req = (BircMfReq *)w->data;
  if (req->cards)
    req->code = birc_cards_run((int)req->local, req->source, &req->out, &req->out_n);
  else
    req->code = birc_media_run((int)req->local, req->source, &req->out, &req->out_n);
}

static Term media_load_pack(Env e, IoWork *w) {
  BircMfReq *req = (BircMfReq *)w->data;
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
    free(req->source);
    free(req->out);
    free(req);
  }
  w->data = NULL;
  return packed;
}

#if CID_MEDIA_LOAD
Term media_load_run(Env e, Term *f, IoWork *w) {
  uint64_t n = 0;
  BircMfReq *req = (BircMfReq *)calloc(1, sizeof *req);
  w->data = (char *)req;
  if (!req) {
    term_sink(e, f[0]);
    term_sink(e, f[1]);
    return media_load_pack(e, w);
  }
  req->local = (uint32_t)f[0];
  term_sink(e, f[0]);
  req->source = io_cstr(e, f[1], &n);
  req->cards = 0;
  if (!req->source || io_nul(req->source, n)) {
    req->code = 2;
    return media_load_pack(e, w);
  }
  return io_work(w, media_load_call, media_load_pack);
}

static void __attribute__((constructor)) media_load_use(void) {
  io_eff(CID_MEDIA_LOAD, media_load_run);
}
#endif

#if CID_CARDS_LOAD
Term cards_load_run(Env e, Term *f, IoWork *w) {
  uint64_t n = 0;
  BircMfReq *req = (BircMfReq *)calloc(1, sizeof *req);
  w->data = (char *)req;
  if (!req) {
    term_sink(e, f[0]);
    term_sink(e, f[1]);
    return media_load_pack(e, w);
  }
  req->local = (uint32_t)f[0];
  term_sink(e, f[0]);
  req->source = io_cstr(e, f[1], &n);
  req->cards = 1;
  if (!req->source || io_nul(req->source, n)) {
    req->code = 2;
    return media_load_pack(e, w);
  }
  return io_work(w, media_load_call, media_load_pack);
}

static void __attribute__((constructor)) cards_load_use(void) {
  io_eff(CID_CARDS_LOAD, cards_load_run);
}
#endif
#endif /* BIRC_MEDIA_CORE_ONLY */
#endif /* BIRC_MEDIA_FETCH_FFI_C */
