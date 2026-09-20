/* Bend DNS lookup — getaddrinfo A (IPv4 dotted quad).
 * UDP String recv cannot recover wire bytes 0x80–0xC1 (WHATWG U+FFFD),
 * so live resolve cannot parse many real A records (e.g. irc.libera.chat).
 * Include-guarded: Bend inlines this via lookup_a. */
#ifndef BIRC_DNS_FFI_C
#define BIRC_DNS_FFI_C

#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200112L
#endif

#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/in.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>

#ifdef CID_LOOKUP_A
Term lookup_a_run(Env e, Term *f, IoWork *w) {
  uint64_t n = 0;
  char *host = io_cstr(e, f[0], &n);
  struct addrinfo hints;
  struct addrinfo *res = NULL;
  struct sockaddr_in *in;
  char ip[INET_ADDRSTRLEN];
  int rc;
  (void)w;
  if (!host)
    return io_fail(e, 1u, "dns");
  memset(&hints, 0, sizeof hints);
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  rc = getaddrinfo(host, NULL, &hints, &res);
  free(host);
  if (rc != 0 || res == NULL || res->ai_addr == NULL) {
    if (res)
      freeaddrinfo(res);
    return io_fail(e, 1u, "dns");
  }
  in = (struct sockaddr_in *)(void *)res->ai_addr;
  if (inet_ntop(AF_INET, &in->sin_addr, ip, sizeof ip) == NULL) {
    freeaddrinfo(res);
    return io_fail(e, 1u, "dns");
  }
  freeaddrinfo(res);
  return io_done(e, io_str(e, ip, strlen(ip)));
}

static void __attribute__((constructor)) lookup_a_use(void) {
  io_eff(CID_LOOKUP_A, lookup_a_run, 0);
}
#endif

#endif
