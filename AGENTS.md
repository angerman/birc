# birc — agent instructions

## Work mode — current process authority (2026-10-12)

Follow `~/.config/ai/AGENTS.md` and the shared `iterate-fast` workflow.
**BUILD is the default. HARDEN is for an explicit audit, release, or final
qualification.** These modes replace older procedural rules in goals, plans,
review checklists and this file: per-commit freezes, separate red commits,
mandatory model/provider chains, repeated approval packets and full-suite
reruns. Product scope, technical contracts, compatibility, source restrictions,
security and data-safety requirements still apply.

- In BUILD, choose one real user action and the smallest command that proves
  it. Implement a vertical slice, run focused checks, and commit useful work.
  For defects, add a failing case and a correct sibling before or with the fix.
  A new API may be built with its tests; no design/red review gate is required.
- Repair test setup, teardown, imports, mocks, build flags and observations
  without approval when the intended product oracle stays intact. This includes
  existing fixtures. Explain the repair and preserve meaningful positive and
  negative cases. Never change expected product behavior, weaken rejection or
  cleanup, relax safety deadlines, or hide failures to make a candidate pass.
  Ask when the intended behavior is unresolved.
- Keep the author through correction rounds. Use isolated worktrees for
  concurrent writers. Review the changed behavior and its affected assumptions;
  put unrelated findings in the existing backlog. Do not create new review
  rounds, execution packets or plan amendments for routine corrections.
- Run one relevant broad gate on the integrated batch. Carry unchanged evidence
  forward; repeat checks only for changed inputs, failures or unresolved risk.
  HARDEN adds the independent review and platform, compatibility, sanitizer and
  release checks needed for the final claim. Keep synthetic, host and real-device
  evidence distinct.
- After two unsuccessful correction rounds, reduce to one reproducer and decide
  the next implementation step. Do not grow an evidence framework. Keep one
  short pickup note with the current result, open blocker and next command.
- Bound heavyweight commands and owned child processes; serialize heavy builds
  when the host is busy. Preserve cleanup, user files and unrelated work.
  Instrument before optimizing. Never push without explicit authorization;
  stricter project no-remote and crypto rules below remain in force.

When using Bend:
- run `bend guide` to learn it
- use `LAWS.bend` to keep important rules
- run the full proof with the integrated batch gate; no selective law-check target exists
- a commit that adds or renames a `src/` file updates the concern row it belongs to — never a file list
- use parallel work only for independent, useful slices with separate writers

When using timui.h:
- one header, C99, POSIX file descriptors, no ncurses
- define `TIMUI_IMPLEMENTATION` in exactly one translation unit (`src/ffi/timui_ffi.c`)
- draw only between `timui_begin` and `timui_end` (inside a single `Timui.frame`)

## Scope

`birc` is an IRC client: **Bend 2 owns main, protocol, client, submit, framer,
networking, and the frame loop**; C is thin native FFI under `src/ffi/`; the
TUI is `src/ui/timui.h`. **The product itself is Bend + C + timui.h only.**
Do not add Python to the live client, the packaged binary, or a product helper
that `birc` must spawn. Python may remain in tests and Makefile/PTY harnesses.
Do not add a packaged Python helper for a path that already has a native owner.
IRC defaults to verified OpenSSL TLS and port 6697. `--plain` explicitly selects
plaintext and defaults to 6667; `--tls` and `--plain` conflict. An explicit port
never selects the transport. Never hand-roll cryptography, disable certificate
verification, or fall back to plaintext after TLS failure. No ncurses or curl-pipe
installers. History search uses the linked native scan (`BIRC_SEARCH_HELPER`
defaults to `native`). Preferences use the linked native file effect
(`BIRC_PREFS_HELPER` defaults to `native`): C admits the private file and
TOML document; Bend owns the wire and settings policy. Desktop notifications
spawn `notify-send` or `/usr/bin/osascript` directly. Remote image and card
previews use the linked native fetch/decode (`BIRC_MEDIA_HELPER` and
`BIRC_CARDS_HELPER` default to `native`): C admits files, talks HTTP/1.1 over
the existing OpenSSL stack, and decodes with vendored stb_image; Bend owns
request identity, queues, and visible admission.
Never fetch supplied private chat URLs during tests.
Confirmed file uploads use the linked native HTTPS effect
(`BIRC_UPLOAD_HELPER` defaults to `native`): C admits one regular file and
posts HTTP/1.1 over the existing OpenSSL stack to `0x0.st`; Bend owns
consent and URL policy. Tests use synthetic files, fake helpers, and owned
loopback servers; never upload user files or contact the public service from
tests.

Original material: Apache-2.0; author Moritz Angermann <moritz@zw3rk.com>.
Preserve upstream licenses. Do not add model attribution.

## Provision and run

Nix provisions dependencies. The root Makefile is the sole driver.

```
make bootstrap   # create flake.lock (once)
make shell       # enter the locked shell
make check       # integrated batch gate: proof + Bend tests + net + UI smoke
make run-demo    # offline TimUI demo
make run HOST=…  # live verified TLS IRC; optional PORT=… or TRANSPORT=plain
```

Do not use Homebrew/global installs, ambient compilers, `sudo make`, or
silent flake/source pin updates. Routine Nix work uses
`--no-update-lock-file`. Only `make update CONFIRM=yes` may move pins.

## Layout

Concern rows name a glob and an invariant. A commit that adds or renames a
`src/` file updates the concern row it belongs to — never a file list.
Per-file rows are only the modules whose contract is easy to misread.

| Path | Invariant |
|---|---|
| `TODO.md` | Migration checklist through M27. Current contracts are this file; the milestone history is not a status board. |
| `LAWS.bend` / `PROOF.bend` | Laws discharged 1:1. `make proof` generates one book per law under `build/proof` (`scripts/split-proof.py`); one book that imports the whole closure does not finish. `LAWS.bend` must never import the IO/effect layer. Cheap gate: `make lint-laws-io` (`scripts/check-laws-io.sh`; wired into `lint-ffi` / `check`). |
| `src/bend/{actor,app,auth_bridge,net,wsnet,timui,dns,tls,transport,clock,*_io,*_live,*_worker,*_runtime}.bend` | IO/effect layer: foreign effects, or the modules that run them. `LAWS.bend` must never import these. `dns` here is `src/bend/dns.bend` only; `src/bend/dns_wire.bend` and `src/bend/dns_query.bend` are pure. |
| `src/bend/*.bend` | Pure domain modules that are outside the IO/effect row and do not import it. Proofs may import those. |
| `src/ffi/*.c` | Thin native effects. C does not parse IRC or decide authentication. `TIMUI_IMPLEMENTATION` lives only in `src/ffi/timui_ffi.c`. |
| `src/launcher/*.py` / `src/media/*.py` / `tests/lib/*.py` | Test oracles only — not the IRC client. Image, cards, preferences, history search, confirmed uploads, and Keychain launch are native. Do not add Python to the product path. |
| `src/ui/timui.h` | Vendored single-header TUI. |
| `docs/FFI.md` / `docs/build-speed.md` / `docs/column-walker-retention.md` / `docs/handover-2026-10-08.md` | Reference notes. The handover is superseded by this file. This file wins when they disagree. |

| Path | Invariant |
|---|---|
| `src/bend/cap_notify.bend` | IRCv3 capability registry and the sole `CAP END` owner. Not notification policy. |
| `src/bend/notify.bend` | Per-event notification policy. Delivery effects stay in `src/bend/notify_io.bend`. |
| `src/bend/auth.bend` | Parsed, phase-gated SASL. Credentials bind to the initial host and port. |
| `src/bend/outbound.bend` | Proof-facing send-cap batches and finite credits. Queue rules stay here, not in `src/bend/actor.bend`. |
| `src/bend/history_io.bend` | Foreign history append. The proof-facing history module does not own this effect. |
| `src/bend/history_startup.bend` | Auth-free startup snapshots, nontrimming import, and fresh-ID dividers. The archive worker is `src/bend/history_startup_io.bend`. |
| `src/bend/live_context.bend` / `src/bend/startup_headless.bend` | Settings-before-history startup and generation-scoped actor release. Both import the IO layer, so `LAWS.bend` must not import them. |
| `src/bend/preferences_runtime.bend` | Bounded settings queue, edit-wins loading, and quit drain. Live loading is `src/bend/preferences_live.bend`. |
| `src/bend/join_plan.bend` | Desired membership, transient keys, and the welcome/auth recovery barrier. |
| `src/bend/replay.bend` | Bounded file-snapshot replay through the live byte framer; fails closed. It imports `src/bend/clock.bend`, so proofs must not import it. |
| `src/bend/media.bend` | Image request identity, one-worker queue, and stale-result policy (pure). |
| `src/bend/upload.bend` | Local path decoding, per-file consent, and fixed-origin results (pure). The process effect is `src/bend/upload_io.bend`. |
| `src/bend/transport_policy.bend` | Pure transport and default-port policy. TLS effects stay in `src/bend/tls.bend`. |
| `src/bend/client_laws.bend` / `src/bend/view_laws.bend` | Proof-facing feed and view predicates. |
| `src/bend/emoji.bend` | View-only shortcodes. Wire text and history keep the raw source. |
| `src/bend/session_keys.bend` | Pure composer key, panel, and input-recall decisions. `session.bend` keeps `Hist`/`Comp`/`Keys` constructors and applies the returned plan. |

## Engineering

- Fail closed: missing targets exit nonzero.
- Never list global process command lines during diagnostics; they can contain
  credentials. Inspect only owned process IDs and non-argument fields such as
  executable, elapsed time, and CPU usage. Never log command-line secrets.
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
- Net: `IO.spawn` actor owns affine `Tr.Conn`; UI ↔ actor via `Chan(NetEvt)` / `Chan(NetCmd)` (Data). Live inbound is `recv_octets` + `Fr.push`; completed lines are UTF-8, with Latin-1 fallback if a line is not valid UTF-8. The actor owns the fd/TLS handle (never `Chan(Conn)`). `SEND_CAP` is 8 outbound lines per actor tick; leftover stays in `pending`. `--frames N` is N ticks (at most `SEND_CAP*N` lines during the loop); cmd close and fuel-0 flush `pending` so `/quit` is not dropped. `frames=0` live loops are `@unsafe`. Live DNS A is Bend UDP plus `recv_octets`. Demo/offline idle actor waits for `Dial`; Demo/Connecting `Cont` carries no IRC outs (no flush after Dial). C does not tokenize. Clock is applied at log IO, not every paint. `--replay FILE` uses `src/bend/replay.bend` and fails closed. `--help` is Bend's runtime CLI; birc usage is `--help-irc`.
- Shutdown (P5): the writer flushes its healthy pending FIFO, closes its connection, and posts `WriterDone`. Only the current generation's `WriterDone` acknowledges shutdown; reader EOF and stale completions cannot. Demo/Offline idle writers acknowledge too; Connecting/Reconnecting do not wait for a pending dial. Then `Timui.close`, bounded status output, and `Sys.exit_done` ensure parked IO cannot linger. Do not use `IO.die` for successful UI shutdown: the pinned runtime writes an unbounded stderr newline even for an empty message. TimUI teardown restores terminal state before the final `_Exit`.
- All terminal writes, including BEL and OSC 52, use the frame deadline. The native transport owns at most three UTF-8 suffix bytes; later writes must complete them first. Clipboard process work runs through Bend `Process.run` outside the frame, not synchronous `popen` in C.
- Log lines carry author identity and stable global IDs. Never infer new events by comparing rendered text/timestamps. Reconnect dividers are `Reconnect`, not a substring test; `Reconnecting` preserves same-endpoint intent through dialing. Unread names and alert levels are separate fields.
- Scroll uses one message-and-character anchor (`ScrollAt{after, tail}`). View wrapping supplies both paint rows and navigation bounds. Never clamp live navigation by logical line count or store width-dependent row offsets.
- `BIRC2` history includes the hostname and port. The IO reader rejects ambiguous legacy records, reads bounded chunks to the initial file size, and retains recent records. Save the current event before loading a changed endpoint; install the loaded client as the next history checkpoint so restored rows are not appended again. Replay uses the same byte framer as live input, reads the initial file snapshot in bounded chunks, preserves a final unterminated record, and fails closed on size/read/early-EOF errors.
- Preference-enabled startup paints first, resolves settings, reads an auth-free
  archive worker snapshot, and sends one generation-scoped `Begin`. Unknown
  settings policy cannot read/write history without accepted explicit intent.
  Import preserves current rows, IDs, metadata, and tabs. Report owned worker
  diagnostics before capturing the archive cutoff; add dividers only to
  imported targets with spare capacity. The postimport client is the checkpoint
  before completion-paint input, so imported rows are not saved again but new
  input still is. Box wide continuation state: the pinned Bend backend permits
  at most 247 flattened capture words. Headless resolves the same policy once
  before registration; `BIRC_PREFERENCES=none` keeps the direct startup path.
- `*log*` is lazy, read-only, app-session state: reserve one of 16 buffer slots, keep at most 128 rows of 512 characters, and preserve it across endpoint changes. Error mirrors keep their original event IDs and never steal focus. Log rows never enter chat history. Helper diagnostics include only safe stage labels and numeric codes; never log child output. A history-save failure goes directly to the log and schedules a coalesced repaint, not a persisted chat error or another save. Normalize wire targets before reserved-name validation and lookup; share target predicates with submission. Generic local lookups must still resolve synthetic tabs. Preserve the `NOTICE *` broadcast exception.
- Images use one bounded helper worker, eight pending requests, and eight cached results. Production View uploads only accepted nonzero `OpMedia` tokens; pending/failed intents draw placeholders, never a raw-file fallback. Bend's prospective completion supplies retained payload tokens to native admission; native FIFO must not evict a token that Bend still owns. Legacy `OpImage` adapters are for characterization/law tests only. Decode/ingestion does not allocate terminal image IDs or write output; an accepted frame owns its copied media. Late completions release the active worker but cannot restore disabled/stale previews. Kitty/iTerm animation is terminal-side; do not add an app animation timer.
- Query terminal image support once after opening the UI. No selected protocol
  means no image helper or placeholder area; preserve exact URL text and report
  one fixed explanation in the lazy log. Support never changes the saved image
  preference. Visible saved-history chat uses the live bounded media path;
  replay/demo stays offline. Use exact painted panes, mute filters, row anchors,
  and stable event IDs. Preserve selected visible results at cache capacity,
  reject hidden completions before native ingestion when no slot is available,
  and never start a queued image worker after Stopping. Manual previews remain
  explicit intent.
- The optional remote-source cache uses private owned files, exact-URL hashed
  names, and 64-entry/64-MiB FIFO bounds plus one atomic staging file of at most
  8 MiB. Decode and normalize every hit. Cache failures fall back to guarded
  fetching; local previews never enter the disk cache. Refuse symlinked paths,
  unsafe ownership, nonregular files, and nonprivate directories without
  changing unrelated directory permissions. `BIRC_IMAGE_CACHE=none` disables
  persistence; tests isolate or disable cache access. Never clean up a staging
  file whose exclusive creation failed.
- Native cells store complete UTF-8 clusters in buffer-owned arenas. Bare cell copies must not transfer arena attachments. Bend layout, native tabs, and FFI clipping use the same TimUI common-cluster boundaries and widths, not scalar sums. Selection appends complete clusters with checked growth; failure leaves the previous clipboard unchanged. OSC8 targets are exact through 1024 bytes; decline larger targets.
- Bend keeps clusters whole across source style runs, with the leading character's style. Word wrapping prefers complete IRC spaces; oversized words/URLs hard-wrap. Hidden boundary spaces still contribute to source-character anchors. Tab-label byte clipping must retain complete common clusters.
- History append creates `0600` files and repairs owned regular files via descriptor `fchmod` before writing. Reject final symlinks, nonregular files, and foreign ownership; never change the global umask. Keep the foreign append effect in `src/bend/history_io.bend`, not the proof-facing History module.
- Keep actual channel names such as `+#room` unchanged in creation, membership events, and stored history. At message/typing audience boundaries, prefer an exact resident channel before STATUSMSG fallback; `@#room` remains an unambiguous alias. Measure nickname-prefix columns on the complete painted text, not nickname width plus punctuation.
- Canonicalize known synthetic identities at creation, not generic stored-name lookup. A peer named `server` is a query; construct the control buffer with `server_buf`. A new connection clears channel roster/topic, but keeps same-endpoint chat history. Split NICK handling shares Client's accepted-rename predicate.
- `Sub.slash_rows` is the command/completion catalog, including Session-owned aliases in their established order. Space-scan wrappers must preserve their distinct remainder policies: protocol keeps separators, verb drops one, word drops all.
- Authentication profiles bind credentials to the initial host and port. Any endpoint change permanently clears credentials and disables actor SASL negotiation; same-endpoint reconnects retain the profile. SASL uses parsed control events and 400-character UTF-8 Base64 chunks. NickServ requires a phase-gated HELP identity probe before IDENTIFY and exact full-prefix/current-recipient/display-text confirmation. Only explicit unavailable-SASL replies can trigger fallback, not a bad password. Track explicit nicknames separately; resolve defaults after CLI/environment settings are combined.
- The first valid connection-server `001` owns the assigned nickname. Normalize
  it before Auth, JoinPlan, and Client consume that welcome. Reject malformed,
  peer-prefixed, and later conflicting welcomes without changing live state.
  Reconnect guards must verify actual SASL wire exchange and all desired rooms,
  not only registration or the launch channel.
- `src/ffi/keychain_birc.c` owns the packaged `keychain-birc` launcher: nonsecret TOML profiles and macOS `security` access. Verified TLS profiles need no relay or unsafe flag. Plaintext requires a declared trusted IPv4 loopback relay or per-launch `--allow-insecure-auth`. Resolve the TLS/default-port selection before endpoint-bound Keychain lookup. Never test real credentials or Keychain writes. Versioned ASCII envelopes preserve Unicode through security's hex-print behavior. The wrapper sends raw UTF-8 through an inherited EOF pipe; the separate one-shot `BIRC_AUTH_OK\n` pipe is emitted only on Bend's monotonic auth-success edge. Descriptor env values are not secrets; the native bridge sets CLOEXEC. Never infer success from stdout or child exit. Manual service credential commands skip local echo/history, but manually typed composer drafts remain visible. `tests/lib/keychain_birc.py` is the test-only policy oracle.
- Headless (stdin is not a tty) awaits the bounded initial registration result before painting `--frames N` and exiting; initial failure exits nonzero. On a tty, `N` is a message cap and the loop parks; loop tests need a pty (`make test-pty`).
- IRCv3 `+typing` state is Bend-owned, capped at 32 entries, and expires from a one-second `TypingTick`; active lasts 6 s and paused lasts 30 s. The tick repaints only for expiry changes, writable short frames, or timed input pending after a non-key paint. The last case repairs a watcher that parked before the frame read input; normal Esc still has its 50-ms watcher deadline. Partial UTF-8 has no idle expiry. `UiKeys.more` is input-only; terminal recovery does not schedule synthetic input wakes. Ordinary frames have a 40-ms output budget; writable repairs have 200 ms; still-full repairs do not wait.
- Use deterministic progress conditions in PTY tests. Repeat the affected case
  when investigating a timing or race defect; do not require three reruns before
  every commit. Preserve real deadlines and terminal/process cleanup assertions.
- Prove laws; do not weaken them to make a candidate pass.
- The pinned Bend `Bool.pick` evaluates both alternatives eagerly. For recursive branches or row construction, use parameter matches or a lazy continuation; do not pass recursive calls as its values. `BIRC_FRAME_PROFILE=1` measures pure View separately from native frame phases; instrumentation is default-off.
- Keep proof-facing queue rules in `src/bend/outbound.bend`, not the IO actor module. Importing the actor into `LAWS.bend` brings foreign/unsafe dependencies and the checker rejects the proof set.
- Bend pitfalls: no `match f(x)`; `+T` is copyable; match binders in param order;
  self-recursion needs decreasing fuel as the first arg; no dotted forward refs;
  `match` cannot scrutinize a computed value, a local binder, or a destructuring let;
  escapes: `Maybe.default`, `Maybe.bind`, `do Maybe`, `Bool.pick`, decision `Bool` as a parameter;
  `law T: Type` needs `def T(): SomeHandleType` (e.g. `Window`).
