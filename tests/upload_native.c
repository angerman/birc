/* SPDX-License-Identifier: Apache-2.0
 * Native upload admission and URL oracles. No public 0x0.st contact. */
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define BIRC_UPLOAD_CORE_ONLY
#include "../src/ffi/upload_ffi.c"

static void must(int ok, const char *label) {
  if (!ok) {
    fprintf(stderr, "upload_native: %s\n", label);
    exit(1);
  }
}

int main(void) {
  char url[128];
  char *out = NULL;
  uint32_t http = 0;
  char path[] = "/tmp/birc-upload-native-XXXXXX";
  int fd;
  must(!birc_up_public_address("2002:0102:0304::1"), "6to4");
  must(!birc_up_public_address("2001:0000::1"), "teredo");
  must(birc_up_public_address("2001:4860:4860::8888"), "public v6");
  must(birc_upload_checked_url("https://0x0.st/s/secret/abc.png\n", 31, url, sizeof url), "good url");
  must(strcmp(url, "https://0x0.st/s/secret/abc.png") == 0, "strip newline");
  must(!birc_upload_checked_url("https://evil.example/x\n", 23, url, sizeof url), "foreign origin");
  must(!birc_upload_checked_url("https://0x0.st/../x\n", 20, url, sizeof url), "dotdot");
  must(!birc_upload_checked_url("https://0x0.st//x\n", 18, url, sizeof url), "empty part");
  must(birc_upload_run("", &out, &http) == 1 && out == NULL, "empty path");
  must(birc_upload_run("/no/such/birc-upload-file", &out, &http) == 2 && out == NULL, "missing");
  fd = mkstemp(path);
  must(fd >= 0, "mkstemp");
  (void)close(fd);
  must(birc_upload_run(path, &out, &http) == 2 && out == NULL, "empty file");
  (void)unlink(path);
  {
    char folder[] = "/tmp/birc-upload-fifo-XXXXXX";
    char fifo[64];
    uint32_t code;
    int n;
    must(mkdtemp(folder) != NULL, "fifo dir");
    n = snprintf(fifo, sizeof fifo, "%s/fifo", folder);
    must(n > 0 && (size_t)n < sizeof fifo && mkfifo(fifo, 0600) == 0, "mkfifo");
    code = birc_upload_run(fifo, &out, &http);
    (void)unlink(fifo);
    (void)rmdir(folder);
    must(code == 2 && out == NULL, "fifo");
  }
  printf("upload_native=ok\n");
  return 0;
}
