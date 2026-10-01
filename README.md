# birc

A terminal IRC client built with **Bend 2** and **timui.h**.

Bend owns the protocol, client state, networking, and frame loop. Pure laws and
runtime tests check different parts of the application; neither proves the
whole client correct.

---

## Highlights

- **Bend core**: IRC parsing, message dispatch, connection state, line framing, command submission, and DNS packet handling live in Bend. IO drivers use Bend effects and thin POSIX FFI.
- **Checked pure core**: `bend PROOF.bend` checks quantified sanitization, single-chunk framer bounds, and authentication-state laws, plus concrete protocol, scroll, and rendering examples. See the exact proof scope below.
- **Parked event loop**: Descriptor watchers wake one Bend `Chan(UiMsg)`. A one-second maintenance tick expires typing state and checks whether refused terminal output can resume; a full output queue does not cause a busy retry loop.
- **Bend DNS**: A-record lookup, bounded CNAME handling, and UDP-to-TCP truncation fallback, without libc `getaddrinfo`.
- **Terminal UI**: C99 single-header rendering through [`timui.h`](https://timui.dev). Multi-channel tabs, activity/mention alerts, terminal bells, soft wrapping, mouse navigation, exact clickable links, typing indicators, bracketed paste, nested formatting (`*bold*` or `**bold**`, `_italic_`, `` `code` ``), and view-only emoji aliases. This is not a general Markdown renderer.
- **Image previews**: New live image links expand inline. Explicit `/preview`
  accepts local files and HTTP(S) URLs. Common formats use a bounded,
  provisioned decoder; supported Kitty/iTerm2 terminals can play animations.
- **Explicit bounds**: 512-byte IRC lines, capped buffers, bounded terminal writes, and UTF-8 decoding with Latin-1 fallback. Foreign effects and malformed inputs still need runtime tests.
- **Deterministic Offline & Replay Modes**: Built-in canned interactive demo (`--demo`) and deterministic session replayer (`--replay <file>`).

---

## Architecture

`birc` enforces a strict division of responsibilities: **Bend 2 owns the application lifecycle, protocol, client state, networking, and the frame loop**. C provides terminal rendering primitives and POSIX socket/clock calls; it does not parse IRC or own the frame loop.

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
|             | List<DrawOp> (OpSplit, OpImage, OpMedia)                  |
|             v                                                          |
+-------------|----------------------------------------------------------+
              | Foreign Effect (Timui.frame)
              v
+------------------------------------------------------------------------+
|                       C99 TimUI FFI (src/ffi/)                         |
|  - timui_ffi.c : Walks DrawOps, paints to terminal, returns keys       |
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
| [`src/bend/view.bend`](src/bend/view.bend) | Bend 2 | ViewModel generation, token-aware wrapping, and `List<DrawOp>` layout |
| [`src/bend/links.bend`](src/bend/links.bend) | Bend 2 | Shared URL/span lexer for rendering, listing, and opening |
| [`src/bend/media.bend`](src/bend/media.bend) | Bend 2 | Bounded image request identity, queue, cache policy, and stale-result guards |
| [`src/bend/diagnostic.bend`](src/bend/diagnostic.bend) | Bend 2 | Bounded private diagnostic text and safe helper results |
| [`src/bend/columns.bend`](src/bend/columns.bend) | Bend 2 | Terminal column widths and common cluster boundaries for wrapping |
| [`src/bend/auth.bend`](src/bend/auth.bend) | Bend 2 | Parsed SASL phase transitions and credential replies |
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
| [`src/media/image.py`](src/media/image.py) | Python | Bounded HTTP(S)/local image loading and normalization with Pillow |
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
- **`split_control_key`**, **`split_control_lookup`**, **`split_server_query_lookup`**: Internal pane keys distinguish control from a query named `server` for every client value.
- **`sasl_idle_no_reply`**, **`sasl_done_no_reply`**: No control event can send credentials before authentication is enabled or restart a completed exchange.
- **`auth_preserves_settings`**, **`timestamp_preserves_log_sequence`**: Authentication changes preserve settings; assigning timestamps preserves log identity.
- **`actor_zero_split`**, **`actor_exhausted_keeps_pending`**: Zero credit cannot emit or discard pending lines, for any queue.
- **`framer_roundtrip`**, **`flood_buffers`**, **`scroll_bounds`**, **`log_chrono`**, **`tokenize_*`**: Concrete framing, cap, scroll, ordering, and tokenization examples. `flood_server_clean` checks that rejected JOINs add server diagnostics; it does not prove general absence of corruption.
- **`narrow_cluster_source_count`**, **`wide_cluster_source_count`**: Concrete source-length checks for a multi-codepoint emoji with and without a narrow-pane replacement.
- **`tokenize_unclosed_source_order`**, **`code_span_dim`**: Concrete source-order checks for three unmatched markers and the live dim attribute for one code span.

Verify all proofs at any time:
```sh
make proof
```

The normal gate uses Bend's checker. `make proof-kernel` also requests the
independent BendTT kernel. It needs Lean v4.34.0 or a configured `BENDTT`;
missing tools fail the target. Foreign effects and `@unsafe` live loops are
outside these pure proof guarantees. Runtime, PTY, and sanitizer tests cover
those paths separately.

Terminal writes have a shared frame deadline. Partial UTF-8 scalars retain at
most three suffix bytes, which must precede later output. One serialized frame
retains its accepted-byte offset and resumes on a writable maintenance tick;
it does not restart its prefix. Capture is capped at 64 MiB. Allocation or cap
failure discards that whole capture and exits through normal terminal cleanup
with a nonzero status. A full output queue does not cause a busy retry loop.
Ordinary frames have 40 ms, writable repairs have 200 ms.
Signal restoration owns stable descriptor references. A handler already using
Ui can retain one complete owner until final exit; close never waits for it.
Final output suppresses same-stream status while ownership or terminal debt
remains unresolved. This is not general concurrent access support for Ui.
Headless live startup awaits the bounded registration result and reports
initial connection failure with a nonzero exit.

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

# Or invoke the built binary inside the locked development shell
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
endpoints do not share chat buffers or stored history. The in-memory `*log*`
belongs to the app session and survives endpoint changes. The reader scans the file to its
initial size, keeps only the configured recent records, and rejects malformed
or overlong records. An incomplete final record is not loaded.

The pinned file-size API supports at most 4,294,967,295 bytes. Larger files
produce a visible history error instead of an empty restore. Other size/read
errors are also visible. A failed read retains only completed records from
the prefix already read. A missing optional history file is normal.

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

Display formatting supports `*bold*`, `**bold**`, `_italic_`, nested bold and
italic, and opaque dim backticks. Unmatched markers stay literal. A backslash
escapes `*`, `_`, backticks, backslash, or colon. The 22 chat-demo emoji aliases
(for example `:eyes:`, `:fire:`, and `:+1:`) expand only in displayed text.
Unknown names, code spans, and exact URLs stay unchanged. Sent text and history
keep the original message. Styled URLs close formatting at the token end;
internal URL punctuation is not markup.

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
| `/log` | Open the read-only diagnostic buffer; also works offline |
| `/split [orientation] [buffer]` | Open a stacked split by default; orientation is `horizontal` or `vertical`, and the target must already be open |
| `/vsplit [buffer]` | Open a side-by-side split with an existing buffer |
| `/focus` | Move focus to the other split pane |
| `/split-off` or `/unsplit` | Close the split without closing either buffer |
| `/preview <path-or-url>` | Preview a local image (also `file://`-prefixed paths) or an HTTP(S) image URL in `*preview*` |
| `/images on` / `/images off` | Enable or disable automatic image previews; explicit `/preview` remains available |
| `/set bell on` / `/set bell off` | Enable or disable terminal bells for mentions and private messages |
| `/nick <newnick>` | Change your current nickname |
| `/me <action>` | Send a CTCP ACTION message (e.g. `/me waves`) |
| `/quit [reason]` | Disconnect from the server and exit `birc` |

Send, scroll, nick-list, and status actions use the focused pane. Split commands
never join a channel or create a buffer. Use `/split *server*` to select the
control buffer explicitly. `/split server` selects a private query named
`server` if it exists; otherwise it keeps the legacy control-buffer alias.

Live connections automatically reconnect to the saved host and port two seconds
after an unexpected disconnect. A manual `/connect` cancels the pending retry.
Use `/set autoreconn off` to disable this behavior.

### Diagnostic log

Errors stay in their original buffer. A private copy also appears in `*log*`,
without changing focus. `/log` opens the log; `/close` removes it. The next
error creates it again. Connection, reconnect, and authentication stages are
recorded while the log exists.

The log holds at most 128 rows of 512 characters in memory. It survives server
changes, but is not saved to chat history. One of the existing 16 buffer slots
is reserved for it. Diagnostic copies remove HTTP(S) URLs and configured SASL
credentials. Helper failures show only the operation and numeric error or exit
code, never child output. This does not redact the original chat/error row.

The log includes failed clipboard helpers, link openers, image previews,
history loads/saves, and socket reads. A fatal startup error can exit before
there is an interactive buffer; it remains an exit diagnostic.

### Images and privacy

Automatic previews apply to new live messages with direct PNG, JPEG, GIF,
WebP, BMP, TIFF, or AVIF links, or Markdown `![alt](URL)` image links. Saved
history, replay, and demo messages do not trigger automatic requests. Sent
messages and stored history keep the exact original text and URL.

Fetching an image discloses your IP address to its host. Use `/images off` or
start with `BIRC_IMAGES=off` to prevent automatic requests. Disabling previews
clears their visible state and ignores late automatic results. A helper already
running finishes within its bound; disabling or quitting does not cancel it.

The helper permits only public HTTP(S) hosts on standard ports. It checks every
redirect, pins resolved addresses for connection, verifies HTTPS certificates,
and sends no cookies or proxy credentials. It does not fetch private/loopback
hosts, follow HTTPS-to-HTTP redirects, or load local paths posted in chat.
Explicit local previews require a bounded regular file.

Downloads are capped at 8 MiB; local inputs at 16 MiB. Source images are capped
at 4096 pixels per side and 16,777,216 pixels. Normalized previews fit within
320 pixels per side. Animations have at most 24 frames, with additional total
pixel and encoded-output limits. The helper has an eight-second deadline.
Bend allows one active helper, eight queued requests, and eight cached results.

Kitty and iTerm2 handle animation in the terminal; birc does not add an
animation timer. Sixel uses the first frame. Unsupported image terminals show
a placeholder. A partially clipped iTerm2 image also shows a placeholder,
because that protocol has no source-crop command. Terminal and multiplexer
support can differ.

Use `make shell` before invoking `./build/birc` directly. The Nix package sets
an absolute helper path. `BIRC_MEDIA_HELPER` can override the helper program
for development and synthetic tests; it is an executable path, not a shell
command. Reload an existing Nix shell after provisioning changes.

---

## Development & Verification

The project root [`Makefile`](Makefile) is the sole driver. Routine development uses `--no-update-lock-file` to ensure strict reproducibility.

```sh
make shell                 # Enter the locked Nix development environment
make check                 # Proofs + pure tests + FFI lints + UI smoke
make proof                 # Run Bend formal proof checker (PROOF.bend)
make test-pty              # Run the PTY integration suite
make test-live             # Run mock IRC socket handshake test
make lint-ffi              # Strict syntax and compiler warning lint of C FFI
make clean                 # Remove build artifacts
```

### Testing Strategy

`birc` employs a multi-tiered test harness:
1. **Bend Proof Checks**: `PROOF.bend` checks quantified laws and concrete examples. `make proof-kernel` is the separate independent validity gate.
2. **Pure Functional Unit Tests**: Fast tests in `tests/bend/` verifying protocol serialization, state transitions, client routing, and argument parsing.
3. **PTY End-to-End Suite**: Automated pseudo-terminal tests in `tests/pty/` exercise real terminal behavior (terminal resizes, rapid pasting, channel switching latency, buffer flood, stalled I/O, TCP disconnects/reconnects, and signal handling).
4. **C FFI Linting**: The warning flags are defined by `LINT_FFI_CFLAGS` in the Makefile. Warnings fail the lint gate.

---

## License

Licensed under the **Apache License, Version 2.0** ([`LICENSE`](LICENSE)).

Copyright (c) Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
