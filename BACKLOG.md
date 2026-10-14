# birc backlog — findings awaiting a calm host or a fix slice

- Column-walker retention: direct-call rewrite APPLIED to
  `src/bend/columns.bend` (helpers kept, continuations replaced by fuel,
  `cluster_crlf_cut` match; zero lambdas remain). Pending calm host:
  `make test-columns-width`, `make test-ui-review-columns`, then the idle +
  15-channel census per `docs/column-walker-retention.md` (frozen bump,
  frozen CID_SCON, lambda task rows gone).
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
