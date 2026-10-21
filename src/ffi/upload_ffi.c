/* SPDX-License-Identifier: Apache-2.0
 * Confirmed local upload to 0x0.st. Bend owns consent and URL policy.
 * This effect admits one regular file and posts HTTP/1.1 over OpenSSL. */
#ifndef BIRC_UPLOAD_FFI_C
#define BIRC_UPLOAD_FFI_C

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
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <openssl/bio.h>
#include <openssl/err.h>
#include <openssl/pem.h>
#include <openssl/ssl.h>
#include <openssl/x509v3.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#if defined(__APPLE__)
int getentropy(void *buffer, size_t size);
#else
#include <sys/random.h>
#endif

#define BIRC_UP_HOST "0x0.st"
#define BIRC_UP_MAX_FILE (32u * 1024u * 1024u)
#define BIRC_UP_MAX_RESPONSE 1024u
#define BIRC_UP_CHUNK 65536u
#define BIRC_UP_DEADLINE_MS 30000u
#define BIRC_UP_UA "birc/0.1 (IRC client; confirmed local file upload)"

enum {
  BIRC_UP_USAGE = 1,
  BIRC_UP_SOURCE = 2,
  BIRC_UP_CHANGED = 3,
  BIRC_UP_IO = 4,
  BIRC_UP_REPLY = 5,
  BIRC_UP_TIME = 6
};

typedef struct {
  uint64_t size;
  uint64_t mtime_ns;
  uint64_t ctime_ns;
} BircUpStamp;

static uint64_t birc_up_now_ms(void) {
  struct timespec ts;
  if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
    return 0;
  return (uint64_t)ts.tv_sec * 1000ull + (uint64_t)ts.tv_nsec / 1000000ull;
}

static uint64_t birc_up_ns(const struct timespec *ts) {
  return (uint64_t)ts->tv_sec * 1000000000ull + (uint64_t)ts->tv_nsec;
}

static BircUpStamp birc_up_stamp(const struct stat *info) {
  BircUpStamp st;
  st.size = (uint64_t)info->st_size;
#if defined(__APPLE__)
  st.mtime_ns = birc_up_ns(&info->st_mtimespec);
  st.ctime_ns = birc_up_ns(&info->st_ctimespec);
#else
  st.mtime_ns = birc_up_ns(&info->st_mtim);
  st.ctime_ns = birc_up_ns(&info->st_ctim);
#endif
  return st;
}

static int birc_up_stamp_eq(BircUpStamp a, BircUpStamp b) {
  return a.size == b.size && a.mtime_ns == b.mtime_ns && a.ctime_ns == b.ctime_ns;
}

static int birc_up_poll(int fd, short events, uint64_t deadline) {
  struct pollfd p;
  uint64_t now = birc_up_now_ms();
  int ms;
  if (now >= deadline)
    return -1;
  p.fd = fd;
  p.events = events;
  p.revents = 0;
  ms = (int)(deadline - now);
  if (ms < 1)
    ms = 1;
  return poll(&p, 1, ms) == 1 && (p.revents & events) ? 0 : -1;
}

static int birc_up_public_v4(uint32_t a) {
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

static int birc_up_public_address(const char *value) {
  struct in_addr a4;
  struct in6_addr a6;
  if (!value || !value[0])
    return 0;
  if (strchr(value, ':')) {
    if (inet_pton(AF_INET6, value, &a6) != 1)
      return 0;
    if (IN6_IS_ADDR_V4MAPPED(&a6)) {
      memcpy(&a4, a6.s6_addr + 12, 4);
      return birc_up_public_v4(ntohl(a4.s_addr));
    }
    if (IN6_IS_ADDR_MULTICAST(&a6) || IN6_IS_ADDR_LOOPBACK(&a6) || IN6_IS_ADDR_LINKLOCAL(&a6)
        || IN6_IS_ADDR_SITELOCAL(&a6) || IN6_IS_ADDR_UNSPECIFIED(&a6))
      return 0;
    if ((a6.s6_addr[0] & 0xe0) != 0x20)
      return 0;
    return 1;
  }
  if (inet_pton(AF_INET, value, &a4) != 1)
    return 0;
  return birc_up_public_v4(ntohl(a4.s_addr));
}

static int birc_up_no_password(char *bytes, int size, int writing, void *data) {
  (void)bytes;
  (void)size;
  (void)writing;
  (void)data;
  return 0;
}

static int birc_up_ca_file(SSL_CTX *ctx, const char *path) {
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
  items = PEM_X509_INFO_read_bio(bio, NULL, birc_up_no_password, NULL);
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

static int birc_up_trust(SSL_CTX *ctx) {
  const char *file = getenv("SSL_CERT_FILE");
  const char *directory = getenv("SSL_CERT_DIR");
  if (!ctx)
    return 0;
  if (file || directory) {
    if ((file && file[0] == 0) || (directory && directory[0] == 0))
      return 0;
    if (file && !birc_up_ca_file(ctx, file))
      return 0;
    return directory == NULL || SSL_CTX_load_verify_locations(ctx, NULL, directory) == 1;
  }
  return SSL_CTX_set_default_verify_paths(ctx) == 1;
}

static int birc_up_connect(struct addrinfo *list, uint64_t deadline) {
  const struct addrinfo *it;
  for (it = list; it; it = it->ai_next) {
    int fd, flags;
    if (it->ai_addr->sa_family == AF_INET) {
      char ip[INET_ADDRSTRLEN];
      const struct sockaddr_in *sa = (const struct sockaddr_in *)it->ai_addr;
      inet_ntop(AF_INET, &sa->sin_addr, ip, sizeof ip);
      if (!birc_up_public_address(ip))
        return -1;
    } else if (it->ai_addr->sa_family == AF_INET6) {
      char ip[INET6_ADDRSTRLEN];
      const struct sockaddr_in6 *sa = (const struct sockaddr_in6 *)it->ai_addr;
      inet_ntop(AF_INET6, &sa->sin6_addr, ip, sizeof ip);
      if (!birc_up_public_address(ip))
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
    if (birc_up_poll(fd, POLLOUT, deadline) == 0) {
      int err = 0;
      socklen_t n = sizeof err;
      if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &n) == 0 && err == 0)
        return fd;
    }
    (void)close(fd);
  }
  return -1;
}

static int birc_up_ssl_wait(SSL *ssl, int fd, int why, uint64_t deadline) {
  (void)ssl;
  if (why == SSL_ERROR_WANT_READ)
    return birc_up_poll(fd, POLLIN, deadline);
  if (why == SSL_ERROR_WANT_WRITE)
    return birc_up_poll(fd, POLLOUT, deadline);
  return -1;
}

static int birc_up_write(int fd, SSL *ssl, const void *buf, size_t n, uint64_t deadline) {
  const char *p = (const char *)buf;
  size_t sent = 0;
  while (sent < n) {
    int got;
    ERR_clear_error();
    got = SSL_write(ssl, p + sent, (int)(n - sent > 65536u ? 65536u : n - sent));
    if (got > 0) {
      sent += (size_t)got;
      continue;
    }
    if (birc_up_ssl_wait(ssl, fd, SSL_get_error(ssl, got), deadline) != 0)
      return -1;
  }
  return 0;
}

static ssize_t birc_up_read(int fd, SSL *ssl, void *buf, size_t n, uint64_t deadline) {
  for (;;) {
    int got;
    ERR_clear_error();
    got = SSL_read(ssl, buf, (int)n);
    if (got > 0)
      return got;
    if (got == 0)
      return 0;
    if (birc_up_ssl_wait(ssl, fd, SSL_get_error(ssl, got), deadline) != 0)
      return -1;
  }
}

static int birc_up_header(const char *headers, const char *name, char *out, size_t n) {
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

int birc_upload_checked_url(const char *body, size_t n, char *out, size_t out_n) {
  static const char origin[] = "https://0x0.st/";
  const char *path;
  size_t origin_n = sizeof origin - 1u;
  size_t i, start, part;
  if (!body || !out || out_n < 16u)
    return 0;
  if (n >= 2u && body[n - 2] == '\r' && body[n - 1] == '\n')
    n -= 2u;
  else if (n >= 1u && body[n - 1] == '\n')
    n -= 1u;
  if (n == 0 || n > BIRC_UP_MAX_RESPONSE || n >= out_n)
    return 0;
  for (i = 0; i < n; i++) {
    unsigned char c = (unsigned char)body[i];
    if (c < 0x20 || c > 0x7e)
      return 0;
  }
  memcpy(out, body, n);
  out[n] = 0;
  if (n <= origin_n || strncmp(out, origin, origin_n) != 0)
    return 0;
  path = out + origin_n;
  if (path[0] == 0)
    return 0;
  start = 0;
  for (i = 0;; i++) {
    if (path[i] && path[i] != '/') {
      unsigned char c = (unsigned char)path[i];
      if (!(isalnum(c) || c == '.' || c == '_' || c == '~' || c == '-'))
        return 0;
      continue;
    }
    part = i - start;
    if (part == 0 || (part == 1 && path[start] == '.')
        || (part == 2 && path[start] == '.' && path[start + 1] == '.'))
      return 0;
    if (!path[i])
      break;
    start = i + 1;
  }
  return 1;
}

static void birc_up_extension(const char *path, char *out, size_t n) {
  const char *base, *dot;
  size_t i;
  memcpy(out, ".bin", 5);
  if (!path || n < 18u)
    return;
  base = strrchr(path, '/');
  base = base ? base + 1 : path;
  dot = strrchr(base, '.');
  if (!dot || dot == base)
    return;
  if (strlen(dot) < 2u || strlen(dot) > 17u)
    return;
  for (i = 1; dot[i]; i++) {
    if (!isalnum((unsigned char)dot[i]))
      return;
  }
  out[0] = '.';
  for (i = 1; dot[i]; i++)
    out[i] = (char)tolower((unsigned char)dot[i]);
  out[i] = 0;
}

static int birc_up_boundary(char *out, size_t n) {
  unsigned char raw[16];
  static const char hex[] = "0123456789abcdef";
  size_t i;
  if (n < 38u)
    return 0;
#if defined(__APPLE__)
  if (getentropy(raw, sizeof raw) != 0)
    return 0;
#else
  if (getentropy(raw, sizeof raw) != 0)
    return 0;
#endif
  memcpy(out, "birc-", 5);
  for (i = 0; i < sizeof raw; i++) {
    out[5 + i * 2u] = hex[raw[i] >> 4];
    out[6 + i * 2u] = hex[raw[i] & 15u];
  }
  out[37] = 0;
  return 1;
}

static int birc_up_open(const char *path, BircUpStamp *stamp) {
  struct stat info;
  int fd;
  if (!path || !path[0] || !stamp)
    return -1;
  fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0)
    return -1;
  if (fstat(fd, &info) != 0 || !S_ISREG(info.st_mode)
      || info.st_size <= 0 || (uintmax_t)info.st_size > (uintmax_t)BIRC_UP_MAX_FILE) {
    (void)close(fd);
    return -1;
  }
  *stamp = birc_up_stamp(&info);
  return fd;
}

uint32_t birc_upload_run(const char *path, char **url, uint32_t *http_status) {
  BircUpStamp stamp, now;
  struct addrinfo hints;
  struct addrinfo *list = NULL;
  SSL_CTX *ctx = NULL;
  SSL *ssl = NULL;
  uint64_t deadline;
  int fd = -1, sock = -1, status = 0;
  uint32_t code = BIRC_UP_IO;
  char boundary[40];
  char ext[20];
  char prefix[256];
  char footer[48];
  char hdr[8192];
  char req[512];
  char encoding[64];
  char clen[32];
  char reply[BIRC_UP_MAX_RESPONSE + 8u];
  char checked[BIRC_UP_MAX_RESPONSE + 8u];
  size_t prefix_n, footer_n, hdr_n = 0, reply_n = 0, left;
  *url = NULL;
  if (http_status)
    *http_status = 0;
  if (!path || !path[0])
    return BIRC_UP_USAGE;
  deadline = birc_up_now_ms() + BIRC_UP_DEADLINE_MS;
  fd = birc_up_open(path, &stamp);
  if (fd < 0)
    return BIRC_UP_SOURCE;
  if (!birc_up_boundary(boundary, sizeof boundary)) {
    code = BIRC_UP_IO;
    goto done;
  }
  birc_up_extension(path, ext, sizeof ext);
  prefix_n = (size_t)snprintf(prefix, sizeof prefix,
      "--%s\r\nContent-Disposition: form-data; name=\"secret\"\r\n\r\n\r\n"
      "--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"upload%s\"\r\n"
      "Content-Type: application/octet-stream\r\n\r\n",
      boundary, boundary, ext);
  footer_n = (size_t)snprintf(footer, sizeof footer, "\r\n--%s--\r\n", boundary);
  if (prefix_n >= sizeof prefix || footer_n >= sizeof footer) {
    code = BIRC_UP_IO;
    goto done;
  }
  memset(&hints, 0, sizeof hints);
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_family = AF_UNSPEC;
  if (birc_up_now_ms() >= deadline) {
    code = BIRC_UP_TIME;
    goto done;
  }
  if (getaddrinfo(BIRC_UP_HOST, "443", &hints, &list) != 0 || !list) {
    code = BIRC_UP_IO;
    goto done;
  }
  sock = birc_up_connect(list, deadline);
  freeaddrinfo(list);
  list = NULL;
  if (sock < 0) {
    code = BIRC_UP_IO;
    goto done;
  }
  ctx = SSL_CTX_new(TLS_client_method());
  if (!ctx)
    goto done;
  SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);
  if (SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION) != 1 || !birc_up_trust(ctx))
    goto done;
  (void)SSL_CTX_set_options(ctx, SSL_OP_NO_RENEGOTIATION);
  ssl = SSL_new(ctx);
  if (!ssl || SSL_set1_host(ssl, BIRC_UP_HOST) != 1 || SSL_set_tlsext_host_name(ssl, BIRC_UP_HOST) != 1
      || SSL_set_fd(ssl, sock) != 1)
    goto done;
  SSL_set_hostflags(ssl, X509_CHECK_FLAG_NEVER_CHECK_SUBJECT | X509_CHECK_FLAG_NO_PARTIAL_WILDCARDS);
  SSL_set_connect_state(ssl);
  for (;;) {
    int rc, why;
    ERR_clear_error();
    rc = SSL_connect(ssl);
    if (rc == 1 && SSL_get_verify_result(ssl) == X509_V_OK)
      break;
    why = SSL_get_error(ssl, rc);
    if (birc_up_ssl_wait(ssl, sock, why, deadline) != 0) {
      code = BIRC_UP_TIME;
      goto done;
    }
  }
  if (snprintf(req, sizeof req,
               "POST / HTTP/1.1\r\nHost: %s\r\nUser-Agent: %s\r\n"
               "Content-Type: multipart/form-data; boundary=%s\r\n"
               "Content-Length: %llu\r\nAccept: text/plain\r\n"
               "Accept-Encoding: identity\r\nConnection: close\r\n\r\n",
               BIRC_UP_HOST, BIRC_UP_UA, boundary,
               (unsigned long long)(prefix_n + (size_t)stamp.size + footer_n)) >= (int)sizeof req)
    goto done;
  if (birc_up_write(sock, ssl, req, strlen(req), deadline) != 0
      || birc_up_write(sock, ssl, prefix, prefix_n, deadline) != 0) {
    code = BIRC_UP_IO;
    goto done;
  }
  left = (size_t)stamp.size;
  while (left) {
    unsigned char chunk[BIRC_UP_CHUNK];
    size_t want = left < sizeof chunk ? left : sizeof chunk;
    ssize_t got;
    if (birc_up_now_ms() >= deadline) {
      code = BIRC_UP_TIME;
      goto done;
    }
    got = read(fd, chunk, want);
    if (got <= 0) {
      code = BIRC_UP_CHANGED;
      goto done;
    }
    if (birc_up_write(sock, ssl, chunk, (size_t)got, deadline) != 0) {
      code = BIRC_UP_IO;
      goto done;
    }
    left -= (size_t)got;
  }
  {
    unsigned char extra;
    struct stat info;
    if (read(fd, &extra, 1) > 0) {
      code = BIRC_UP_CHANGED;
      goto done;
    }
    if (fstat(fd, &info) != 0) {
      code = BIRC_UP_CHANGED;
      goto done;
    }
    now = birc_up_stamp(&info);
    if (!birc_up_stamp_eq(stamp, now)) {
      code = BIRC_UP_CHANGED;
      goto done;
    }
  }
  if (birc_up_write(sock, ssl, footer, footer_n, deadline) != 0) {
    code = BIRC_UP_IO;
    goto done;
  }
  while (hdr_n + 1u < sizeof hdr) {
    ssize_t got = birc_up_read(sock, ssl, hdr + hdr_n, sizeof hdr - 1u - hdr_n, deadline);
    if (got < 0) {
      code = BIRC_UP_TIME;
      goto done;
    }
    if (got == 0)
      break;
    hdr_n += (size_t)got;
    hdr[hdr_n] = 0;
    if (strstr(hdr, "\r\n\r\n"))
      break;
  }
  {
    char *sep = strstr(hdr, "\r\n\r\n");
    char *line_end;
    size_t preface;
    if (!sep || sscanf(hdr, "HTTP/%*s %d", &status) != 1) {
      code = BIRC_UP_REPLY;
      goto done;
    }
    line_end = strstr(hdr, "\r\n");
    if (!line_end) {
      code = BIRC_UP_REPLY;
      goto done;
    }
    preface = (size_t)(sep + 4 - hdr);
    if (status != 200) {
      code = BIRC_UP_REPLY;
      if (http_status && status >= 100 && status <= 599)
        *http_status = (uint32_t)status;
      goto done;
    }
    encoding[0] = 0;
    if (birc_up_header(line_end + 2, "Content-Encoding", encoding, sizeof encoding)
        && strcasecmp(encoding, "identity") != 0) {
      code = BIRC_UP_REPLY;
      goto done;
    }
    clen[0] = 0;
    if (birc_up_header(line_end + 2, "Content-Length", clen, sizeof clen)) {
      size_t i;
      char *end = NULL;
      unsigned long want;
      if (!clen[0] || strlen(clen) > 10u)
        goto reply_fail;
      for (i = 0; clen[i]; i++) {
        if (!isdigit((unsigned char)clen[i]))
          goto reply_fail;
      }
      errno = 0;
      want = strtoul(clen, &end, 10);
      if (errno || !end || *end || want > BIRC_UP_MAX_RESPONSE)
        goto reply_fail;
    }
    if (hdr_n > preface) {
      reply_n = hdr_n - preface;
      if (reply_n > BIRC_UP_MAX_RESPONSE + 1u)
        goto reply_fail;
      memcpy(reply, hdr + preface, reply_n);
    }
    while (reply_n <= BIRC_UP_MAX_RESPONSE) {
      ssize_t got = birc_up_read(sock, ssl, reply + reply_n, BIRC_UP_MAX_RESPONSE + 1u - reply_n, deadline);
      if (got < 0) {
        code = BIRC_UP_TIME;
        goto done;
      }
      if (got == 0)
        break;
      reply_n += (size_t)got;
    }
    if (reply_n > BIRC_UP_MAX_RESPONSE)
      goto reply_fail;
    if (clen[0] && reply_n != strtoul(clen, NULL, 10))
      goto reply_fail;
    if (!birc_upload_checked_url(reply, reply_n, checked, sizeof checked))
      goto reply_fail;
    *url = (char *)malloc(strlen(checked) + 1u);
    if (!*url) {
      code = BIRC_UP_IO;
      goto done;
    }
    memcpy(*url, checked, strlen(checked) + 1u);
    code = 0;
    goto done;
  reply_fail:
    code = BIRC_UP_REPLY;
    goto done;
  }
done:
  if (ssl)
    SSL_free(ssl);
  if (ctx)
    SSL_CTX_free(ctx);
  if (sock >= 0)
    (void)close(sock);
  if (fd >= 0)
    (void)close(fd);
  ERR_clear_error();
  if (birc_up_now_ms() >= deadline && code != 0 && code != BIRC_UP_SOURCE && code != BIRC_UP_USAGE)
    return BIRC_UP_TIME;
  return code;
}

#ifndef BIRC_UPLOAD_CORE_ONLY
#ifndef CID_UPLOAD_PUT
#define CID_UPLOAD_PUT CID(upload_put)
#endif

typedef struct {
  char *path;
  uint32_t code;
  uint32_t http;
  char *url;
} BircUpReq;

static void upload_put_call(IoWork *w) {
  BircUpReq *req = (BircUpReq *)w->data;
  req->code = birc_upload_run(req->path, &req->url, &req->http);
}

static Term upload_put_pack(Env e, IoWork *w) {
  BircUpReq *req = (BircUpReq *)w->data;
  Term packed;
  const char *data = "";
  uint64_t len = 0;
  uint32_t code = BIRC_UP_IO;
  uint32_t http = 0;
  if (req) {
    code = req->code;
    http = req->http;
    if (req->url) {
      data = req->url;
      len = (uint64_t)strlen(req->url);
    }
  }
  packed = io_tup(e, (Term)code, io_tup(e, io_str(e, data, len), (Term)http));
  if (req) {
    free(req->path);
    free(req->url);
    free(req);
  }
  w->data = NULL;
  return packed;
}

#if CID_UPLOAD_PUT
Term upload_put_run(Env e, Term *f, IoWork *w) {
  uint64_t n = 0;
  BircUpReq *req = (BircUpReq *)calloc(1, sizeof *req);
  w->data = (char *)req;
  if (!req) {
    term_sink(e, f[0]);
    return upload_put_pack(e, w);
  }
  req->path = io_cstr(e, f[0], &n);
  if (!req->path || io_nul(req->path, n)) {
    req->code = BIRC_UP_USAGE;
    return upload_put_pack(e, w);
  }
  return io_work(w, upload_put_call, upload_put_pack);
}

static void __attribute__((constructor)) upload_put_use(void) {
  io_eff(CID_UPLOAD_PUT, upload_put_run);
}
#endif
#endif /* BIRC_UPLOAD_CORE_ONLY */
#endif /* BIRC_UPLOAD_FFI_C */
