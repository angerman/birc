# birc — agent instructions

When using Bend:
- run `bend guide` to learn it
- use `LAWS.bend` to keep important rules
- run `bend PROOF.bend` before committing
- parallelize the code whenever possible

When using timui.h:
- one header, C99, POSIX file descriptors, no ncurses
- define `TIMUI_IMPLEMENTATION` in exactly one translation unit (`src/ffi/timui_ffi.c`)
- draw only between `timui_begin` and `timui_end` (inside a single `Timui.frame`)

## Scope

`birc` is an IRC client: **Bend 2 owns main, protocol, client, submit, framer,
networking, and the frame loop**; C is thin TimUI FFI under `src/ffi/`. Plaintext IRC only (host:6667). No crypto, no ncurses, no curl-pipe
installers.

Original material: Apache-2.0; author Moritz Angermann <moritz@zw3rk.com>.
Preserve upstream licenses. Do not add model attribution.

## Provision and run

Nix provisions dependencies. The root Makefile is the sole driver.

```
make bootstrap   # create flake.lock (once)
make shell       # enter the locked shell
make check       # proof + Bend tests + net + UI smoke
make run-demo    # offline TimUI demo
make run HOST=…  # live plaintext IRC (Bend net + TimUI.frame)
```

Do not use Homebrew/global installs, ambient compilers, `sudo make`, or
silent flake/source pin updates. Routine Nix work uses
`--no-update-lock-file`. Only `make update CONFIRM=yes` may move pins.

## Layout

| Path | Role |
|---|---|
| `TODO.md` | Bend migration checklist (M8 = TimUI example parity) |
| `src/bend/*.bend` | Protocol, client, submit, frame, session (pure), natutil, paint, dns_wire, net (IO), view, app |
| `src/ffi/` | TimUI foreign effects + `main`→`bend_main` |
| `src/ui/timui.h` | Vendored single-header TUI |
| `LAWS.bend` / `PROOF.bend` | Laws and proofs |

## Engineering

- Fail closed: missing targets exit nonzero.
- Keep IRC lines ≤ 512 bytes including CRLF.
- Bend owns frame iteration (`Timui.frame` = one begin/draw/end, returns `Ui & UiKeys`); C has no outer frame while-loop. Live paint is packed `BodyLine`/`Span`/`Tab` Data; C interprets it and does not tokenize or classify IRC. Keys are Data on the frame return, not a second latch IO.
- Net: `IO.spawn` actor owns `Socket`; UI ↔ actor via `Chan(NetEvt)` / `Chan(NetCmd)` (Data). Live framing is `push_text`; `push` stays the octet framer for laws. The connecting fiber owns the fd (never `Chan(Socket)`). Boot is Data (`Ready`/`Down`/`Timeout`); UI recvs one then `Chan.close` so the loser send cannot wait on a full channel. `--frames N` is one fuel tick per event; `frames=0` live loops are `@unsafe`. Live DNS A is `getaddrinfo` (`src/ffi/dns_ffi.c`); `dns_wire.bend` stays the pure encode/parse for tests (UDP `String` cannot recover A octets `0x80`–`0xC1`). Demo/offline uses an idle actor (Tick/Cont) until `/connect` sends `Dial{host,port}`; C does not tokenize. `Clock.hhmmss` stamps empty `Line.ts` at paint. `--replay FILE` is `File.read` → `feed_all`, fail closed.
- Shutdown (P5): `Socket.close` then `Timui.close`.
- Prove laws; do not weaken them to make a candidate pass.
- Bend pitfalls: no `match f(x)`; `+T` is copyable; match binders in param order;
  self-recursion needs decreasing fuel as the first arg; no dotted forward refs;
  `law T: Type` needs `def T(): SomeHandleType` (e.g. `Window`).
