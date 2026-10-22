/* SPDX-License-Identifier: Apache-2.0
 * Verified TLS, retry and affine ownership controls. All certificates and
 * sockets are ephemeral fixtures, generated with OpenSSL library APIs. */
#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <openssl/pem.h>
#include <openssl/ssl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#ifndef BIRC_TLS_TEST_FFI
#define BIRC_TLS_CORE_ONLY
#endif
static int allocation_fail;
static void (*allocation_hook)(void);
static size_t ssl_read_ex_calls;
static int (*real_ssl_read_ex)(SSL *, void *, size_t, size_t *) = SSL_read_ex;
static int counting_ssl_read_ex(SSL *ssl, void *buf, size_t num, size_t *readbytes) {
  ssl_read_ex_calls++;
  return real_ssl_read_ex(ssl, buf, num, readbytes);
}
static void *fixture_alloc(size_t count, size_t size) {
  if (allocation_hook != NULL) allocation_hook();
  return allocation_fail ? NULL : calloc(count, size);
}
#define BIRC_TLS_ALLOC fixture_alloc
#define SSL_read_ex counting_ssl_read_ex
#include "../src/ffi/tls_ffi.c"
#undef SSL_read_ex

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "tls_native:%d: %s\n", __LINE__, #x); return 1; } } while (0)
typedef struct {
  EVP_PKEY *key;
  X509 *ca, *certificate, *dns_only, *expired, *cn_only;
  char ca_path[64];
} Certificates;
typedef struct { SSL_CTX *ctx; SSL *ssl; int fd; BircTls *client; } Pair;
static uint64_t ticks(void) {
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) abort();
  return (uint64_t)now.tv_sec * UINT64_C(1000000000) + (uint64_t)now.tv_nsec;
}
static int nonblocking(int fd) {
  int flags = fcntl(fd, F_GETFL);
  return flags >= 0 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0;
}
static int extension(X509 *cert, X509 *issuer, int nid, const char *value) {
  X509V3_CTX context;
  X509_EXTENSION *ext;
  X509V3_set_ctx(&context, issuer, cert, NULL, NULL, 0);
  ext = X509V3_EXT_conf_nid(NULL, &context, nid, value);
  if (ext == NULL) return 0;
  int result = X509_add_ext(cert, ext, -1);
  X509_EXTENSION_free(ext);
  return result == 1;
}
static X509 *certificate(EVP_PKEY *key, X509 *issuer, long serial,
                          const char *san, int expired) {
  X509 *cert = X509_new();
  X509_NAME *name;
  if (cert == NULL) return NULL;
  name = X509_get_subject_name(cert);
  if (name == NULL || X509_set_version(cert, 2L) != 1 ||
      ASN1_INTEGER_set(X509_get_serialNumber(cert), serial) != 1 ||
      X509_gmtime_adj(X509_getm_notBefore(cert), -3600L) == NULL ||
      X509_gmtime_adj(X509_getm_notAfter(cert), expired ? -60L : 3600L) == NULL ||
      X509_set_pubkey(cert, key) != 1 ||
      X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC,
          (const unsigned char *)(issuer == NULL ? "fixture CA" : "localhost"),
          -1, -1, 0) != 1 ||
      X509_set_issuer_name(cert, issuer == NULL ? name : X509_get_subject_name(issuer)) != 1 ||
      !extension(cert, issuer == NULL ? cert : issuer, NID_basic_constraints,
          issuer == NULL ? "critical,CA:TRUE" : "critical,CA:FALSE") ||
      !extension(cert, issuer == NULL ? cert : issuer, NID_key_usage,
          issuer == NULL ? "critical,keyCertSign,cRLSign" : "critical,digitalSignature,keyEncipherment") ||
      (issuer != NULL && (!extension(cert, issuer, NID_ext_key_usage, "serverAuth") ||
                          (san != NULL && !extension(cert, issuer, NID_subject_alt_name, san)))) ||
      X509_sign(cert, key, EVP_sha256()) <= 0) {
    X509_free(cert);
    return NULL;
  }
  return cert;
}
static int certificates(Certificates *c) {
  FILE *file;
  int fd;
  const char template[] = "/tmp/birc-tls-ca.XXXXXX";
  memset(c, 0, sizeof *c);
  c->key = EVP_RSA_gen(2048u);
  CHECK(c->key != NULL);
  c->ca = certificate(c->key, NULL, 1L, NULL, 0);
  CHECK(c->ca != NULL);
  c->certificate = certificate(c->key, c->ca, 2L, "DNS:localhost,IP:127.0.0.1", 0);
  c->dns_only = certificate(c->key, c->ca, 3L, "DNS:localhost", 0);
  c->expired = certificate(c->key, c->ca, 4L, "DNS:localhost,IP:127.0.0.1", 1);
  c->cn_only = certificate(c->key, c->ca, 5L, NULL, 0);
  CHECK(c->certificate != NULL && c->dns_only != NULL && c->expired != NULL && c->cn_only != NULL);
  memcpy(c->ca_path, template, sizeof template);
  fd = mkstemp(c->ca_path);
  CHECK(fd >= 0);
  file = fdopen(fd, "w");
  CHECK(file != NULL && PEM_write_X509(file, c->ca) == 1 && fclose(file) == 0);
  CHECK(setenv("SSL_CERT_FILE", c->ca_path, 1) == 0);
  CHECK(setenv("SSL_CERT_DIR", "/birc-owned-fixture-no-ca-directory", 1) == 0);
  return 0;
}
static void certificates_free(Certificates *c) {
  (void)unlink(c->ca_path);
  X509_free(c->cn_only); X509_free(c->expired); X509_free(c->dns_only); X509_free(c->certificate);
  X509_free(c->ca); EVP_PKEY_free(c->key);
}
static int sockets(int *client, int *server) {
  struct sockaddr_in address;
  socklen_t size = (socklen_t)sizeof address;
  int listener = socket(AF_INET, SOCK_STREAM, 0);
  memset(&address, 0, sizeof address);
  address.sin_family = AF_INET;
  address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  CHECK(listener >= 0 && bind(listener, (struct sockaddr *)&address, size) == 0);
  CHECK(getsockname(listener, (struct sockaddr *)&address, &size) == 0 && listen(listener, 1) == 0);
  *client = socket(AF_INET, SOCK_STREAM, 0);
  CHECK(*client >= 0 && connect(*client, (struct sockaddr *)&address, size) == 0);
  *server = accept(listener, NULL, NULL);
  CHECK(*server >= 0 && close(listener) == 0 && nonblocking(*client) && nonblocking(*server));
  return 0;
}
static int pair_new(Pair *p, Certificates *c, X509 *cert, const char *hostname) {
  BircTlsError error;
  int client;
  memset(p, 0, sizeof *p);
  p->fd = -1;
  CHECK(sockets(&client, &p->fd) == 0);
  p->ctx = SSL_CTX_new(TLS_server_method());
  CHECK(p->ctx != NULL && SSL_CTX_use_certificate(p->ctx, cert) == 1);
  CHECK(SSL_CTX_use_PrivateKey(p->ctx, c->key) == 1);
  p->ssl = SSL_new(p->ctx);
  CHECK(p->ssl != NULL && SSL_set_fd(p->ssl, p->fd) == 1);
  SSL_set_accept_state(p->ssl);
  p->client = birc_tls_new(client, hostname, strlen(hostname), &error);
  CHECK(p->client != NULL && error.code == 0u && !p->client->state->verified);
  return 0;
}
static void pair_free(Pair *p) {
  birc_tls_close(p->client);
  SSL_free(p->ssl); SSL_CTX_free(p->ctx);
  if (p->fd >= 0) (void)close(p->fd);
}
static int handshake(Pair *p, uint32_t expected) {
  uint64_t deadline = ticks() + UINT64_C(2000000000);
  BircTlsError error = {0u, NULL};
  short want = 0;
  int client_done = 0, server_done = 0;
  while (ticks() < deadline) {
    if (!client_done) {
      int result = birc_tls_handshake(p->client, ticks(), deadline, &want, &error);
      if (result < 0) {
        if (error.code != expected || expected == 0u)
          fprintf(stderr, "fixture-handshake: code=%u stage=%s verify=%ld\n",
                  error.code, error.stage, SSL_get_verify_result(p->client->state->ssl));
        CHECK(error.code == expected && expected != 0u);
        return 0;
      }
      client_done = result == 1;
    }
    if (!server_done) {
      ERR_clear_error();
      int result = SSL_accept(p->ssl);
      int why = result == 1 ? SSL_ERROR_NONE : SSL_get_error(p->ssl, result);
      server_done = result == 1;
      CHECK(server_done || why == SSL_ERROR_WANT_READ || why == SSL_ERROR_WANT_WRITE || expected != 0u);
    }
    if (client_done && server_done) {
      CHECK(expected == 0u && p->client->state->verified);
      return 0;
    }
    struct pollfd fds[2] = {{p->client->state->fd, POLLIN | POLLOUT, 0}, {p->fd, POLLIN | POLLOUT, 0}};
    CHECK(poll(fds, 2u, 1) >= 0);
  }
  CHECK(0);
}
static int identities(Certificates *c) {
  Pair p;
  CHECK(pair_new(&p, c, c->certificate, "localhost") == 0 && handshake(&p, 0u) == 0);
  CHECK(SSL_get_servername(p.ssl, TLSEXT_NAMETYPE_host_name) != NULL);
  CHECK(strcmp(SSL_get_servername(p.ssl, TLSEXT_NAMETYPE_host_name), "localhost") == 0);
  CHECK(SSL_version(p.client->state->ssl) >= TLS1_2_VERSION);
  pair_free(&p);
  CHECK(pair_new(&p, c, c->certificate, "localhost.") == 0 && handshake(&p, 0u) == 0);
  CHECK(SSL_get_servername(p.ssl, TLSEXT_NAMETYPE_host_name) != NULL);
  CHECK(strcmp(SSL_get_servername(p.ssl, TLSEXT_NAMETYPE_host_name), "localhost") == 0);
  pair_free(&p);
  CHECK(pair_new(&p, c, c->certificate, "localhost") == 0);
  CHECK(SSL_set_max_proto_version(p.ssl, TLS1_2_VERSION) == 1 && handshake(&p, 0u) == 0);
  CHECK(SSL_version(p.client->state->ssl) == TLS1_2_VERSION);
  pair_free(&p);
  CHECK(pair_new(&p, c, c->certificate, "127.0.0.1") == 0 && handshake(&p, 0u) == 0);
  CHECK(SSL_get_servername(p.ssl, TLSEXT_NAMETYPE_host_name) == NULL);
  pair_free(&p);
  CHECK(pair_new(&p, c, c->certificate, "wrong.invalid") == 0 && handshake(&p, (uint32_t)EACCES) == 0);
  pair_free(&p);
  CHECK(pair_new(&p, c, c->dns_only, "127.0.0.1") == 0 && handshake(&p, (uint32_t)EACCES) == 0);
  pair_free(&p);
  CHECK(pair_new(&p, c, c->expired, "localhost") == 0 && handshake(&p, (uint32_t)EACCES) == 0);
  pair_free(&p);
  CHECK(pair_new(&p, c, c->cn_only, "localhost") == 0 && handshake(&p, (uint32_t)EACCES) == 0);
  pair_free(&p);
  /* Trust a valid unrelated certificate, not a missing-file setup failure. */
  FILE *file = fopen(c->ca_path, "w");
  CHECK(file != NULL && PEM_write_X509(file, c->certificate) == 1 && fclose(file) == 0);
  CHECK(pair_new(&p, c, c->dns_only, "localhost") == 0 && handshake(&p, (uint32_t)EACCES) == 0);
  pair_free(&p);
  file = fopen(c->ca_path, "w");
  CHECK(file != NULL && PEM_write_X509(file, c->ca) == 1 && fclose(file) == 0);
  CHECK(setenv("SSL_CERT_FILE", c->ca_path, 1) == 0);
  return 0;
}
static int setup_ownership(void) {
  BircTlsError error;
  int client, server, ip;
  static const char *bad[] = {"", ".", ".localhost", "localhost..", "localhost/evil", "localhost\n", "*.localhost"};
  for (size_t i = 0u; i < sizeof bad / sizeof bad[0]; i++) {
    CHECK(sockets(&client, &server) == 0);
    CHECK(birc_tls_new(client, bad[i], strlen(bad[i]), &error) == NULL && error.code == (uint32_t)EINVAL);
    CHECK(fcntl(client, F_GETFD) == -1 && errno == EBADF && close(server) == 0);
  }
  CHECK(!birc_tls_hostname(NULL, 1u, &ip) && !birc_tls_hostname("localhost", 9u, NULL));
  CHECK(!birc_tls_hostname("localhost", 8u, &ip));
  char maximum[255];
  memset(maximum, 'a', sizeof maximum);
  maximum[63] = '.'; maximum[127] = '.'; maximum[191] = '.';
  maximum[253] = '\0';
  CHECK(birc_tls_hostname(maximum, 253u, &ip) && !ip);
  maximum[253] = '.'; maximum[254] = '\0';
  CHECK(birc_tls_hostname(maximum, 254u, &ip) && !ip);
  CHECK(sockets(&client, &server) == 0);
  BircTls *absolute = birc_tls_new(client, maximum, 254u, &error);
  CHECK(absolute != NULL && error.code == 0u);
  const char *sni = SSL_get_servername(absolute->state->ssl, TLSEXT_NAMETYPE_host_name);
  CHECK(sni != NULL && strlen(sni) == 253u && memcmp(sni, maximum, 253u) == 0);
  birc_tls_close(absolute);
  CHECK(fcntl(client, F_GETFD) == -1 && errno == EBADF && close(server) == 0);
  maximum[253] = 'a';
  CHECK(!birc_tls_hostname(maximum, 254u, &ip));
  CHECK(sockets(&client, &server) == 0);
  CHECK(birc_tls_new(client, maximum, 254u, &error) == NULL && error.code == (uint32_t)EINVAL);
  CHECK(fcntl(client, F_GETFD) == -1 && errno == EBADF && close(server) == 0);
  CHECK(sockets(&client, &server) == 0);
  allocation_fail = 1;
  CHECK(birc_tls_new(client, "localhost", 9u, &error) == NULL && error.code == (uint32_t)ENOMEM);
  allocation_fail = 0;
  CHECK(fcntl(client, F_GETFD) == -1 && errno == EBADF && close(server) == 0);
  return 0;
}
/* A CA FIFO must refuse promptly, not block before the handshake timer.
 * Each child owns only fixture sockets and is forcibly bounded by SIGALRM. */
static int ca_file_case(const char *path, int accepts) {
  int client, server, status = 0;
  CHECK(sockets(&client, &server) == 0);
  pid_t child = fork();
  CHECK(child >= 0);
  if (child == 0) {
    BircTlsError error;
    (void)signal(SIGALRM, SIG_DFL);
    (void)alarm(2u);
    (void)close(server);
    if (setenv("SSL_CERT_FILE", path, 1) != 0) _Exit(70);
    BircTls *handle = birc_tls_new(client, "localhost", 9u, &error);
    int good = accepts ? handle != NULL && error.code == 0u
                       : handle == NULL && error.code == (uint32_t)EIO;
    birc_tls_close(handle);
    if (!accepts && !(fcntl(client, F_GETFD) == -1 && errno == EBADF)) good = 0;
    _Exit(good ? 0 : 71);
  }
  CHECK(close(client) == 0 && close(server) == 0);
  CHECK(waitpid(child, &status, 0) == child);
  CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0);
  return 0;
}
static int ca_files(Certificates *c) {
  char folder[] = "/tmp/birc-tls-files.XXXXXX";
  char fifo[96], empty[96], large[96], link[96];
  CHECK(mkdtemp(folder) != NULL);
  int n = snprintf(fifo, sizeof fifo, "%s/fifo", folder);
  CHECK(n > 0 && (size_t)n < sizeof fifo && mkfifo(fifo, 0600) == 0);
  n = snprintf(empty, sizeof empty, "%s/empty", folder);
  CHECK(n > 0 && (size_t)n < sizeof empty);
  n = snprintf(large, sizeof large, "%s/large", folder);
  CHECK(n > 0 && (size_t)n < sizeof large);
  n = snprintf(link, sizeof link, "%s/link", folder);
  CHECK(n > 0 && (size_t)n < sizeof link && symlink(c->ca_path, link) == 0);
  int fd = open(empty, O_CREAT | O_WRONLY | O_EXCL, 0600);
  CHECK(fd >= 0 && close(fd) == 0);
  FILE *file = fopen(large, "w");
  CHECK(file != NULL && PEM_write_X509(file, c->ca) == 1);
  CHECK(ftruncate(fileno(file), (off_t)(8u * 1024u * 1024u)) == 0 && fclose(file) == 0);
  CHECK(ca_file_case(c->ca_path, 1) == 0 && ca_file_case(link, 1) == 0);
  CHECK(ca_file_case(large, 1) == 0);
  fd = open(large, O_WRONLY);
  CHECK(fd >= 0 && ftruncate(fd, (off_t)(8u * 1024u * 1024u + 1u)) == 0 && close(fd) == 0);
  CHECK(ca_file_case(fifo, 0) == 0 && ca_file_case(folder, 0) == 0);
  CHECK(ca_file_case(empty, 0) == 0 && ca_file_case(large, 0) == 0);
  CHECK(unlink(fifo) == 0 && unlink(empty) == 0 && unlink(large) == 0 && unlink(link) == 0);
  CHECK(rmdir(folder) == 0);
  return 0;
}
/* Library parsing must keep AUX trust and CRLs, including duplicate inputs. */
static int ca_contents(Certificates *c) {
  char path[] = "/tmp/birc-tls-contents.XXXXXX";
  X509 *aux = X509_dup(c->ca);
  X509_CRL *crl = X509_CRL_new();
  ASN1_TIME *last = ASN1_TIME_set(NULL, time(NULL) - 60);
  ASN1_TIME *next = ASN1_TIME_set(NULL, time(NULL) + 3600);
  SSL_CTX *ctx = SSL_CTX_new(TLS_client_method());
  CHECK(aux != NULL && crl != NULL && last != NULL && next != NULL && ctx != NULL);
  CHECK(X509_alias_set1(aux, (const unsigned char *)"owned", 5) == 1);
  CHECK(X509_add1_trust_object(aux, OBJ_nid2obj(NID_server_auth)) == 1);
  CHECK(X509_CRL_set_version(crl, 1L) == 1);
  CHECK(X509_CRL_set_issuer_name(crl, X509_get_subject_name(c->ca)) == 1);
  CHECK(X509_CRL_set1_lastUpdate(crl, last) == 1 && X509_CRL_set1_nextUpdate(crl, next) == 1);
  CHECK(X509_CRL_sign(crl, c->key, EVP_sha256()) > 0);
  int fd = mkstemp(path);
  CHECK(fd >= 0);
  FILE *file = fdopen(fd, "w");
  CHECK(file != NULL && PEM_write_X509_AUX(file, aux) == 1 && PEM_write_X509_AUX(file, aux) == 1);
  CHECK(PEM_write_X509_CRL(file, crl) == 1 && PEM_write_X509_CRL(file, crl) == 1 && fclose(file) == 0);
  CHECK(setenv("SSL_CERT_FILE", path, 1) == 0 && birc_tls_trust(ctx));
  STACK_OF(X509_OBJECT) *objects = X509_STORE_get0_objects(SSL_CTX_get_cert_store(ctx));
  CHECK(objects != NULL && sk_X509_OBJECT_num(objects) == 2);
  int certs = 0, crls = 0;
  for (int i = 0; i < sk_X509_OBJECT_num(objects); i++) {
    X509_OBJECT *object = sk_X509_OBJECT_value(objects, i);
    CHECK(object != NULL);
    X509 *loaded = X509_OBJECT_get0_X509(object);
    if (loaded != NULL) {
      int size = 0;
      unsigned char *alias = X509_alias_get0(loaded, &size);
      STACK_OF(ASN1_OBJECT) *trust = X509_get0_trust_objects(loaded);
      CHECK(alias != NULL && size == 5 && memcmp(alias, "owned", 5u) == 0);
      CHECK(trust != NULL && sk_ASN1_OBJECT_num(trust) == 1);
      CHECK(OBJ_obj2nid(sk_ASN1_OBJECT_value(trust, 0)) == NID_server_auth);
      certs++;
    } else {
      X509_CRL *loaded_crl = X509_OBJECT_get0_X509_CRL(object);
      CHECK(loaded_crl != NULL && X509_CRL_cmp(loaded_crl, crl) == 0);
      crls++;
    }
  }
  CHECK(certs == 1 && crls == 1);
  file = fopen(path, "w");
  CHECK(file != NULL && PEM_write_PrivateKey(file, c->key, EVP_aes_256_cbc(),
      (const unsigned char *)"fixture", 7, NULL, NULL) == 1 && fclose(file) == 0);
  CHECK(ca_file_case(path, 0) == 0);
  CHECK(setenv("SSL_CERT_FILE", c->ca_path, 1) == 0 && unlink(path) == 0);
  SSL_CTX_free(ctx); X509_free(aux); X509_CRL_free(crl);
  ASN1_TIME_free(last); ASN1_TIME_free(next);
  return 0;
}
static int handshake_timeout(Certificates *c) {
  Pair p;
  BircTlsError error;
  short want;
  CHECK(pair_new(&p, c, c->certificate, "localhost") == 0);
  uint64_t deadline = ticks() + UINT64_C(30000000);
  CHECK(birc_tls_handshake(p.client, ticks(), deadline, &want, &error) == 0 && want != 0);
  struct pollfd fd = {p.client->state->fd, POLLIN, 0};
  CHECK(poll(&fd, 1u, 50) >= 0);
  CHECK(birc_tls_handshake(p.client, ticks(), deadline, &want, &error) == -1);
  CHECK(error.code == (uint32_t)ETIMEDOUT && !p.client->state->verified);
  CHECK(p.client->state->stopped && strcmp(error.stage, "tls-timeout") == 0);
  char *bytes = strdup("must not send");
  CHECK(bytes != NULL && birc_tls_write_new(p.client, bytes, 13u, deadline, &error) == NULL);
  pair_free(&p);
  CHECK(pair_new(&p, c, c->certificate, "localhost") == 0);
  deadline = ticks() + UINT64_C(1000000000);
  CHECK(birc_tls_handshake(p.client, ticks(), deadline, &want, &error) == 0);
  CHECK(send(p.fd, "plaintext IRC\r\n", 15u, 0) == 15);
  int result;
  do { result = birc_tls_handshake(p.client, ticks(), deadline, &want, &error); }
  while (result == 0 && ticks() < deadline);
  CHECK(result == -1 && error.code == (uint32_t)EPROTO && strcmp(error.stage, "tls-handshake") == 0);
  CHECK(!p.client->state->verified);
  pair_free(&p);
  return 0;
}
static int buffered_and_refs(Certificates *c) {
  Pair p;
  BircTlsError error;
  BircTlsRead *in;
  BircTls *copy;
  short want;
  uint64_t deadline;
  size_t sent = 0u;
  CHECK(pair_new(&p, c, c->certificate, "localhost") == 0 && handshake(&p, 0u) == 0);
  copy = birc_tls_dup(p.client, &error);
  CHECK(copy != NULL && error.code == 0u && copy->state == p.client->state && copy->state->refs == 2u);
  allocation_fail = 1;
  CHECK(birc_tls_dup(p.client, &error) == NULL && error.code == (uint32_t)ENOMEM && copy->state->refs == 2u);
  allocation_fail = 0;
  CHECK(SSL_write_ex(p.ssl, "abcdef", 6u, &sent) == 1 && sent == 6u);
  in = birc_tls_read_new(copy, 2u, &error);
  CHECK(in != NULL && birc_tls_read_new(p.client, 1u, &error) == NULL && error.code == (uint32_t)EBUSY);
  uint64_t limit = ticks() + UINT64_C(1000000000);
  int result;
  do { result = birc_tls_read_step(in, ticks(), &want, &deadline, &error); } while (result == 0 && ticks() < limit);
  CHECK(result == 1 && in->got == 2u && memcmp(in->bytes, "ab", 2u) == 0);
  CHECK(SSL_pending(copy->state->ssl) == 4);
  birc_tls_read_free(in);
  in = birc_tls_read_new(copy, 4096u, &error);
  CHECK(in != NULL && birc_tls_read_step(in, ticks(), &want, &deadline, &error) == 1);
  CHECK(in->got == 4u && memcmp(in->bytes, "cdef", 4u) == 0);
  birc_tls_read_free(in);
  in = birc_tls_read_new(copy, 4096u, &error);
  CHECK(in != NULL && birc_tls_read_step(in, ticks(), &want, &deadline, &error) == 0 && want == POLLIN);
  int fd = copy->state->fd;
  birc_tls_close(p.client); p.client = NULL;
  CHECK(copy->state->refs == 1u && fcntl(fd, F_GETFD) >= 0);
  CHECK(birc_tls_shutdown(copy).code == 0u && birc_tls_shutdown(copy).code == 0u);
  CHECK(birc_tls_read_step(in, ticks(), &want, &deadline, &error) == 1 && in->got == 0u);
  birc_tls_read_free(in);
  birc_tls_close(copy);
  CHECK(fcntl(fd, F_GETFD) == -1 && errno == EBADF);
  pair_free(&p);
  return 0;
}
static int write_wants_read(Certificates *c);
static int writes(Certificates *c) {
  Pair p;
  BircTlsError error;
  BircTlsWrite *out;
  BircTlsRead *in;
  short want;
  uint64_t deadline;
  const size_t size = 4u * 1024u * 1024u;
  char *bytes;
  unsigned char received[32768];
  size_t total = 0u;
  int small = 4096, blocked = 0;
  CHECK(pair_new(&p, c, c->certificate, "localhost") == 0 && handshake(&p, 0u) == 0);
  CHECK(setsockopt(p.client->state->fd, SOL_SOCKET, SO_SNDBUF, &small, (socklen_t)sizeof small) == 0);
  bytes = malloc(size);
  CHECK(bytes != NULL);
  for (size_t i = 0u; i < size; i++) bytes[i] = (char)(i % 127u);
  out = birc_tls_write_new(p.client, bytes, size, ticks() + UINT64_C(5000000000), &error);
  CHECK(out != NULL);
  CHECK(birc_tls_write_new(p.client, strdup("other"), 5u, out->deadline, &error) == NULL && error.code == (uint32_t)EBUSY);
  while (!out->finished && ticks() < out->deadline) {
    size_t previous = out->sent;
    int result = birc_tls_write_step(out, ticks());
    CHECK(result >= 0 && out->sent >= previous);
    if (out->want != 0) {
      CHECK(out->sent == previous);
      blocked = 1;
      break;
    }
  }
  CHECK(blocked && out->want == POLLOUT && out->sent < size);
  in = birc_tls_read_new(p.client, 8u, &error);
  CHECK(in != NULL);
  CHECK(birc_tls_read_step(in, ticks(), &want, &deadline, &error) == 0);
  CHECK(want == POLLOUT && deadline == out->deadline && !p.client->state->stopped);
  birc_tls_read_free(in);
  while ((!out->finished || total < size) && ticks() < out->deadline) {
    if (!out->finished) CHECK(birc_tls_write_step(out, ticks()) >= 0);
    size_t got = 0u;
    ERR_clear_error();
    int result = SSL_read_ex(p.ssl, received, sizeof received, &got);
    int why = result == 1 ? SSL_ERROR_NONE : SSL_get_error(p.ssl, result);
    CHECK(result == 1 || why == SSL_ERROR_WANT_READ || why == SSL_ERROR_WANT_WRITE);
    for (size_t i = 0u; i < got; i++) CHECK(received[i] == (unsigned char)((total + i) % 127u));
    total += got;
  }
  CHECK(out->finished && out->error.code == 0u && out->sent == size && total == size);
  birc_tls_write_free(out);
  bytes = strdup("short");
  CHECK(bytes != NULL);
  out = birc_tls_write_new(p.client, bytes, 5u, ticks(), &error);
  CHECK(out != NULL && birc_tls_write_step(out, ticks()) == -1);
  CHECK(out->error.code == (uint32_t)ETIMEDOUT && out->sent == 0u && p.client->state->stopped);
  birc_tls_write_free(out);
  pair_free(&p);
  /* Abort an actual pending SSL_write retry: shutdown must not try a second
   * TLS operation, and its stored write fails without advancing any offset. */
  CHECK(pair_new(&p, c, c->certificate, "localhost") == 0 && handshake(&p, 0u) == 0);
  CHECK(setsockopt(p.client->state->fd, SOL_SOCKET, SO_SNDBUF, &small, (socklen_t)sizeof small) == 0);
  bytes = calloc(size, 1u);
  CHECK(bytes != NULL);
  out = birc_tls_write_new(p.client, bytes, size, ticks() + UINT64_C(1000000000), &error);
  CHECK(out != NULL);
  while (!out->finished && out->want == 0) CHECK(birc_tls_write_step(out, ticks()) >= 0);
  CHECK(out->want == POLLOUT && !out->finished);
  size_t offset = out->sent;
  CHECK(birc_tls_shutdown(p.client).code == 0u);
  CHECK(birc_tls_write_step(out, ticks()) == -1 && out->error.code == (uint32_t)EPIPE && out->sent == offset);
  birc_tls_write_free(out);
  pair_free(&p);
  CHECK(write_wants_read(c) == 0);
  return 0;
}
/* The next SSL_write on this verified socket reports WANT_READ. Count
 * SSL_read_ex calls made by the shared object; the read step must not make
 * one while that write is unfinished. Owned loopback, synthetic certificate. */
static int write_wants_read_flag;
static long write_wants_read_cb(BIO *bio, int oper, const char *argp, size_t len,
                                int argi, long argl, int ret, size_t *processed) {
  (void)argp; (void)len; (void)argi; (void)argl; (void)processed;
  if (write_wants_read_flag && oper == BIO_CB_WRITE) {
    BIO_clear_retry_flags(bio);
    BIO_set_retry_read(bio);
    return -1;
  }
  return ret;
}
static int write_wants_read(Certificates *c) {
  Pair p;
  BircTlsError error;
  BircTlsWrite *out;
  BircTlsRead *in;
  BIO *transport;
  short want;
  uint64_t deadline, limit;
  size_t sent;
  char *bytes;
  int result;
  CHECK(pair_new(&p, c, c->certificate, "localhost") == 0 && handshake(&p, 0u) == 0);
  transport = SSL_get_wbio(p.client->state->ssl);
  CHECK(transport != NULL && transport == SSL_get_rbio(p.client->state->ssl));
  BIO_set_callback_ex(transport, write_wants_read_cb);
  write_wants_read_flag = 1;
  bytes = strdup("ping");
  CHECK(bytes != NULL);
  out = birc_tls_write_new(p.client, bytes, 4u, ticks() + UINT64_C(1000000000), &error);
  CHECK(out != NULL && birc_tls_write_step(out, ticks()) == 0);
  CHECK(out->want == POLLIN && !out->finished && out->sent == 0u);
  ssl_read_ex_calls = 0u;
  in = birc_tls_read_new(p.client, 8u, &error);
  CHECK(in != NULL);
  CHECK(birc_tls_read_step(in, ticks(), &want, &deadline, &error) == 0);
  CHECK(ssl_read_ex_calls == 0u && want == POLLIN && deadline == out->deadline);
  CHECK(!out->finished && out->sent == 0u && !p.client->state->stopped);
  write_wants_read_flag = 0;
  BIO_set_callback_ex(transport, NULL);
  while (!out->finished && ticks() < out->deadline) {
    CHECK(birc_tls_write_step(out, ticks()) >= 0);
    if (!out->finished && out->want != 0) {
      struct pollfd ready = {p.client->state->fd, out->want, 0};
      CHECK(poll(&ready, 1u, 20) >= 0);
    }
  }
  CHECK(out->finished && out->error.code == 0u && out->sent == 4u);
  birc_tls_write_free(out);
  sent = 0u;
  limit = ticks() + UINT64_C(1000000000);
  while (sent < 4u && ticks() < limit) {
    size_t chunk = 0u;
    const char pong[] = "pong";
    ERR_clear_error();
    int wrote = SSL_write_ex(p.ssl, &pong[sent], 4u - sent, &chunk);
    int why = wrote == 1 ? SSL_ERROR_NONE : SSL_get_error(p.ssl, wrote);
    if (wrote == 1) {
      sent += chunk;
      continue;
    }
    CHECK(why == SSL_ERROR_WANT_READ || why == SSL_ERROR_WANT_WRITE);
    if (why == SSL_ERROR_WANT_READ) {
      unsigned char sink[512];
      size_t got = 0u;
      ERR_clear_error();
      (void)SSL_read_ex(p.ssl, sink, sizeof sink, &got);
    }
    struct pollfd ready = {p.fd, why == SSL_ERROR_WANT_READ ? POLLIN : POLLOUT, 0};
    CHECK(poll(&ready, 1u, 20) >= 0);
  }
  CHECK(sent == 4u);
  do {
    result = birc_tls_read_step(in, ticks(), &want, &deadline, &error);
    if (result == 0) {
      struct pollfd ready = {p.client->state->fd, want != 0 ? want : POLLIN, 0};
      CHECK(poll(&ready, 1u, 20) >= 0);
    }
  } while (result == 0 && ticks() < limit);
  CHECK(result == 1 && error.code == 0u && in->got == 4u && memcmp(in->bytes, "pong", 4u) == 0);
  CHECK(ssl_read_ex_calls > 0u);
  birc_tls_read_free(in);
  pair_free(&p);
  return 0;
}
#ifndef BIRC_TLS_TEST_FFI
int main(void) {
  Certificates c;
  CHECK(signal(SIGPIPE, SIG_IGN) != SIG_ERR);
  CHECK(certificates(&c) == 0 && setup_ownership() == 0 && identities(&c) == 0);
  CHECK(ca_files(&c) == 0 && ca_contents(&c) == 0);
  CHECK(handshake_timeout(&c) == 0 && buffered_and_refs(&c) == 0 && writes(&c) == 0);
  certificates_free(&c);
  puts("tls_native=ok");
  return 0;
}
#endif
