/* UDP recv as octets (0..255). Base UDP.recv_from is a String (WHATWG
 * io_str), so A rdata 0x80–0xC1 cannot be recovered. Non-blocking;
 * None means EAGAIN/EINTR. Returns peer host+port beside the octets.
 * Bend owns encode/send/parse. send_octets is the outbound twin. */
#ifndef BIRC_DNS_FFI_C
#define BIRC_DNS_FFI_C
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
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
#ifndef CID_RECV_OCTETS
#define CID_RECV_OCTETS CID(recv_octets)
#endif
#ifndef CID_RECV_NB
#define CID_RECV_NB CID(recv_nb)
#endif
#ifndef CID_SOCKET_DUP
#define CID_SOCKET_DUP CID(Socket.dup)
#endif
#ifndef CID_SOCKET_SHUTDOWN
#define CID_SOCKET_SHUTDOWN CID(Socket.shutdown)
#endif
#ifndef CID_SEND_OCTETS
#define CID_SEND_OCTETS CID(send_octets)
#endif
#ifndef CID_TCP_CONNECT_FOR
#define CID_TCP_CONNECT_FOR CID(TCP.connect_for)
#endif
#ifndef CID_TCP_SEND_FOR
#define CID_TCP_SEND_FOR CID(TCP.send_for)
#endif
#ifndef CID_SEND_OCTETS_FOR
#define CID_SEND_OCTETS_FOR CID(send_octets_for)
#endif

#if CID_TCP_CONNECT_FOR
/* Unlike a raced IO.within, this operation closes its own descriptor when
 * its absolute deadline expires. The socket stays nonblocking for life. */
static Term tcp_connect_for_more(Env e, IoWork *w) {
  int fd = (int)w->hand;
  int err = 0;
  socklen_t len = (socklen_t)sizeof err;
  if (io_tick() >= w->size)
    err = ETIMEDOUT;
  else if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len) != 0)
    err = errno;
  if (err != 0) {
    (void)close(fd);
    return io_fail(e, (u32)err, NULL);
  }
  return io_done(e, io_hand((u64)fd));
}
Term tcp_connect_for_run(Env e, Term *f, IoWork *w) {
  struct sockaddr_in dst;
  u64 len = 0;
  char *host = io_cstr(e, f[0], &len);
  int fd = -1;
  int err = EINVAL;
  memset(&dst, 0, sizeof dst);
  dst.sin_family = AF_INET;
  dst.sin_port = htons((uint16_t)(u32)f[1]);
  if (host && strlen(host) == len && (u32)f[1] <= 65535u &&
      (u32)f[2] != 0 && inet_pton(AF_INET, host, &dst.sin_addr) == 1) {
    fd = socket(AF_INET, SOCK_STREAM, 0);
    err = fd < 0 ? errno : 0;
  }
  free(host);
  if (fd >= 0) {
    int flags = fcntl(fd, F_GETFL);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0)
      err = errno;
    else if (connect(fd, (struct sockaddr *)&dst, (socklen_t)sizeof dst) != 0)
      err = errno;
  }
  if (err == EINPROGRESS || err == EWOULDBLOCK || err == EINTR) {
    w->hand = (intptr_t)fd;
    w->size = io_tick() + (u64)(u32)f[2] * 1000000ull;
    return io_wait_on(w, fd, POLLOUT, w->size, tcp_connect_for_more);
  }
  if (err != 0 && fd >= 0)
    (void)close(fd);
  return err != 0 ? io_fail(e, (u32)err, NULL)
                  : io_done(e, io_hand((u64)fd));
}
static void __attribute__((constructor)) tcp_connect_for_use(void) {
  io_eff(CID_TCP_CONNECT_FOR, tcp_connect_for_run, 0);
}
#endif

#if CID_TCP_SEND_FOR || CID_SEND_OCTETS_FOR
typedef struct {
  char *bytes;
  size_t size;
  size_t sent;
  u64 deadline;
  int datagram;
  struct sockaddr_in dst;
} BircWrite;

static Term birc_write_end(Env e, IoWork *w, u32 code) {
  BircWrite *out = (BircWrite *)w->data;
  free(out->bytes);
  free(out);
  w->data = NULL;
  return io_tup(e, io_hand((u64)w->hand),
                code != 0 ? io_fail(e, code, NULL)
                          : io_done(e, term_pak(CID_UNIT, 0)));
}

/* Retain the offset across short TCP writes. Datagrams go whole or fail.
 * Each retry checks one absolute deadline; EAGAIN never extends it. */
static Term birc_write_more(Env e, IoWork *w) {
  BircWrite *out = (BircWrite *)w->data;
  int fd = (int)w->hand;
  while (out->sent < out->size) {
    ssize_t n;
    if (io_tick() >= out->deadline)
      return birc_write_end(e, w, (u32)ETIMEDOUT);
    if (out->datagram)
      n = sendto(fd, out->bytes, out->size, 0,
                 (struct sockaddr *)&out->dst, (socklen_t)sizeof out->dst);
    else
      n = send(fd, out->bytes + out->sent, out->size - out->sent, 0);
    if (n < 0) {
      int err = errno;
      if (err == EAGAIN || err == EWOULDBLOCK || err == EINTR)
        return io_wait_on(w, fd, POLLOUT, out->deadline, birc_write_more);
      return birc_write_end(e, w, (u32)err);
    }
    if (n == 0 || (out->datagram && (size_t)n != out->size))
      return birc_write_end(e, w, (u32)EIO);
    out->sent += (size_t)n;
  }
  return birc_write_end(e, w, 0);
}

static BircWrite *birc_write_new(IoWork *w, u32 timeout_ms) {
  BircWrite *out = (BircWrite *)calloc(1, sizeof *out);
  if (!out)
    return NULL;
  out->deadline = io_tick() + (u64)timeout_ms * 1000000ull;
  w->data = (char *)out;
  return out;
}
#endif

#if CID_TCP_SEND_FOR
Term tcp_send_for_run(Env e, Term *f, IoWork *w) {
  u64 len = 0;
  BircWrite *out;
  w->hand = (intptr_t)io_hand_v(f[0]);
  if ((u32)f[2] == 0)
    return io_tup(e, f[0], io_fail(e, EINVAL, NULL));
  out = birc_write_new(w, (u32)f[2]);
  if (!out)
    return io_tup(e, f[0], io_fail(e, ENOMEM, NULL));
  out->bytes = io_cstr(e, f[1], &len);
  out->size = (size_t)len;
  if (!out->bytes)
    return birc_write_end(e, w, ENOMEM);
  return birc_write_more(e, w);
}
static void __attribute__((constructor)) tcp_send_for_use(void) {
  io_eff(CID_TCP_SEND_FOR, tcp_send_for_run, 0);
}
#endif

#if CID_SEND_OCTETS_FOR
Term send_octets_for_run(Env e, Term *f, IoWork *w) {
  Term xs = f[3], t[2];
  u64 hlen = 0;
  char *host = io_cstr(e, f[1], &hlen);
  BircWrite *out;
  u32 err = 0;
  w->hand = (intptr_t)io_hand_v(f[0]);
  out = birc_write_new(w, (u32)f[4]);
  if (!out) {
    free(host);
    term_sink(e, xs);
    return io_tup(e, f[0], io_fail(e, ENOMEM, NULL));
  }
  out->bytes = (char *)malloc(512u);
  if (!out->bytes)
    err = ENOMEM;
  while (term_aux(xs) == CID_CON) {
    u64 sp = ctr_take(e, xs, 2, t);
    if ((u32)t[0] > 255u)
      err = EINVAL;
    else if (out->size >= 512u)
      err = EMSGSIZE;
    else if (out->bytes)
      out->bytes[out->size++] = (char)(uint8_t)(u32)t[0];
    xs = t[1];
    spare_free(e, cls_fit(2), sp);
  }
  if (!host || strlen(host) != hlen || (u32)f[2] > 65535u || (u32)f[4] == 0)
    err = EINVAL;
  else if (host[0] != '\0') {
    out->datagram = 1;
    out->dst.sin_family = AF_INET;
    out->dst.sin_port = htons((uint16_t)(u32)f[2]);
    if (inet_pton(AF_INET, host, &out->dst.sin_addr) != 1)
      err = EINVAL;
  }
  free(host);
  return err != 0 ? birc_write_end(e, w, err) : birc_write_more(e, w);
}
static void __attribute__((constructor)) send_octets_for_use(void) {
  io_eff(CID_SEND_OCTETS_FOR, send_octets_for_run, 0);
}
#endif

#if CID_RECV_OCTETS
Term recv_octets_run(Env e, Term *f, IoWork *w) {
  return recv_try(e, (int)io_hand_v(f[0]), (u32)f[1], w, 1);
}
static void __attribute__((constructor)) recv_octets_use(void) {
  io_eff(CID_RECV_OCTETS, recv_octets_run, IO_READ);
}
#endif
#if CID_RECV_NB
Term recv_nb_run(Env e, Term *f, IoWork *w) {
  (void)w;
  return recv_try(e, (int)io_hand_v(f[0]), (u32)f[1], NULL, 0);
}
static void __attribute__((constructor)) recv_nb_use(void) {
  io_eff(CID_RECV_NB, recv_nb_run, 0);
}
#endif
#if CID_SOCKET_DUP
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
#if CID_SOCKET_SHUTDOWN
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
#if CID_SEND_OCTETS
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
    u64 sp = ctr_take(e, xs, 2, t);
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
  else if (!host || (host[0] != '\0' && inet_pton(AF_INET, host, &dst.sin_addr) != 1))
    err = EINVAL;
  else if (host[0] == '\0') {
    wr = send((int)io_hand_v(f[0]), buf, n, 0);
    if (wr < 0)
      err = errno ? errno : 1;
  } else {
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
