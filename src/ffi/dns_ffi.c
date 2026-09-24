/* UDP recv as octets (0..255). Base UDP.recv_from is a String (WHATWG
 * io_str), so A rdata 0x80–0xC1 cannot be recovered. Non-blocking;
 * None means EAGAIN/EINTR. Returns peer host+port beside the octets.
 * Bend owns encode/send/parse. send_octets is the outbound twin. */
#ifndef BIRC_DNS_FFI_C
#define BIRC_DNS_FFI_C
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <poll.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#ifndef IO_READ
#define IO_READ 1
#endif
/* park=1: EAGAIN waits again (TCP reader). park=0: EAGAIN is None (DNS). */
static Term recv_fill(Env e, uint8_t *data, ssize_t n, const struct sockaddr_in *src) {
  char host[INET_ADDRSTRLEN];
  Term xs = term_pak(CID_NIL, 0);
  u64 i;
  u64 nn = (u64)n;
  u32 port = (u32)ntohs(src->sin_port);
  host[0] = '\0';
  if (src->sin_family == AF_INET)
    (void)inet_ntop(AF_INET, &src->sin_addr, host, (socklen_t)sizeof host);
  for (i = nn; i > 0; i -= 1)
    xs = io_node(e, CID_CON, data[i - 1], xs);
  return io_done(e, io_box(e, CID_SOME,
                            io_tup(e, io_str(e, host, (u64)strlen(host)),
                                   io_tup(e, (Term)port, xs))));
}
static Term recv_more(Env e, IoWork *w);
static Term recv_try(Env e, int fd, u32 max, IoWork *w, int park) {
  uint8_t *data;
  struct sockaddr_in src;
  socklen_t slen;
  ssize_t n;
  u32 code;
  Term r;
  if (max > 4096u)
    max = 4096u;
  data = io_mem(malloc((size_t)max + 1u));
  memset(&src, 0, sizeof src);
  slen = (socklen_t)sizeof src;
  n = recvfrom(fd, data, (size_t)max, 0, (struct sockaddr *)&src, &slen);
  code = n < 0 ? (u32)errno : 0;
  if (code == (u32)EAGAIN || code == (u32)EWOULDBLOCK || code == (u32)EINTR) {
    free(data);
    if (park && w) {
      w->hand = (intptr_t)fd;
      w->made = (intptr_t)max;
      return io_wait_on(w, fd, POLLIN, 0, recv_more);
    }
    return io_tup(e, io_hand((u64)fd), io_done(e, term_pak(CID_NONE, 0)));
  } else if (code != 0 || n < 0) {
    r = io_fail(e, code != 0 ? code : 1u, NULL);
  } else {
    r = recv_fill(e, data, n, &src);
  }
  free(data);
  return io_tup(e, io_hand((u64)fd), r);
}
static Term recv_more(Env e, IoWork *w) {
  return recv_try(e, (int)w->hand, (u32)w->made, w, 1);
}
#ifdef CID_RECV_OCTETS
Term recv_octets_run(Env e, Term *f, IoWork *w) {
  u32 max = f[1] < INT32_MAX ? (u32)f[1] : INT32_MAX;
  return recv_try(e, (int)io_hand_v(f[0]), max, w, 1);
}
static void __attribute__((constructor)) recv_octets_use(void) {
  io_eff(CID_RECV_OCTETS, recv_octets_run, IO_READ);
}
#endif
#ifdef CID_RECV_NB
Term recv_nb_run(Env e, Term *f, IoWork *w) {
  u32 max = f[1] < INT32_MAX ? (u32)f[1] : INT32_MAX;
  (void)w;
  return recv_try(e, (int)io_hand_v(f[0]), max, NULL, 0);
}
static void __attribute__((constructor)) recv_nb_use(void) {
  io_eff(CID_RECV_NB, recv_nb_run, 0);
}
#endif
#ifdef CID_SOCKET_DUP
Term socket_dup_run(Env e, Term *f, IoWork *w) {
  int fd = (int)io_hand_v(f[0]);
  int d;
  (void)w;
  d = dup(fd);
  if (d < 0)
    return io_tup(e, f[0], io_fail(e, (u32)errno, NULL));
  return io_tup(e, f[0], io_done(e, io_hand((u64)d)));
}
static void __attribute__((constructor)) socket_dup_use(void) {
  io_eff(CID_SOCKET_DUP, socket_dup_run, 0);
}
#endif
#ifdef CID_SOCKET_SHUTDOWN
Term socket_shutdown_run(Env e, Term *f, IoWork *w) {
  int fd = (int)io_hand_v(f[0]);
  (void)w;
  if (shutdown(fd, SHUT_RDWR) != 0)
    return io_tup(e, f[0], io_fail(e, (u32)errno, NULL));
  return io_tup(e, f[0], io_done(e, term_pak(CID_UNIT, 0)));
}
static void __attribute__((constructor)) socket_shutdown_use(void) {
  io_eff(CID_SOCKET_SHUTDOWN, socket_shutdown_run, 0);
}
#endif
#ifdef CID_SEND_OCTETS
Term send_octets_run(Env e, Term *f, IoWork *w) {
  uint8_t buf[512];
  size_t n = 0;
  int over = 0;
  Term xs = f[3], t[2];
  struct sockaddr_in dst;
  u64 hlen = 0;
  char *host = io_cstr(e, f[1], &hlen);
  ssize_t wr = -1;
  (void)w;
  memset(&dst, 0, sizeof dst);
  dst.sin_family = AF_INET;
  dst.sin_port = htons((uint16_t)(u32)f[2]);
  while (term_aux(xs) == CID_CON) {
    Loc sp = ctr_take(e, xs, 2, t);
    if (n < sizeof buf)
      buf[n++] = (uint8_t)(u32)t[0];
    else
      over = 1;
    xs = t[1];
    spare_free(e, cls_fit(2), sp);
  }
  int err = 0;
  if (over)
    err = EMSGSIZE;
  else if (!host || inet_pton(AF_INET, host, &dst.sin_addr) != 1)
    err = EINVAL;
  else {
    wr = sendto((int)io_hand_v(f[0]), buf, n, 0, (struct sockaddr *)&dst,
                (socklen_t)sizeof dst);
    if (wr < 0)
      err = errno ? errno : 1;
  }
  free(host);
  return io_tup(e, f[0], err != 0 ? io_fail(e, (u32)err, NULL)
                                  : io_done(e, term_pak(CID_UNIT, 0)));
}
static void __attribute__((constructor)) send_octets_use(void) {
  io_eff(CID_SEND_OCTETS, send_octets_run, 0);
}
#endif
#endif /* BIRC_DNS_FFI_C */
