# birc backlog — findings awaiting a calm host or a fix slice

- Multiserver `/quit` only quit the focused server: **FIXED** (`0962849`).
  `tests/pty/server_multiserver.py` — the first test ever to execute the
  `--server` path — reproduced it stably across two runs. With two loopback
  peers, `/quit` put `QUIT :birc` on the focused part's socket only; the other
  part's wire ended at `JOIN #t` / `PONG` and never received `QUIT`, yet the
  process exited 0 and printed `birc=ok`. Cause: `/quit` enqueued on the focused
  part, so the other writer's pending FIFO was empty and `ws_shutdown.drop`
  (`src/bend/wsnet.bend:2171`) acknowledged its `WriterDone` without a line ever
  being sent; `ws_shutdown.close` (`:2293`) then closed every command channel.
  Peers saw a socket close, not a clean quit.
  Fix: `quit_broadcast` (`src/bend/workspace.bend:1400`) copies every
  `QUIT `-prefixed line onto the other live parts as `Cont`, skipping the focused
  part, with **no generation bump**. `step_keys.routed` / `step_keys.routed.pick`
  (`workspace.bend:522` / `:517`) are untouched, so `route_transport`'s `{==}`
  definitional-equality mirror still holds. Verified `server_multiserver=ok`,
  exit 0, and the second peer's wire now ends
  `…PONG :beta-routed\r\nQUIT :birc\r\n`; re-verified on a quiet lane after the
  `wsnet` continuation refactor (`0600a0c`) that also touched this path. The
  target is still deliberately **not** in `PTY_SUITE_TARGETS`, so run it
  directly. The assertion was never weakened to hide the original defect.

- Input latency scales with scrollback: `visible_lines` walks the whole
  buffer twice per frame per pane (`List.length` + `List.drop`) before
  wrapping only the visible rows. Measured `view_us` 1.5ms (tiny demo)
  vs 10ms (2000 rows) under load 26; calm-host numbers needed to split
  algorithmic cost from scheduling stalls (`begin` is O(1) input drain,
  so its 100ms average there is descheduling, not work). Repro:
  `BIRC_FRAME_PROFILE=1` on a pty with `--replay` of a large transcript.
  Fix direction: cached lengths or anchor-relative slicing; keep scroll
  and navigation semantics pinned while touching this path.
  **PARTIALLY FIXED, now measured.** `columns.bend` no longer derives
  cluster-walk fuel from `String.length(rest)`, `pending_display_lines`
  short-circuits when nothing is pending, and the live-bottom path builds a
  bounded newest-first suffix instead of reversing the whole scrollback.
  `tests/perf/long_lines.py` on a quiet lane: 64 → 510 octets per line is
  ×7.97 in length and ×7.96 in `view_us`, i.e. linear where the per-cluster
  length scan was quadratic. Keystroke-to-glyph p95 went 1.46 → 1.18 ms and is
  gated by `tests/perf/key_latency.py`. Still open: scrolled-away frames call
  `List.length` over the whole line list (`view.bend:1236` and siblings), and
  `rev_tail` recursion depth still follows scrollback.

- runtime_reconnect C-backend arity: FIXED (test-only) — main holding
  4 live Sessions breached the 247-word native continuation limit
  ("an arity over 247") as Session grew. Split into phase defs holding
  only SBox singleton-list cells (session_drafts_demo idiom);
  assertions unchanged, in the same order. `runtime_reconnect=ok`.

- test-dns-live red: FIXED — the "wrong answer" was a correct AAAA
  response: dual-stack `Dns.resolve` now parses A and AAAA, and the
  live test accepts a well-formed AAAA record for one.one.one.one.
  `dns_live=ok`; `dns_demo` pins the parse shape.

- pty-diagnostic SASL fixture: FIXED (test-only, no product change) —
  red since the Oct 3 welcome/auth barrier (df95f2c): the fixture sent
  a bare 001 with SASL creds configured and the client correctly held
  JOIN behind the barrier, so `missing channel join` failed. The
  fixture now completes a real SASL PLAIN exchange (ACK/`+`/903/CAP
  END) on the initial endpoint, asserting each client step, and the
  post-`/connect` welcome passes `expect_auth=False` with a negative
  guard (JOIN flows, no AUTHENTICATE — pins credential clearing).
  Residual design question (not a defect): against a CAP-silent
  server with creds configured, 001 lands the auth phase in AuthDone
  via SaslRegistered and joins hold forever under the misleading
  "authentication failed" notice. No real server skips CAP LS; if one
  appears, the fix is an auth-negotiation timeout, not a barrier
  release (fail closed per contract 2).
- media_history C-backend arity: FIXED — the 66-statement main holding
  ~10 live Sessions breached the 247-word native continuation limit
  ("an arity over 247"). Main is split into phase defs holding only
  boxed Sessions (SBox singleton-list cells, session_drafts_demo
  idiom); assertions unchanged, in the same order. Native C build
  plus `media_history=ok` verified, JS gate stays green.
- Column-walker retention: phase machines LANDED (a1aa3e6), post-fix
  census DONE, and the idle-creep watch item is ATTRIBUTED (see
  "Follow-up: idle SCON attribution" in
  `docs/column-walker-retention.md`): a 16-min soak plus a live probe
  show zero COLUMNS rows in 30 dumps (column fix exonerated) and the
  live +336 SCON/interval is PONG keepalive trickle logged via
  `feed_unk`, with the raw excess as freelist residue. FIXED with it:
  PONG is now quiet in feed like PING (`feed_pong` no-op, both
  dispatchers; lag arm still measures RTT pre-feed), pinned by
  `pong_quiet`/`pong_lag`/`pong_quiet_with` in net_demo. Residual
  watch items: the >90-min SCROLL_CAP bind was not observed (trickle
  must flatten once buffer 0 hits 1024 lines); the negotiated-fold
  PONG-out arm (`fold_step.ping_at_with`) still emits and is a
  probable live-dupe vestige — needs a live-server probe before any
  change (removal without one risks keepalive).
- wf-composer split prefix: UNIFIED under one rule (reverse of the
  suggested default, justified): C always seats exactly one text
  widget (`src/ffi/timui_ffi.c` chooser dropped its zero-inner skip and
  picks bottom-most/left-most over ALL panes, even zero-inner), and
  Bend always paints the `<nick>` prefix in that same pane
  (`src/bend/view.bend` composer_inner_w/composer_row mirror C's inner
  geometry exactly, possibly zero bytes; split_composer_rect orders by
  C's inner bottoms, fixing 1-high stacked panes where outer bottoms
  tie). Typing stays live at every size. Why the reverse: the A6
  tinyquit docstring records "always create the text area" as intent,
  `test-pty-tinyquit` was RED on 1col/2col/3col-then-1x1 at baseline
  (needs live typing; Bend-silence would keep it red without weakening
  the test), and the skip regressed single-pane narrow typing when the
  split chooser landed (c19445d). Pins: `test-pty-split-composer`
  asserts zero nick-prefix bytes across bounce repaint windows +
  steady-cursor seat origins (22;3H stacked-24x6, 22;2H side-24x6/24x4)
  + live typing, plus stacked-3x80 full-prefix agreement at (3,3)/3;9H;
  `test-pty-tinyquit` asserts no prefix bytes at 1-2col single-pane
  while /quit works there again. Gates GREEN: `split_composer=ok`,
  `tinyquit=ok` (all 8 cases), `split_pty=ok`, `build-ui`.
- wf-composer: `src/ffi/timui_ffi.c` full compile RESOLVED — `make build-ui`
  links (`build/birc`) and `draw_composer` is defined, called, and
  present in the emitted TU, so the FFI content compiles. (Split-prefix
  entry still owns the split-mode PTY gate.)
- wf-cards URL dedup: all-empty cards now yield zero rows; title-empty but
  desc-bearing cards still echo the URL as the card title line. Confirm the
  partial-metadata echo is the wanted look (item 3 screenshot was the
  no-metadata case, now fixed).
- test-auth-privacy: FIXED — root cause was `hist_after_typed` judging
  only per-line fragments, so a credential verb fractured across a line
  break (`IDEN\rTIFY`) read benign. It now also judges the joined whole
  and fails closed. `auth_privacy=ok` verified (calm-host batch).
  Watch item RESOLVED via timeout bump (calm-host pinning rejected as
  larger/riskier: new ssh-dispatch machinery in the build path).
  Calm-host (aarch64-darwin-1) measurements: `build/birc` -O2 link
  143 s, `auth_privacy` Bend build 92 s, app codegen 102 s (all well
  inside old bounds when calm; ~280 s / ~180 s under laptop load).
  `BUILD_TIMEOUT` 300 -> 600 (~2x worst observed; `=900` override
  stays for extreme load) and explicit `auth_privacy` 360 s Bend
  bound (~2x worst observed, literal per test-build-deadlines).
  `build-ui`, `test-auth-privacy`, `test-submit` green with native
  timeouts on the calm host.
- test-feed body_ys: FIXED — oracle drift, not a view regression.
  `c19445d` (inline <nick> composer) moved `status_y` rows-2 -> rows-1
  and appended one `composer_ops` OpLine per frame without updating
  `VL.body_ys_ok`. Probe proved count = vis_n+1 in all 12 cases and
  `lay` now (1,2,3)/(1,22,23) vs the stale (1,1,2)/(1,21,22). The law
  now pins count = vis_n+1, last = composer row, sorted + mutually
  distinct history, strict whenever the box separates history from
  the composer (tiny boxes rows 1/2/3/5 share the row: geometry, not
  a bug). One genuine view wart fixed with it: `body_y0` underflowed
  to y=U32::MAX on 1-row terminals (empty hist rect); it now starts
  at the top row (`src/bend/view.bend`, `body_y0.zero` guard —
  behavior-identical except y=0,h=0; `inner_last` untouched so
  `cards.bend` fullscreen math is unaffected). `feed_demo=ok`
  verified on the calm host; `test-proto` + `proto-parity` sanity
  green.
- test-theme-ws-render: FIXED (`9b5bd55`) — oracle drift, not a view
  regression, and the same family as `test-feed body_ys` above.
  `ws2 framed rendered bytes exact` compares `lines_text`, which
  concatenates every `OpLine`. Since the inline-`<nick>` composer
  (`c19445d`) each frame also carries a `composer_ops` OpLine holding
  the nine-space timestamp indent plus `<nick> `, and the expectation
  predated that, stopping at `...a end`. It now includes the composer
  prefix, which matches the documented intent in the `wf-composer split
  prefix` entry above ("Bend always paints the `<nick>` prefix in that
  same pane"). Green on a quiet lane at `4f75027`. No product change was
  needed and none was made; the assertion was not relaxed.
- proof: **`bend PROOF.bend` as one book does not finish** (Bun GC; system ≫
  user; measured 3h timeout). That is not a host-load problem — do not rerun
  the monolithic book on a calmer host hoping for green. An earlier "510 TODOs"
  probe was misread as unshardable; the working gate is one law per book under
  `build/proof` (`scripts/split-proof.py`, `make proof`). See `PROOF.bend`
  header and `docs/plan-2026-10-16-simplification.md`. Keep `law` ↔ `def Laws.X`
  1:1. Never weaken a law to force a shard green.
- workspace GC oracles: `epoch_redial_*`, `composer_*_ok`, and most
  `runtime_*_ok` conjunctions still explode Bun GC as one-law shards. They stay
  in `tests/bend/sessws_s1s5_demo.bend`, now wired into `test-review-pure` /
  `make check`. Prefer more one-observation laws when a shard normalizes alone.
- test-media-anchor and the native `build/session_cards_demo`: both were
  FAILING with `Error: an arity over 247`, the C-backend flattened-capture-word
  cap. Verified identical on the pre-review baseline `208f7c9` and on
  current master, so pre-existing; both compile fine for the **JS**
  backend (`-o build/X.js` rc=0), which is why `make test-session-cards`
  passes while the native build does not. `test-media-anchor` is a
  `test-review-pure` prerequisite, and `test-goldens-view` dies at the
  first arity error without printing its `bins=` line, so this blocks
  part of `make check`. Same class as the `runtime_reconnect` entry above.
  **Status after the `SBox`/`ADBox` boxing pass:** `media_anchor` now
  compiles natively (rc=0) but its run exposes a *second*, previously
  masked failure — see the next entry. `session_cards_demo` native still
  reports `an arity over 247`; the remaining suspects are `ph_rows`
  holding one `C.State` and any single unboxed `Session` temporary the C
  flattener keeps across a `ph_*` bind.
- media_anchor stacked clips: resolved by keeping paint geometry.
  `body_hist_rect` is the history window (composer row reserved, then the
  inner border). The old want `(y=7, clip_y=1, clip_h=3)` sits on the lower
  pane's border row. The paint result `(y=8, clip_y=2, clip_h=2)` is the
  inner window. `page_height` for stacked panes now uses that same window;
  the old lower-only composer drop matched paint only at 24 rows.
- test-state: FAILING on the pre-review baseline `208f7c9`, so not a
  regression from the simplification waves. `query_collision` fails —
  `state_demo.bend:68 query_collision_ok` feeds PRIVMSGs from `a` and
  `b`, then `:a!u@h NICK :B` collides case-insensitively with the
  existing `b`. It asserts six things at once (buffer count 2, active
  `server`, exact rendered text, one alert, unread level 2 for `"B"`,
  and the history extract `B\tSYS\t\ta is now known as B\n`).
  **This is a behavioural oracle, not a stale constant** — unlike the
  body-height fixtures it cannot be fixed by updating an expected
  number. Diagnose which of the six assertions fails first. Sits in the
  feed/target-normalization path, so re-check after any `_with`/`_cm`
  or casemapping refactor lands.
- test-state-review-identity: FAILING on the same baseline.
  `state_review_identity.bend:54` expects `CL.buf_texts(mode, 1n)` to
  contain `MODE #ab +o bob` — i.e. MODE must render the **canonical**
  channel name, not the wire alias the test feeds. Same caveat: a
  behavioural oracle in the target-normalization path, and there are
  four separate implementations of target normalization
  (`irc.bend:214-262`, `buffer.bend:57-82`, `isupport.bend:715-783`,
  `buffer.bend:1047-1073`). Consolidating those may fix or move this.
- test-media-view: FAILING on committed HEAD d286f90 (pre-existing).
  `new live message schedules got=[0] want=[1]`: a folded live
  PRIVMSG schedules no media job. Reproduced identically in the
  working tree and in a pristine /tmp/birc-proof-base checkout, so
  it is unrelated to the optimistic-send slice. Media-slice owner
  to triage.
- test-pty-m20-media-cache: FAILING, and **pre-existing** — verified at the
  pre-review baseline `208f7c9` on a quiet lane (`make
  test-pty-m20-media-cache` rc=2, identical assertion, identical line).
  `tests/pty/m20_media_cache.py:89` asserts
  `expected['a'] not in png_uploads(live.output)`: after the remote image
  cache evicts its oldest entry, that entry must be served without
  re-uploading, but it is uploaded instead. It is the **only** red target in
  `make test-pty` — every other PTY case is green (`link_click`, `launchers
  failed/absent/slow/slowquit`, `media kitty/iterm/pending_quit/
  unread_recovery`, `cycles=12/12`, `many_eof`). Not caused by the
  `src/media/_cache.py` extraction, which postdates the failure. Two traps for
  whoever picks it up: running the file directly (`python3
  tests/pty/m20_media_cache.py ./build/birc`) dies with `ImportError: cannot
  import name 'Protocol' from 'typing'`, because `tests/pty/typing.py` shadows
  the stdlib module via `sys.path[0]` — use the make target; and this is a
  behavioural oracle about cache eviction, so do not relax it.

## Resolved

Recorded here so the open items above stay the work list. These cleanups
were not performed.

- Do not delete `handover-recovery/`. It is tracked (220 files), so a
  gitignore line would not hide it. Deletion is the author's call.
- Do not prune `.muse/` worktrees. That is the author's call. `.muse/`
  is now ignored for untracked files.
