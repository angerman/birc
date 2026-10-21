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
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include "bend_cid.h"
/* Owned sockets close-on-exec. SOCK_CLOEXEC when the platform has it;
 * otherwise F_SETFD after a plain socket (Darwin). */
static int birc_socket(int domain, int type, int protocol) {
  int fd;
#ifdef SOCK_CLOEXEC
  fd = socket(domain, type | SOCK_CLOEXEC, protocol);
#else
  fd = socket(domain, type, protocol);
#endif
  if (fd < 0)
    return -1;
#ifndef SOCK_CLOEXEC
  if (fcntl(fd, F_SETFD, FD_CLOEXEC) < 0) {
    int err = errno;
    (void)close(fd);
    errno = err;
    return -1;
  }
#endif
  return fd;
}

/* park=1: EAGAIN waits again (TCP reader). park=0: EAGAIN is None (DNS). */
static Term recv_fill(Env e, uint8_t *data, ssize_t n, const struct sockaddr_storage *src) {
  char host[INET6_ADDRSTRLEN];
  Term xs = term_pak(CID_NIL, 0);
  u64 i;
  u64 nn = (u64)n;
  u32 port = 0;
  host[0] = '\0';
  if (src->ss_family == AF_INET) {
    const struct sockaddr_in *v4 = (const struct sockaddr_in *)src;
    port = (u32)ntohs(v4->sin_port);
    (void)inet_ntop(AF_INET, &v4->sin_addr, host, (socklen_t)sizeof host);
  } else if (src->ss_family == AF_INET6) {
    const struct sockaddr_in6 *v6 = (const struct sockaddr_in6 *)src;
    port = (u32)ntohs(v6->sin6_port);
    (void)inet_ntop(AF_INET6, &v6->sin6_addr, host, (socklen_t)sizeof host);
  }
  for (i = nn; i > 0; i -= 1)
    xs = io_node(e, CID_CON, data[i - 1], xs);
  return io_done(e, io_box(e, CID_SOME,
                            io_tup(e, io_str(e, host, (u64)strlen(host)),
                                   io_tup(e, (Term)port, xs))));
}
static Term recv_more(Env e, IoWork *w);
static Term recv_try(Env e, int fd, u32 max, IoWork *w, int park) {
  uint8_t *data;
  struct sockaddr_storage src;
  socklen_t slen;
  ssize_t n;
  u32 code;
  Term r;
  /* One recv coalesces a burst into few UI cycles (fewer paints before a
   * trailing PING); the framer stays size-agnostic with overlong-drop. */
  if (max > 65536u)
    max = 65536u;
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
#ifndef CID_TCP_CONNECT_FOR
#define CID_TCP_CONNECT_FOR CID(TCP.connect_for)
#endif
#ifndef CID_TCP_SEND_FOR
#define CID_TCP_SEND_FOR CID(TCP.send_for)
#endif
#ifndef CID_SEND_OCTETS_FOR
#define CID_SEND_OCTETS_FOR CID(send_octets_for)
#endif
#ifndef CID_UDP_BIND6
#define CID_UDP_BIND6 CID(UDP.bind6)
#endif

#if CID_UDP_BIND6
/* IPv6 UDP bind. Base UDP.bind is AF_INET-only (io_sys_addr rejects
 * "::1" with EINVAL), so the v6 loopback probe binds here. v6 literals
 * only: v4 text and garbage fail EINVAL, like a family mismatch. The
 * owned socket stays nonblocking for life, like UDP.bind. */
Term udp_bind6_run(Env e, Term *f, IoWork *w) {
  struct sockaddr_in6 at;
  u64 len = 0;
  char *host = io_cstr(e, f[0], &len);
  int fd = -1;
  u32 err = EINVAL;
  int flags;
  (void)w;
  memset(&at, 0, sizeof at);
  if (host && strlen(host) == len && (u32)f[1] <= 65535u &&
      inet_pton(AF_INET6, host, &at.sin6_addr) == 1) {
    at.sin6_family = AF_INET6;
    at.sin6_port = htons((uint16_t)(u32)f[1]);
    fd = birc_socket(AF_INET6, SOCK_DGRAM, 0);
    err = fd < 0 ? (u32)errno : 0;
    if (fd >= 0 && bind(fd, (struct sockaddr *)&at, sizeof at) != 0) {
      err = (u32)errno;
      (void)close(fd);
      fd = -1;
    }
  }
  free(host);
  if (fd >= 0) {
    flags = fcntl(fd, F_GETFL);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) {
      err = (u32)errno;
      (void)close(fd);
      fd = -1;
    }
  }
  return fd < 0 ? io_fail(e, err != 0 ? err : 1u, NULL)
                : io_done(e, io_hand((u64)fd));
}
static void __attribute__((constructor)) udp_bind6_use(void) {
  io_eff(CID_UDP_BIND6, udp_bind6_run);
}
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
/* Owned nonblocking dial-trace sink (default-off test seam).
 * BIRC_DIAL_TRACE arms; BIRC_DIAL_TRACE_FD names the harness-owned
 * write pipe. Everything else is refused: unset/empty switch,
 * unparsable fd, stdio fds, non-FIFO, or a blocking fd (checked
 * read-only via F_GETFL -- inherited flags are NEVER mutated here).
 * One write() on a validated nonblocking FIFO is bounded; every
 * error (EAGAIN, EPIPE, EINTR) drops the marker instead of widening
 * the dial path. The harness configures O_NONBLOCK pre-fork and
 * drains promptly; the runtime ignores SIGPIPE, so a closed reader
 * surfaces as EPIPE, never a signal death. */
static void dial_trace_emit(void) {
  static const char mark[] = "native-setup-started\n";
  const char *on = getenv("BIRC_DIAL_TRACE");
  const char *fds;
  long fd;
  int flags;
  struct stat st;
  char *end = NULL;
  if (!on || !*on)
    return;
  fds = getenv("BIRC_DIAL_TRACE_FD");
  if (!fds || !*fds)
    return;
  errno = 0;
  fd = strtol(fds, &end, 10);
  if (errno != 0 || !end || *end != '\0' || fd <= 2 || fd > 1024 * 1024)
    return;
  flags = fcntl((int)fd, F_GETFL);
  if (flags < 0 || !(flags & O_NONBLOCK))
    return;
  if (fstat((int)fd, &st) != 0 || !S_ISFIFO(st.st_mode))
    return;
  (void)write((int)fd, mark, sizeof mark - 1);
}
Term tcp_connect_for_run(Env e, Term *f, IoWork *w) {
  struct sockaddr_storage dst;
  socklen_t dstlen = 0;
  u64 len = 0;
  char *host = io_cstr(e, f[0], &len);
  int fd = -1;
  int err = EINVAL;
  memset(&dst, 0, sizeof dst);
  if (host && strlen(host) == len && (u32)f[1] <= 65535u && (u32)f[2] != 0) {
    struct sockaddr_in *v4 = (struct sockaddr_in *)&dst;
    struct sockaddr_in6 *v6 = (struct sockaddr_in6 *)&dst;
    if (inet_pton(AF_INET, host, &v4->sin_addr) == 1) {
      v4->sin_family = AF_INET;
      v4->sin_port = htons((uint16_t)(u32)f[1]);
      dstlen = (socklen_t)sizeof *v4;
      fd = birc_socket(AF_INET, SOCK_STREAM, 0);
      err = fd < 0 ? errno : 0;
    } else if (inet_pton(AF_INET6, host, &v6->sin6_addr) == 1) {
      /* Inner literals only; callers strip parse_any brackets first. */
      v6->sin6_family = AF_INET6;
      v6->sin6_port = htons((uint16_t)(u32)f[1]);
      dstlen = (socklen_t)sizeof *v6;
      fd = birc_socket(AF_INET6, SOCK_STREAM, 0);
      err = fd < 0 ? errno : 0;
    }
  }
  free(host);
  if (fd >= 0) {
    int flags = fcntl(fd, F_GETFL);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0)
      err = errno;
    else if (connect(fd, (struct sockaddr *)&dst, dstlen) != 0)
      err = errno;
  }
  /* Actual native setup-start evidence (default-off test seam): the
   * connect() above issued the SYN. Gen-less by design (no actor
   * state here); the harness correlates by dial phase. The owned
   * sink refuses unbounded fds, so this never parks serial IO;
   * production output unchanged when unset. */
  if (err == 0 || err == EINPROGRESS || err == EWOULDBLOCK)
    dial_trace_emit();
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
  io_eff(CID_TCP_CONNECT_FOR, tcp_connect_for_run);
}
#endif

#if CID_TCP_SEND_FOR || CID_SEND_OCTETS_FOR
typedef struct {
  char *bytes;
  size_t size;
  size_t sent;
  u64 deadline;
  int datagram;
  struct sockaddr_storage dst;
  socklen_t dstlen;
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
                 (struct sockaddr *)&out->dst, out->dstlen);
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
  io_eff(CID_TCP_SEND_FOR, tcp_send_for_run);
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
    struct sockaddr_in *v4 = (struct sockaddr_in *)&out->dst;
    struct sockaddr_in6 *v6 = (struct sockaddr_in6 *)&out->dst;
    out->datagram = 1;
    if (inet_pton(AF_INET, host, &v4->sin_addr) == 1) {
      v4->sin_family = AF_INET;
      v4->sin_port = htons((uint16_t)(u32)f[2]);
      out->dstlen = (socklen_t)sizeof *v4;
    } else if (inet_pton(AF_INET6, host, &v6->sin6_addr) == 1) {
      v6->sin6_family = AF_INET6;
      v6->sin6_port = htons((uint16_t)(u32)f[2]);
      out->dstlen = (socklen_t)sizeof *v6;
    } else {
      err = EINVAL;
    }
  }
  free(host);
  return err != 0 ? birc_write_end(e, w, err) : birc_write_more(e, w);
}
static void __attribute__((constructor)) send_octets_for_use(void) {
  io_eff(CID_SEND_OCTETS_FOR, send_octets_for_run);
}
#endif

#if CID_RECV_OCTETS
Term recv_octets_run(Env e, Term *f, IoWork *w) {
  return recv_try(e, (int)io_hand_v(f[0]), (u32)f[1], w, 1);
}
static void __attribute__((constructor)) recv_octets_use(void) {
  io_eff(CID_RECV_OCTETS, recv_octets_run);
}
#endif
#if CID_RECV_NB
Term recv_nb_run(Env e, Term *f, IoWork *w) {
  (void)w;
  return recv_try(e, (int)io_hand_v(f[0]), (u32)f[1], NULL, 0);
}
static void __attribute__((constructor)) recv_nb_use(void) {
  io_eff(CID_RECV_NB, recv_nb_run);
}
#endif
#if CID_SOCKET_DUP
Term socket_dup_run(Env e, Term *f, IoWork *w) {
  int fd = (int)io_hand_v(f[0]);
  int d;
  (void)w;
  d = fcntl(fd, F_DUPFD_CLOEXEC, 0);
  if (d < 0)
    return io_tup(e, f[0], io_fail(e, (u32)errno, NULL));
  return io_tup(e, f[0], io_done(e, io_hand((u64)d)));
}
static void __attribute__((constructor)) socket_dup_use(void) {
  io_eff(CID_SOCKET_DUP, socket_dup_run);
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
  io_eff(CID_SOCKET_SHUTDOWN, socket_shutdown_run);
}
#endif
#endif /* BIRC_DNS_FFI_C */
