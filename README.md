# birc

A lean, formally verified terminal IRC client built with **Bend 2** and **timui.h**.

`birc` demonstrates that a concurrent, network-driven interactive application can be written in Bend's interaction-calculus model with formal mathematical proofs, ultra-low resource usage, and minimal foreign effects.

---

## Highlights

- **Pure Functional Core (>91% Bend 2)**: IRC protocol parsing, message dispatch, connection state, line framing, command submission, and UDP DNS resolution are implemented purely in Bend.
- **Checked pure core**: `bend PROOF.bend` checks quantified sanitization, single-chunk framer bounds, and authentication-state laws, plus concrete protocol, scroll, and rendering examples. See the exact proof scope below.
- **Zero-Poll / 0.0% Idle CPU**: The event loop parks on OS descriptors (terminal tty, `SIGWINCH` resize pipe, and socket dup) waking a single Bend `Chan(UiMsg)` channel. No polling, no busy-waiting.
- **Native DNS Engine**: Full RFC 1035 UDP A-record DNS client implemented directly in Bend with wire-format packet cursors, CNAME chasing, and fault tolerance—independent of libc `getaddrinfo`.
- **Modern Terminal Experience**: Rendered via a clean C99 single-header library ([`timui.h`](https://timui.dev)). Supports multi-channel tabs, visual activity/mention alerts, configurable terminal bells, resize-safe soft wrapping, mouse navigation, clickable OSC 8 links, IRCv3 live typing indicators, bracketed paste, and markdown formatting (`*bold*`, `_italic_`, `` `code` ``).
- **Hardened for Production**: Bounded memory, strict 512-byte IRC wire clamping, UTF-8 decoder with Latin-1 fallback, flood protection, and fail-closed error handling.
- **Deterministic Offline & Replay Modes**: Built-in canned interactive demo (`--demo`) and deterministic session replayer (`--replay <file>`).

---

## Architecture

`birc` enforces a strict division of responsibilities: **Bend 2 owns the application lifecycle, protocol, client state, networking, and the frame loop**. C is restricted to a thin (~760 line) FFI wrapper providing terminal rendering primitives and POSIX socket/clock calls.

```text
+------------------------------------------------------------------------+
|                              Bend 2 Core                               |
|                                                                        |
|  +---------------------+   Outbound Lines   +-----------------------+  |
|  |   Composer/Submit   | -----------------> |      Net Actor        |  |
|  |   (submit.bend)     |                    |    (actor.bend)       |  |
|  +---------------------+                    +-----------------------+  |
|             ^                                       |         ^        |
|             | Key/Mouse                             | TCP     | recv   |
|             v Events                                v send    | octets |
|  +---------------------+   Inbound Lines    +-----------------------+  |
|  |    Client State     | <----------------- |     CRLF Framer       |  |
|  | (client/buffer.bend)|                    |     (frame.bend)      |  |
|  +---------------------+                    +-----------------------+  |
|             |                                                          |
|             | ViewModel                                                |
|             v                                                          |
|  +---------------------+                                               |
|  |     View Layout     |                                               |
|  |     (view.bend)     |                                               |
|  +---------------------+                                               |
|             |                                                          |
|             | List<DrawOp> (includes OpSplit and OpImage)              |
|             v                                                          |
+-------------|----------------------------------------------------------+
              | Foreign Effect (Timui.frame)
              v
+------------------------------------------------------------------------+
|                       C99 TimUI FFI (src/ffi/)                         |
|  - timui_ffi.c : Walks DrawOps, paints to terminal, polls input        |
|  - dns_ffi.c   : POSIX socket dup, shutdown, octet send/recv           |
|  - clock_ffi.c : Local clock seconds-of-day                            |
+------------------------------------------------------------------------+
```

### Module Layout

| Path | Language | Role |
|---|---|---|
| [`src/bend/app.bend`](src/bend/app.bend) | Bend 2 | Application entrypoint, CLI dispatch, and lifecycle |
| [`src/bend/irc.bend`](src/bend/irc.bend) | Bend 2 | Pure RFC 1459/2812 parser, classifier, and wire formatter |
| [`src/bend/client.bend`](src/bend/client.bend) | Bend 2 | Incoming IRC event dispatcher (`feed`) and state transitions |
| [`src/bend/buffer.bend`](src/bend/buffer.bend) | Bend 2 | Channel/query buffer container and nick list data structures |
| [`src/bend/client_laws.bend`](src/bend/client_laws.bend) | Bend 2 | Feed inspectors, invariants, and client law predicates |
| [`src/bend/submit.bend`](src/bend/submit.bend) | Bend 2 | User slash-command parsing and outbound line formatting |
| [`src/bend/frame.bend`](src/bend/frame.bend) | Bend 2 | Structural CRLF octet framer and UTF-8 decoder with Latin-1 fallback |
| [`src/bend/dns.bend`](src/bend/dns.bend) | Bend 2 | High-level UDP DNS resolution driver with fuel timeout |
| [`src/bend/dns_wire.bend`](src/bend/dns_wire.bend) | Bend 2 | RFC 1035 DNS packet encoder, parser, and cursor combinators |
| [`src/bend/view.bend`](src/bend/view.bend) | Bend 2 | ViewModel generation, span tokenizer, and `List<DrawOp>` layout |
| [`src/bend/session.bend`](src/bend/session.bend) | Bend 2 | UI session state, history ring buffer, and key mapping |
| [`src/bend/typing.bend`](src/bend/typing.bend) | Bend 2 | Bounded IRCv3 typing state and wrap-safe expiry |
| [`src/bend/actor.bend`](src/bend/actor.bend) | Bend 2 | Background network actor: socket ownership and read/write loops |
| [`src/bend/outbound.bend`](src/bend/outbound.bend) | Bend 2 | Pure outbound batches, FIFO splits, and finite send credits |
| [`src/bend/net.bend`](src/bend/net.bend) | Bend 2 | UI channel event loop, descriptor watchers, and shutdown |
| [`src/bend/args.bend`](src/bend/args.bend) | Bend 2 | Pure command-line argument parser |
| [`src/bend/timui.bend`](src/bend/timui.bend) | Bend 2 | Bend handles and effect declarations for TimUI FFI |
| [`src/bend/clock.bend`](src/bend/clock.bend) | Bend 2 | Timestamp formatting (`HH:MM:SS`) from seconds-of-day |
| [`src/ffi/timui_ffi.c`](src/ffi/timui_ffi.c) | C99 | Thin TimUI rendering bridge, tty watcher, and winch pipe |
| [`src/ffi/dns_ffi.c`](src/ffi/dns_ffi.c) | C99 | UDP/TCP socket primitives: `recv_octets`, `send_octets`, dup, shutdown |
| [`src/ffi/clock_ffi.c`](src/ffi/clock_ffi.c) | C99 | POSIX `local_secs` clock reader |
| [`LAWS.bend`](LAWS.bend) / [`PROOF.bend`](PROOF.bend) | Bend 2 | Quantified proofs and concrete checked examples |

---

## Formal Verification

`birc` uses Bend's interaction calculus proof checker to verify protocol properties and structural invariants before compilation. All proofs live in [`PROOF.bend`](PROOF.bend) and correspond directly to declarations in [`LAWS.bend`](LAWS.bend).

Quantified laws apply to every input named in their declarations. Most other
laws check concrete examples, not all possible inputs. Current coverage includes:
- **`strip_ctl_clean`**: Inductive proof that `strip_ctl(s)` eliminates all CR and LF characters across **all** possible strings `s`:
  ```bend
  law strip_ctl_clean:
    for s: String
    {Irc.has_crlf(Irc.strip_ctl(s)) == False{} : Bool}
  ```
- **`push_rem_bound`**: For every octet chunk, `push(Nil, chunk)` retains at most `LINE_OCTET_MAX + 1` octets. This statement starts with an empty remainder; it is not a quantified multi-chunk invariant.
- **`search_empty_line`**, **`split_focus_involution`**: Quantified empty-query and two-focus-toggle properties.
- **`sasl_idle_no_reply`**, **`sasl_done_no_reply`**: No control event can send credentials before authentication is enabled or restart a completed exchange.
- **`auth_preserves_settings`**, **`timestamp_preserves_log_sequence`**: Authentication changes preserve settings; assigning timestamps preserves log identity.
- **`actor_zero_split`**, **`actor_exhausted_keeps_pending`**: Zero credit cannot emit or discard pending lines, for any queue.
- **`framer_roundtrip`**, **`flood_buffers`**, **`scroll_bounds`**, **`log_chrono`**, **`tokenize_*`**: Concrete framing, cap, scroll, ordering, and tokenization examples. `flood_server_clean` checks that rejected JOINs add server diagnostics; it does not prove general absence of corruption.

Verify all proofs at any time:
```sh
make proof
```

The normal gate uses Bend's checker. `make proof-kernel` also requests the
independent BendTT kernel. It needs Lean v4.34.0 or a configured `BENDTT`;
missing tools fail the target. Foreign effects and `@unsafe` live loops are
outside these pure proof guarantees. Runtime, PTY, and sanitizer tests cover
those paths separately.

---

## Quick Start

### Run Directly with Nix Flakes

Run `birc` instantly without cloning:

```sh
# Launch offline interactive demo
nix run github:angerman/birc -- --demo

# Connect to a live IRC network
nix run github:angerman/birc -- --connect irc.libera.chat --channel '#bend'
```

### 1. Build and Test Locally

```sh
make bootstrap   # Once: create flake.lock
make check       # Run formal proofs, unit tests, live mock, and FFI lints
```

### 2. Offline Interactive Demo

Experience the full TimUI interface, rich text rendering, and mock channels without connecting to a network:

```sh
make run-demo
```

### 3. Connect to Live IRC

Connect to any plaintext IRC network:

```sh
# Run directly without cloning
nix run github:angerman/birc -- --connect irc.libera.chat --nick mynick --channel '#birc'

# Or via make in a cloned checkout
make run HOST=irc.libera.chat NICK=birc_user CHAN='#birc'

# Or invoke the built binary directly
./build/birc --connect irc.libera.chat --port 6667 --nick mynick --channel '#birc'
```

### 4. Replay Captured Sessions

Replay raw IRC wire logs deterministically for testing or inspection:

```sh
./build/birc --replay fixtures/demo.irc
```

---

## Command-Line Options

Run `./build/birc --help-irc` for a full summary:

| Option | Argument | Description |
|---|---|---|
| `--connect` | `<host>` | IRC server hostname or IPv4 address |
| `--port` | `<port>` | Server port (1–65535, default: `6667`) |
| `--nick` | `<nick>` | IRC nickname (default: `birc`) |
| `--channel` | `<channel>` | Initial channel to join upon registration (default: `#birc`) |
| `--demo` | — | Run offline demo with canned mock activity |
| `--replay` | `<file>` | Feed an IRC log capture into the client and launch UI |
| `--frames` | `<n>` | Run for `n` frames/ticks (headless batch test if stdin not a tty) |
| `--help-irc` | — | Show birc client command-line options |

### Stored history

History records use `BIRC2` and include the server hostname and port. Different
endpoints do not share buffers or history. The reader scans the file to its
initial size, keeps only the configured recent records, and rejects malformed
or overlong records. An incomplete final record is not loaded.

Older records without an endpoint remain in the file but are not restored.
Their server identity cannot be recovered safely. Reconnect dividers and
`/links` output are display data and are not saved as chat.

---

## Navigation & Controls

### Keyboard Navigation

| Key | Action |
|---|---|
| <kbd>Shift</kbd> + <kbd>&larr;</kbd> | Switch to previous buffer tab |
| <kbd>Shift</kbd> + <kbd>&rarr;</kbd> | Switch to next buffer tab |
| <kbd>Page Up</kbd> | Scroll active buffer view up |
| <kbd>Page Down</kbd> | Scroll active buffer view down |
| <kbd>F6</kbd> / <kbd>Ctrl</kbd> + <kbd>W</kbd> | Move focus to the other split pane |
| <kbd>&uarr;</kbd> (Up Arrow) | Recall previous command from history |
| <kbd>&darr;</kbd> (Down Arrow) | Recall next command from history |
| <kbd>Ctrl</kbd> + <kbd>A</kbd> | Move the composer cursor to the start of the line |
| <kbd>Ctrl</kbd> + <kbd>K</kbd> | Delete from the composer cursor to the end of the line |
| <kbd>Enter</kbd> | Send typed message or slash command; snap scroll to latest |
| <kbd>Esc</kbd> / <kbd>F10</kbd> | Cleanly disconnect and quit |

### Mouse Navigation

- **Click Tab**: Directly switch to any visible buffer tab.
- **Mouse Wheel**: Scroll buffer scrollback history up or down.
- **Drag in a Pane**: Select and copy text within that pane.

### In-Client Commands

Type commands into the composer prompt:

| Command | Description |
|---|---|
| `/connect <host> [port]` | Connect to an IRC server (from demo or offline mode) |
| `/reconnect` | Reconnect to the saved server and port |
| `/join <channel>` | Join an IRC channel (e.g. `/join #bend`) |
| `/part [reason]` | Leave the active channel |
| `/close` | Close the active private query buffer tab |
| `/msg <target> <text>` | Send a private message to a nick or channel |
| `/search <query>` | Search all buffer scrollback and open the results in `*search*` |
| `/split [orientation] [buffer]` | Open a stacked split by default; orientation is `horizontal` or `vertical`, and the target must already be open |
| `/vsplit [buffer]` | Open a side-by-side split with an existing buffer |
| `/focus` | Move focus to the other split pane |
| `/split-off` or `/unsplit` | Close the split without closing either buffer |
| `/preview <local-path>` | Preview one local PNG from a path or `file://`-prefixed local path; HTTP(S) is rejected |
| `/set bell on` / `/set bell off` | Enable or disable terminal bells for mentions and private messages |
| `/nick <newnick>` | Change your current nickname |
| `/me <action>` | Send a CTCP ACTION message (e.g. `/me waves`) |
| `/quit [reason]` | Disconnect from the server and exit `birc` |

Send, scroll, nick-list, and status actions use the focused pane. Split commands
never join a channel or create a buffer.

Live connections automatically reconnect to the saved host and port two seconds
after an unexpected disconnect. A manual `/connect` cancels the pending retry.
Use `/set autoreconn off` to disable this behavior.

---

## Development & Verification

The project root [`Makefile`](Makefile) is the sole driver. Routine development uses `--no-update-lock-file` to ensure strict reproducibility.

```sh
make shell                 # Enter the locked Nix development environment
make check                 # Proofs + pure tests + FFI lints + UI smoke
make proof                 # Run Bend formal proof checker (PROOF.bend)
make test-pty              # Run comprehensive 28-scenario PTY integration suite
make test-live             # Run mock IRC socket handshake test
make lint-ffi              # Strict syntax and compiler warning lint of C FFI
make clean                 # Remove build artifacts
```

### Testing Strategy

`birc` employs a multi-tiered test harness:
1. **Mathematical Proofs**: `PROOF.bend` proves core invariants at the language level.
2. **Pure Functional Unit Tests**: Fast tests in `tests/bend/` verifying protocol serialization, state transitions, client routing, and argument parsing.
3. **PTY End-to-End Suite**: 28 automated pseudo-terminal tests in `tests/pty/` exercising real terminal behavior (terminal resizes, rapid pasting, channel switching latency, buffer flood, stalled I/O, TCP disconnects/reconnects, and signal handling).
4. **C FFI Linting**: Clang `-Wall -Wextra -pedantic -Wshadow -Wconversion -Werror` linting of all foreign interfaces.

---

## License

Licensed under the **Apache License, Version 2.0** ([`LICENSE`](LICENSE)).

Copyright (c) Moritz Angermann <moritz.angermann@gmail.com>.
