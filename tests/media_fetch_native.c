/* SPDX-License-Identifier: Apache-2.0
 * Native image/card fetch oracles. Synthetic files only; no public hosts. */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE
#endif
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define BIRC_MEDIA_CORE_ONLY
#include "../src/ffi/media_fetch_ffi.c"

static const unsigned char kPng2[] = {
  0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a,0x00,0x00,0x00,0x0d,0x49,0x48,0x44,0x52,
  0x00,0x00,0x00,0x02,0x00,0x00,0x00,0x02,0x08,0x02,0x00,0x00,0x00,0xfd,0xd4,0x9a,
  0x73,0x00,0x00,0x00,0x12,0x49,0x44,0x41,0x54,0x78,0x9c,0x63,0x14,0xd1,0xb0,0x61,
  0x60,0x60,0x60,0x62,0x00,0x03,0x00,0x05,0xa2,0x00,0x7c,0xa5,0xca,0xb4,0x1d,0x00,
  0x00,0x00,0x00,0x49,0x45,0x4e,0x44,0xae,0x42,0x60,0x82
};

static void must(int ok, const char *label) {
  if (!ok) {
    fprintf(stderr, "media_fetch_native: %s\n", label);
    exit(1);
  }
}

static int regular_file(const char *path) {
  struct stat st;
  return lstat(path, &st) == 0 && S_ISREG(st.st_mode);
}

static void put_card(const char *cards, unsigned i) {
  char path[512];
  FILE *f;
  int wr = snprintf(path, sizeof path, "%s/%064x.card", cards, i);
  must(wr > 0 && (size_t)wr < sizeof path, "card path");
  f = fopen(path, "wb");
  must(f != NULL, "card fopen");
  must(fwrite("c", 1, 1, f) == 1, "card byte");
  must(fclose(f) == 0, "card fclose");
}

static void image_path(const char *root, const char *url, char *path, size_t n) {
  char name[80];
  int wr;
  birc_mf_sha_name(url, ".img", name, sizeof name);
  wr = snprintf(path, n, "%s/%s", root, name);
  must(name[0] != 0 && wr > 0 && (size_t)wr < n, "image path");
}

static int b64_digit(unsigned char c) {
  if (c >= 'A' && c <= 'Z') return c - 'A';
  if (c >= 'a' && c <= 'z') return c - 'a' + 26;
  if (c >= '0' && c <= '9') return c - '0' + 52;
  if (c == '+') return 62;
  if (c == '/') return 63;
  return -1;
}

static size_t b64_decode(const char *in, unsigned char *out, size_t out_n) {
  size_t i = 0, o = 0, n = strlen(in);
  while (i < n && in[i] != '=') {
    int a = b64_digit((unsigned char)in[i]);
    int b = i + 1 < n ? b64_digit((unsigned char)in[i + 1]) : -1;
    int c = i + 2 < n && in[i + 2] != '=' ? b64_digit((unsigned char)in[i + 2]) : 0;
    int d = i + 3 < n && in[i + 3] != '=' ? b64_digit((unsigned char)in[i + 3]) : 0;
    unsigned int v;
    if (a < 0 || b < 0)
      return 0;
    v = ((unsigned int)a << 18) | ((unsigned int)b << 12)
      | ((unsigned int)c << 6) | (unsigned int)d;
    if (o < out_n) out[o++] = (unsigned char)(v >> 16);
    if (in[i + 2] != '=' && o < out_n) out[o++] = (unsigned char)(v >> 8);
    if (in[i + 3] != '=' && o < out_n) out[o++] = (unsigned char)v;
    i += 4;
  }
  return o;
}

int main(void) {
  BircMfUrl url;
  char *out = NULL;
  size_t n = 0;
  unsigned char payload[4096];
  size_t pn;
  char dir[] = "/tmp/birc-media-fetch-XXXXXX";
  char path[512];
  const char *priv[] = {
    "127.0.0.1", "0.0.0.0", "10.1.2.3", "172.16.0.1", "192.168.1.1",
    "169.254.169.254", "100.64.0.1", "224.0.0.1", "255.255.255.255",
    "::1", "fe80::1", "fc00::1", "ff02::1", "::ffff:127.0.0.1",
    "2002:7f00:1::", "64:ff9b::7f00:1", "fec0::1"
  };
  size_t i;

  for (i = 0; i < sizeof priv / sizeof priv[0]; i++)
    must(!birc_media_public_address(priv[i]), priv[i]);
  must(birc_media_public_address("93.184.216.34"), "example v4");
  must(birc_media_public_address("2606:4700:4700::1111"), "example v6");

  must(!birc_media_parse_url("file:///tmp/a.png", 0, &url), "file");
  must(!birc_media_parse_url("https://me:secret@example.test/a.png", 0, &url), "user");
  must(!birc_media_parse_url("https://example.test:9999/a.png", 0, &url), "port");
  must(!birc_media_parse_url("http://example.test:443/a.png", 0, &url), "http port");
  must(!birc_media_parse_url("https://example.test:0/a.png", 0, &url), "zero");
  must(!birc_media_parse_url("http://example.test/read", 1, &url), "cards http");
  must(birc_media_parse_url("https://example.test/Screenshot%202026.png?q=x%2Fy", 0, &url), "ok");
  must(strcmp(url.host, "example.test") == 0 && url.port == 443, "host/port");
  must(strcmp(url.path, "/Screenshot%202026.png?q=x%2Fy") == 0, "path");

  must(birc_media_encode(kPng2, sizeof kPng2, &out, &n) == 0 && out && n > 0, "encode");
  pn = b64_decode(out, payload, sizeof payload);
  must(pn >= 32 && memcmp(payload, "BIRCIMG1", 8) == 0, "magic");
  must(payload[8] == 0 && payload[11] == 2 && payload[15] == 2, "size");
  must(payload[19] == 1 && payload[23] == 1, "count");
  free(out);
  out = NULL;

  must(birc_media_encode((const unsigned char *)"<html>", 6, &out, &n) == 1, "html");
  must(birc_media_encode(NULL, 0, &out, &n) == 1, "empty");

  {
    const char *html =
      "<meta property=\"og:title\" content=\"T &amp; U\">"
      "<meta property=\"og:description\" content=\"D\">"
      "<meta property=\"og:image\" content=\"https://cdn.test/i.png\">";
    must(birc_cards_parse((const unsigned char *)html, strlen(html),
                          "https://example.test/read", &out, &n) == 0, "cards");
  }
  must(out && strcmp(out, "T & U\nD\nhttps://cdn.test/i.png\n") == 0, out ? out : "cards text");
  free(out);
  out = NULL;

  must(birc_cards_parse((const unsigned char *)"<title>Fall back</title>", 24,
                        "https://example.test/read", &out, &n) == 0, "title");
  must(out && strcmp(out, "Fall back\n\n\n") == 0, "title text");
  free(out);
  out = NULL;

  {
    const char *html = "<meta property=\"og:title\" content=\"&#x1F600;\">";
    must(birc_cards_parse((const unsigned char *)html, strlen(html),
                          "https://example.test/read", &out, &n) == 0, "emoji title");
  }
  must(out && strcmp(out, "\xF0\x9F\x98\x80\n\n\n") == 0, "emoji bytes");
  free(out);
  out = NULL;

  {
    const char *html = "<meta property=\"og:title\" content=\"&#xD800;\">";
    const unsigned char cesu[3] = {0xed, 0xa0, 0x80};
    must(birc_cards_parse((const unsigned char *)html, strlen(html),
                          "https://example.test/read", &out, &n) == 0, "surrogate title");
    must(out && n >= 3, "surrogate length");
    {
      size_t at;
      int found = 0;
      for (at = 0; at + 3u <= n; at++) {
        if (memcmp(out + at, cesu, 3) == 0)
          found = 1;
      }
      must(!found, "surrogate bytes");
    }
    must(strcmp(out, "&#xD800;\n\n\n") == 0, "surrogate text");
  }
  free(out);
  out = NULL;

  {
    const char *html = "<meta property=\"og:image\" content=\"http://example.test/i.png\">";
    must(birc_cards_parse((const unsigned char *)html, strlen(html),
                          "https://example.test/read", &out, &n) == 0, "http thumb");
  }
  must(out && strcmp(out, "\n\n\n") == 0, "http thumb empty");
  free(out);
  out = NULL;

  must(mkdtemp(dir) != NULL, "mkdtemp");
  must(snprintf(path, sizeof path, "%s/image.png", dir) < (int)sizeof path, "path");
  {
    FILE *f = fopen(path, "wb");
    must(f != NULL, "fopen");
    must(fwrite(kPng2, 1, sizeof kPng2, f) == sizeof kPng2, "write png");
    must(fclose(f) == 0, "fclose");
  }
  must(birc_media_run(1, path, &out, &n) == 0 && out && n > 0, "local image");
  free(out);
  out = NULL;
  must(birc_media_run(1, "/no/such/image.png", &out, &n) == 1, "missing image");

  {
    char html[512];
    must(snprintf(html, sizeof html, "%s/page.html", dir) < (int)sizeof html, "html path");
    FILE *f = fopen(html, "wb");
    must(f != NULL, "fopen html");
    must(fputs("<meta property=\"og:title\" content=\"Local\">\n", f) > 0, "html write");
    must(fclose(f) == 0, "fclose html");
    must(birc_cards_run(1, html, &out, &n) == 0, "local card");
    must(out && strncmp(out, "Local\n", 6) == 0, "local card text");
    free(out);
  }

  must(birc_media_run(0, "https://127.0.0.1/a.png", &out, &n) != 0, "loopback image");
  must(birc_cards_run(0, "http://example.test/read", &out, &n) != 0, "plain card");

  {
    char root[] = "/tmp/birc-mf-cap-XXXXXX";
    char cards[128], admit[512], capped[512], kept[512], lockpath[160];
    const unsigned char img[] = {1, 2, 3, 4};
    const char *admit_url = "https://example.test/admit.png";
    const char *capped_url = "https://example.test/capped.png";
    int parent, wr;
    unsigned i;
    must(mkdtemp(root) != NULL, "cap dir");
    must(chmod(root, 0700) == 0, "cap mode");
    wr = snprintf(cards, sizeof cards, "%s/cards", root);
    must(wr > 0 && (size_t)wr < sizeof cards, "cards path");
    must(mkdir(cards, 0700) == 0 && chmod(cards, 0700) == 0, "cards dir");
    for (i = 0; i + 1u < BIRC_MF_MAX_CACHE_ENTRIES; i++)
      put_card(cards, i);
    parent = open(root, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    must(parent >= 0, "cap parent");
    birc_mf_cache_write(parent, 0, admit_url, img, sizeof img, NULL);
    image_path(root, admit_url, admit, sizeof admit);
    must(regular_file(admit), "admit under cap");
    put_card(cards, BIRC_MF_MAX_CACHE_ENTRIES - 1u);
    wr = snprintf(kept, sizeof kept, "%s/%064x.card", cards, BIRC_MF_MAX_CACHE_ENTRIES - 1u);
    must(wr > 0 && (size_t)wr < sizeof kept, "kept card path");
    birc_mf_cache_write(parent, 0, capped_url, img, sizeof img, NULL);
    image_path(root, capped_url, capped, sizeof capped);
    must(!regular_file(capped), "image at card cap");
    must(regular_file(admit), "admitted image kept");
    must(regular_file(kept), "cards kept");
    must(close(parent) == 0, "close parent");
    must(unlink(admit) == 0, "unlink admit");
    for (i = 0; i < BIRC_MF_MAX_CACHE_ENTRIES; i++) {
      char gone[512];
      wr = snprintf(gone, sizeof gone, "%s/%064x.card", cards, i);
      must(wr > 0 && (size_t)wr < sizeof gone && unlink(gone) == 0, "unlink card");
    }
    wr = snprintf(lockpath, sizeof lockpath, "%s/.lock", root);
    must(wr > 0 && (size_t)wr < sizeof lockpath && unlink(lockpath) == 0, "unlink lock");
    must(rmdir(cards) == 0 && rmdir(root) == 0, "rmdir cap");
  }

  printf("media_fetch_native=ok\n");
  return 0;
}
