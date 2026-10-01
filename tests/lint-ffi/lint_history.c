/* Syntax-only check of the private append seam with the runtime stand-in. */
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE
#endif
#include "ffi_stub.h"
int io_nul(const char *s, u64 n);
Term io_work(IoWork *w, void (*call)(IoWork *), Term (*pack)(Env, IoWork *));
#include "history_ffi.c"
