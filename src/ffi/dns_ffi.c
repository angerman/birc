/* UDP recv as octets (0..255). Base UDP.recv_from is a String (WHATWG
 * io_str), so A rdata 0x80–0xC1 cannot be recovered. Non-blocking;
 * None means EAGAIN/EINTR. Returns peer host+port beside the octets.
 * Bend owns encode/send/parse. send_octets is the outbound twin. */
#ifndef BIRC_DNS_FFI_C
#define BIRC_DNS_FFI_C
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#ifdef CID_RECV_OCTETS
Term recv_octets_run(Env e, Term *f, IoWork *w) {
  int fd = (int)io_hand_v(f[0]);
  u32 max = f[1] < INT32_MAX ? (u32)f[1] : INT32_MAX;
  uint8_t *data;
  struct sockaddr_in src;
  socklen_t slen;
  ssize_t n;
  u32 code;
  Term r;
  (void)w;
  if (max > 4096u)
    max = 4096u;
  data = io_mem(malloc((size_t)max + 1u));
  memset(&src, 0, sizeof src);
  slen = (socklen_t)sizeof src;
  n = recvfrom(fd, data, (size_t)max, 0, (struct sockaddr *)&src, &slen);
  code = n < 0 ? (u32)errno : 0;
  if (code == (u32)EAGAIN || code == (u32)EWOULDBLOCK || code == (u32)EINTR) {
    r = io_done(e, term_pak(CID_NONE, 0));
  } else if (code != 0 || n < 0) {
    r = io_fail(e, code != 0 ? code : 1u, NULL);
  } else {
    char host[INET_ADDRSTRLEN];
    Term xs = term_pak(CID_NIL, 0);
    u64 i;
    u64 nn = (u64)n;
    u32 port = (u32)ntohs(src.sin_port);
    host[0] = '\0';
    if (src.sin_family == AF_INET)
      (void)inet_ntop(AF_INET, &src.sin_addr, host, (socklen_t)sizeof host);
    for (i = nn; i > 0; i -= 1)
      xs = io_node(e, CID_CON, data[i - 1], xs);
    r = io_done(e, io_box(e, CID_SOME,
                          io_tup(e, io_str(e, host, (u64)strlen(host)),
                                 io_tup(e, (Term)port, xs))));
  }
  free(data);
  return io_tup(e, f[0], r);
}
static void __attribute__((constructor)) recv_octets_use(void) {
  io_eff(CID_RECV_OCTETS, recv_octets_run, 0);
}
#endif
#ifdef CID_FD_HINT
Term fd_hint_run(Env e, Term *f, IoWork *w) {
  uint32_t fd = (uint32_t)io_hand_v(f[0]);
  (void)w;
  return io_tup(e, f[0], (Term)(uint64_t)fd);
}
static void __attribute__((constructor)) fd_hint_use(void) {
  io_eff(CID_FD_HINT, fd_hint_run, 0);
}
#endif
#ifdef CID_SEND_OCTETS
Term send_octets_run(Env e, Term *f, IoWork *w) {
  uint8_t buf[512];
  size_t n = 0;
  Term xs = f[3], t[2];
  struct sockaddr_in dst;
  u64 hlen = 0;
  char *host = io_cstr(e, f[1], &hlen);
  ssize_t wr = -1;
  (void)w;
  memset(&dst, 0, sizeof dst);
  dst.sin_family = AF_INET;
  dst.sin_port = htons((uint16_t)(u32)f[2]);
  while (n < sizeof buf && term_aux(xs) == CID_CON) {
    Loc sp = ctr_take(e, xs, 2, t);
    buf[n++] = (uint8_t)(u32)t[0];
    xs = t[1];
    spare_free(e, cls_fit(2), sp);
  }
  if (host && inet_pton(AF_INET, host, &dst.sin_addr) == 1)
    wr = sendto((int)io_hand_v(f[0]), buf, n, 0, (struct sockaddr *)&dst,
                (socklen_t)sizeof dst);
  free(host);
  return io_tup(e, f[0], wr < 0 ? io_fail(e, errno ? (u32)errno : 1u, NULL)
                               : io_done(e, term_pak(CID_UNIT, 0)));
}
static void __attribute__((constructor)) send_octets_use(void) {
  io_eff(CID_SEND_OCTETS, send_octets_run, 0);
}
#endif
#endif /* BIRC_DNS_FFI_C */
