/* Minimal stand-in for the Bend runtime prelude so the project's own FFI
 * .c files can be compiled with warnings on. */
#ifndef BIRC_FFI_STUB_H
#define BIRC_FFI_STUB_H
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

typedef uint32_t u32;
typedef uint64_t u64;
typedef uint8_t u8;
typedef uint64_t Term;
typedef uint64_t Loc;
typedef uint32_t Cls;
typedef Term *Corpus;

typedef struct {
  Corpus mem;
  u64 *alc;
} Env;

typedef struct IoWork {
  intptr_t hand;
  intptr_t made;
  u32 word;
  u64 size;
  char *data;
  char *text;
  u32 code;
} IoWork;

typedef Term (*Effect)(Env e, Term *f, IoWork *w);

#define CID_UNIT 1u
#define CID_NONE 2u
#define CID_SOME 3u
#define CID_NIL 4u
#define CID_CON 5u
#define CID_UIKEYS 6u
#define CID_TIMUI_OPEN 7u
#define CID_TIMUI_FRAME 8u
#define CID_TIMUI_CLOSE 9u
#define CID_HHMMSS 10u
#define CID_LOCAL_SECS 12u
#define CID_RECV_OCTETS 11u
#define CID_VIEW_OPHEADER 13u
#define CID_VIEW_OPTABS 14u
#define CID_VIEW_OPBODY 15u
#define CID_VIEW_OPNICKS 16u
#define CID_VIEW_OPSTATUS 17u
#define CID_VIEW_BODYLN 18u
#define CID_VIEW_SPN 19u
#define CID_VIEW_LNK 20u
#define CID_VIEW_RECT 21u
#ifndef THR
#define THR
#endif
u64 term_aux(Term t);
Loc ctr_take(Env e, Term t, u32 n, Term *out);
void spare_free(Env e, Cls cls, Loc loc);

#define term_ctr(cid, loc) ((Term)(((u64)(cid) << 48) | (u64)(loc)))
#define term_pak(cid, loc) ((Term)(((u64)(cid) << 48) | (u64)(loc)))
#define io_hand(v) ((Term)(v))
#define io_hand_v(t) ((u64)(t))
#define io_seal(e, t, cid) ((void)(e), (void)(cid), (t))

Cls cls_fit(u32 words);
Loc heap_alloc(Env e, Cls cls);
void *io_mem(void *mem);
char *io_cstr(Env e, Term s, u64 *len);
Term io_str(Env e, const char *p, u64 n);
Term io_node(Env e, u64 cid, Term a, Term b);
Term io_box(Env e, u64 cid, Term v);
Term io_tup(Env e, Term a, Term b);
Term io_done(Env e, Term v);
Term io_fail(Env e, u32 code, const char *text);
void io_eff(u32 cid, Effect run, u32 need);

#endif
