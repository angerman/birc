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
networking, and the frame loop**; C is thin native FFI under `src/ffi/`.
IRC defaults to verified OpenSSL TLS and port 6697. `--plain` explicitly selects
plaintext and defaults to 6667; `--tls` and `--plain` conflict. An explicit port
never selects the transport. Never hand-roll cryptography, disable certificate
verification, or fall back to plaintext after TLS failure. No ncurses or curl-pipe
installers. Remote image previews may use the provisioned Python/Pillow helper
with standard-library HTTPS certificate verification.
Never fetch supplied private chat URLs during tests.
Confirmed file uploads use the provisioned standard-library HTTPS helper for
`0x0.st`. Tests use synthetic files, fake helpers, and owned loopback servers;
never upload user files or contact the public service from tests.

Original material: Apache-2.0; author Moritz Angermann <moritz@zw3rk.com>.
Preserve upstream licenses. Do not add model attribution.

## Provision and run

Nix provisions dependencies. The root Makefile is the sole driver.

```
make bootstrap   # create flake.lock (once)
make shell       # enter the locked shell
make check       # proof + Bend tests + net + UI smoke
make run-demo    # offline TimUI demo
make run HOST=…  # live verified TLS IRC; optional PORT=… or TRANSPORT=plain
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
| `src/bend/view_laws.bend` | View fixtures and proof-facing predicates |
| `src/bend/auth.bend` | Parsed, phase-gated SASL exchange (pure) |
| `src/bend/outbound.bend` | Pure send-cap batches and finite credits |
| `src/bend/replay.bend` | Bounded file-snapshot replay through the live byte framer |
| `src/bend/history_io.bend` | Private history append effects; keep foreign IO outside proof-facing History |
| `src/bend/links.bend` | Shared URL lexical rules (pure) |
| `src/bend/diagnostic.bend` | Bounded log text/redaction and numeric helper diagnostics (pure) |
| `src/bend/media.bend` | Image request identity, one-worker queue, and stale-result policy (pure) |
| `src/bend/upload.bend` | Local path decoding, per-file consent, worker ownership, and fixed-origin results (pure) |
| `src/bend/upload_io.bend` | Bounded uploader process; never forward child diagnostics |
| `src/ffi/timui_ffi.c` | TimUI open/frame/close |
| `src/ffi/dns_ffi.c` | Byte reads, deadline-owned connect/send, socket dup/shutdown |
| `src/bend/endpoint.bend` | Shared DNS/IPv4 host:port syntax and conflicting-port checks |
| `src/bend/transport_policy.bend` | Pure transport/default-port policy for CLI and proofs |
| `src/bend/transport.bend` / `src/bend/tls.bend` | Affine plaintext/TLS connection dispatch and TLS effect declarations |
| `src/ffi/tls_ffi.c` | Verified OpenSSL transport; no IRC parsing or authentication policy |
| `src/ffi/clock_ffi.c` | Local clock for log timestamps |
| `src/media/image.py` | Bounded HTTP(S) image helper; normalized frames, no temporary files |
| `src/media/upload.py` | Confirmed, bounded streaming uploads to `0x0.st` |
| `src/ui/timui.h` | Vendored single-header TUI |
| `LAWS.bend` / `PROOF.bend` | Laws and proofs |

## Engineering

- Fail closed: missing targets exit nonzero.
- TLS verifies the certificate chain and original requested DNS hostname or IP
  SAN before IRC registration. DNS names use SNI. The native operation owns a
  five-second setup/handshake deadline; reads check buffered plaintext before parking.
  Reader/writer handles share one TLS connection on the pinned serial IO loop.
  Preserve exact OpenSSL retry buffers; shutdown must wake the shared reader.
  Tests use synthetic certificates and owned loopback peers, never live accounts.
  The launch transport persists across later Dials. `/connect HOST[:PORT] [PORT]`
  rejects conflicting explicit ports; an omitted port reuses the Session port.
  `/reconnect` preserves the exact saved host/port. Preserve host spelling and
  terminal DNS root dots for credential scope; IPv6 remains unsupported.
  Explicit `SSL_CERT_FILE`/`SSL_CERT_DIR` overrides must not be silently replaced
  by Nix trust defaults. Explicit CA files use descriptor-checked regular-file
  snapshots capped at 8 MiB, parsed by OpenSSL without password prompts. Remote
  filesystem calls and CA-directory lookups have no hard cancellation guarantee.
  Normalize one DNS root dot for SNI/verification, not credential endpoint scope.
  The pinned IO loop detaches parked work into local `todo`; an owned buffered
  reader there must become due without a duplicate queue insertion. Keep TLS IO
  outside the proof-facing policy module.
- Upload consent is a later physical F8, never Enter or pasted text. A new
  request must cross a completed warning frame before F8 can authorize it.
  Invalidate consent on every endpoint, target, or connection transition;
  returning to the old scope must not revive it. C reports keys; Bend owns
  Escape cancellation and F10 shutdown. Never replace a draft with a warning.
- Keep IRC lines ≤ 512 bytes including CRLF.
- Bend owns frame iteration (`Timui.frame` = one begin/draw/end, returns `Ui & UiKeys`); C has no outer frame while-loop or blocking input poll. Output readiness checks and waits use the bounded frame-output budget. Live paint is `List<DrawOp>` (`OpBox` / `OpSplit` / `OpText` / `OpTabs` / `OpLine` / `OpMedia`); C walks and paints, and does not tokenize, classify, or wrap IRC. Bend expands logical chat lines into resize-safe visible rows with hanging indents. `OpTabs` carries Bend-owned alert levels plus the bell enable flag and event sequence. C renders activity with reverse video, mentions/private messages with gold, and emits one BEL when the sequence advances. Keys are Data on the frame return; a clicked chat link returns its exact URL for Bend to open. C reports the raw key, mods, and wheel; Bend maps Shift-arrows, PageUp/PageDown (`Sess.body_h`), history, and Esc/F10. A tty watcher and a `SIGWINCH` pipe wake one `Chan(UiMsg)`. The UI parks on that channel. Every paint applies the keys the frame read, including a chunk or Eof paint.
- Net: `IO.spawn` actor owns affine `Tr.Conn`; UI ↔ actor via `Chan(NetEvt)` / `Chan(NetCmd)` (Data). Live inbound is `recv_octets` + `Fr.push`; completed lines are UTF-8, with Latin-1 fallback if a line is not valid UTF-8. The actor owns the fd/TLS handle (never `Chan(Conn)`). `SEND_CAP` is 8 outbound lines per actor tick; leftover stays in `pending`. `--frames N` is N ticks (at most `SEND_CAP*N` lines during the loop); cmd close and fuel-0 flush `pending` so `/quit` is not dropped. `frames=0` live loops are `@unsafe`. Live DNS A is Bend UDP plus `recv_octets`. Demo/offline idle actor waits for `Dial`; Demo/Connecting `Cont` carries no IRC outs (no flush after Dial). C does not tokenize. Clock is applied at log IO, not every paint. `--replay FILE` uses `replay.bend` and fails closed. `--help` is Bend's runtime CLI; birc usage is `--help-irc`.
- Shutdown (P5): the writer flushes its healthy pending FIFO, closes its connection, and posts `WriterDone`. Only the current generation's `WriterDone` acknowledges shutdown; reader EOF and stale completions cannot. Demo/Offline idle writers acknowledge too; Connecting/Reconnecting do not wait for a pending dial. Then `Timui.close`, bounded status output, and `Sys.exit_done` ensure parked IO cannot linger. Do not use `IO.die` for successful UI shutdown: the pinned runtime writes an unbounded stderr newline even for an empty message. TimUI teardown restores terminal state before the final `_Exit`.
- All terminal writes, including BEL and OSC 52, use the frame deadline. The native transport owns at most three UTF-8 suffix bytes; later writes must complete them first. Clipboard process work runs through Bend `Process.run` outside the frame, not synchronous `popen` in C.
- Log lines carry author identity and stable global IDs. Never infer new events by comparing rendered text/timestamps. Reconnect dividers are `Reconnect`, not a substring test; `Reconnecting` preserves same-endpoint intent through dialing. Unread names and alert levels are separate fields.
- Scroll uses one message-and-character anchor (`ScrollAt{after, tail}`). View wrapping supplies both paint rows and navigation bounds. Never clamp live navigation by logical line count or store width-dependent row offsets.
- `BIRC2` history includes the hostname and port. The IO reader rejects ambiguous legacy records, reads bounded chunks to the initial file size, and retains recent records. Save the current event before loading a changed endpoint; install the loaded client as the next history checkpoint so restored rows are not appended again. Replay uses the same byte framer as live input, reads the initial file snapshot in bounded chunks, preserves a final unterminated record, and fails closed on size/read/early-EOF errors.
- `*log*` is lazy, read-only, app-session state: reserve one of 16 buffer slots, keep at most 128 rows of 512 characters, and preserve it across endpoint changes. Error mirrors keep their original event IDs and never steal focus. Log rows never enter chat history. Helper diagnostics include only safe stage labels and numeric codes; never log child output. A history-save failure goes directly to the log and schedules a coalesced repaint, not a persisted chat error or another save. Normalize wire targets before reserved-name validation and lookup; share target predicates with submission. Generic local lookups must still resolve synthetic tabs. Preserve the `NOTICE *` broadcast exception.
- Images use one bounded helper worker, eight pending requests, and eight cached results. Production View uploads only accepted nonzero `OpMedia` tokens; pending/failed intents draw placeholders, never a raw-file fallback. Bend's prospective completion supplies retained payload tokens to native admission; native FIFO must not evict a token that Bend still owns. Legacy `OpImage` adapters are for characterization/law tests only. Decode/ingestion does not allocate terminal image IDs or write output; an accepted frame owns its copied media. Late completions release the active worker but cannot restore disabled/stale previews. Kitty/iTerm animation is terminal-side; do not add an app animation timer.
- Native cells store complete UTF-8 clusters in buffer-owned arenas. Bare cell copies must not transfer arena attachments. Bend layout, native tabs, and FFI clipping use the same TimUI common-cluster boundaries and widths, not scalar sums. Selection appends complete clusters with checked growth; failure leaves the previous clipboard unchanged. OSC8 targets are exact through 1024 bytes; decline larger targets.
- Bend keeps clusters whole across source style runs, with the leading character's style. Word wrapping prefers complete IRC spaces; oversized words/URLs hard-wrap. Hidden boundary spaces still contribute to source-character anchors. Tab-label byte clipping must retain complete common clusters.
- History append creates `0600` files and repairs owned regular files via descriptor `fchmod` before writing. Reject final symlinks, nonregular files, and foreign ownership; never change the global umask. Keep the foreign append effect in `history_io.bend`, not the proof-facing History module.
- Keep actual channel names such as `+#room` unchanged in creation, membership events, and stored history. At message/typing audience boundaries, prefer an exact resident channel before STATUSMSG fallback; `@#room` remains an unambiguous alias. Measure nickname-prefix columns on the complete painted text, not nickname width plus punctuation.
- Canonicalize known synthetic identities at creation, not generic stored-name lookup. A peer named `server` is a query; construct the control buffer with `server_buf`. A new connection clears channel roster/topic, but keeps same-endpoint chat history. Split NICK handling shares Client's accepted-rename predicate.
- `Sub.slash_rows` is the command/completion catalog, including Session-owned aliases in their established order. Space-scan wrappers must preserve their distinct remainder policies: protocol keeps separators, verb drops one, word drops all.
- Authentication profiles bind credentials to the initial host and port. Any endpoint change permanently clears credentials and disables actor SASL negotiation; same-endpoint reconnects retain the profile. SASL uses parsed control events and 400-character UTF-8 Base64 chunks. NickServ requires a phase-gated HELP identity probe before IDENTIFY and exact full-prefix/current-recipient/display-text confirmation. Only explicit unavailable-SASL replies can trigger fallback, not a bad password. Track explicit nicknames separately; resolve defaults after CLI/environment settings are combined.
- `src/launcher/keychain_birc.py` owns nonsecret TOML profiles and macOS `security` access. Verified TLS profiles need no relay or unsafe flag. Plaintext requires a declared trusted IPv4 loopback relay or per-launch `--allow-insecure-auth`. Resolve the TLS/default-port selection before endpoint-bound Keychain lookup. Never test real credentials or Keychain writes. Versioned ASCII envelopes preserve Unicode through security's hex-print behavior. The wrapper sends raw UTF-8 through an inherited EOF pipe; the separate one-shot `BIRC_AUTH_OK\n` pipe is emitted only on Bend's monotonic auth-success edge. Descriptor env values are not secrets; the native bridge sets CLOEXEC. Never infer success from stdout or child exit. Manual service credential commands skip local echo/history, but manually typed composer drafts remain visible.
- Headless (stdin is not a tty) awaits the bounded initial registration result before painting `--frames N` and exiting; initial failure exits nonzero. On a tty, `N` is a message cap and the loop parks; loop tests need a pty (`make test-pty`).
- IRCv3 `+typing` state is Bend-owned, capped at 32 entries, and expires from a one-second `TypingTick`; active lasts 6 s and paused lasts 30 s. The tick repaints only for expiry changes, writable short frames, or timed input pending after a non-key paint. The last case repairs a watcher that parked before the frame read input; normal Esc still has its 50-ms watcher deadline. Partial UTF-8 has no idle expiry. `UiKeys.more` is input-only; terminal recovery does not schedule synthetic input wakes. Ordinary frames have a 40-ms output budget; writable repairs have 200 ms; still-full repairs do not wait.
- A new or changed pty test must pass three consecutive runs before its commit.
- Prove laws; do not weaken them to make a candidate pass.
- The pinned Bend `Bool.pick` evaluates both alternatives eagerly. For recursive branches or row construction, use parameter matches or a lazy continuation; do not pass recursive calls as its values. `BIRC_FRAME_PROFILE=1` measures pure View separately from native frame phases; instrumentation is default-off.
- Keep proof-facing queue rules in `outbound.bend`, not the IO actor module. Importing the actor into `LAWS.bend` brings foreign/unsafe dependencies and the checker rejects the proof set.
- Bend pitfalls: no `match f(x)`; `+T` is copyable; match binders in param order;
  self-recursion needs decreasing fuel as the first arg; no dotted forward refs;
  `match` cannot scrutinize a computed value, a local binder, or a destructuring let;
  escapes: `Maybe.default`, `Maybe.bind`, `do Maybe`, `Bool.pick`, decision `Bool` as a parameter;
  `law T: Type` needs `def T(): SomeHandleType` (e.g. `Window`).
