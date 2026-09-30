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
| `src/bend/*.bend` | Protocol, client, submit, frame, session (pure), dns_wire, actor, net (IO), view, app |
| `src/bend/buffer.bend` | Buffer / Client container types (I15b) |
| `src/bend/client_laws.bend` | Feed inspectors and `*_ok` predicates (I15a) |
| `src/bend/auth.bend` | Parsed, phase-gated SASL exchange (pure) |
| `src/bend/outbound.bend` | Pure send-cap batches and finite credits |
| `src/bend/links.bend` | Shared URL lexical rules (pure) |
| `src/ffi/timui_ffi.c` | TimUI open/frame/close |
| `src/ffi/dns_ffi.c` | Byte reads, deadline-owned connect/send, socket dup/shutdown |
| `src/ffi/clock_ffi.c` | Local clock for log timestamps |
| `src/ui/timui.h` | Vendored single-header TUI |
| `LAWS.bend` / `PROOF.bend` | Laws and proofs |

## Engineering

- Fail closed: missing targets exit nonzero.
- Keep IRC lines ≤ 512 bytes including CRLF.
- Bend owns frame iteration (`Timui.frame` = one begin/draw/end, returns `Ui & UiKeys`); C has no outer frame while-loop and the frame does not poll. Live paint is `List<DrawOp>` (`OpBox` / `OpText` / `OpTabs` / `OpLine`); C walks and paints, and does not tokenize, classify, or wrap IRC. Bend expands logical chat lines into resize-safe visible rows with hanging indents. `OpTabs` carries Bend-owned alert levels plus the bell enable flag and event sequence. C renders activity with reverse video, mentions/private messages with gold, and emits one BEL when the sequence advances. Keys are Data on the frame return; a clicked chat link returns its exact URL for Bend to open. C reports the raw key, mods, and wheel; Bend maps Shift-arrows, PageUp/PageDown (`Sess.body_h`), history, and Esc/F10. A tty watcher and a `SIGWINCH` pipe wake one `Chan(UiMsg)`. The UI parks on that channel. Every paint applies the keys the frame read, including a chunk or Eof paint.
- Net: `IO.spawn` actor owns `Socket`; UI ↔ actor via `Chan(NetEvt)` / `Chan(NetCmd)` (Data). Live inbound is `recv_octets` + `Fr.push`; completed lines are UTF-8, with Latin-1 fallback if a line is not valid UTF-8. The actor owns the fd (never `Chan(Socket)`). `SEND_CAP` is 8 outbound lines per actor tick; leftover stays in `pending`. `--frames N` is N ticks (at most `SEND_CAP*N` lines during the loop); cmd close and fuel-0 flush `pending` so `/quit` is not dropped. `frames=0` live loops are `@unsafe`. Live DNS A is Bend UDP plus `recv_octets`. Demo/offline idle actor waits for `Dial`; Demo/Connecting `Cont` carries no IRC outs (no flush after Dial). C does not tokenize. Clock is applied at log IO, not every paint. `--replay FILE` is `File.read` → `feed_all`, fail closed. `--help` is Bend's runtime CLI; birc usage is `--help-irc`.
- Shutdown (P5): `Socket.close` then `Timui.close`, then bounded status output and `Sys.exit_done` so parked IO cannot linger. Do not use `IO.die` for successful UI shutdown: the pinned runtime writes an unbounded stderr newline even for an empty message. TimUI teardown restores terminal state before the final `_Exit`.
- All terminal writes, including BEL and OSC 52, use the frame deadline. The native transport owns at most three UTF-8 suffix bytes; later writes must complete them first. Clipboard process work runs through Bend `Process.run` outside the frame, not synchronous `popen` in C.
- Log lines carry author identity and stable global IDs. Never infer new events by comparing rendered text/timestamps. Reconnect dividers are `Reconnect`, not a substring test. Unread names and alert levels are separate fields.
- Scroll uses one message-and-character anchor (`ScrollAt{after, tail}`). View wrapping supplies both paint rows and navigation bounds. Never clamp live navigation by logical line count or store width-dependent row offsets.
- `BIRC2` history includes the hostname and port. The IO reader rejects ambiguous legacy records, reads bounded chunks to the initial file size, and retains recent records. Save the current event before loading a changed endpoint; install the loaded client as the next history checkpoint so restored rows are not appended again.
- SASL uses parsed control events and a persistent authentication phase. Credentials are UTF-8 octets; Base64 AUTHENTICATE payloads use 400-character chunks. Registration and completion disable further authentication responses.
- Headless (stdin is not a tty) awaits the bounded initial registration result before painting `--frames N` and exiting; initial failure exits nonzero. On a tty, `N` is a message cap and the loop parks; loop tests need a pty (`make test-pty`).
- IRCv3 `+typing` state is Bend-owned, capped at 32 entries, and expires from a one-second `TypingTick`; active lasts 6 s and paused lasts 30 s. The tick repaints only for expiry changes or a short frame whose output is writable. `UiKeys.more` is input-only; terminal recovery does not schedule synthetic input wakes. Ordinary frames have a 40-ms output budget; writable repairs have 200 ms; still-full repairs do not wait.
- A new or changed pty test must pass three consecutive runs before its commit.
- Prove laws; do not weaken them to make a candidate pass.
- Keep proof-facing queue rules in `outbound.bend`, not the IO actor module. Importing the actor into `LAWS.bend` brings foreign/unsafe dependencies and the checker rejects the proof set.
- Bend pitfalls: no `match f(x)`; `+T` is copyable; match binders in param order;
  self-recursion needs decreasing fuel as the first arg; no dotted forward refs;
  `match` cannot scrutinize a computed value, a local binder, or a destructuring let;
  escapes: `Maybe.default`, `Maybe.bind`, `do Maybe`, `Bool.pick`, decision `Bool` as a parameter;
  `law T: Type` needs `def T(): SomeHandleType` (e.g. `Window`).
