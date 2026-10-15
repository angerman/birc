# birc backlog — findings awaiting a calm host or a fix slice

- media_history C-backend arity: FIXED — the 66-statement main holding
  ~10 live Sessions breached the 247-word native continuation limit
  ("an arity over 247"). Main is split into phase defs holding only
  boxed Sessions (SBox singleton-list cells, session_drafts_demo
  idiom); assertions unchanged, in the same order. Native C build
  plus `media_history=ok` verified, JS gate stays green.
- Column-walker retention: phase machines LANDED (a1aa3e6) and the
  post-fix census is DONE (see "Post-fix census — 2026-10-15" in
  `docs/column-walker-retention.md`): bump frozen both runs (1033/9193),
  zero COLUMNS task rows in all dumps, channels CID_SCON flat. Watch
  item (not a rejection): idle CID_SCON still creeps inside frozen
  pages — needs a longer soak or instrumented probe to attribute.
- wf-composer split prefix: FIXED in `src/bend/view.bend`, and the new
  `test-pty-split-composer` gate is GREEN (`split_composer=ok`; pins
  survival + resize-back recovery + Escape-quit at 24x4 and the
  /quit-alive boundary at 24x10). Deliberately NOT pinned: exact
  degenerate prefix bytes (would bake in Bend/C disagreement). OPEN
  src decision: unify Bend inner-width/prefix emission with the C
  chooser skip rule (same class as the tinyquit 1-2col single-pane
  failure).
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
