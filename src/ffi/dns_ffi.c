/* UDP recv as octets (0..255). Base UDP.recv_from is a String (WHATWG
 * io_str), so A rdata 0x80–0xC1 cannot be recovered. Non-blocking;
 * None means EAGAIN/EINTR. Returns peer host+port beside the octets.
 * Bend owns encode/send/parse. */
#ifndef BIRC_DNS_FFI_C
#define BIRC_DNS_FFI_C

#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200112L
#endif

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

#endif /* BIRC_DNS_FFI_C */
