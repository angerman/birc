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
- **Verified IRC TLS**: OpenSSL checks certificate trust and the server name.
  TLS is the default; only `--plain` selects plaintext. Ports do not select mode.
- **Terminal UI**: C99 single-header rendering through [`timui.h`](https://timui.dev). Multi-channel tabs, activity/mention alerts, terminal bells, soft wrapping, mouse navigation, exact clickable links, typing indicators, bracketed paste, nested formatting (`*bold*` or `**bold**`, `_italic_`, `` `code` ``), and view-only emoji aliases. This is not a general Markdown renderer.
- **Image previews**: New live image links expand inline. Explicit `/preview`
  accepts local files and HTTP(S) URLs. Common formats use a bounded,
  provisioned decoder; supported Kitty/iTerm2 terminals can play animations.
- **Confirmed file uploads**: Exact local file drops and `/upload` stage a
  public upload to 0x0.st. Each file needs its own F8 confirmation.
- **Explicit bounds**: 512-byte IRC lines, capped buffers, bounded terminal writes, and UTF-8 decoding with Latin-1 fallback. Foreign effects and malformed inputs still need runtime tests.
- **Deterministic Offline & Replay Modes**: Built-in canned interactive demo (`--demo`) and deterministic session replayer (`--replay <file>`).

---

## Architecture

`birc` enforces a strict division of responsibilities: **Bend 2 owns the application lifecycle, protocol, client state, networking, and the frame loop**. C provides terminal rendering, POSIX socket/clock calls, and verified OpenSSL TLS effects; it does not parse IRC or own the frame loop.

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
|             | List<DrawOp> (OpSplit, OpMedia, text and geometry)         |
|             v                                                          |
+-------------|----------------------------------------------------------+
              | Foreign Effect (Timui.frame)
              v
+------------------------------------------------------------------------+
|                       C11 Native FFI (src/ffi/)                        |
|  - timui_ffi.c : Walks DrawOps, paints to terminal, returns keys       |
|  - dns_ffi.c   : POSIX socket dup, shutdown, octet send/recv           |
|  - tls_ffi.c   : Verified OpenSSL handshake and encrypted IO          |
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
| [`src/bend/replay.bend`](src/bend/replay.bend) | Bend 2 | Bounded file-snapshot replay through the live byte framer |
| [`src/bend/submit.bend`](src/bend/submit.bend) | Bend 2 | User slash-command parsing and outbound line formatting |
| [`src/bend/irc_commands.bend`](src/bend/irc_commands.bend) / [`message_chunks.bend`](src/bend/message_chunks.bend) | Bend 2 | Shared command validation and lossless cluster-safe wire splitting |
| [`src/bend/join_plan.bend`](src/bend/join_plan.bend) / [`channel_policy.bend`](src/bend/channel_policy.bend) | Bend 2 | Desired channels, transient keys, and authentication-gated recovery |
| [`src/bend/frame.bend`](src/bend/frame.bend) | Bend 2 | Structural CRLF octet framer and UTF-8 decoder with Latin-1 fallback |
| [`src/bend/dns.bend`](src/bend/dns.bend) | Bend 2 | High-level UDP DNS resolution driver with fuel timeout |
| [`src/bend/dns_wire.bend`](src/bend/dns_wire.bend) | Bend 2 | RFC 1035 DNS packet encoder, parser, and cursor combinators |
| [`src/bend/view.bend`](src/bend/view.bend) | Bend 2 | ViewModel generation, token-aware wrapping, and `List<DrawOp>` layout |
| [`src/bend/view_laws.bend`](src/bend/view_laws.bend) | Bend 2 | View fixtures and proof-facing layout predicates |
| [`src/bend/links.bend`](src/bend/links.bend) | Bend 2 | Shared URL/span lexer for rendering, listing, and opening |
| [`src/bend/media.bend`](src/bend/media.bend) | Bend 2 | Bounded image request identity, queue, cache policy, and stale-result guards |
| [`src/bend/diagnostic.bend`](src/bend/diagnostic.bend) | Bend 2 | Bounded private diagnostic text and safe helper results |
| [`src/bend/columns.bend`](src/bend/columns.bend) | Bend 2 | Terminal column widths and common cluster boundaries for wrapping |
| [`src/bend/history_io.bend`](src/bend/history_io.bend) | Bend 2 | Private history append effects, separate from proof-facing history rules |
| [`src/bend/history_startup.bend`](src/bend/history_startup.bend) / [`history_startup_io.bend`](src/bend/history_startup_io.bend) | Bend 2 | Auth-free snapshots, nontrimming import, and fresh-ID startup dividers |
| [`src/bend/preferences_runtime.bend`](src/bend/preferences_runtime.bend) / [`preferences_live.bend`](src/bend/preferences_live.bend) | Bend 2 | Bounded settings queue, edit-wins loading, and quit drain |
| [`src/bend/live_context.bend`](src/bend/live_context.bend) / [`startup_headless.bend`](src/bend/startup_headless.bend) | Bend 2 | Settings-before-history ordering and generation-scoped connection release |
| [`src/bend/auth.bend`](src/bend/auth.bend) | Bend 2 | Parsed SASL phase transitions and credential replies |
| [`src/bend/session.bend`](src/bend/session.bend) | Bend 2 | UI session state, history ring buffer, and key mapping |
| [`src/bend/typing.bend`](src/bend/typing.bend) | Bend 2 | Bounded IRCv3 typing state and wrap-safe expiry |
| [`src/bend/actor.bend`](src/bend/actor.bend) | Bend 2 | Background network actor: transport ownership and read/write loops |
| [`src/bend/transport_policy.bend`](src/bend/transport_policy.bend) / [`src/bend/transport.bend`](src/bend/transport.bend) | Bend 2 | Pure TLS selection and affine plaintext/TLS IO dispatch |
| [`src/bend/outbound.bend`](src/bend/outbound.bend) | Bend 2 | Pure outbound batches, FIFO splits, and finite send credits |
| [`src/bend/net.bend`](src/bend/net.bend) | Bend 2 | UI channel event loop, descriptor watchers, and shutdown |
| [`src/bend/args.bend`](src/bend/args.bend) | Bend 2 | Pure command-line argument parser |
| [`src/bend/timui.bend`](src/bend/timui.bend) | Bend 2 | Bend handles and effect declarations for TimUI FFI |
| [`src/bend/clock.bend`](src/bend/clock.bend) / [`utc_time.bend`](src/bend/utc_time.bend) | Bend 2 | Receipt timestamps and complete UTC event-date validation |
| [`src/ffi/timui_ffi.c`](src/ffi/timui_ffi.c) | C99 | Thin TimUI rendering bridge, tty watcher, and winch pipe |
| [`src/ffi/dns_ffi.c`](src/ffi/dns_ffi.c) | C99 | UDP/TCP socket primitives: `recv_octets`, `send_octets`, dup, shutdown |
| [`src/bend/tls.bend`](src/bend/tls.bend) / [`src/ffi/tls_ffi.c`](src/ffi/tls_ffi.c) | Bend 2 / C11 | Bounded, verified OpenSSL TLS transport |
| [`src/ffi/clock_ffi.c`](src/ffi/clock_ffi.c) | C99 | Local receipt clock and date-aware UTC-to-local conversion |
| [`src/media/image.py`](src/media/image.py) | Python | Bounded HTTP(S)/local image loading and normalization with Pillow |
| [`src/bend/upload.bend`](src/bend/upload.bend) / [`src/bend/upload_io.bend`](src/bend/upload_io.bend) | Bend 2 | Per-file consent, worker ownership, scoped completion, and bounded helper calls |
| [`src/media/upload.py`](src/media/upload.py) | Python | Fixed-origin HTTPS file upload with streamed input and checked URL output |
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
- **`refused_startup_archive_keeps_current_client`**, **`absent_startup_target_keeps_current_client`**, **`captured_image_preference_is_preserved`**: Quantified refusal and preference-field preservation. Additional recovery, timestamp, command, and chunk laws check concrete examples.
- **`framer_roundtrip`**, **`flood_buffers`**, **`scroll_bounds`**, **`log_chrono`**, **`tokenize_*`**: Concrete framing, cap, scroll, ordering, and tokenization examples. `flood_server_clean` checks that rejected JOINs add server diagnostics; it does not prove general absence of corruption.
- **`narrow_cluster_source_count`**, **`wide_cluster_source_count`**: Concrete source-length checks for a multi-codepoint emoji with and without a narrow-pane replacement.
- **`tokenize_unclosed_source_order`**, **`code_span_dim`**: Concrete source-order checks for three unmatched markers and the live dim attribute for one code span.

Verify all proofs at any time:
```sh
make proof
```

The default deadline is 180 seconds. Use `make proof PROOF_TIMEOUT=600` for a
bounded retry on a slower machine; this does not change the laws or checker.

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

Run `birc` without cloning:

```sh
# Launch offline interactive demo
nix run github:angerman/birc -- --demo

# Connect to a live IRC network with verified TLS
nix run github:angerman/birc -- --connect irc.libera.chat --tls --channel '#bend'
```

### 1. Build and Test Locally

```sh
make bootstrap   # Once: create flake.lock
make check       # Run formal proofs, unit tests, live mock, and FFI lints
```

Nix can evaluate or build before the client starts. To prebuild the installed
package and then launch it without another flake evaluation:

```sh
make build-package
./build/package-birc/bin/birc --demo
```

The installed package supplies its image and upload helpers. This bypasses
Nix launch work; it does not fix a slow Nix store or daemon.

`make build-package-profiled` reports coarse code-generation and native-compile
times. Timers are off in the normal package. The profiled package is a separate
build and does not populate the default app's cache.

### 2. Offline Interactive Demo

Experience the full TimUI interface, rich text rendering, and mock channels without connecting to a network:

```sh
make run-demo
```

### 3. Connect to Live IRC

Use verified TLS for a live IRC network:

```sh
# Run directly without cloning
nix run github:angerman/birc -- --connect irc.libera.chat --tls --nick mynick --channel '#birc'

# Or via make in a cloned checkout
make run HOST=irc.libera.chat PORT=6697 NICK=birc_user CHAN='#birc'

# Or invoke the built binary inside the locked development shell
./build/birc --connect irc.libera.chat --tls --nick mynick --channel '#birc'
```

Verified TLS is the default, with port 6697. `--plain` explicitly selects
plaintext, with port 6667. `--tls` explicitly selects the default secure mode;
using both selectors is an error. A port never selects the transport:
`--port 6667` still uses TLS unless `--plain` is present.
`--connect HOST:PORT` and `/connect HOST:PORT` accept DNS names or IPv4 addresses.
An additional port may match the inline port; conflicting values are rejected
in either order. IPv6 is not supported.
The selected transport persists across later connections. `/connect HOST`
reuses the current port, including a custom port. `/reconnect` reuses the saved
host and port. With Make, use `TRANSPORT=plain` for plaintext; `PORT` is optional.
TLS failure does not retry with plaintext. TLS uses the Nix-provisioned CA
bundle and verifies the hostname or IPv4 address; DNS names also use SNI.
For a private CA, set `SSL_CERT_FILE` to its trusted PEM bundle. This changes
trust, not verification: there is no certificate-verification bypass flag.
Explicit CA files use bounded regular-file snapshots. TLS handshake and write
waits have deadlines. Access to arbitrary remote filesystems or CA directories
does not have a universal hard-cancellation guarantee.

### 4. Replay Captured Sessions

Replay raw IRC wire logs deterministically for testing or inspection:

```sh
./build/birc --replay fixtures/demo.irc
```

Replay reads the initial file snapshot in bounded chunks, including captures
larger than one MiB. UTF-8 and CRLF can cross chunk boundaries. A final record
without a newline is retained. Open, size, and read failures exit nonzero;
an early EOF does not silently paint a partial capture. The file-size API
supports snapshots up to 4,294,967,295 bytes.

---

## Command-Line Options

Run `./build/birc --help-irc` for a full summary:

| Option | Argument | Description |
|---|---|---|
| `--connect` | `<host[:port]>` | IRC server hostname or IPv4 address, with optional port |
| `--port` | `<port>` | Server port (1–65535); does not change transport mode |
| `--tls` | — | Verified TLS (default); default port 6697 |
| `--plain` | — | Explicit plaintext; default port 6667; conflicts with `--tls` |
| `--nick` | `<nick>` | IRC nickname (default: `birc`) |
| `--channel` | `<channel[,channel…]>` | Initial channels (default: `#birc`); an empty argument joins none |
| `--demo` | — | Run offline demo with canned mock activity |
| `--replay` | `<file>` | Feed an IRC log capture into the client and launch UI |
| `--frames` | `<n>` | Run for `n` frames/ticks (headless batch test if stdin not a tty) |
| `--sasl-user` | `<account>` | Authentication account; defaults to `BIRC_SASL_USER` |
| `--sasl-pass` | `<password>` | Legacy secret flag; prefer the Keychain wrapper, not process arguments |
| `--auth` | `sasl`, `nickserv`, `sasl-nickserv` | SASL by default; explicit NickServ or unavailable-SASL fallback |
| `--nickserv-prefix` | `nick!user@host` | Exact trusted service identity; no wildcard masks |
| `--nickserv-success` | `<text>` | Exact successful NOTICE text after IRC formatting controls are removed |
| `--help-irc` | — | Show birc client command-line options |

An explicit `--nick` always wins, including `me` and `birc`. Without `--nick`,
the SASL username supplies the nickname when configured; otherwise it is `birc`.
This default is resolved after CLI and environment SASL settings are combined.

### Authentication profiles and macOS Keychain

`keychain-birc` keeps passwords in macOS Keychain, not the profile file.
Create `~/.config/birc/config.toml` (or `$XDG_CONFIG_HOME/birc/config.toml`):

```toml
[profiles.work]
host = "irc.example.net"
tls = true
account = "myaccount"
nick = "mynick"
auth = "sasl"
channels = ["#birc", "#work"] # optional names only; never JOIN keys
```

Profiles default to verified TLS and port 6697. `tls = false` explicitly selects
plaintext and defaults to port 6667. An explicit profile port stays unchanged
and never changes transport mode. The profile `host` also accepts `HOST:PORT`;
an additional `port` must agree with it. The wrapper's `--tls` or `--plain`
overrides the profile mode; using both is an error. It resolves the endpoint
before looking up the endpoint-bound Keychain item.
An explicit `--channel` overrides profile channels. Without that flag or a
profile list, birc can use the channel names saved for the exact host and port.
An explicitly saved empty list means no automatic JOIN.

TLS profiles need no unsafe flag or local relay. A plaintext profile instead
needs a declared trusted IPv4 loopback relay, or per-launch
`--allow-insecure-auth`. For example, an existing trusted local TLS relay can
use `host = "127.0.0.1"`, `port = 16667`, `tls = false`, and `trusted_relay = true`.
The wrapper does not create that relay or verify its TLS configuration.
The owned profile file must be a regular file, not a symlink, and must not
allow group or other users to write it. Password fields are rejected.

```sh
chmod 600 ~/.config/birc/config.toml
nix run .#keychain-birc -- --profile work --channel '#birc'
# For a separate, existing plaintext profile, accept the risk for this launch:
nix run .#keychain-birc -- --profile legacy --allow-insecure-auth
```

The wrapper uses `/usr/bin/security` to find the profile/account password.
If none is usable, it prompts with terminal echo disabled. It saves a newly
entered password only after the client confirms actual authentication on the
initial endpoint. Exit status, welcome messages, and printed text do not
count as success. An existing Keychain item is never overwritten. Denied
Keychain access, failed authentication, or cancelled input does not save it.
To replace a saved password, remove its `birc.auth.v1:` item in Keychain Access
and launch the profile again. The wrapper does not silently update an item.
Keychain items use a versioned `birc.auth.v1:` service name and an encoded
`birc-v1:` value to preserve spaces and Unicode. This encoding is not encryption;
Keychain supplies storage protection. The wrapper does not put its password in
child arguments, environment variables, temporary files, or diagnostic logs.
Authentication requests do not enter chat history. Arbitrary incoming messages
are not globally redacted.

To use NickServ, select `auth = "nickserv"`. To prefer SASL and fall back only
when SASL is explicitly unavailable, select `auth = "sasl-nickserv"`. Both
require network-specific trusted metadata, for example:

```toml
nickserv_prefix = "NickServ!service@services.example"
nickserv_success = "You are now identified for myaccount."
```

Replace both values with the service's real identity and successful NOTICE.
Use a trusted network or relay that reserves and controls the service nickname.
IRC messages address nicknames, so the prefix probe does not cryptographically
bind the recipient or protect against a compromised server or nickname takeover.
The client first sends a harmless `HELP` request. Only a NOTICE from that exact
full identity, directed to the current nick, releases the `IDENTIFY` password.
Only the exact configured confirmation then marks authentication successful.
NickServ credentials must fit one IRC line and contain no whitespace; invalid
credentials are not truncated or sent.
There is no fallback after a bad SASL password. Changing host or port clears
the loaded credentials for the rest of that client session, even if you return
to the original endpoint. Start the wrapper again to load another profile.

Direct launches still support `BIRC_SASL_USER` and `BIRC_SASL_PASS`; a nonempty
CLI value takes precedence. They do not persist a password. On a plaintext
connection, SASL PLAIN and NickServ IDENTIFY expose the password. Use native
TLS or a trusted TLS relay unless you accept this risk explicitly. The unsafe
flag belongs to the wrapper, not the core IRC client.

Automatic authentication bypasses the composer. Manual service credential
commands retain their wire text but use a redacted local echo and skip command
history; their own server echoes are also suppressed. Text typed manually in
the composer remains visible. Prefer the wrapper for private password entry.

### Stored history

History records use `BIRC2` and include the server hostname and port. Different
hosts or ports do not share stored history. Archive lookup ignores hostname
case; credentials, runtime keys, and preferences use exact host spelling and
port. An endpoint change clears live chat buffers. The in-memory `*log*`
belongs to the app session and survives endpoint changes. The reader scans the file to its
initial size, keeps only the configured recent records, and rejects malformed
or overlong records. An incomplete final record is not loaded.
When historical conversations exceed the available buffer slots, restore
retains the most recently used targets. Server and local tabs are preserved.
A zero history cap restores no chat targets.

History writes create private `0600` files. An existing regular file owned by
the current user is repaired to `0600` before appending, without changing its
contents. Symlinks, nonregular files, and files owned by another user are not
written. A failed permission check or write is reported in `*log*`.

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
| <kbd>F8</kbd> | Confirm the currently staged public file upload |
| <kbd>Esc</kbd> | Cancel a pending/running upload; otherwise disconnect and quit |
| <kbd>F10</kbd> | Cleanly disconnect and quit |

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
internal URL punctuation is not markup. URLs inside styles or code remain
display text, not clickable links or automatic preview requests.
Native output and selection preserve combining marks and emoji sequences.
Wrapping prefers spaces between words, including across formatting runs.
Oversized words and URLs still hard-wrap at complete cluster boundaries.
Spaces hidden at a row boundary remain part of scroll and resize anchors.
A cluster that crosses a style boundary uses its leading character's style.
Hanging indents measure the complete painted nickname prefix, including any
cluster that crosses its punctuation.
OSC8 hyperlinks keep exact targets through 1024 bytes; larger targets are
declined instead of shortened. Visible glyphs still depend on terminal fonts.

Type commands into the composer prompt:

| Command | Description |
|---|---|
| `/connect <host[:port]> [port]` | Connect using the launch transport; an omitted port reuses the current port |
| `/reconnect` | Reconnect to the saved server and port |
| `/join <channel[,channel…]> [key[,key…]]` | Join channels; retain at most 14 desired channels for recovery |
| `/part [channel]` | Leave the named channel, or the active channel if omitted |
| `/close [buffer]` | Close a query or local tab, or leave a channel; the server buffer cannot close |
| `/msg <target> <text>` | Send a private message to a nick or channel |
| `/notice <target> <text>` | Send a notice without a reply request |
| `/whois [server] <nick[,nick…]>` | Request user information |
| `/who [mask] [flags]` | Request matching users; defaults to the active channel |
| `/list [channels] [server]` | Request channel listings |
| `/names [channels] [server]` | Request nicknames; defaults to the active channel |
| `/topic [channel] [text]` | Query or set a channel topic; `:` clears it |
| `/mode [target] [modes] [args]` | Query or change modes; defaults to the active target |
| `/kick [channel] <nick> [reason]` | Remove a user from a channel |
| `/invite <nick> [channel]` | Invite a user; defaults to the active channel |
| `/away [text]` | Set an away message; omitted text clears it |
| `/raw <command>` / `/quote <command>` | Send one validated IRC command; no prefix or tags |
| `/search <query>` | Search all buffer scrollback and open the results in `*search*` |
| `/log` | Open the read-only diagnostic buffer; also works offline |
| `/links` | List links from the focused buffer |
| `/open [n-or-url]` | Open a numbered link or HTTP(S) URL; omitted arguments select the first listed link |
| `/settings` | Open the settings panel |
| `/split [orientation] [buffer]` | Open a stacked split by default; orientation is `horizontal` or `vertical`, and the target must already be open |
| `/vsplit [buffer]` | Open a side-by-side split with an existing buffer |
| `/focus` | Move focus to the other split pane |
| `/split-off` or `/unsplit` | Close the split without closing either buffer |
| `/preview <path-or-url>` | Preview a local image (also `file://`-prefixed paths) or an HTTP(S) image URL in `*preview*` |
| `/images on` / `/images off` | Enable or disable automatic image previews; explicit `/preview` remains available |
| `/upload <local-path> [more-paths]` | Stage local files for individual public-upload confirmation; quote paths containing spaces |
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

Recovery remembers the desired channel set, not only the launch channel.
Accepted `/join` adds intent; PART, closing a channel, and a self-KICK remove it.
The desired set holds at most 14 channels; an overflowing JOIN is rejected
without a partial send or state change.
An offline PART can cancel a future rejoin without sending a wire command.
JOIN keys stay in memory for that endpoint and do not enter history or saved
preferences. A new endpoint clears runtime keys and credentials. Its saved
channel names can then supply fresh autojoin intent. Host spelling and port
are part of the saved endpoint identity.
On each connection birc starts authentication again. With configured
credentials, it waits for welcome and verified SASL or NickServ success before
joining. A rejected or untrusted authentication notice cannot release JOIN.

Ordinary messages, `/msg`, `/query`, `/notice`, and `/me` split into complete
IRC lines when needed. Splits preserve text and common Unicode clusters.
Every action chunk has its own complete CTCP ACTION envelope. A cluster that
cannot fit rejects the entire message. Credential commands are never split
or truncated. `/raw` and `/quote` reject line injection, enforce the 510-byte
payload and 15-parameter limits, and never enter composer history.
Channel key MODE arguments are hidden in chat and disk history. Ordinary
message text is not globally redacted. Until complete server mode metadata is
available, a key-bearing MODE row hides all arguments rather than guessing
which one is the key.

Live server-time tags are UTC event times. birc converts their complete date
and time into your local timezone, including date-specific daylight saving
time. Invalid tags use local receipt time. Untagged messages use receipt time.
Previously saved history contains only `HH:MM:SS`, without a date or timezone;
it cannot be safely converted retroactively.

Runtime preferences changed by `/set` or `/toggle`, scoped mutes, and
`/images on|off` use a separate private, versioned preferences file:
`$XDG_CONFIG_HOME/birc/preferences.toml`, or `~/.config/birc/preferences.toml`.
Set `BIRC_PREFERENCES` to another path, or `none` to disable preference IO.
`BIRC_PREFS_HELPER` can select a literal executable path; an empty value uses
the provisioned default. It is not a shell command.
The file contains UI settings and per-endpoint channel names, not passwords
or JOIN keys. The Keychain launcher still reads auth profiles from `config.toml`
and passwords from Keychain; chat history uses its own file.

Interactive preference loading runs after the first paint. Explicit settings edits made
during loading win over stored values. Explicit `--channel`, `BIRC_IMAGES`,
and `BIRC_HISTORY_LINES` take precedence. New files use `0600`; malformed,
unknown-version, symlinked, foreign-owned, or unsafe writable files are not
overwritten. Failures use numeric diagnostics in `*log*`.

On live startup, settings resolve before history loads and the first connection
starts. Local input and quit remain available while the helper or history
worker runs. A failed settings read does not restore or write history under an
unknown policy; an explicit `/set history on` can enable it. Headless startup
resolves the same policy before registration. `BIRC_PREFERENCES=none` keeps the
direct startup path. Later endpoint reads load channel names, not stale global
settings. History file IO has no hard cancellation guarantee on remote file
systems.
Restored targets get a `Reconnected:` divider when a row is available. A full
buffer keeps its retained rows instead of removing one for the divider.

One helper owns at most 16 distinct endpoint scopes, including its active job.
Normal quit waits up to
22 seconds for pending saves. If requested changes cannot be saved, birc
restores the terminal and exits nonzero with a fixed warning.

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
IRC events cannot create, rename, or target reserved local buffers such as
`*log*`. Ordinary channels, private queries, and server broadcasts stay separate.

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
Local and remote previews both require helper acceptance and normalization;
pending or rejected input is never uploaded through a raw-file fallback.

Downloads are capped at 8 MiB; local inputs at 16 MiB. Source images are capped
at 4096 pixels per side and 16,777,216 pixels. Normalized previews fit within
320 pixels per side. Animations have at most 24 frames, 33,554,432 source-frame
pixels (including an APNG fallback image), and 1,536,000 normalized pixels in
total. The binary envelope is capped at 2 MiB before base64 encoding. The
helper has an eight-second deadline.
Bend allows one active helper, eight queued requests, and eight cached results.

Kitty and iTerm2 handle animation in the terminal; birc does not add an
animation timer. Sixel uses the first frame. Unsupported image terminals show
a placeholder. A partially clipped iTerm2 image also shows a placeholder,
because that protocol has no source-crop command. Terminal and multiplexer
support can differ.

Use `make shell` before invoking `./build/birc` directly. The Nix package defaults
an unset helper variable to its absolute helper path. Use `BIRC_MEDIA_HELPER`
to override the helper for development and synthetic tests. It is an executable
path, not a shell command. An explicitly empty value uses `birc-image` from
PATH. Reload an existing Nix shell after provisioning changes.

### Public file uploads

Focus an online channel or query. Drop exact absolute paths or local
`file:///` URLs into the composer, then press Enter. You can also use:

```text
/upload '/path/to/image.jpg' './another file.txt'
```

Quotes and backslashes decode literal paths. They do not run a shell or
expand variables, globs, or `~`. Up to eight files can be staged together.
Bare `/name` is treated as a slash command, not an implicit root-level file
drop. Use `/upload /name` or quote the path to remove that ambiguity.
Images and other regular files are supported, through 32 MiB per file.
Empty files, final symlinks, and nonregular files are refused.

The status row identifies the public destination, target, and next basename.
Press F8 to authorize that file. Each remaining file needs another F8.
Enter or pasted confirmation text cannot authorize an upload. Ordinary
draft editing, completion, history, and navigation remain available while
the helper runs. Upload commands and dropped paths do not enter command
history or chat. A successful URL is sent as ordinary IRC text and can be
saved in chat history. An overlong URL is refused, never shortened.

This sends file contents to public storage. 0x0.st also receives your IP
address and user agent. The helper requests a harder-to-guess URL, not
encryption or access control. Do not upload a file that must remain private.
The remote filename is generic; the file contents can still identify you.

Esc cancels pending consent and queued files. If text is selected, the first
Esc clears the selection; press Esc again to cancel the upload.
For an upload already running,
it prevents the resulting URL from being sent; it cannot retract bytes already
sent to storage. Changing the connection or focused target also invalidates
that result, even if you later return. Cancelling or quitting does not kill
the running helper. It has a 30-second wall-clock bound; Bend's helper call
has a separate 35-second bound. Only one upload helper runs at a time.

The Nix package supplies Python, CA trust, and an absolute default uploader.
Use `make shell` before running `./build/birc` directly. An existing shell
must be reloaded to find the new uploader. `BIRC_UPLOAD_HELPER` is a literal
executable-path override for development and offline tests, not a shell
command. An explicitly empty value uses `birc-upload` from PATH.
Upload code 5 means an HTTP rejection or an invalid service reply. A verified
numeric HTTP status appears in `*log*` when available. Response bodies,
private paths, and arbitrary helper diagnostics stay hidden.

---

## Development & Verification

The project root [`Makefile`](Makefile) is the sole driver. Routine development uses `--no-update-lock-file` to ensure strict reproducibility.

```sh
make shell                 # Enter the locked Nix development environment
make check                 # Proofs + pure tests + FFI lints + UI smoke
make proof                 # Run Bend formal proof checker (PROOF.bend)
make test-pty              # Run the PTY integration suite
make test-pty-recovery-settings # Focused recovery, settings, history, timestamp, and upload checks
make test-preferences      # Private settings helper and runtime guards
make test-live             # Run mock IRC socket handshake test
make test-package          # Installed wrapper, local images, helper overrides, offline CA
make check-hardening       # Bounded hostile, sanitizer, and performance checks
make lint-ffi              # Strict syntax and compiler warning lint of C FFI
make test-auth-profiles    # Auth state, privacy, Keychain fakes, pipes, and real loopback PTY
make test-keychain-tls     # Offline TLS profiles, port policy, and child argv
make test-build-tls        # TLS flag preservation and build-cache invalidation
make test-tls-native       # OpenSSL verification, retry, ownership, and IO queue guards
make test-pty-tls          # Owned loopback TLS, authentication, reconnect, and quit
make test-tls-package      # Installed CA selection, pinned libraries, and clean-PATH failures
make test-auth-bridge-ubsan # Authentication pipe guard with UBSan
make test-perf-startup      # Separate cached nix run launch time from first client paint
make build-package-profiled # Opt-in Nix codegen/native stage timing; not the default package
make test-upload           # Public-upload guards, owned helpers, and loopback IRC only
make test-upload-package   # Installed uploader trust/provenance and loopback override
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
