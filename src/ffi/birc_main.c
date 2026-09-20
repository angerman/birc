/* Process entry. Bend's generated main is renamed bend_main; it strips
 * --threads/--gpu/--help and exposes the rest through IO.args.
 * Hostnames are resolved in Bend (src/bend/dns.bend) before TCP.connect. */

#include <stdio.h>
#include <string.h>

int bend_main(int argc, char **argv);

int main(int argc, char **argv) {
  int i;
  for (i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--") == 0)
      break;
    if (strcmp(argv[i], "--help") == 0) {
      fprintf(stderr,
              "usage: birc [--frames N] [--connect HOST] [--port N] [--nick N] "
              "[--channel #c]\n");
      return 2;
    }
  }
  return bend_main(argc, argv);
}
