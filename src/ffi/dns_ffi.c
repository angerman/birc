/* UDP recv as octets (0..255). Base UDP.recv_from is a String (WHATWG
 * io_str), so A rdata 0x80–0xC1 cannot be recovered. Non-blocking;
 * None means EAGAIN. Bend owns encode/send/parse. */
#ifndef BIRC_DNS_FFI_C
#define BIRC_DNS_FFI_C

#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200112L
#endif

#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/types.h>

#ifdef CID_RECV_OCTETS
Term recv_octets_run(Env e, Term *f, IoWork *w) {
  int fd = (int)io_hand_v(f[0]);
  u32 max = f[1] < INT32_MAX ? (u32)f[1] : INT32_MAX;
  uint8_t *data = io_mem(malloc((size_t)max + 1u));
  ssize_t n;
  u32 code;
  Term r;
  (void)w;
  n = recvfrom(fd, data, (size_t)max, 0, NULL, NULL);
  code = n < 0 ? (u32)errno : 0;
  if (code == (u32)EAGAIN || code == (u32)EWOULDBLOCK) {
    r = io_done(e, term_pak(CID_NONE, 0));
  } else if (code != 0) {
    r = io_fail(e, code, NULL);
  } else {
    Term xs = term_pak(CID_NIL, 0);
    u64 i;
    for (i = (u64)n; i > 0; i -= 1)
      xs = io_node(e, CID_CON, data[i - 1], xs);
    r = io_done(e, io_box(e, CID_SOME, xs));
  }
  free(data);
  return io_tup(e, f[0], r);
}

static void __attribute__((constructor)) recv_octets_use(void) {
  io_eff(CID_RECV_OCTETS, recv_octets_run, 0);
}
#endif

#endif /* BIRC_DNS_FFI_C */
