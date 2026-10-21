/* Syntax-only check of the image/card fetch seam. */
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE
#endif
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE
#endif
#include "ffi_stub.h"
int io_nul(const char *s, u64 n);
Term io_work(IoWork *w, void (*call)(IoWork *), Term (*pack)(Env, IoWork *));
#include "media_fetch_ffi.c"
