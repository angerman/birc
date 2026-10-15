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
- wf-composer: `src/ffi/timui_ffi.c` full compile unverified (needs Bend FFI
  headers from the Nix shell; host saturated). Static check so far:
  `draw_composer` def + sole caller arities match; patched regions are
  body-local. Run `make build-ui` when calm.
- wf-cards URL dedup: all-empty cards now yield zero rows; title-empty but
  desc-bearing cards still echo the URL as the card title line. Confirm the
  partial-metadata echo is the wanted look (item 3 screenshot was the
  no-metadata case, now fixed).
- test-auth-privacy: FIXED — root cause was `hist_after_typed` judging
  only per-line fragments, so a credential verb fractured across a line
  break (`IDEN\rTIFY`) read benign. It now also judges the joined whole
  and fails closed. `auth_privacy=ok` verified (calm-host batch).
  Watch item: `build/birc` -O2 link (~280 s) and the `auth_privacy`
  Bend build (~180 s) sit at their `timeout` edges under host load;
  consider a timeout bump or calm-host pinning.
