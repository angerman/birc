# birc backlog — findings awaiting a calm host or a fix slice

- media_history C-backend arity: FIXED — the 66-statement main holding
  ~10 live Sessions breached the 247-word native continuation limit
  ("an arity over 247"). Main is split into phase defs holding only
  boxed Sessions (SBox singleton-list cells, session_drafts_demo
  idiom); assertions unchanged, in the same order. Native C build
  plus `media_history=ok` verified, JS gate stays green.
- Column-walker retention: phase-machine rewrite in `src/bend/columns.bend`
  (UNCOMMITTED; the committed 0066b43 does not compile — mutual recursion).
  Harnesses pass on darwin-4: `columns_width=ok`, `ui_review_columns=ok`,
  parity ok. Pending: commit, then the idle + 15-channel census per
  `docs/column-walker-retention.md` (frozen bump, frozen CID_SCON, lambda
  task rows gone). Census scripts alive in /tmp; app codegen + inject next.
- wf-composer split prefix: FIXED in `src/bend/view.bend`
  (`split_composer_rect` mirrors the C bottom-most/left-most chooser; both
  split call sites converted, single-pane untouched). Pending calm host:
  `make build-ui` + split-mode PTY gate. Known unpinned edge: degenerate
  1-2 col panes (single-pane has the same divergence; no test pins it).
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
