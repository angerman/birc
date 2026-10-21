/* SPDX-License-Identifier: Apache-2.0
 * Native preferences file oracles. Synthetic paths only. */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE
#endif
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define BIRC_PREFS_CORE_ONLY
#include "../src/ffi/preferences_ffi.c"

static char root[1024];

static void must(int ok, const char *label) {
  if (!ok) {
    fprintf(stderr, "preferences_native: %s\n", label);
    exit(1);
  }
}

static void path_at(char *out, size_t n, const char *name) {
  must(snprintf(out, n, "%s/%s", root, name) < (int)n, "path");
}

static const char *wire(void) {
  return "BIRC_PREFS1\n"
         "settings\t0\t1\t0\t1\t200\t1\t0\t0\t1\n"
         "mute\talice*#room@irc.example\n"
         "channel\t+#room\n"
         "channel\t#日本語\n";
}

static void expect_read(const char *path, const char *host, uint32_t port,
                        uint32_t code, const char *want, const char *label) {
  char out[BIRC_PREFS_MAX_WIRE + 1u];
  size_t n = 0;
  uint32_t got = birc_prefs_read(path, host, port, out, sizeof out, &n);
  must(got == code, label);
  if (want == NULL)
    must(n == 0, label);
  else
    must(n == strlen(want) && memcmp(out, want, n) == 0, label);
}

int main(void) {
  char dir[] = "/tmp/birc-preferences-native-XXXXXX";
  char path[1024];
  char other[1024];
  char out[BIRC_PREFS_MAX_WIRE + 1u];
  size_t n = 0;
  char unknown[256];
  struct stat info;
  mode_t um;
  char *slash;

  must(mkdtemp(dir) != NULL, "mkdtemp");
  must((size_t)snprintf(root, sizeof root, "%s", dir) < sizeof root, "root");
  path_at(path, sizeof path, "preferences.toml");

  expect_read(path, "irc.example", 6697, 0, NULL, "missing is success");
  must(birc_prefs_write(path, "irc.example", 6697, wire(), strlen(wire())) == 0, "write");
  must(stat(path, &info) == 0 && (info.st_mode & 0777) == 0600, "0600");
  expect_read(path, "irc.example", 6697, 0, wire(), "roundtrip");

  slash = strstr(wire(), "channel\t");
  must(slash != NULL, "wire channels");
  must((size_t)(slash - wire()) + strlen("scope\t0\n") < sizeof unknown, "unknown size");
  memcpy(unknown, wire(), (size_t)(slash - wire()));
  memcpy(unknown + (slash - wire()), "scope\t0\n", strlen("scope\t0\n") + 1u);
  expect_read(path, "other.example", 6697, 0, unknown, "other endpoint keeps settings");
  expect_read(path, "irc.example.", 6697, 0, unknown, "root-dot is another scope");
  expect_read(path, "irc.example", 6667, 0, unknown, "port is another scope");

  path_at(other, sizeof other, "copy.toml");
  must(birc_prefs_write(other, "other.example", 6697,
                        "BIRC_PREFS1\nsettings\t0\t1\t0\t1\t200\t1\t0\t0\t1\nchannel\t#other\n",
                        strlen("BIRC_PREFS1\nsettings\t0\t1\t0\t1\t200\t1\t0\t0\t1\nchannel\t#other\n")) == 0,
       "other write");
  expect_read(path, "irc.example", 6697, 0, wire(), "first endpoint unchanged");

  must(birc_prefs_write(path, "", 0, "BIRC_PREFS1\nsettings\t0\t1\t0\t1\t300\t1\t0\t0\t1\n",
                        strlen("BIRC_PREFS1\nsettings\t0\t1\t0\t1\t300\t1\t0\t0\t1\n")) == 0,
       "global write");
  must(birc_prefs_read(path, "irc.example", 6697, out, sizeof out, &n) == 0, "global read");
  must(n > 0 && memmem(out, n, "\t300\t", 5) != NULL, "global cap");
  must(memmem(out, n, "channel\t+#room\n", 15) != NULL, "global keeps channels");
  must(birc_prefs_write(path, "", 0,
                        "BIRC_PREFS1\nsettings\t0\t1\t0\t1\t300\t1\t0\t0\t1\nchannel\t#fake\n",
                        strlen("BIRC_PREFS1\nsettings\t0\t1\t0\t1\t300\t1\t0\t0\t1\nchannel\t#fake\n")) == 2,
       "offline fake channel");

  {
    FILE *f = fopen(path, "w");
    must(f != NULL, "open future");
    must(fputs("version = 999\n", f) >= 0, "future text");
    must(fclose(f) == 0, "close future");
    must(chmod(path, 0600) == 0, "future mode");
    must(birc_prefs_read(path, "irc.example", 6697, out, sizeof out, &n) == 2, "future read");
    must(birc_prefs_write(path, "irc.example", 6697, wire(), strlen(wire())) == 2, "future write");
    must(unlink(path) == 0, "drop future");
  }

  {
    char link[1024];
    char fifo[1024];
    path_at(link, sizeof link, "link.toml");
    path_at(fifo, sizeof fifo, "fifo.toml");
    must(birc_prefs_write(path, "irc.example", 6697, wire(), strlen(wire())) == 0, "restore");
    must(symlink(path, link) == 0, "symlink");
    must(birc_prefs_read(link, "irc.example", 6697, out, sizeof out, &n) == 3, "symlink read");
    must(birc_prefs_write(link, "irc.example", 6697, wire(), strlen(wire())) == 3, "symlink write");
    must(birc_prefs_read(root, "irc.example", 6697, out, sizeof out, &n) == 3, "dir read");
    must(mkfifo(fifo, 0600) == 0, "fifo");
    must(birc_prefs_read(fifo, "irc.example", 6697, out, sizeof out, &n) == 3, "fifo read");
    must(chmod(path, 0644) == 0, "world read");
    must(birc_prefs_read(path, "irc.example", 6697, out, sizeof out, &n) == 3, "nonprivate read");
    must(chmod(path, 0600) == 0, "restore mode");
  }

  um = umask(0777);
  must(birc_prefs_write(path, "irc.example", 6697, wire(), strlen(wire())) == 0, "umask write");
  (void)umask(um);
  must(stat(path, &info) == 0 && (info.st_mode & 0777) == 0600, "umask 0600");

  must(birc_prefs_write("", "irc.example", 6697, wire(), strlen(wire())) == 0, "empty path write");
  expect_read("", "irc.example", 6697, 0, NULL, "empty path read");

  must(birc_prefs_write(path, "irc.example", 6697,
                        "BIRC_PREFS1\nsettings\t0\t1\t0\t1\t200\t1\t0\t0\t1\nchannel\t#\n",
                        strlen("BIRC_PREFS1\nsettings\t0\t1\t0\t1\t200\t1\t0\t0\t1\nchannel\t#\n")) == 2,
       "bare prefix");
  must(birc_prefs_write(path, "irc.example", 6697,
                        "BIRC_PREFS1\nsettings\t0\t1\t0\t1\t200\t1\t0\t0\t1\nchannel\tserver\n",
                        strlen("BIRC_PREFS1\nsettings\t0\t1\t0\t1\t200\t1\t0\t0\t1\nchannel\tserver\n")) == 2,
       "query name");

  {
    char lock[1024];
    char link[1024];
    char fifo[1024];
    path_at(lock, sizeof lock, "preferences.toml.lock");
    path_at(link, sizeof link, "link.toml");
    path_at(fifo, sizeof fifo, "fifo.toml");
    (void)unlink(path);
    (void)unlink(other);
    (void)unlink(lock);
    (void)unlink(link);
    (void)unlink(fifo);
    path_at(lock, sizeof lock, "copy.toml.lock");
    (void)unlink(lock);
  }
  (void)rmdir(dir);
  printf("preferences_native=ok\n");
  return 0;
}
