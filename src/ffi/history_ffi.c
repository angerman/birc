/* SPDX-License-Identifier: Apache-2.0
 * Scoped private history append. No global umask or path-based chmod. */
#ifndef BIRC_HISTORY_FFI_C
#define BIRC_HISTORY_FFI_C

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct {
  uint32_t stage; /* 0 success, 1 open/policy, 2 write/close */
  uint32_t code;
} BircHistoryResult;

static BircHistoryResult birc_history_append(const char *path,
                                            const char *bytes, size_t size) {
  BircHistoryResult result = {1u, 0u};
  struct stat info;
  int fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC
                     | O_NOFOLLOW | O_NONBLOCK, 0600);
  if (fd < 0) {
    result.code = (uint32_t)errno;
    return result;
  }
  if (fstat(fd, &info) != 0) {
    result.code = (uint32_t)errno;
  } else if (!S_ISREG(info.st_mode) || info.st_uid != geteuid()) {
    result.code = (uint32_t)EPERM;
  } else if (fchmod(fd, 0600) != 0) {
    result.code = (uint32_t)errno;
  } else {
    size_t offset = 0;
    result.stage = 2u;
    while (offset < size) {
      ssize_t written = write(fd, bytes + offset, size - offset);
      if (written < 0) {
        if (errno == EINTR)
          continue;
        result.code = (uint32_t)errno;
        break;
      }
      if (written == 0) {
        result.code = (uint32_t)EIO;
        break;
      }
      offset += (size_t)written;
    }
  }
  if (close(fd) != 0 && result.code == 0)
    result.code = (uint32_t)errno;
  if (result.code == 0)
    result.stage = 0u;
  return result;
}

#ifndef BIRC_HISTORY_CORE_ONLY
#ifndef CID_APPEND_PRIVATE
#define CID_APPEND_PRIVATE CID(append_private)
#endif
#if CID_APPEND_PRIVATE
typedef struct {
  char *path;
  char *bytes;
  size_t size;
} BircHistoryAppend;

static void history_append_private_call(IoWork *w) {
  BircHistoryAppend *request = (BircHistoryAppend *)w->data;
  BircHistoryResult result = birc_history_append(request->path, request->bytes,
                                                request->size);
  w->word = result.stage;
  w->code = result.code;
}

static Term history_append_private_pack(Env e, IoWork *w) {
  BircHistoryAppend *request = (BircHistoryAppend *)w->data;
  if (request) {
    free(request->path);
    free(request->bytes);
    free(request);
  }
  w->data = NULL;
  return io_tup(e, (Term)w->word, (Term)(uint32_t)w->code);
}

Term history_append_private_run(Env e, Term *f, IoWork *w) {
  uint64_t path_size = 0, data_size = 0;
  BircHistoryAppend *request = (BircHistoryAppend *)calloc(1, sizeof *request);
  w->data = (char *)request;
  w->word = 1u;
  if (!request) {
    term_sink(e, f[0]);
    term_sink(e, f[1]);
    w->code = ENOMEM;
    return history_append_private_pack(e, w);
  }
  request->path = io_cstr(e, f[0], &path_size);
  request->bytes = io_cstr(e, f[1], &data_size);
  if (!request->path || !request->bytes) {
    w->code = ENOMEM;
    return history_append_private_pack(e, w);
  }
  if (data_size > SIZE_MAX || io_nul(request->path, path_size)) {
    w->code = data_size > SIZE_MAX ? EOVERFLOW : EILSEQ;
    return history_append_private_pack(e, w);
  }
  request->size = (size_t)data_size;
  return io_work(w, history_append_private_call, history_append_private_pack);
}

static void __attribute__((constructor)) history_append_private_use(void) {
  io_eff(CID_APPEND_PRIVATE, history_append_private_run);
}
#endif
#endif /* BIRC_HISTORY_CORE_ONLY */
#endif /* BIRC_HISTORY_FFI_C */
