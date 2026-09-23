# Bend ↔ TimUI / native FFI

Pinned Bend: see `flake.lock` (`bend-src`). Foreign effects follow bendano
TOOLCHAIN conventions and upstream `bend2/effs/*.c`.

## Shape

```bend
law Timui.frame:
  Ui -> List<&2, V.DrawOp> -> String -> U32 -> U32 -> U32 -> U32 -> IO(Ui & UiKeys)

def Timui.frame(ui, ops, input, seed, page, wait_ms, wake_fd):
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
| `Timui.open` / `Timui.frame` / `Timui.close` | `src/ffi/timui_ffi.c` | `TIMUI_IMPLEMENTATION` once |
| `recv_octets` | `src/ffi/dns_ffi.c` | UDP/TCP octets + peer; not `UDP.recv` String |
| `send_octets` | `src/ffi/dns_ffi.c` | UDP datagram from `List U32` (twin of recv) |
| `fd_hint` | `src/ffi/dns_ffi.c` | `Socket -> IO(Socket & U32)`; copies the fd, keeps the handle |
| `local_secs` | `src/ffi/clock_ffi.c` | local seconds-of-day as `U32`; Bend formats HH:MM:SS |
| `wake_poke` | `src/ffi/timui_ffi.c` | write one byte on the Ui self-pipe; actor posts after Up/Chunk/Fail/Eof |

Live TCP outbound is Base `TCP.send` (String). Live inbound is `recv_octets` +
`Fr.push`, not `TCP.recv`. `recv_octets` is non-blocking (`io_eff` flags `0`);
`None` is EAGAIN/EINTR so the actor can still Tick. It is **not** registered
with `IO_READ` (that park would freeze Ticks). Peer is `host & (port & octets)`
beside the payload (C7).

The actor maps both a `Fail` (RST, POLLERR, other recv errno) and a
`Done{Some{…, Nil{}}}` (zero-length read, clean FIN) to `NetEvt.Eof`. The UI
then paints `disconnected` and stays up. `Done{None{}}` is idle (Tick).

## Build

`bend src/bend/app.bend -o build/birc_bend.c`, then
`$CC -std=c11 -O2 -pthread -w -Isrc/ui -Isrc/ffi build/birc_bend.c -o build/birc`.

The real build uses `-w` because Bend's emitted C trips `-Wall`. Warning lint
of the project FFI is `make lint-ffi`: stub header `tests/lint-ffi/ffi_stub.h`,
`-Wall -Wextra -pedantic -Wshadow -Wconversion -fsyntax-only -isystem src/ui`.

## App UI

```text
law Ui: Type

Timui.open  : IO(Result<&1,&1, U32 & String, Ui>)
Timui.frame : Ui -> List<&2, DrawOp> -> String -> U32 -> U32 -> U32 -> U32 -> IO(Ui & UiKeys)
Timui.close : Ui -> IO(Unit)
```

`UiKeys` is Data. `typed` is a `String` (the composer field). `rows` and `cols`
are the live root size. Other fields are U32 flags/counters (`quit`, `enter`,
`tab`, `click`, `up`, `dn`, `hist`). Unpack like `Window.frame`. Do not put
`Ui` inside a `Result`. `seed != 0` reseeds the composer from `input`,
including `""`. `page` is `Sess.body_h` (PageUp/PageDown line count).
`wait_ms` is how long C `poll()`s the tty (and optional `wake_fd`) before
`timui_begin`. Bend uses 16 ms while `Connecting`, while `now < hot_until`
(50 ms after Up/Chunk/Fail/Eof or keys, via `IO.now`; the poke byte already
wakes the frame after an event), or if the composer is
non-empty; else 1000 ms. C also caps the poll at 0 ms if `event_count` or
`pending_*` is non-empty, and at 16 ms if the composer has text or the
previous frame saw keys (`hot_next`), so a one-write line+CR after idle
cannot lose Enter behind a 1000 ms wait. Idle CPU (`tickrate.py`): ~0.5% of a core. With one
inbound line every 1.5–2 s (`ratecpu.py`): ~1.0% of a core (was 5–6% at a
2000 ms window). Actor events sit in a channel, so a 1000 ms poll
would miss them (001 → JOIN waited a full idle tick). `wake_fd` is a **wake hint**: the actor's socket fd
as a plain `U32` (0 = none), from `fd_hint`. The UI never reads that socket;
the actor still owns the handle. A self-pipe on the Ui handle is also polled;
`wake_poke` writes one byte when the actor posts Up/Chunk/Fail/Eof so those
events do not wait out the idle poll. `Timui.open` sets TimUI `input_poll_ms` to 0
so `timui_begin` does not sleep again after the FFI poll.
Test-only: `BIRC_DIE_AFTER_OPEN=1` calls `exit(1)` after `atexit` is
registered so `tests/pty/restore.py` can check cooked mode without
`Timui.close`.

### Vendored `timui.h` patches

Local edits to `src/ui/timui.h` (re-apply on an upstream update):

1. **`input_poll_ms`** on `TimuiConfig` (default 16). `timui_begin` uses it for
   the tty poll and the non-tty nanosleep. birc sets 0 so begin does not sleep
   after the FFI `wait_ms` poll.
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
   same hold/unget when the tables are full. The PASTE hold guard bounds
   `text_in_len + paste.len` (not a 4-byte code point). The deferred
   post-Enter tail also keeps Backspace and cursor ops (`pending_edit_ops`).

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
  past `maxx` (no continuation row). A URL longer than 511 bytes is drawn as
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

## K1 — input actor (design, not yet the code)

Replaces the C wait path (`birc_wait_fds`, the Ui self-pipe, `wake_poke`,
`fd_hint`, `wait_ms` / `wake_fd`, the Bend hot window). The runtime already
parks an effect registered with `IO_READ` on the fd of its first handle
argument until `POLLIN` (`bend2/comp.ts` `io_step`; `tcp_recv.c` is the
pattern). K2 implements this section. Until that commit, the paragraphs
above are still what the program does.

### Wake sources

One UI channel, `Chan(UiMsg)`, capacity 64. Three producers:

| Producer | Message | How it wakes |
|---|---|---|
| Net actor | `FromNet{NetEvt}` | `Chan.send`, as today |
| Tty watcher | `Key{}` | parks in `Tty.ready` |
| Winch watcher | `Resize{}` | parks in `Winch.ready` |

The UI thread blocks only in `Chan.recv`. It does not poll.

`Timui.tty(ui) -> Tty` dups the tty fd into a fresh linear handle. The Ui
keeps the original fd. `Tty.ready(tty) -> IO(Unit)` is `io_eff(..., IO_READ)`
and does not read the bytes (`timui_begin` does). The watcher loop is:

```text
Tty.ready(tty)
Chan.send(ui_evt, Key{})
Chan.recv(ack)
```

The ack is what stops a busy loop while the tty stays readable. The UI
sends it only after `Timui.frame` has returned. `Tty.close` closes the dup.

### Resize

TimUI has no `SIGWINCH` handler. `timui_term_size` is `TIOCGWINSZ`, and the
frame already uses that size. A 1 s `IO.sleep` tick would paint about once
a second. A frame costs about 5 ms, so that is about 0.5% of a core, over
the K4 idle cap of 0.3%, and it is not zero frames.

Decision: a signal pipe, not a timer. One self-pipe, both ends
`O_NONBLOCK`. The `SIGWINCH` handler writes one byte and ignores `EAGAIN`
(a pending byte already means "resize"). `Winch.ready` is `IO_READ` on the
read end and consumes that byte, then the watcher sends `Resize{}`. No ack:
the byte is gone, so the next `ready` parks until the next signal. The UI
frame calls `timui_term_size` and repaints. That is well inside the 1.1 s
resize bound, and idle is zero frames when nothing happens.

This pipe is not the old wake pipe. Net events do not use it.

### Frame

`FromNet`, `Key`, and `Resize` each run one `Timui.frame` with no wait.
`input_poll_ms` stays 0, and the vendored patch stays: `timui_begin` must
not sleep again after the runtime has already woken us. `wait_ms` and
`wake_fd` go away.

`--frames N` (N > 0) is still a fuel cap: at most N messages, then
shutdown. `frames=0` is the unbounded park (`@unsafe`). Demo and replay do
not start the tty or winch watchers; they keep a fuel loop of frames with
no wait.

### NetCmd counting

The net actor's bargain does not change. After it sends one `NetEvt` it
waits for exactly one `NetCmd` (`idle_after_tick`, `reader_go`). The UI
sends that command only when the message it just took is `FromNet{e}`.

`Key` and `Resize` are not net events. Handling them does not
`Chan.send` a `NetCmd`. Their ack, if any, is the watcher's ack channel,
not the command channel. A key that arrives while the actor is blocked in
`Chan.recv(cmd)` stays queued until the UI has answered the outstanding
`FromNet`; it must not be that answer.
