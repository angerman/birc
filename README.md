# birc

IRC client built with **Bend 2** (protocol, client, net, view, main) and **timui.h**
(terminal UI via thin foreign effects).

Plaintext IRC only (`host:6667`). No ncurses. No crypto.

**Bend owns the frame loop and networking.** C provides `Timui.open` /
`Timui.frame` (one begin/draw/end) / `Timui.close`; `app.bend` / `net.bend`
iterate with `Nat` fuel. Live IRC: an `IO.spawn` net actor owns the `Socket`
and talks to the UI over copyable `Chan`s (`NetEvt` / `NetCmd`). Base
`TCP.send` carries `String`s. Live inbound is `recv_octets` + `Fr.push`
(UTF-8 lines, Latin-1 if invalid).

## Quick start

```sh
make bootstrap   # once: lock Nix inputs
make check       # proofs + Bend proto/feed/submit/frame/net + UI smoke
make run-demo    # offline TimUI demo
make run HOST=irc.example.net   # live plaintext IRC (Bend DNS A + TCP)
./build/birc --replay fixtures/demo.irc   # File.read → feed_all (fail closed)
```

## Layout

| Path | Role |
|---|---|
| `src/bend/irc.bend` | Pure RFC 1459/2812 parse / classify / format |
| `src/bend/buffer.bend` | Buffer / Client container types |
| `src/bend/client.bend` | `feed` dispatcher |
| `src/bend/client_laws.bend` | Feed inspectors and law predicates |
| `src/bend/submit.bend` | Composer → outbound IRC lines |
| `src/bend/frame.bend` | CRLF octet framer + UTF-8 line decode |
| `src/bend/view.bend` | ViewModel + scroll bounds |
| `src/bend/net.bend` | Chan UI loop, watchers, shutdown |
| `src/bend/actor.bend` | Writer owns the socket; reader parks on a dup |
| `src/bend/timui.bend` | `Timui.open` / `frame` / `close`, tty, winch |
| `src/bend/app.bend` | Bend `main` (demo + live dispatch) |
| `src/ffi/timui_ffi.c` | Thin TimUI FFI (`TIMUI_IMPLEMENTATION`) |
| `src/ffi/dns_ffi.c` | `recv_octets`, `recv_nb`, `send_octets`, dup, shutdown |
| `src/ffi/clock_ffi.c` | Local seconds-of-day; Bend formats HH:MM:SS |
| `build/birc_bend.c` | **Build artefact** — Bend emits the whole program as one C TU; not hand-written |
| `src/ui/timui.h` | Vendored [timui.h](https://timui.dev) |
| `LAWS.bend` / `PROOF.bend` | Protocol / feed / submit / framer / scroll laws |

## Make targets

Run `make` (or `make help`) for the full list. Nix provisions Bend, clang, and bun; routine targets never update `flake.lock` unless you run `make update CONFIRM=yes`.

## License

Apache-2.0. See `LICENSE`.
