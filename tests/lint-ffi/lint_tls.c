/* Syntax-only check of the verified TLS bridge. The Bend runtime prelude is
 * not present here; this stand-in matches the park-queue shape tls_ffi.c walks
 * (IoWork.next/item/time, io_park, io_runs). */
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE
#endif
#include <stddef.h>
#include <stdint.h>

typedef uint32_t u32;
typedef uint64_t u64;
typedef uint64_t Term;
typedef struct {
  int unused;
} Env;
typedef struct IoWork IoWork;
typedef Term (*IoPack)(Env e, IoWork *w);
struct IoWork {
  intptr_t hand;
  intptr_t made;
  u32 word;
  u64 size;
  char *data;
  char *text;
  u32 code;
  Term item;
  u64 time;
  IoWork *next;
};
typedef Term (*Effect)(Env e, Term *f, IoWork *w);

#define CID(name) 1u
#define IO_PARK (~(Term)0)
#define io_hand(v) ((Term)(v))
#define io_hand_v(t) ((u64)(t))
#define term_pak(cid, loc) ((Term)(((u64)(cid) << 48) | (u64)(loc)))

extern IoWork *io_park;
extern IoWork *io_runs;

char *io_cstr(Env e, Term s, u64 *len);
Term io_str(Env e, const char *p, u64 n);
Term io_node(Env e, u64 cid, Term a, Term b);
Term io_box(Env e, u64 cid, Term v);
Term io_tup(Env e, Term a, Term b);
Term io_done(Env e, Term v);
Term io_fail(Env e, u32 code, const char *text);
void io_eff(u32 cid, Effect run);
u64 io_tick(void);
Term io_wait_on(IoWork *w, int fd, short evts, uint64_t time, IoPack more);
void io_push(IoWork **queue, IoWork *work);

#include "tls_ffi.c"
