# Bend ↔ TimUI / native FFI

Pinned Bend: see `flake.lock` (`bend-src`). Foreign effects follow bendano
TOOLCHAIN conventions and upstream `bend2/effs/*.c`.

## Shape

```bend
law Timui.frame:
  Ui -> List<&2, V.DrawOp> -> String -> U32 -> U32 -> IO(Ui & UiKeys)

def Timui.frame(ui, ops, input, seed, page):
  import "../ffi/timui_ffi.c"
```

- Body is **only** `import "….c"`.
- Must return base `IO(...)`.
- C registers with `io_eff(CID_<NAME>, run, flags)` from a constructor.
- `Timui.frame` → `CID_TIMUI_FRAME` (`name_clean` then uppercased).

## Terms

| Bend | Native |
|---|---|
| `U32` / `Nat` (≤ 2^48−1) | low bits of raw `Term` word |
| `Unit` | `term_pak(CID_UNIT, 0)` |
| `String` | `io_cstr` / `io_str` (UTF-8) |
| `List<&2, U32>` octets | walk `CID_CON` / build with `io_node` |
| Handle (`Ui`, `Socket`, …) | `io_hand(ptr)` / `io_hand_v(term)` — **never** store pointers in `U32`/`Nat` |
| `Result` | `io_done` / `io_fail` |
| Pair | `io_tup` |

## Effects

| Effect | C file | Notes |
|---|---|---|
| `Timui.open` / `frame` / `close` / `isatty` / `tty` | `src/ffi/timui_ffi.c` | `TIMUI_IMPLEMENTATION` once |
| `Tty.ready` / `Tty.close` / `Winch.open` / `ready` / `close` | `src/ffi/timui_ffi.c` | tty and winch share `fd_ready` |
| `recv_octets` / `recv_nb` | `src/ffi/dns_ffi.c` | one `recv_try`; octets + peer, not `UDP.recv` String |
| `send_octets` | `src/ffi/dns_ffi.c` | UDP datagram from `List U32` |
| `Socket.dup` / `Socket.shutdown` | `src/ffi/dns_ffi.c` | reader dup; `SHUT_RDWR` wakes that dup |
| `local_secs` | `src/ffi/clock_ffi.c` | local seconds-of-day as `U32`; Bend formats HH:MM:SS |

Live TCP outbound is Base `TCP.send` (String). Live inbound is `recv_octets`
(`IO_READ`) + `Fr.push`, not `TCP.recv`. DNS uses `recv_nb` (flags 0) so its
fuel timeout still runs. Peer is `host & (port & octets)` beside the payload.
`EINTR` is treated like `EAGAIN`. `max` is clamped to 4096.

The reader maps a `Fail` and a zero-length read to `FromNet{gen, Eof}`. The
UI paints `disconnected` and stays up. It drops a `FromNet` whose generation
is not current.

## Build

`bend src/bend/app.bend -o build/birc_bend.c`, then
`$CC -std=c11 -O2 -pthread -w -Isrc/ui -Isrc/ffi build/birc_bend.c -o build/birc`.

The real build uses `-w` because Bend's emitted C trips `-Wall`. Warning lint
of the project FFI is `make lint-ffi`: stub header `tests/lint-ffi/ffi_stub.h`,
`-Wall -Wextra -pedantic -Wshadow -Wconversion -fsyntax-only -isystem src/ui`.

## App UI

```text
law Ui: Type

Timui.open   : IO(Result<&1,&1, U32 & String, Ui>)
Timui.frame  : Ui -> List<&2, DrawOp> -> String -> U32 -> U32 -> IO(Ui & UiKeys)
Timui.close  : Ui -> IO(Unit)
Timui.isatty : IO(U32)
Timui.tty    : Ui -> IO(Ui & Result<&1,&1, U32 & String, Tty>)
```

`UiKeys` is Data. `typed` is a `String` (the composer field). `rows` and `cols`
are the live root size. Other fields are U32 flags/counters (`quit`, `enter`,
`tab`, `click`, `up`, `dn`, `hist`). Unpack like `Window.frame`. Do not put
`Ui` inside a `Result`. `seed != 0` reseeds the composer from `input`,
including `""`. `page` is `Sess.body_h` (PageUp/PageDown line count).
The frame does not wait. A tty watcher and a winch watcher wake the UI;
see K1 below. `Timui.open` sets `input_poll_ms` to 0.
On a non-tty, `--frames N` paints N frames and exits. On a tty, `N` is a
cap of messages and the loop parks. Test-only: `BIRC_DIE_AFTER_OPEN=1`
calls `exit(1)` after `atexit` is registered so `tests/pty/restore.py` can
check cooked mode without `Timui.close`.

### Vendored `timui.h` patches

Local edits to `src/ui/timui.h` (re-apply on an upstream update):

1. **`input_poll_ms`** on `TimuiConfig` (default 16). `timui_begin` uses it for
   the tty poll and the non-tty nanosleep. birc sets 0 so begin does not sleep.
   The frame still polls 50 ms when a lone Esc is pending, because a parked
   UI has no next tick to notice the timeout.
2. **Enter table size** `enter_at` / `pending_enter_at` is 64 (upstream 32).
3. **Lossless Enter overflow.** When `enter_at`, `text_in`, or `edit_ops` is
   full, `timui_begin` ungets the current event and stops consuming; leftover
   events stay queued and no further `transport.read` runs until they drain.
   Enters are never merged or dropped. `pending_*` still carries the
   post-submit tail of the current table. While events are held, the input
   parser's Esc/paste/string clocks are re-anchored so a split CSI (arrow
   key) does not idle-out across those frames.
4. **Bracketed paste CR/LF split.** `TIMUI_EVENT_PASTE` payloads (ESC[200~ …
   ESC[201~) are split on CR/LF into text plus `enter_at` entries, with the
   same hold/unget when the tables are full. The PASTE hold guard breaks when
   expanding invalid bytes cannot fit in `text_in` (lossless). A CR ending a
   chunk marks `paste_skip_lf` to skip a leading LF in the following chunk.
   Incomplete UTF-8 tails are stashed only when followed by continuation bytes;
   an unconsumed prefix of the stashed tail is restored on early exit. Held
   input preserves queued focus events across frames. The deferred post-Enter
   tail also keeps Backspace and cursor ops (`pending_edit_ops`).

### Pure domain types

```text
Client, Buffer, Line, LineKind
NetEvt, NetCmd, ViewModel, DrawOp, SpanOp
Args.Cfg{demo, frames, host, port, nick, chan, replay}
```

## DrawOp contract

C walks `List<DrawOp>` inside one `Timui.frame` (one begin/draw/end). Bend owns
layout, colours, spans, and the y of every body line. Nested `Rect` Data does
not unpack as four U32s in C, so coordinates are flat fields on each op.

```text
type SpanOp is Data:
  Spn{attrs: U32, text: String}     # bold=1, italic=4
  Lnk{url: String, text: String}

type DrawOp is Data:
  OpBox{x, y, w, h: U32}
  OpText{x, y, w, fg, attrs: U32, text: String}
  OpTabs{x, y, w, sel: U32, names: List String}
  OpLine{x, y, w, fg: U32, ts: String, spans: List SpanOp}
```

- `OpBox` — rounded border; C clips `h` to the live root.
- `OpText` — label at `(x,y)`, clipped to `x+w`.
- `OpTabs` — `timui_tabs`; click reports only when the widget changes `sel`.
- `OpLine` — timestamp (dim) then spans at the Bend-assigned `y`. No C buffer,
  no 64-line cap, no bottom-align arithmetic.
- C does not tokenize. `TextSpan` is the tokenize law type; live paint uses
  `SpanOp`.
- Wrapping: each IRC line is one paint line. C clips a span that would run
  past `maxx` (no continuation row). A URL longer than 255 bytes is drawn as
  a plain span.
- Composer stays a C textarea widget (`timui_text_area_mut`).

## Decisions

| ID | Choice |
|---|---|
| D1 | Coarse paint inside one `Timui.frame` (Bend owns iteration) |
| D2 | `IO.spawn` net actor + `Chan` Data events; UI paints then `Chan.recv` |
| D3 | Base `TCP.send` strings; live inbound `recv_octets` + octet `Fr.push` |
| D4 | `--frames` fuel; `frames=0` live `@unsafe` idle |
| D5 | C demo deleted; Bend `build/birc` only |
| D6 | `List<DrawOp>`; C interprets, does not tokenize |

`--replay FILE` is `File.open`/`File.read` → `replay_lines` → `feed_all` (fail
closed if missing). Demo/offline share the live `Timui.frame` loop via an idle
actor that waits for `NetCmd.Dial` (never a `Socket` on a Chan). `local_secs`
is a thin localtime FFI; Bend sets `Client.now` at the IO edge so `buf_log_ts`
stores `Line.ts` at log time.

## K1 — input actor

Replaces the C wait path (`birc_wait_fds`, the Ui self-pipe, `wake_poke`,
`fd_hint`, `wait_ms` / `wake_fd`, the Bend hot window). The runtime parks
an effect registered with `IO_READ` on the fd of its first handle
argument until `POLLIN` (`bend2/comp.ts` `io_step`; `tcp_recv.c` is the
pattern). K2 is this section.

### Wake sources

One UI channel, `Chan(UiMsg)`, capacity 64. Producers:

| Producer | Message | How it wakes |
|---|---|---|
| Reader actor | `FromNet{gen, Chunk}` / `FromNet{gen, Eof}` | parks in `recv_octets` (`IO_READ`) |
| Dial job | `FromNet{gen, Up}` / `FromNet{gen, Fail}` | after `TCP.connect` |
| Tty watcher | `Key{}` | parks in `Tty.ready` |
| Winch watcher | `Resize{}` | parks in `Winch.ready` |

The UI blocks only in `Chan.recv`. It does not poll. There is no `Tick`.

`Timui.tty(ui) -> Tty` dups the tty fd into a fresh linear handle. The Ui
keeps the original fd. `Tty.ready` and `Winch.ready` are one C function.
It parks with `io_wait_on` (not `IO_READ`, so a paste tail still in TimUI
can return). It does not read the tty. It drains only the winch pipe.
The watcher loop is:

```text
Tty.ready(tty)
Chan.send(ui_evt, Key{})
Chan.recv(ack)
```

The ack stops a busy loop while the tty stays readable. The UI sends it
only after `Timui.frame` has returned. `Tty.close` closes the dup, never
the Ui's fd.

### Outbound, and why the net side is two actors

Today a typed line leaves because the actor wakes every 16 ms and each
`Tick` gives the UI one `NetCmd` slot for `Cont{outs}`. Parking the reader
on the socket removes those ticks. If the UI sent a `NetCmd` only as the
answer to `FromNet`, a `PRIVMSG` on a quiet channel would wait for the
server (seconds to minutes).

The net side splits.

**Writer.** Owns the `Socket`. Blocks in `Chan.recv(cmd)`. The UI sends
`Cont{outs}` when it has lines, not as a reply to a net event. The writer
sends them at once. `SEND_CAP` (8 lines) stays inside the writer: the rest
sits in the writer's own list, not in a bargain with the UI. On quit, and
on `/connect` before the old socket is replaced, the writer calls
`Socket.shutdown` (`SHUT_RDWR`) and then `Socket.close`.

**Reader.** Owns a `dup` of that socket as its own linear handle (same
trick as `Timui.tty`). Parks in `recv_octets` with `IO_READ`. Sends
`FromNet{gen, Chunk}` or `FromNet{gen, Eof}`. Never touches `NetCmd`.
`shutdown` makes `recv` return 0, so it posts `Eof` for that generation,
closes only the dup, and exits.

**Dial.** `/connect` works from demo and from an already online session
(the old "already connected" refusal goes away). The UI bumps a
generation, then the dial job connects, dups the fd, starts the reader
on the dup with that generation, gives the `Socket` to the writer, and
posts `FromNet{gen, Up}`. That post is how the UI learns the dial
finished. `Up`'s fd number is not a poll hint.

**Generation.** Same class of race as `c3bffde`. On `/connect` while
connected, the writer shuts down the old socket, so the old reader posts
`FromNet{old, Eof}` possibly after the new dial has posted
`FromNet{new, Up}`. If the UI treated that `Eof` as "disconnected" it
would mark the new connection offline. Every `FromNet` (`Up`, `Chunk`,
`Eof`, and `Fail`) carries a `U32` generation. The UI starts at 0 and
bumps it on each `Dial`, including the first connect, and passes that
value to the dial job and the reader. The UI drops any `FromNet` whose
generation is not the current one. `tests/pty/gen_eof.py` locks it:
connect, `/connect` to a second mock, the first server stays open for
1 s and then closes; the client must stay on the second connection and
send `JOIN` there.

**DNS time bound (K3).** A `recv_octets` registered with `IO_READ` parks
until the socket is readable. It has no timeout, so the resolver's fuel
loop would never reach `IO.sleep`, the resend, or fuel 0. Decision: DNS
keeps the non-blocking path. `recv_nb` is the same C function with
`io_eff` flags `0` (EAGAIN is `None`). `wait_ans` keeps calling it, so
the existing sleep and fuel stay the time bound. The TCP reader is the
only caller of parked `recv_octets`. No timer actor.
`tests/bend/dns_timeout.bend` looks up `example.test` at `192.0.2.1`
(the packet is dropped) and must print `timeout` within 15 s. Peer
check, the 4096 clamp, and the EINTR retry stay on both recv paths.

`Tick`, `hold_cmd`, and the pending/ack coupling between the UI and the
net actor go away. The tty ack stays; it is not a `NetCmd`. `Key` and
`Resize` never answer a net event. The UI sends `Cont{outs}` only when a
frame produced lines (or `Dial` for `/connect`).

Base has no `shutdown`. K2 adds `Socket.shutdown(sock) -> IO(Socket)`,
always `SHUT_RDWR`, a few lines of C, counted in the `src/ffi` total. It
returns the same socket so the writer can close it next.

### Who closes which fd

`dup` shares one open file description. `shutdown` affects that
description, so the reader's `recv` wakes. `close` on one descriptor does
not close the other, and does not by itself deliver EOF. No descriptor
number is closed twice.

1. Writer: `Socket.shutdown(sock)` then `Socket.close(sock)`. Only the
   writer closes `sock`. It does not wait for the reader, and it does not
   close the dup.
2. Reader: `recv` returns 0, send `FromNet{gen, Eof}`, `close` the dup
   only, exit. It never closes `sock`. A late `Eof` still carries the
   old generation, so the UI drops it after a newer dial.
3. UI, on `Eof`, closes neither socket fd.
4. Quit also stops the watchers, then `Timui.close`. `Tty.close` closes
   the tty dup; `Timui.close` closes the fd inside the `Ui`.
5. `Winch.close` restores the previous `SIGWINCH` handler first, then
   closes the write end, then the read end, so the handler cannot write a
   fd that was already closed.

### Resize

TimUI has no `SIGWINCH` handler. `timui_term_size` is `TIOCGWINSZ`. A 1 s
timer frame is about 5 ms of paint, about 0.5% of a core, over the 0.3%
idle cap, and it is not zero frames.

Decision: a signal pipe, not a timer. Both ends `O_NONBLOCK`. The handler
writes one byte and ignores `EAGAIN`. `Winch.ready` is the shared fd
park and consumes that byte, and the watcher sends `Resize{}`. No ack.
The frame calls
`timui_term_size` and repaints, inside the 1.1 s bound. Idle is zero frames
when nothing happens. This pipe is not a net wake.

### Frame

`FromNet`, `Key`, and `Resize` each run one `Timui.frame` with no wait.
`input_poll_ms` stays 0 (the vendored patch stays) so `timui_begin` does
not sleep again. `wait_ms` and `wake_fd` go away.

### K4 measurements

Same pty, before `f34bbc9` and after the parked UI. Idle CPU is the
marginal sample after the first paint. `cpu_pty.py` divides cumulative
rusage by the window, so it includes startup and is not the idle rate.

| | before | after |
|---|---|---|
| idle frames | 0.97/s (`--frames 20` in 20.70 s) | 0 (0 tty bytes in a 3 s quiet window) |
| idle CPU | 0.53% over those 20 frames | 0.00% / 0.01% (`tickrate.py`) |
| 1 msg / 1.5 s | 1.1% | 0.7% |
| key | min 4.1 ms | min 10.2 ms |
| resize | min 542 ms | min 6.2 ms |
| 001 → JOIN | 33.7 ms | 1.2 ms |
| paint wake | 42.5 ms | 8.1 ms |
| redial JOIN | min 90.1 ms | 1.6 ms |

Flood at about 100 lines/s was 33–50% before and 18–33% after. That is
not the 1% traffic gate. The full pty set on the after binary exited 0.

Every mode that opens a UI starts the tty watcher and the winch watcher,
including demo and replay. Demo `/connect` is typed on that tty. `frames=0`
parks forever (`@unsafe`). `frames=N` (N > 0) on a tty is a cap: at most N
messages, then shutdown. It does not spin.

The only loop that does not wait is the headless smoke
`birc --demo --frames 3` (no tty). It paints N frames and exits. A pty
test measures idle CPU of `--demo` with a tty and no input, so a busy
frame loop cannot hide there.
