# birc backlog — findings awaiting a calm host or a fix slice

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
