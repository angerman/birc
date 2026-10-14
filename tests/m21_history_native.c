/* SPDX-License-Identifier: Apache-2.0
 * Actual private append core and FFI ownership, using synthetic files only. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include "lint-ffi/ffi_stub.h"

enum { NORMAL, STAT_FAIL, OWNER_FAIL, MODE_FAIL, INTERRUPT_PARTIAL,
       ZERO_WRITE, WRITE_FAIL, CLOSE_FAIL };
static int mode, writes, closes, chmods;
static int fail_allocation, consumed[2], cstrings, released[3];
static void *owned[3];
static const char *fixture_path;

static int probe_open(const char *path, int flags, mode_t permissions) {
  return open(path, flags, permissions);
}
static int probe_stat(int fd, struct stat *info) {
  if (mode == STAT_FAIL) { errno = EIO; return -1; }
  if (fstat(fd, info) != 0) return -1;
  if (mode == OWNER_FAIL) info->st_uid = (uid_t)(geteuid() == 0 ? 1 : 0);
  return 0;
}
static int probe_chmod(int fd, mode_t permissions) {
  chmods++;
  if (mode == MODE_FAIL) { errno = EPERM; return -1; }
  return fchmod(fd, permissions);
}
static ssize_t probe_write(int fd, const void *bytes, size_t size) {
  struct stat info;
  writes++;
  if (fstat(fd, &info) != 0 || (info.st_mode & 0777) != 0600) abort();
  if (mode == INTERRUPT_PARTIAL && writes == 1) { errno = EINTR; return -1; }
  if (mode == INTERRUPT_PARTIAL && writes == 2 && size > 2) size = 2;
  if (mode == ZERO_WRITE) return 0;
  if (mode == WRITE_FAIL && writes == 1 && size > 2) size = 2;
  else if (mode == WRITE_FAIL) { errno = ENOSPC; return -1; }
  return write(fd, bytes, size);
}
static int probe_close(int fd) {
  int result;
  closes++;
  result = close(fd);
  if (mode == CLOSE_FAIL) { errno = EIO; return -1; }
  return result;
}
static void *probe_calloc(size_t count, size_t size) {
  owned[2] = fail_allocation ? NULL : calloc(count, size);
  return owned[2];
}
static void probe_free(void *pointer) {
  size_t index;
  if (pointer) {
    for (index = 0; index < 3; index++) {
      if (pointer == owned[index]) {
        released[index]++;
        owned[index] = NULL;
      }
    }
  }
  free(pointer);
}
static size_t argument(Term term) {
  if (term == 17) return 0;
  if (term == 34) return 1;
  abort();
}
void term_sink(Env e, Term term) { (void)e; consumed[argument(term)]++; }
char *io_cstr(Env e, Term term, u64 *size) {
  size_t index = argument(term);
  const char *text = index == 0 ? fixture_path : "fixture\n";
  (void)e;
  consumed[index]++; cstrings++;
  *size = (u64)strlen(text);
  owned[index] = malloc((size_t)*size + 1);
  if (!owned[index]) abort();
  memcpy(owned[index], text, (size_t)*size + 1);
  return owned[index];
}
Term io_tup(Env e, Term first, Term second) { (void)e; return (first << 32) | second; }
void io_eff(u32 cid, Effect run) { (void)cid; (void)run; }
/* Run the actual helper callback synchronously, then the actual owning pack. */
static Term io_work(IoWork *work, void (*call)(IoWork *), Term (*pack)(Env, IoWork *)) {
  Env env = {NULL, NULL};
  call(work);
  return pack(env, work);
}
#define io_nul(s, n) (strlen(s) != (n))
#define open probe_open
#define fstat probe_stat
#define fchmod probe_chmod
#define write probe_write
#define close probe_close
#define calloc probe_calloc
#define free probe_free
#include "../src/ffi/history_ffi.c"
#undef open
#undef fstat
#undef fchmod
#undef write
#undef close
#undef calloc
#undef free

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "m21_history_native:%d: %s\n", __LINE__, #x); return 1; } } while (0)
static BircHistoryResult append(const char *path, int failure) {
  mode = failure; writes = 0; closes = 0; chmods = 0;
  return birc_history_append(path, "fixture\n", 8);
}
static int content(const char *path, const char *wanted) {
  char bytes[128];
  int fd = open(path, O_RDONLY);
  ssize_t size;
  CHECK(fd >= 0);
  size = read(fd, bytes, sizeof bytes);
  CHECK(close(fd) == 0);
  CHECK(size >= 0 && (size_t)size == strlen(wanted));
  CHECK(memcmp(bytes, wanted, (size_t)size) == 0);
  return 0;
}
static int core(const char *root) {
  char path[256], link[256], fifo[256];
  struct stat info;
  BircHistoryResult result;
  int fd, reader;
  CHECK(snprintf(path, sizeof path, "%s/history", root) > 0);
  CHECK(snprintf(link, sizeof link, "%s/link", root) > 0);
  CHECK(snprintf(fifo, sizeof fifo, "%s/fifo", root) > 0);
  fd = open(path, O_CREAT | O_WRONLY, 0644);
  CHECK(fd >= 0 && write(fd, "retained\n", 9) == 9 && close(fd) == 0);
  CHECK(chmod(path, 0644) == 0);
  result = append(path, INTERRUPT_PARTIAL);
  CHECK(result.stage == 0 && result.code == 0 && writes == 3 && closes == 1 && chmods == 1);
  CHECK(stat(path, &info) == 0 && (info.st_mode & 0777) == 0600);
  CHECK(content(path, "retained\nfixture\n") == 0);
  CHECK(chmod(path, 0644) == 0);
  result = append(path, MODE_FAIL);
  CHECK(result.stage == 1 && result.code == EPERM && writes == 0 && closes == 1);
  CHECK(stat(path, &info) == 0 && (info.st_mode & 0777) == 0644);
  CHECK(content(path, "retained\nfixture\n") == 0);
  result = append(path, STAT_FAIL);
  CHECK(result.stage == 1 && result.code == EIO && writes == 0 && closes == 1 && chmods == 0);
  result = append(path, OWNER_FAIL);
  CHECK(result.stage == 1 && result.code == EPERM && writes == 0 && closes == 1 && chmods == 0);
  CHECK(content(path, "retained\nfixture\n") == 0);
  result = append(path, ZERO_WRITE);
  CHECK(result.stage == 2 && result.code == EIO && writes == 1 && closes == 1);
  CHECK(content(path, "retained\nfixture\n") == 0);
  result = append(path, WRITE_FAIL);
  CHECK(result.stage == 2 && result.code == ENOSPC && writes == 2 && closes == 1);
  CHECK(content(path, "retained\nfixture\nfi") == 0);
  result = append(path, CLOSE_FAIL);
  CHECK(result.stage == 2 && result.code == EIO && writes == 1 && closes == 1);
  CHECK(content(path, "retained\nfixture\nfifixture\n") == 0);
  CHECK(symlink(path, link) == 0);
  result = append(link, NORMAL);
  CHECK(result.stage == 1 && result.code != 0 && writes == 0 && chmods == 0);
  CHECK(content(path, "retained\nfixture\nfifixture\n") == 0);
  CHECK(mkfifo(fifo, 0600) == 0);
  reader = open(fifo, O_RDONLY | O_NONBLOCK);
  CHECK(reader >= 0);
  result = append(fifo, NORMAL);
  CHECK(result.stage == 1 && result.code == EPERM && writes == 0 && closes == 1 && chmods == 0);
  CHECK(close(reader) == 0);
  result = append(root, NORMAL);
  CHECK(result.stage == 1 && result.code != 0 && writes == 0 && chmods == 0);
  CHECK(unlink(fifo) == 0 && unlink(link) == 0 && unlink(path) == 0);
  return 0;
}
static int ownership(const char *root) {
  char path[256];
  struct stat info;
  Env env = {NULL, NULL};
  IoWork work = {0};
  Term fields[2] = {17, 34}, result;
  CHECK(snprintf(path, sizeof path, "%s/ffi", root) > 0);
  fixture_path = path;
  mode = NORMAL;
  result = history_append_private_run(env, fields, &work);
  CHECK(result == 0 && !work.data && cstrings == 2);
  CHECK(consumed[0] == 1 && consumed[1] == 1);
  CHECK(released[0] == 1 && released[1] == 1 && released[2] == 1);
  CHECK(stat(path, &info) == 0 && (info.st_mode & 0777) == 0600);
  CHECK(content(path, "fixture\n") == 0);
  memset(consumed, 0, sizeof consumed); memset(released, 0, sizeof released);
  memset(owned, 0, sizeof owned); cstrings = 0;
  fail_allocation = 1;
  result = history_append_private_run(env, fields, &work);
  CHECK((result >> 32) == 1 && (uint32_t)result == ENOMEM && !work.data);
  CHECK(cstrings == 0);
  CHECK(consumed[0] == 1 && consumed[1] == 1);
  CHECK(released[0] == 0 && released[1] == 0 && released[2] == 0);
  CHECK(content(path, "fixture\n") == 0);
  CHECK(unlink(path) == 0);
  return 0;
}
int main(void) {
  char root[] = "/tmp/birc-history-native-XXXXXX";
  CHECK(mkdtemp(root) != NULL);
  CHECK(core(root) == 0);
  CHECK(ownership(root) == 0);
  CHECK(rmdir(root) == 0);
  puts("m21_history_native=ok");
  return 0;
}
