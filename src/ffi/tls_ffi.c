/* SPDX-License-Identifier: Apache-2.0
 * Verified OpenSSL transport. Only the pinned Bend IO loop calls SSL APIs:
 * effects and io_wait_on callbacks are serial (comp.ts io_loop/io_wait).
 * No IRC policy, TLS registry, helper thread, or insecure fallback lives here. */
#ifndef BIRC_TLS_FFI_C
#define BIRC_TLS_FFI_C
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <openssl/err.h>
#include <openssl/pem.h>
#include <openssl/ssl.h>
#include <openssl/x509v3.h>
#include <poll.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef BIRC_TLS_ALLOC
#define BIRC_TLS_ALLOC calloc
#endif

typedef struct { uint32_t code; const char *stage; } BircTlsError;
typedef struct BircTlsRead BircTlsRead;
typedef struct BircTlsWrite BircTlsWrite;
typedef struct {
  SSL_CTX *ctx;
  SSL *ssl;
  int fd;
  uint32_t refs;
  int verified;
  int stopped;
  BircTlsRead *reader;
  BircTlsWrite *writer;
} BircTlsState;
typedef struct { BircTlsState *state; } BircTls;
struct BircTlsRead {
  BircTls *handle;
  void *work;
  size_t size;
  size_t got;
  /* Same burst coalescing as the plaintext clamp; one heap read at a time. */
  unsigned char bytes[65536];
};
struct BircTlsWrite {
  BircTls *handle;
  char *bytes;
  size_t size;
  size_t sent;
  uint64_t deadline;
  short want;
  int finished;
  BircTlsError error;
};

static BircTlsError birc_tls_error(uint32_t code, const char *stage) {
  BircTlsError error = {code, stage};
  return error;
}
static void birc_tls_stop(BircTlsState *state) {
  if (state != NULL && !state->stopped) {
    state->stopped = 1;
    (void)shutdown(state->fd, SHUT_RDWR);
  }
}
static void birc_tls_close(BircTls *handle) {
  if (handle != NULL) {
    BircTlsState *state = handle->state;
    free(handle);
    if (state != NULL && --state->refs == 0u) {
      SSL_free(state->ssl);
      SSL_CTX_free(state->ctx);
      (void)close(state->fd);
      free(state);
    }
  }
}
static BircTls *birc_tls_dup(BircTls *handle, BircTlsError *error) {
  BircTls *copy;
  if (error == NULL) return NULL;
  *error = birc_tls_error((uint32_t)EINVAL, "tls-config");
  if (handle == NULL || handle->state == NULL) return NULL;
  if (handle->state->refs == UINT32_MAX) {
    *error = birc_tls_error((uint32_t)EOVERFLOW, "tls-config");
    return NULL;
  }
  copy = (BircTls *)BIRC_TLS_ALLOC(1u, sizeof *copy);
  if (copy == NULL) {
    *error = birc_tls_error((uint32_t)ENOMEM, "tls-config");
    return NULL;
  }
  copy->state = handle->state;
  copy->state->refs++;
  *error = birc_tls_error(0u, NULL);
  return copy;
}
/* Reject host-list/suffix semantics and control bytes before passing an exact
 * DNS name to OpenSSL. IP literals use IP SAN matching and do not send SNI. */
static int birc_tls_hostname(const char *host, size_t size, int *ip) {
  unsigned char address[16];
  size_t label = 0u;
  if (host == NULL || ip == NULL || size == 0u || size > 254u ||
      strlen(host) != size) return 0;
  *ip = inet_pton(AF_INET, host, address) == 1 ||
        inet_pton(AF_INET6, host, address) == 1;
  if (*ip) return 1;
  /* One DNS root dot is valid; a second still leaves an empty label. */
  if (size > 1u && host[size - 1u] == '.') size--;
  if (size > 253u) return 0;
  for (size_t i = 0u; i < size; i++) {
    unsigned char c = (unsigned char)host[i];
    if (c == '.') {
      if (label == 0u || label > 63u) return 0;
      label = 0u;
    } else if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
               (c >= '0' && c <= '9') || c == '-') {
      label++;
    } else return 0;
  }
  return label != 0u && label <= 63u;
}
/* CA input cannot prompt for a private-key passphrase. */
static int birc_tls_no_password(char *bytes, int size, int writing, void *data) {
  (void)bytes; (void)size; (void)writing; (void)data;
  return 0;
}
/* Own the opened descriptor before checking its type/size. O_NONBLOCK avoids
 * opening a FIFO synchronously, including after a pathname replacement.
 * Parse at most the initial 8 MiB snapshot with OpenSSL's certificate/CRL
 * loader semantics, retaining AUX trust and library duplicate handling.
 * Regular remote-filesystem calls and CA-directory lookups are not cancellable. */
static int birc_tls_ca_file(SSL_CTX *ctx, const char *path) {
  const size_t cap = 8u * 1024u * 1024u;
  struct stat info;
  unsigned char *bytes = NULL;
  BIO *bio = NULL;
  STACK_OF(X509_INFO) *items = NULL;
  X509_STORE *store;
  size_t size, used = 0u;
  int fd = -1, count = 0, good = 0;
  if (ctx == NULL || path == NULL) return 0;
  store = SSL_CTX_get_cert_store(ctx);
  if (store == NULL) return 0;
  fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
  if (fd < 0 || fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) ||
      info.st_size <= 0 || (uintmax_t)info.st_size > (uintmax_t)cap) goto done;
  size = (size_t)info.st_size;
  bytes = (unsigned char *)BIRC_TLS_ALLOC(size, 1u);
  if (bytes == NULL) goto done;
  while (used < size) {
    size_t want = size - used < 65536u ? size - used : 65536u;
    ssize_t got = read(fd, bytes + used, want);
    /* Errors, including interruption, fail closed; no unbounded retry loop. */
    if (got <= 0) goto done;
    used += (size_t)got;
  }
  if (close(fd) != 0) { fd = -1; goto done; }
  fd = -1;
  bio = BIO_new_mem_buf(bytes, (int)size);
  if (bio == NULL) goto done;
  items = PEM_X509_INFO_read_bio(bio, NULL, birc_tls_no_password, NULL);
  if (items == NULL) goto done;
  for (int i = 0; i < sk_X509_INFO_num(items); i++) {
    X509_INFO *item = sk_X509_INFO_value(items, i);
    if (item == NULL) goto done;
    if (item->x509 != NULL) {
      if (X509_STORE_add_cert(store, item->x509) != 1) goto done;
      count++;
    }
    if (item->crl != NULL) {
      if (X509_STORE_add_crl(store, item->crl) != 1) goto done;
      count++;
    }
  }
  good = count != 0;
done:
  if (fd >= 0) (void)close(fd);
  sk_X509_INFO_pop_free(items, X509_INFO_free);
  BIO_free(bio);
  free(bytes);
  return good;
}
/* Load explicit standard overrides directly. Nix OpenSSL's default-path
 * patch can prefer NIX_SSL_CERT_FILE to SSL_CERT_FILE; that must not silently
 * defeat the package default or an explicitly selected private CA file. */
static int birc_tls_trust(SSL_CTX *ctx) {
  const char *file = getenv("SSL_CERT_FILE");
  const char *directory = getenv("SSL_CERT_DIR");
  if (ctx == NULL) return 0;
  if (file != NULL || directory != NULL) {
    if ((file != NULL && file[0] == '\0') ||
        (directory != NULL && directory[0] == '\0')) return 0;
    if (file != NULL && !birc_tls_ca_file(ctx, file)) return 0;
    return directory == NULL || SSL_CTX_load_verify_locations(ctx, NULL, directory) == 1;
  }
  return SSL_CTX_set_default_verify_paths(ctx) == 1;
}
/* Ownership transfers even when setup fails. Packages supply a CA default. */
static BircTls *birc_tls_new(int fd, const char *host, size_t size,
                             BircTlsError *error) {
  BircTls *handle = NULL;
  BircTlsState *state = NULL;
  char sni[254];
  int ip = 0, flags;
  if (error == NULL) { if (fd >= 0) (void)close(fd); return NULL; }
  *error = birc_tls_error((uint32_t)EINVAL, "tls-config");
  if (fd < 0 || !birc_tls_hostname(host, size, &ip)) goto fail;
  /* SNI excludes the DNS root dot (RFC 6066); verification uses that same
   * exact local name. The original Bend endpoint/credential scope is intact. */
  if (!ip && size > 1u && host[size - 1u] == '.') size--;
  memcpy(sni, host, size);
  sni[size] = '\0';
  {
    unsigned char address[16];
    ip = inet_pton(AF_INET, sni, address) == 1 ||
         inet_pton(AF_INET6, sni, address) == 1;
  }
  flags = fcntl(fd, F_GETFL);
  if (flags < 0 || (flags & O_NONBLOCK) == 0) goto fail;
  handle = (BircTls *)BIRC_TLS_ALLOC(1u, sizeof *handle);
  state = (BircTlsState *)BIRC_TLS_ALLOC(1u, sizeof *state);
  if (handle == NULL || state == NULL) {
    *error = birc_tls_error((uint32_t)ENOMEM, "tls-config");
    goto fail;
  }
  state->fd = fd;
  state->refs = 1u;
  state->ctx = SSL_CTX_new(TLS_client_method());
  if (state->ctx == NULL) goto ssl_fail;
  SSL_CTX_set_verify(state->ctx, SSL_VERIFY_PEER, NULL);
  if (SSL_CTX_set_min_proto_version(state->ctx, TLS1_2_VERSION) != 1 ||
      !birc_tls_trust(state->ctx)) goto ssl_fail;
  (void)SSL_CTX_set_options(state->ctx, SSL_OP_NO_RENEGOTIATION);
  state->ssl = SSL_new(state->ctx);
  if (state->ssl == NULL) goto ssl_fail;
  /* Require SANs; do not accept legacy common-name or partial wildcards. */
  SSL_set_hostflags(state->ssl, X509_CHECK_FLAG_NEVER_CHECK_SUBJECT |
                               X509_CHECK_FLAG_NO_PARTIAL_WILDCARDS);
  if ((ip && X509_VERIFY_PARAM_set1_ip_asc(SSL_get0_param(state->ssl), sni) != 1) ||
      (!ip && (SSL_set1_host(state->ssl, sni) != 1 ||
               SSL_set_tlsext_host_name(state->ssl, sni) != 1)) ||
      SSL_set_fd(state->ssl, fd) != 1) goto ssl_fail;
  (void)SSL_set_mode(state->ssl, SSL_MODE_ENABLE_PARTIAL_WRITE);
  SSL_set_connect_state(state->ssl);
  handle->state = state;
  *error = birc_tls_error(0u, NULL);
  return handle;
ssl_fail:
  *error = birc_tls_error((uint32_t)EIO, "tls-config");
fail:
  if (state != NULL) {
    SSL_free(state->ssl);
    SSL_CTX_free(state->ctx);
  }
  free(state);
  free(handle);
  if (fd >= 0) (void)close(fd);
  ERR_clear_error();
  return NULL;
}
/* SSL_get_error is adjacent to its operation, on the same IO-loop thread,
 * with a cleared error queue. Never return OpenSSL's diagnostic strings. */
static int birc_tls_handshake(BircTls *handle, uint64_t now, uint64_t deadline,
                               short *want, BircTlsError *error) {
  BircTlsState *state;
  int result, why;
  if (error == NULL || want == NULL) return -1;
  *want = 0;
  *error = birc_tls_error((uint32_t)EINVAL, "tls-config");
  if (handle == NULL || handle->state == NULL) return -1;
  state = handle->state;
  if (now >= deadline) {
    *error = birc_tls_error((uint32_t)ETIMEDOUT, "tls-timeout");
    birc_tls_stop(state);
    return -1;
  }
  ERR_clear_error();
  errno = 0;
  result = SSL_connect(state->ssl);
  why = result == 1 ? SSL_ERROR_NONE : SSL_get_error(state->ssl, result);
  if (result == 1 && SSL_get_verify_result(state->ssl) == X509_V_OK) {
    state->verified = 1;
    *error = birc_tls_error(0u, NULL);
    return 1;
  }
  if (why == SSL_ERROR_WANT_READ || why == SSL_ERROR_WANT_WRITE) {
    *want = why == SSL_ERROR_WANT_READ ? POLLIN : POLLOUT;
    *error = birc_tls_error(0u, NULL);
    return 0;
  }
  *error = SSL_get_verify_result(state->ssl) != X509_V_OK
      ? birc_tls_error((uint32_t)EACCES, "tls-verify")
      : birc_tls_error((uint32_t)EPROTO, "tls-handshake");
  birc_tls_stop(state);
  return -1;
}
static BircTlsWrite *birc_tls_write_new(BircTls *handle, char *bytes,
                                        size_t size, uint64_t deadline,
                                        BircTlsError *error) {
  BircTlsWrite *out;
  if (error == NULL) { free(bytes); return NULL; }
  *error = birc_tls_error((uint32_t)EINVAL, "tls-write");
  if (handle == NULL || handle->state == NULL || bytes == NULL ||
      !handle->state->verified || handle->state->stopped) { free(bytes); return NULL; }
  if (handle->state->writer != NULL) {
    *error = birc_tls_error((uint32_t)EBUSY, "tls-write");
    free(bytes);
    return NULL;
  }
  out = (BircTlsWrite *)BIRC_TLS_ALLOC(1u, sizeof *out);
  if (out == NULL) {
    *error = birc_tls_error((uint32_t)ENOMEM, "tls-write");
    free(bytes);
    return NULL;
  }
  out->handle = handle;
  out->bytes = bytes;
  out->size = size;
  out->deadline = deadline;
  handle->state->writer = out;
  *error = birc_tls_error(0u, NULL);
  return out;
}
static int birc_tls_write_step(BircTlsWrite *out, uint64_t now) {
  BircTlsState *state;
  size_t sent = 0u;
  int result, why;
  if (out == NULL || out->handle == NULL || out->handle->state == NULL) return -1;
  state = out->handle->state;
  if (out->finished) return out->error.code == 0u ? 1 : -1;
  if (now >= out->deadline || state->stopped) {
    out->error = now >= out->deadline
        ? birc_tls_error((uint32_t)ETIMEDOUT, "tls-timeout")
        : birc_tls_error((uint32_t)EPIPE, "tls-write");
    goto fail;
  }
  if (out->sent == out->size) { out->finished = 1; out->want = 0; return 1; }
  ERR_clear_error();
  errno = 0;
  result = SSL_write_ex(state->ssl, out->bytes + out->sent,
                        out->size - out->sent, &sent);
  why = result == 1 ? SSL_ERROR_NONE : SSL_get_error(state->ssl, result);
  if (result == 1 && sent != 0u && sent <= out->size - out->sent) {
    /* Only success advances offset. WANT_* retries use the identical pointer
     * and length; partial-write mode completes one record before advancing. */
    out->sent += sent;
    out->want = 0;
    if (out->sent == out->size) { out->finished = 1; return 1; }
    return 0;
  }
  if (why == SSL_ERROR_WANT_READ || why == SSL_ERROR_WANT_WRITE) {
    out->want = why == SSL_ERROR_WANT_READ ? POLLIN : POLLOUT;
    return 0;
  }
  out->error = birc_tls_error((uint32_t)EIO, "tls-write");
fail:
  out->finished = 1;
  out->want = 0;
  birc_tls_stop(state);
  return -1;
}
static void birc_tls_write_free(BircTlsWrite *out) {
  if (out != NULL) {
    if (out->handle != NULL && out->handle->state != NULL &&
        out->handle->state->writer == out) out->handle->state->writer = NULL;
    free(out->bytes);
    free(out);
  }
}
static BircTlsRead *birc_tls_read_new(BircTls *handle, uint32_t max,
                                      BircTlsError *error) {
  BircTlsRead *in;
  if (error == NULL) return NULL;
  *error = birc_tls_error((uint32_t)EINVAL, "tls-read");
  if (handle == NULL || handle->state == NULL || !handle->state->verified || max == 0u)
    return NULL;
  if (handle->state->reader != NULL) {
    *error = birc_tls_error((uint32_t)EBUSY, "tls-read");
    return NULL;
  }
  in = (BircTlsRead *)BIRC_TLS_ALLOC(1u, sizeof *in);
  if (in == NULL) {
    *error = birc_tls_error((uint32_t)ENOMEM, "tls-read");
    return NULL;
  }
  in->handle = handle;
  in->size = max > sizeof in->bytes ? sizeof in->bytes : (size_t)max;
  handle->state->reader = in;
  *error = birc_tls_error(0u, NULL);
  return in;
}
static int birc_tls_read_step(BircTlsRead *in, uint64_t now, short *want,
                              uint64_t *deadline, BircTlsError *error) {
  BircTlsState *state;
  int result, why;
  if (in == NULL || want == NULL || deadline == NULL || error == NULL ||
      in->handle == NULL || in->handle->state == NULL) return -1;
  state = in->handle->state;
  *want = 0;
  *deadline = 0u;
  *error = birc_tls_error(0u, NULL);
  if (state->stopped) { in->got = 0u; return 1; }
  /* An unfinished write forbids other TLS IO until that write finishes.
   * WANT_READ and WANT_WRITE both retry this exact write and park on its
   * want. WANT_READ on an unfinished write also forbids the read. The
   * original callback later packs the stored result. */
  while (state->writer != NULL && !state->writer->finished &&
         (state->writer->want == 0 || state->writer->want == POLLIN ||
          state->writer->want == POLLOUT)) {
    BircTlsWrite *out = state->writer;
    (void)birc_tls_write_step(out, now);
    if (state->stopped) { in->got = 0u; return 1; }
    if (!out->finished && (out->want == POLLIN || out->want == POLLOUT)) {
      *want = out->want;
      *deadline = out->deadline;
      return 0;
    }
  }
  if (state->writer != NULL && !state->writer->finished) {
    *want = state->writer->want;
    *deadline = state->writer->deadline;
    return 0;
  }
  ERR_clear_error();
  errno = 0;
  result = SSL_read_ex(state->ssl, in->bytes, in->size, &in->got);
  why = result == 1 ? SSL_ERROR_NONE : SSL_get_error(state->ssl, result);
  if (result == 1) return 1;
  if (why == SSL_ERROR_ZERO_RETURN) { in->got = 0u; return 1; }
  if (why == SSL_ERROR_WANT_READ || why == SSL_ERROR_WANT_WRITE) {
    *want = why == SSL_ERROR_WANT_READ ? POLLIN : POLLOUT;
    return 0;
  }
  *error = birc_tls_error((uint32_t)EIO, "tls-read");
  birc_tls_stop(state);
  return -1;
}
static void birc_tls_read_free(BircTlsRead *in) {
  if (in != NULL) {
    if (in->handle != NULL && in->handle->state != NULL &&
        in->handle->state->reader == in) in->handle->state->reader = NULL;
    free(in);
  }
}
static BircTlsError birc_tls_shutdown(BircTls *handle) {
  BircTlsState *state;
  if (handle == NULL || handle->state == NULL)
    return birc_tls_error((uint32_t)EINVAL, "tls-shutdown");
  state = handle->state;
  if (state->stopped) return birc_tls_error(0u, NULL);
  /* One nonblocking best effort only; do not violate a pending write retry. */
  if (state->verified && state->writer == NULL) {
    ERR_clear_error();
    (void)SSL_shutdown(state->ssl);
  }
  state->stopped = 1;
  if (shutdown(state->fd, SHUT_RDWR) != 0)
    return birc_tls_error((uint32_t)errno, "tls-shutdown");
  return birc_tls_error(0u, NULL);
}

#ifndef BIRC_TLS_CORE_ONLY
#ifndef CID_TLS_OPEN_FOR
#define CID_TLS_OPEN_FOR CID(open_for)
#endif
#ifndef CID_TLS_RECV_OCTETS
#define CID_TLS_RECV_OCTETS CID(recv_octets)
#endif
#ifndef CID_TLS_SEND_FOR
#define CID_TLS_SEND_FOR CID(send_for)
#endif
#ifndef CID_TLS_DUP
#define CID_TLS_DUP CID(dup)
#endif
#ifndef CID_TLS_SHUTDOWN
#define CID_TLS_SHUTDOWN CID(shutdown)
#endif
#ifndef CID_TLS_CLOSE
#define CID_TLS_CLOSE CID(close)
#endif
static Term birc_tls_recv_more(Env e, IoWork *w);
static Term birc_tls_fail(Env e, BircTlsError error) {
  return io_fail(e, error.code, error.stage != NULL ? error.stage : "tls-config");
}
/* Wake only our own parked reader if SSL_write consumed network data into
 * SSL_pending. io_park is a circular queue owned by this same loop. The pinned
 * io_wait detaches all parked work, then checks each item's current deadline.
 * Marking an owned local item due covers a stale socket-readiness snapshot;
 * removing a global item queues exactly one reader continuation. */
static void birc_tls_wake_reader(Env e, BircTlsState *state) {
  IoWork *target, *prev, *item;
  if (state == NULL || state->reader == NULL || state->reader->work == NULL ||
      (!state->stopped && SSL_pending(state->ssl) == 0)) return;
  target = (IoWork *)state->reader->work;
  if (io_park != NULL) {
    prev = io_park;
    item = prev->next;
    do {
      if (item == target) {
        Term result;
        if (item == prev) io_park = NULL;
        else {
          prev->next = item->next;
          if (io_park == item) io_park = prev;
        }
        item->next = NULL;
        result = birc_tls_recv_more(e, item);
        if (result != IO_PARK) {
          item->item = result;
          io_push(&io_runs, item);
        }
        return;
      }
      prev = item;
      item = item->next;
    } while (prev != io_park);
  }
  /* The reader is in io_wait's local todo, not the global queue. A deadline
   * already in the past makes its normal callback due, without a second
   * queue insertion. recv_more restores the original retry deadline on park. */
  target->time = 1u;
}
static Term birc_tls_open_more(Env e, IoWork *w) {
  BircTls *handle = (BircTls *)(uintptr_t)w->hand;
  BircTlsError error;
  short want;
  int result = birc_tls_handshake(handle, io_tick(), w->size, &want, &error);
  if (result == 0)
    return io_wait_on(w, handle->state->fd, want, w->size, birc_tls_open_more);
  if (result < 0) { birc_tls_close(handle); return birc_tls_fail(e, error); }
  return io_done(e, io_hand((u64)(uintptr_t)handle));
}
Term tls_open_for_run(Env e, Term *f, IoWork *w) {
  int fd;
  char *hostname;
  u64 size = 0u;
  BircTlsError error;
  BircTls *handle;
  if (f == NULL || w == NULL) return io_fail(e, EINVAL, "tls-config");
  w->size = io_tick() + (u64)(u32)f[2] * 1000000ull;
  fd = (int)io_hand_v(f[0]);
  hostname = io_cstr(e, f[1], &size);
  if ((u32)f[2] == 0u || hostname == NULL || size > SIZE_MAX) {
    free(hostname);
    (void)close(fd);
    return io_fail(e, (u32)f[2] == 0u ? EINVAL : ENOMEM, "tls-config");
  }
  handle = birc_tls_new(fd, hostname, (size_t)size, &error);
  free(hostname);
  if (handle == NULL) return birc_tls_fail(e, error);
  w->hand = (intptr_t)(uintptr_t)handle;
  return birc_tls_open_more(e, w);
}
static Term birc_tls_recv_more(Env e, IoWork *w) {
  BircTlsRead *in = (BircTlsRead *)w->data;
  BircTls *handle = in->handle;
  BircTlsError error;
  uint64_t deadline;
  short want;
  int result = birc_tls_read_step(in, io_tick(), &want, &deadline, &error);
  Term answer;
  if (result == 0)
    return io_wait_on(w, handle->state->fd, want, deadline, birc_tls_recv_more);
  if (result < 0) answer = birc_tls_fail(e, error);
  else {
    Term bytes = term_pak(CID(Nil), 0);
    for (size_t i = in->got; i > 0u; i--)
      bytes = io_node(e, CID(Con), in->bytes[i - 1u], bytes);
    answer = io_done(e, io_box(e, CID(Some),
        io_tup(e, io_str(e, "", 0u), io_tup(e, 0u, bytes))));
  }
  birc_tls_read_free(in);
  w->data = NULL;
  return io_tup(e, io_hand((u64)(uintptr_t)handle), answer);
}
Term tls_recv_octets_run(Env e, Term *f, IoWork *w) {
  BircTlsError error;
  BircTlsRead *in;
  if (f == NULL || w == NULL) return io_fail(e, EINVAL, "tls-read");
  in = birc_tls_read_new((BircTls *)(uintptr_t)io_hand_v(f[0]), (u32)f[1], &error);
  if (in == NULL) return io_tup(e, f[0], birc_tls_fail(e, error));
  in->work = w;
  w->data = (char *)in;
  return birc_tls_recv_more(e, w);
}
static Term birc_tls_send_more(Env e, IoWork *w) {
  BircTlsWrite *out = (BircTlsWrite *)w->data;
  BircTls *handle = out->handle;
  int result;
  do { result = birc_tls_write_step(out, io_tick()); }
  while (result == 0 && out->want == 0);
  if (result == 0)
    return io_wait_on(w, handle->state->fd, out->want, out->deadline, birc_tls_send_more);
  {
    BircTlsError error = out->error;
    birc_tls_write_free(out);
    w->data = NULL;
    birc_tls_wake_reader(e, handle->state);
    return io_tup(e, io_hand((u64)(uintptr_t)handle),
        result < 0 ? birc_tls_fail(e, error) : io_done(e, term_pak(CID(Unit), 0)));
  }
}
Term tls_send_for_run(Env e, Term *f, IoWork *w) {
  char *bytes;
  u64 size = 0u;
  BircTlsError error;
  BircTlsWrite *out;
  if (f == NULL || w == NULL) return io_fail(e, EINVAL, "tls-write");
  bytes = io_cstr(e, f[1], &size);
  if ((u32)f[2] == 0u || bytes == NULL || size > SIZE_MAX) {
    free(bytes);
    return io_tup(e, f[0], io_fail(e, (u32)f[2] == 0u ? EINVAL : ENOMEM, "tls-write"));
  }
  out = birc_tls_write_new((BircTls *)(uintptr_t)io_hand_v(f[0]), bytes,
      (size_t)size, io_tick() + (u64)(u32)f[2] * 1000000ull, &error);
  if (out == NULL) return io_tup(e, f[0], birc_tls_fail(e, error));
  w->data = (char *)out;
  return birc_tls_send_more(e, w);
}
Term tls_dup_run(Env e, Term *f, IoWork *w) {
  BircTlsError error;
  BircTls *copy;
  (void)w;
  if (f == NULL) return io_fail(e, EINVAL, "tls-config");
  copy = birc_tls_dup((BircTls *)(uintptr_t)io_hand_v(f[0]), &error);
  return io_tup(e, f[0], copy != NULL
      ? io_done(e, io_hand((u64)(uintptr_t)copy)) : birc_tls_fail(e, error));
}
Term tls_shutdown_run(Env e, Term *f, IoWork *w) {
  BircTlsError error;
  BircTls *handle;
  (void)w;
  if (f == NULL) return io_fail(e, EINVAL, "tls-shutdown");
  handle = (BircTls *)(uintptr_t)io_hand_v(f[0]);
  error = birc_tls_shutdown(handle);
  if (handle != NULL) birc_tls_wake_reader(e, handle->state);
  return io_tup(e, f[0], error.code != 0u
      ? birc_tls_fail(e, error) : io_done(e, term_pak(CID(Unit), 0)));
}
Term tls_close_run(Env e, Term *f, IoWork *w) {
  (void)e;
  (void)w;
  if (f != NULL) birc_tls_close((BircTls *)(uintptr_t)io_hand_v(f[0]));
  return term_pak(CID(Unit), 0);
}
static void __attribute__((constructor)) birc_tls_use(void) {
#if CID_TLS_OPEN_FOR
  io_eff(CID_TLS_OPEN_FOR, tls_open_for_run);
#endif
#if CID_TLS_RECV_OCTETS
  io_eff(CID_TLS_RECV_OCTETS, tls_recv_octets_run);
#endif
#if CID_TLS_SEND_FOR
  io_eff(CID_TLS_SEND_FOR, tls_send_for_run);
#endif
#if CID_TLS_DUP
  io_eff(CID_TLS_DUP, tls_dup_run);
#endif
#if CID_TLS_SHUTDOWN
  io_eff(CID_TLS_SHUTDOWN, tls_shutdown_run);
#endif
#if CID_TLS_CLOSE
  io_eff(CID_TLS_CLOSE, tls_close_run);
#endif
}
#endif /* BIRC_TLS_CORE_ONLY */
#endif /* BIRC_TLS_FFI_C */
