/* Syntax-only check of launch-owned auth pipes with the runtime stand-in. */
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE
#endif
#include "ffi_stub.h"
Term io_work(IoWork *w, void (*call)(IoWork *), Term (*pack)(Env, IoWork *));
#include "auth_bridge_ffi.c"
