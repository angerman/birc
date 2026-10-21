/* SPDX-License-Identifier: Apache-2.0
 * Native Keychain profile oracles. Synthetic paths and secrets only. */
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE
#endif
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define BIRC_KEYCHAIN_CORE_ONLY
#include "../src/ffi/keychain_birc.c"

static char root[1024];

static void must(int ok, const char *label) {
  if (!ok) {
    fprintf(stderr, "keychain_native: %s (%s)\n", label, birc_kc_why);
    exit(1);
  }
}

static void path_at(char *out, size_t n, const char *name) {
  must(snprintf(out, n, "%s/%s", root, name) < (int)n, "path");
}

static void write_cfg(const char *path, const char *body) {
  FILE *f = fopen(path, "w");
  must(f != NULL, "open cfg");
  must(fputs(body, f) >= 0, "write cfg");
  must(fclose(f) == 0, "close cfg");
  must(chmod(path, 0600) == 0, "chmod cfg");
}

int main(void) {
  char path[1100];
  char host[300];
  uint32_t port = 0;
  BircKcProfile p;
  const char *tmpl;
  const char *tmp = getenv("TMPDIR");
  unsigned char secret[64];
  size_t secret_n = 0;
  char svc[256];

  if (!tmp || !tmp[0])
    tmp = "/tmp";
  must(snprintf(root, sizeof root, "%s/birc-keychain-native-XXXXXX", tmp) < (int)sizeof root,
       "root");
  must(mkdtemp(root) != NULL, "mkdtemp");
  path_at(path, sizeof path, "config.toml");

  must(birc_kc_endpoint("irc.invalid", 0, 0, 1, host, sizeof host, &port), "tls default");
  must(strcmp(host, "irc.invalid") == 0 && port == 6697u, "tls port");
  must(birc_kc_endpoint("irc.invalid", 0, 0, 0, host, sizeof host, &port), "plain default");
  must(port == 6667u, "plain port");
  must(birc_kc_endpoint("irc.invalid:07000", 0, 0, 1, host, sizeof host, &port), "inline");
  must(strcmp(host, "irc.invalid") == 0 && port == 7000u, "inline port");
  must(!birc_kc_endpoint("irc.invalid:0", 0, 0, 1, host, sizeof host, &port), "port 0");
  must(!birc_kc_endpoint("irc.invalid:65536", 0, 0, 1, host, sizeof host, &port), "port hi");
  must(!birc_kc_endpoint("[::1]:6697", 0, 0, 1, host, sizeof host, &port), "ipv6");
  must(birc_kc_endpoint("irc.invalid:7000", 1, 7000u, 1, host, sizeof host, &port), "agree");
  must(!birc_kc_endpoint("irc.invalid:7000", 1, 7001u, 1, host, sizeof host, &port), "conflict");

  {
    const char *ok[] = {"+#room", "#日本語"};
    const char *dup[] = {"#room", "#room"};
    const char *bare[] = {"#"};
    must(birc_kc_channels(ok, 2, &p) && p.channel_n == 2u, "channels");
    must(!birc_kc_channels(dup, 2, &p), "dup channels");
    must(!birc_kc_channels(bare, 1, &p), "bare prefix");
    must(birc_kc_channel_csv("", host, sizeof host) && host[0] == 0, "empty csv");
    must(!birc_kc_channel_csv("#a,", host, sizeof host), "trail comma");
  }

  must(birc_kc_name_ok("work") && !birc_kc_name_ok("") && !birc_kc_name_ok("bad name"),
       "name");
  must(birc_kc_loopback("127.0.0.1") && birc_kc_loopback("127.1.2.3"), "loopback");
  must(!birc_kc_loopback("126.0.0.1") && !birc_kc_loopback("localhost"), "not loopback");
  must(birc_kc_valid_prefix("NickServ!services@services.test"), "prefix ok");
  must(!birc_kc_valid_prefix("#room!u@h") && !birc_kc_valid_prefix("NickServ,other!u@h"),
       "prefix bad");
  must(birc_kc_service("test", "irc.invalid", 6697u, svc, sizeof svc), "service");
  must(strcmp(svc, "birc.auth.v1:[\"test\",\"irc.invalid\",6697]") == 0, "service json");
  must(birc_kc_secret_bytes("päss", secret, &secret_n) && secret_n == 5u, "secret utf8");
  must(!birc_kc_secret_bytes("", secret, &secret_n), "empty secret");
  must(!birc_kc_secret_bytes("a\nb", secret, &secret_n), "lf secret");

  tmpl = "[profiles.test]\nhost = \"irc.invalid\"\naccount = \"alice\"\n";
  write_cfg(path, tmpl);
  must(birc_kc_read_profile(path, "test", 0, 0, 0, 0, &p) > 0, "read tls");
  must(p.tls && p.port == 6697u && strcmp(p.account, "alice") == 0, "read fields");
  must(strcmp(p.auth, "sasl") == 0 && !p.has_channels, "read defaults");
  must(birc_kc_read_profile(path, "test", 1, 0, 0, 0, &p) > 0 && !p.tls && p.port == 6667u,
       "cli plain");

  write_cfg(path, "[profiles.test]\nhost = \"irc.invalid\"\naccount = \"alice\"\n"
                  "channels = [\"+#room\", \"#日本語\"]\n");
  must(birc_kc_read_profile(path, "test", 0, 0, 0, 0, &p) > 0, "read chans");
  must(p.has_channels && p.channel_n == 2u && strcmp(p.channels[0], "+#room") == 0, "chan0");
  must(strcmp(p.channels[1], "#日本語") == 0, "chan1");

  write_cfg(path, "[profiles.test]\nhost = \"irc.invalid\"\naccount = \"alice\"\n"
                  "password = \"no\"\n");
  must(birc_kc_read_profile(path, "test", 0, 0, 0, 0, &p) == 0, "password field");

  write_cfg(path, tmpl);
  must(chmod(path, 0666) == 0, "chmod 666");
  must(birc_kc_read_profile(path, "test", 0, 0, 0, 0, &p) == 0, "world writable");
  must(chmod(path, 0600) == 0, "restore 600");

  {
    char linkp[1100];
    path_at(linkp, sizeof linkp, "link.toml");
    must(symlink(path, linkp) == 0, "symlink");
    must(birc_kc_read_profile(linkp, "test", 0, 0, 0, 0, &p) == 0, "follow symlink");
  }

  {
    char created[1100];
    path_at(created, sizeof created, "new.toml");
    must(birc_kc_create_profile(created, "work", "irc.example.net", 0, 0, "mynick",
                                "#birc,#work", 0, 1, &p),
         "create");
    must(p.tls && p.port == 6697u && strcmp(p.nick, "mynick") == 0, "created fields");
    must(p.has_channels && p.channel_n == 2u, "created chans");
    must(!birc_kc_create_profile(created, "work", "irc.example.net", 0, 0, "mynick",
                                 NULL, 0, 1, &p),
         "create exists");
  }

  must(rmdir(root) != 0 || 1, "keep cleanup");
  (void)unlink(path);
  {
    char extra[1100];
    path_at(extra, sizeof extra, "link.toml");
    (void)unlink(extra);
    path_at(extra, sizeof extra, "new.toml");
    (void)unlink(extra);
  }
  must(rmdir(root) == 0, "rmdir");
  fputs("keychain_native=ok\n", stdout);
  return 0;
}
