# Hacking birc

How to build, test, and change birc. What the client does, and how to drive it,
is [README.md](README.md).

Nix provisions the toolchain. The root [`Makefile`](Makefile) is the only driver.
Routine Nix commands pass `--no-update-lock-file`. Only `make update CONFIRM=yes` moves pins.

---

## Build

```sh
make bootstrap   # Once: create flake.lock
make shell       # Enter the locked Nix shell and stay there
make -j check    # Proofs, unit tests, live mock, and FFI lints
```

`make shell` is the environment for a raw `./build/birc`. Helper paths and the CA bundle come from
that shell. `nix run` and the installed package already wrap them.

Nix can evaluate or build before the client starts. To prebuild the installed
package and then launch it without another flake evaluation:

```sh
make build-package
./build/package-birc/bin/birc --demo
```

The installed package supplies its image, upload, and preferences helpers. This
bypasses Nix launch work; it does not fix a slow Nix store or daemon.

`make build-package-profiled` reports coarse code-generation and native-compile times. Timers are off in
the normal package. The profiled package is a separate build and does not
populate the default app's cache. It also reports the owned code-generation
process ID for scoped diagnostics. Failed profiled builds retain their temporary
directory for inspection. Both package targets bound the Nix client and builder
to 900 seconds. The recipe guard keeps its 45-second evaluation default; use `make test-package-build-profile PACKAGE_PLAN_TIMEOUT=300`
for a bounded setup retry. Its six synthetic command-order and failure checks
stay unchanged.

`ci.zw3rk.com` schedules `hydraJobs` only. That job is the installed client, including `bin/keychain-birc`, on `aarch64-darwin`,
`x86_64-linux`, `aarch64-linux`, and `x86_64-darwin`. `birc-profiled` and the Bend compiler stay local packages.

---

## Run a checkout

```sh
make run-demo
make run HOST=irc.ergo.chat NICK=yournick CHAN='#ergo'
./build/birc --connect irc.ergo.chat --tls --nick yournick --channel '#ergo'
```

With Make, verified TLS is the default. `TRANSPORT=plain` selects plaintext. `PORT` is optional.
Transport rules for ports, SNI, and CA files are in the README.

`./build/birc --help-irc` prints birc's options. Bend runtime flags (`--help`, `--threads`, `--gpu`) go between `+RTS` and
`-RTS`, for example `./build/birc +RTS --help -RTS`.

### Replay

`--demo` is the canned offline session. `--replay <file>` feeds a captured IRC log through the live
byte framer:

```sh
./build/birc --replay fixtures/demo.irc
```

Replay reads the initial file snapshot in bounded chunks, including captures
larger than one MiB. UTF-8 and CRLF can cross chunk boundaries. A final record
without a newline is retained. Open, size, and read failures exit nonzero; an
early EOF does not silently paint a partial capture. The file-size API supports
snapshots up to 4,294,967,295 bytes.

### Native helpers

The Nix package links image, card, upload, and preference effects and defaults
an unset helper variable to `native`. `native` is the linked C effect. Any other value is
an executable path, not a shell command. Reload an existing Nix shell after
provisioning changes.

| Variable | Role |
|---|---|
| `BIRC_MEDIA_HELPER` | Image fetch and decode |
| `BIRC_CARDS_HELPER` | OpenGraph card fetch |
| `BIRC_UPLOAD_HELPER` | Public upload POST |
| `BIRC_PREFS_HELPER` | Preferences file effect. An empty value uses the provisioned default |
| `BIRC_SEARCH_HELPER` | History scan. Defaults to `native` |

Use these overrides for development and synthetic tests. `make shell` before `./build/birc` when the
binary is the unwrapped checkout build.

---

## Tests

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

The harness has four tiers:

1. **Bend proof checks.** [`PROOF.bend`](PROOF.bend) checks quantified laws and concrete
   examples. `make proof-kernel` is the separate independent validity gate.
2. **Pure unit tests.**`tests/bend/` covers protocol serialization, state transitions,
   client routing, and argument parsing.
3. **PTY suite.**`tests/pty/` drives a real terminal: resizes, paste, channel switching,
   buffer flood, stalled IO, disconnects, and signals.
4. **C lint.**`LINT_FFI_CFLAGS` in the Makefile. Warnings fail `make lint-ffi`.

Headless (stdin is not a tty), `--frames N` paints N ticks and exits. On a tty, `N` is a
message cap and the loop parks. Loop tests need a pty (`make test-pty`).

---

## Contributing

```sh
make bootstrap   # once, if flake.lock is missing
make shell
make check
```

A commit that adds or renames a file under `src/` updates the concern row it
belongs to in [`Agents.md`](Agents.md). That row is a glob and an invariant, not a file
list.

The client is Bend 2, C under `src/ffi/`, and vendored [`src/ui/timui.h`](src/ui/timui.h). Python
under `tests/` and the Makefile harnesses is not part of the client. Do not add a
Python helper that `birc` spawns.

IRC defaults to verified OpenSSL TLS. Do not hand-roll cryptography, disable
certificate verification, or fall back to plaintext after a TLS failure. `LAWS.bend`
must not import the IO and effect modules. `make lint-laws-io` checks that.

Tests use temporary directories, synthetic certificates, fake helpers, and owned
loopback peers. They must not print a real history log, fetch a private chat
URL, upload a user file, contact `0x0.st`, or write a login Keychain item.

Keep IRC lines at or under 512 bytes including CRLF. Bend owns frame iteration.
C walks `List<DrawOp>` and does not parse IRC.

The license is Apache-2.0. See [`LICENSE`](LICENSE).

---

## Architecture

Bend 2 owns the application lifecycle, protocol, client state, networking, and
the frame loop. C provides terminal rendering, POSIX socket and clock calls, and
verified OpenSSL TLS effects. C does not parse IRC or own the frame loop.

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
|             | List<DrawOp> (OpSplit, OpMedia, text and geometry)       |
|             v                                                          |
+-------------|----------------------------------------------------------+
              | Foreign Effect (Timui.frame)
              v
+------------------------------------------------------------------------+
|                       C11 Native FFI (src/ffi/)                        |
|  - timui_ffi.c          : Walks DrawOps, paints, returns keys          |
|  - dns_ffi.c            : POSIX socket dup, shutdown, octet send/recv  |
|  - tls_ffi.c            : Verified OpenSSL handshake and encrypted IO  |
|  - clock_ffi.c          : Local clock seconds-of-day                   |
|  - auth_bridge_ffi.c    : Launch-pipe setup and auth notify            |
|  - history_ffi.c        : Private history append                       |
|  - history_search_ffi.c : Checked history open and scan                |
+------------------------------------------------------------------------+
```

IRC parsing, message dispatch, connection state, line framing, command
submission, and DNS packet handling live in Bend. IO drivers use Bend effects
and thin POSIX FFI.

Descriptor watchers wake one Bend `Chan(UiMsg)`. A one-second maintenance tick expires
typing state and checks whether refused terminal output can resume. A full
output queue does not cause a busy retry loop.

DNS A lookup, bounded CNAME handling, and UDP-to-TCP truncation fallback are
Bend UDP plus `recv_octets`, without libc `getaddrinfo`.

Lines are capped at 512 bytes including CRLF. Buffers and terminal writes are
bounded. Inbound lines are UTF-8, with a Latin-1 fallback when a line is not
valid UTF-8. Foreign effects and malformed inputs still need runtime tests. Pure
laws and those tests check different parts of the application. Neither proves
the whole client correct.

### Module layout

| Path | Language | Role |
|---|---|---|
| [`src/bend/app.bend`](src/bend/app.bend) | Bend 2 | Application entrypoint, CLI dispatch, and lifecycle |
| [`src/bend/irc.bend`](src/bend/irc.bend) | Bend 2 | Pure RFC 1459/2812 parser, classifier, and wire formatter |
| [`src/bend/client.bend`](src/bend/client.bend) | Bend 2 | Incoming IRC event dispatcher (`feed`) and state transitions |
| [`src/bend/buffer.bend`](src/bend/buffer.bend) | Bend 2 | Channel/query buffer container and nick list data structures |
| [`src/bend/client_laws.bend`](src/bend/client_laws.bend) | Bend 2 | Feed inspectors, invariants, and client law predicates |
| [`src/bend/replay.bend`](src/bend/replay.bend) | Bend 2 | Bounded file-snapshot replay through the live byte framer |
| [`src/bend/submit.bend`](src/bend/submit.bend) | Bend 2 | User slash-command parsing and outbound line formatting |
| [`src/bend/irc_commands.bend`](src/bend/irc_commands.bend) / [`src/bend/message_chunks.bend`](src/bend/message_chunks.bend) | Bend 2 | Shared command validation and lossless cluster-safe wire splitting |
| [`src/bend/join_plan.bend`](src/bend/join_plan.bend) / [`src/bend/channel_policy.bend`](src/bend/channel_policy.bend) | Bend 2 | Desired channels, transient keys, and authentication-gated recovery |
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
| [`src/bend/history_startup.bend`](src/bend/history_startup.bend) / [`src/bend/history_startup_io.bend`](src/bend/history_startup_io.bend) | Bend 2 | Auth-free snapshots, nontrimming import, and fresh-ID startup dividers |
| [`src/bend/preferences_runtime.bend`](src/bend/preferences_runtime.bend) / [`src/bend/preferences_live.bend`](src/bend/preferences_live.bend) | Bend 2 | Bounded settings queue, edit-wins loading, and quit drain |
| [`src/bend/live_context.bend`](src/bend/live_context.bend) / [`src/bend/startup_headless.bend`](src/bend/startup_headless.bend) | Bend 2 | Settings-before-history ordering and generation-scoped connection release |
| [`src/bend/auth.bend`](src/bend/auth.bend) | Bend 2 | Parsed SASL phase transitions and credential replies |
| [`src/bend/session.bend`](src/bend/session.bend) | Bend 2 | UI session state, history ring buffer, and key mapping |
| [`src/bend/typing.bend`](src/bend/typing.bend) | Bend 2 | Bounded IRCv3 typing state and wrap-safe expiry |
| [`src/bend/actor.bend`](src/bend/actor.bend) | Bend 2 | Background network actor: transport ownership and read/write loops |
| [`src/bend/transport_policy.bend`](src/bend/transport_policy.bend) / [`src/bend/transport.bend`](src/bend/transport.bend) | Bend 2 | Pure TLS selection and affine plaintext/TLS IO dispatch |
| [`src/bend/outbound.bend`](src/bend/outbound.bend) | Bend 2 | Pure outbound batches, FIFO splits, and finite send credits |
| [`src/bend/net.bend`](src/bend/net.bend) | Bend 2 | UI channel event loop, descriptor watchers, and shutdown |
| [`src/bend/args.bend`](src/bend/args.bend) | Bend 2 | Pure command-line argument parser |
| [`src/bend/timui.bend`](src/bend/timui.bend) | Bend 2 | Bend handles and effect declarations for TimUI FFI |
| [`src/bend/clock.bend`](src/bend/clock.bend) / [`src/bend/utc_time.bend`](src/bend/utc_time.bend) | Bend 2 | Receipt timestamps and complete UTC event-date validation |
| [`src/ffi/timui_ffi.c`](src/ffi/timui_ffi.c) | C99 | Thin TimUI rendering bridge, tty watcher, and winch pipe |
| [`src/ffi/dns_ffi.c`](src/ffi/dns_ffi.c) | C99 | UDP/TCP socket primitives: `recv_octets`, `send_octets`, dup, shutdown |
| [`src/bend/tls.bend`](src/bend/tls.bend) / [`src/ffi/tls_ffi.c`](src/ffi/tls_ffi.c) | Bend 2 / C11 | Bounded, verified OpenSSL TLS transport |
| [`src/ffi/clock_ffi.c`](src/ffi/clock_ffi.c) | C99 | Local receipt clock and date-aware UTC-to-local conversion |
| [`src/ffi/media_fetch_ffi.c`](src/ffi/media_fetch_ffi.c) / [`src/bend/media_io.bend`](src/bend/media_io.bend) | C11 / Bend 2 | Native image/card fetch, decode, and cache; Bend owns request identity |
| [`src/bend/upload.bend`](src/bend/upload.bend) / [`src/bend/upload_io.bend`](src/bend/upload_io.bend) / [`src/ffi/upload_ffi.c`](src/ffi/upload_ffi.c) | Bend 2 / C11 | Per-file consent and native HTTPS upload to `0x0.st` |
| [`src/ffi/keychain_birc.c`](src/ffi/keychain_birc.c) | C99 | Packaged `keychain-birc` launcher: TOML profiles and macOS Keychain |
| [`LAWS.bend`](LAWS.bend) / [`PROOF.bend`](PROOF.bend) | Bend 2 | Quantified proofs and concrete checked examples |

---

## Formal verification

Proofs live in [`PROOF.bend`](PROOF.bend) and correspond directly to declarations in
[`LAWS.bend`](LAWS.bend).

Quantified laws apply to every input named in their declarations. Most other
laws check concrete examples, not all possible inputs. Current coverage
includes:

- **`strip_ctl_clean`**: Inductive proof that `strip_ctl(s)` eliminates all CR and LF characters across
  **all** possible strings `s`:

  ```bend
  law strip_ctl_clean:
    for s: String
    {Irc.has_crlf(Irc.strip_ctl(s)) == False{} : Bool}
  ```

- **`push_rem_bound`**: For every octet chunk, `push(Nil, chunk)` retains at most `LINE_OCTET_MAX + 1` octets. This
  statement starts with an empty remainder; it is not a quantified multi-chunk
  invariant.
- **`search_empty_line`**, **`split_focus_involution`**: Quantified empty-query and two-focus-toggle properties.
- **`split_control_key`**, **`split_control_lookup`**, **`split_server_query_lookup`**: Internal pane keys distinguish control from a
  query named `server` for every client value.
- **`sasl_idle_no_reply`**, **`sasl_done_no_reply`**: No control event can send credentials before
  authentication is enabled or restart a completed exchange.
- **`auth_preserves_settings`**, **`timestamp_preserves_log_sequence`**: Authentication changes preserve settings; assigning
  timestamps preserves log identity.
- **`actor_zero_split`**, **`actor_exhausted_keeps_pending`**: Zero credit cannot emit or discard pending lines, for
  any queue.
- **`refused_startup_archive_keeps_current_client`**, **`absent_startup_target_keeps_current_client`**, **`captured_image_preference_is_preserved`**: Quantified refusal and preference-field
  preservation. Additional recovery, timestamp, command, and chunk laws check
  concrete examples.
- **`framer_roundtrip`**, **`flood_buffers`**, **`scroll_bounds`**, **`log_chrono`**, **`tokenize_*`**: Concrete framing, cap,
  scroll, ordering, and tokenization examples. `flood_server_clean` checks that rejected JOINs
  add server diagnostics; it does not prove general absence of corruption.
- **`narrow_cluster_source_count`**, **`wide_cluster_source_count`**: Concrete source-length checks for a multi-codepoint
  emoji with and without a narrow-pane replacement.
- **`tokenize_unclosed_source_order`**, **`code_span_dim`**: Concrete source-order checks for three unmatched markers
  and the live dim attribute for one code span.

```sh
make proof
```

The default deadline is 180 seconds. Use `make proof PROOF_TIMEOUT=600` for a bounded retry on a slower
machine; this does not change the laws or checker.

The normal gate uses Bend's checker. `make proof-kernel` also requests the independent BendTT
kernel. It needs Lean v4.34.0 or a configured `BENDTT`; missing tools fail the
target. Foreign effects and `@unsafe` live loops are outside these pure proof
guarantees. Runtime, PTY, and sanitizer tests cover those paths separately.

Terminal writes have a shared frame deadline. Partial UTF-8 scalars retain at
most three suffix bytes, which must precede later output. One serialized frame
retains its accepted-byte offset and resumes on a writable maintenance tick; it
does not restart its prefix. Capture is capped at 64 MiB. Allocation or cap
failure discards that whole capture and exits through normal terminal cleanup
with a nonzero status. A full output queue does not cause a busy retry loop.
Ordinary frames have 40 ms, writable repairs have 200 ms. Signal restoration
owns stable descriptor references. A handler already using Ui can retain one
complete owner until final exit; close never waits for it. Final output
suppresses same-stream status while ownership or terminal debt remains
unresolved. This is not general concurrent access support for Ui. Headless live
startup awaits the bounded registration result and reports initial connection
failure with a nonzero exit.
