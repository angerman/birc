/* SPDX-License-Identifier: Apache-2.0
 * Actual TLS effect/queue ownership using the pinned IO-loop queue shape.
 * The minimal Term packer records synthetic results, not IRC or real secrets. */
#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
typedef uint32_t u32;
typedef uint64_t u64;
typedef uint64_t Term;
typedef struct { int unused; } Env;
struct IoWork;
typedef Term (*IoPack)(Env, struct IoWork *);
typedef struct IoWork {
  intptr_t hand, made;
  u32 word;
  u64 size;
  char *data, *text;
  u32 code;
  IoPack pack;
  Term item;
  u64 time;
  short evts;
  struct IoWork *next;
} IoWork;
typedef Term (*Effect)(Env, Term *, IoWork *);
enum { C_Unit = 1, C_Nil, C_Con, C_Some, C_Tuple, C_Done, C_Fail,
       C_open_for, C_recv_octets, C_send_for, C_dup, C_shutdown, C_close };
#define CID_TLS_OPEN_FOR 8u
#define CID_TLS_RECV_OCTETS 9u
#define CID_TLS_SEND_FOR 10u
#define CID_TLS_DUP 11u
#define CID_TLS_SHUTDOWN 12u
#define CID_TLS_CLOSE 13u
#define CID(name) C_##name
#define IO_PARK UINT64_MAX
#define io_hand(value) ((Term)(value))
#define io_hand_v(value) ((u64)(value))
#define term_pak(cid, value) ((void)(value), (Term)(cid))
typedef struct { u64 cid; Term a, b; } Node;
static Node nodes[32768];
static size_t node_count;
static u32 failure_code, consumed_strings;
static const char *failure_stage;
static Effect effects[32];
static IoWork *io_park, *io_runs;
static u64 tick_offset;
static Term io_node(Env e, u64 cid, Term a, Term b) {
  (void)e;
  if (node_count >= sizeof nodes / sizeof nodes[0]) abort();
  Node *node = &nodes[node_count++];
  *node = (Node){cid, a, b};
  return (Term)(uintptr_t)node;
}
static Term io_box(Env e, u64 cid, Term a) { return io_node(e, cid, a, 0u); }
static Term io_tup(Env e, Term a, Term b) { return io_node(e, C_Tuple, a, b); }
static Term io_done(Env e, Term a) { return io_box(e, C_Done, a); }
static Term io_fail(Env e, u32 code, const char *text) {
  failure_code = code; failure_stage = text;
  return io_box(e, C_Fail, code);
}
static Term io_str(Env e, const char *text, u64 size) {
  (void)e;
  if (size != 0u || text == NULL || text[0] != '\0') abort();
  return 0u;
}
static char *io_cstr(Env e, Term value, u64 *size) {
  const char *text = (const char *)(uintptr_t)value;
  (void)e;
  consumed_strings++;
  *size = (u64)strlen(text);
  return strdup(text);
}
static void io_eff(u32 cid, Effect effect) {
  if (cid >= 32u || effects[cid] != NULL) abort();
  effects[cid] = effect;
}
static u64 io_tick(void) {
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) abort();
  return (u64)now.tv_sec * UINT64_C(1000000000) + (u64)now.tv_nsec + tick_offset;
}
static void io_push(IoWork **queue, IoWork *work) {
  IoWork *tail = *queue != NULL ? *queue : work;
  work->next = tail->next; tail->next = work; *queue = work;
}
static IoWork *io_pop(IoWork **queue) {
  IoWork *work = (*queue)->next;
  (*queue)->next = work->next;
  *queue = work != *queue ? *queue : NULL;
  return work;
}
static Term io_wait_on(IoWork *work, int fd, short evts, u64 deadline, IoPack more) {
  work->word = (u32)fd; work->evts = evts; work->time = deadline; work->pack = more;
  io_push(&io_park, work);
  return IO_PARK;
}
#define BIRC_TLS_TEST_FFI
#include "tls_native.c"

static Node *node(Term value, u64 cid) {
  uintptr_t address = (uintptr_t)value;
  uintptr_t first = (uintptr_t)nodes;
  uintptr_t end = (uintptr_t)(nodes + node_count);
  if (address < first || address >= end || (address - first) % sizeof(Node) != 0u) abort();
  Node *result = (Node *)(uintptr_t)value;
  if (result->cid != cid) abort();
  return result;
}
static BircTls *done_handle(Term answer) {
  return (BircTls *)(uintptr_t)node(answer, C_Done)->a;
}
static int read_answer(Term answer, BircTls *handle, const char *text) {
  Node *pair = node(answer, C_Tuple);
  CHECK((BircTls *)(uintptr_t)pair->a == handle);
  Node *some = node(node(pair->b, C_Done)->a, C_Some);
  Node *peer = node(some->a, C_Tuple);
  CHECK(peer->a == 0u);
  Node *port = node(peer->b, C_Tuple);
  CHECK(port->a == 0u);
  Term bytes = port->b;
  for (size_t i = 0u; i < strlen(text); i++) {
    Node *next = node(bytes, C_Con);
    CHECK(next->a == (Term)(unsigned char)text[i]);
    bytes = next->b;
  }
  CHECK(bytes == C_Nil);
  return 0;
}
static int ffi_handshake(Certificates *c) {
  Env env = {0};
  Pair p;
  IoWork work = {0};
  Term args[3], answer;
  CHECK(pair_new(&p, c, c->certificate, "localhost") == 0);
  int fd = dup(p.client->state->fd);
  CHECK(fd >= 0);
  birc_tls_close(p.client); p.client = NULL;
  args[0] = (Term)(unsigned int)fd;
  args[1] = (Term)(uintptr_t)"localhost"; args[2] = 1000u;
  u32 previous = consumed_strings;
  answer = tls_open_for_run(env, args, &work);
  CHECK(answer == IO_PARK && consumed_strings == previous + 1u);
  u64 limit = io_tick() + UINT64_C(2000000000);
  int server_done = 0;
  while (answer == IO_PARK && io_tick() < limit) {
    if (!server_done) {
      ERR_clear_error();
      int got = SSL_accept(p.ssl);
      int why = got == 1 ? SSL_ERROR_NONE : SSL_get_error(p.ssl, got);
      server_done = got == 1;
      CHECK(server_done || why == SSL_ERROR_WANT_READ || why == SSL_ERROR_WANT_WRITE);
    }
    CHECK(io_pop(&io_park) == &work);
    answer = work.pack(env, &work);
  }
  CHECK(answer != IO_PARK && io_park == NULL);
  p.client = done_handle(answer);
  CHECK(p.client != NULL && p.client->state->verified && SSL_pending(p.client->state->ssl) == 0);
  pair_free(&p);
  CHECK(fcntl(fd, F_GETFD) == -1 && errno == EBADF);
  return 0;
}
static int ffi_buffers_and_wake(Certificates *c) {
  Env env = {0};
  Pair p;
  IoWork work = {0}, unrelated = {0}, local_ready = {0};
  Term args[3], answer;
  size_t sent = 0u, got = 0u;
  unsigned char peek[1];
  CHECK(pair_new(&p, c, c->certificate, "localhost") == 0 && handshake(&p, 0u) == 0);
  CHECK(effects[C_recv_octets] == tls_recv_octets_run);
  CHECK(effects[C_open_for] == tls_open_for_run && effects[C_send_for] == tls_send_for_run);
  CHECK(effects[C_dup] == tls_dup_run && effects[C_shutdown] == tls_shutdown_run && effects[C_close] == tls_close_run);
  args[0] = (Term)(uintptr_t)p.client; args[1] = 2u;
  answer = tls_recv_octets_run(env, args, &work);
  CHECK(answer == IO_PARK && io_park == &work);
  /* Manufacture the same buffered-plaintext condition that writer TLS IO
   * can create, while the reader still waits on the underlying socket. */
  CHECK(SSL_write_ex(p.ssl, "abcdef", 6u, &sent) == 1 && sent == 6u);
  uint64_t limit = ticks() + UINT64_C(1000000000);
  int result;
  do { result = SSL_peek_ex(p.client->state->ssl, peek, sizeof peek, &got); }
  while (result != 1 && ticks() < limit);
  CHECK(result == 1 && got == 1u && SSL_pending(p.client->state->ssl) == 6);
  io_push(&io_park, &unrelated);
  birc_tls_wake_reader(env, p.client->state);
  CHECK(io_park == &unrelated && unrelated.next == &unrelated);
  CHECK(io_runs == &work && p.client->state->reader == NULL && work.data == NULL);
  CHECK(read_answer(work.item, p.client, "ab") == 0);
  birc_tls_wake_reader(env, p.client->state);
  CHECK(io_pop(&io_runs) == &work && io_runs == NULL);
  CHECK(io_pop(&io_park) == &unrelated && io_park == NULL);
  args[1] = 4096u;
  answer = tls_recv_octets_run(env, args, &work);
  CHECK(answer != IO_PARK && read_answer(answer, p.client, "cdef") == 0);
  answer = tls_recv_octets_run(env, args, &local_ready);
  CHECK(answer == IO_PARK && io_pop(&io_park) == &local_ready);
  /* io_wait has already detached this work into its local ready list. The
   * wake helper must not queue or free it a second time. */
  CHECK(SSL_write_ex(p.ssl, "g", 1u, &sent) == 1 && sent == 1u);
  do { result = SSL_peek_ex(p.client->state->ssl, peek, sizeof peek, &got); }
  while (result != 1 && ticks() < limit);
  CHECK(result == 1 && SSL_pending(p.client->state->ssl) == 1);
  struct pollfd snapshot = {p.client->state->fd, POLLIN, 0};
  CHECK(poll(&snapshot, 1u, 0) == 0 && local_ready.time == 0u);
  u64 snapshot_time = io_tick();
  birc_tls_wake_reader(env, p.client->state);
  CHECK(io_runs == NULL && p.client->state->reader != NULL);
  /* io_wait also detaches non-ready entries. Its captured readiness bits no
   * longer report this socket, so the owned item must become explicitly due. */
  CHECK(local_ready.time != 0u && local_ready.time <= snapshot_time);
  answer = local_ready.pack(env, &local_ready);
  CHECK(answer != IO_PARK && read_answer(answer, p.client, "g") == 0);
  answer = tls_recv_octets_run(env, args, &work);
  CHECK(answer == IO_PARK);
  answer = tls_shutdown_run(env, args, NULL);
  CHECK(node(node(answer, C_Tuple)->b, C_Done)->a == C_Unit);
  CHECK(io_park == NULL && io_runs == &work && read_answer(work.item, p.client, "") == 0);
  CHECK(io_pop(&io_runs) == &work && io_runs == NULL);
  pair_free(&p);
  return 0;
}
static int ffi_wake_preserves_deadline(Certificates *c) {
  Env env = {0};
  Pair p;
  BircTlsError error;
  BircTlsWrite *out;
  BircTls *reader;
  IoWork work = {0}, unrelated = {0};
  Term args[3], answer;
  const size_t size = 4u * 1024u * 1024u;
  size_t sent = 0u, got = 0u;
  unsigned char peek;
  int small = 4096, result;
  CHECK(pair_new(&p, c, c->certificate, "localhost") == 0 && handshake(&p, 0u) == 0);
  CHECK(SSL_write_ex(p.ssl, "h", 1u, &sent) == 1 && sent == 1u);
  u64 limit = io_tick() + UINT64_C(1000000000);
  do { result = SSL_peek_ex(p.client->state->ssl, &peek, 1u, &got); }
  while (result != 1 && io_tick() < limit);
  CHECK(result == 1 && SSL_pending(p.client->state->ssl) == 1);
  CHECK(setsockopt(p.client->state->fd, SOL_SOCKET, SO_SNDBUF, &small, (socklen_t)sizeof small) == 0);
  char *bytes = calloc(size, 1u);
  CHECK(bytes != NULL);
  out = birc_tls_write_new(p.client, bytes, size, limit, &error);
  CHECK(out != NULL);
  while (!out->finished && out->want == 0) CHECK(birc_tls_write_step(out, io_tick()) >= 0);
  CHECK(out->want == POLLOUT && !out->finished);
  reader = birc_tls_dup(p.client, &error);
  CHECK(reader != NULL);
  args[0] = (Term)(uintptr_t)reader; args[1] = 1u;
  answer = tls_recv_octets_run(env, args, &work);
  CHECK(answer == IO_PARK && work.time == out->deadline && work.evts == POLLOUT);
  CHECK(io_pop(&io_park) == &work);
  io_push(&io_park, &unrelated);
  /* Not found in global io_park means this reader is in io_wait's local
   * todo. Mark only it; leave the unrelated park queue and run queue alone. */
  birc_tls_wake_reader(env, p.client->state);
  CHECK(work.time == 1u && io_runs == NULL && io_park == &unrelated);
  CHECK(unrelated.time == 0u && unrelated.next == &unrelated);
  answer = work.pack(env, &work);
  CHECK(answer == IO_PARK && work.time == out->deadline && work.evts == POLLOUT);
  CHECK(io_pop(&io_park) == &unrelated && io_pop(&io_park) == &work && io_park == NULL);
  args[0] = (Term)(uintptr_t)p.client;
  answer = tls_shutdown_run(env, args, NULL);
  CHECK(node(node(answer, C_Tuple)->b, C_Done)->a == C_Unit && work.time == 1u);
  answer = work.pack(env, &work);
  CHECK(read_answer(answer, reader, "") == 0 && io_runs == NULL && io_park == NULL);
  CHECK(birc_tls_write_step(out, io_tick()) == -1 && out->error.code == (uint32_t)EPIPE);
  birc_tls_write_free(out);
  birc_tls_close(reader);
  pair_free(&p);
  return 0;
}
static int ffi_failure_ownership(Certificates *c) {
  Env env = {0};
  Pair p;
  IoWork work = {0};
  Term args[3], answer;
  BircTls *copy;
  int client, server;
  CHECK(sockets(&client, &server) == 0);
  args[0] = (Term)(unsigned int)client; args[1] = (Term)(uintptr_t)"localhost"; args[2] = 0u;
  u32 before = consumed_strings;
  answer = tls_open_for_run(env, args, &work);
  CHECK(node(answer, C_Fail)->a == EINVAL && consumed_strings == before + 1u);
  CHECK(fcntl(client, F_GETFD) == -1 && errno == EBADF && close(server) == 0);
  CHECK(sockets(&client, &server) == 0);
  args[0] = (Term)(unsigned int)client; args[2] = 20u;
  answer = tls_open_for_run(env, args, &work);
  CHECK(answer == IO_PARK && io_pop(&io_park) == &work);
  work.size = 0u;
  answer = work.pack(env, &work);
  CHECK(node(answer, C_Fail)->a == ETIMEDOUT && strcmp(failure_stage, "tls-timeout") == 0);
  CHECK(fcntl(client, F_GETFD) == -1 && errno == EBADF && close(server) == 0);
  CHECK(pair_new(&p, c, c->certificate, "localhost") == 0 && handshake(&p, 0u) == 0);
  args[0] = (Term)(uintptr_t)p.client;
  answer = tls_dup_run(env, args, NULL);
  copy = done_handle(node(answer, C_Tuple)->b);
  CHECK(copy != NULL && copy->state->refs == 2u);
  args[1] = (Term)(uintptr_t)"fixture write"; args[2] = 0u;
  before = consumed_strings;
  answer = tls_send_for_run(env, args, &work);
  CHECK(node(node(answer, C_Tuple)->b, C_Fail)->a == EINVAL && consumed_strings == before + 1u);
  allocation_fail = 1; args[2] = 100u;
  before = consumed_strings;
  answer = tls_send_for_run(env, args, &work);
  CHECK(node(node(answer, C_Tuple)->b, C_Fail)->a == ENOMEM && consumed_strings == before + 1u);
  CHECK(p.client->state->writer == NULL && p.client->state->refs == 2u);
  allocation_fail = 0;
  args[0] = (Term)(uintptr_t)copy;
  CHECK(tls_close_run(env, args, NULL) == C_Unit && p.client->state->refs == 1u);
  pair_free(&p);
  return 0;
}
/* Simulate elapsed setup time without sleeping or changing socket readiness.
 * The same absolute budget must already exist before TLS allocation. */
static void elapsed_setup(void) {
  allocation_hook = NULL;
  tick_offset = UINT64_C(1000000000);
}
static int ffi_setup_deadline(void) {
  Env env = {0};
  IoWork work = {0};
  Term args[3];
  int client, server;
  unsigned char byte;
  CHECK(sockets(&client, &server) == 0);
  args[0] = (Term)(unsigned int)client;
  args[1] = (Term)(uintptr_t)"localhost"; args[2] = 100u;
  allocation_hook = elapsed_setup;
  Term answer = tls_open_for_run(env, args, &work);
  tick_offset = 0u;
  CHECK(answer != IO_PARK && node(answer, C_Fail)->a == ETIMEDOUT);
  CHECK(io_park == NULL && strcmp(failure_stage, "tls-timeout") == 0);
  CHECK(fcntl(client, F_GETFD) == -1 && errno == EBADF);
  CHECK(recv(server, &byte, 1u, 0) == 0 && close(server) == 0);
  return 0;
}
int main(void) {
  Certificates c;
  CHECK(signal(SIGPIPE, SIG_IGN) != SIG_ERR);
  CHECK(certificates(&c) == 0 && ffi_setup_deadline() == 0);
  CHECK(setup_ownership() == 0 && identities(&c) == 0);
  CHECK(ca_files(&c) == 0 && ca_contents(&c) == 0);
  CHECK(handshake_timeout(&c) == 0 && buffered_and_refs(&c) == 0 && writes(&c) == 0);
  CHECK(ffi_handshake(&c) == 0 && ffi_buffers_and_wake(&c) == 0 && ffi_failure_ownership(&c) == 0);
  CHECK(ffi_wake_preserves_deadline(&c) == 0);
  CHECK(io_runs == NULL && io_park == NULL);
  certificates_free(&c);
  puts("tls_ffi=ok");
  return 0;
}
