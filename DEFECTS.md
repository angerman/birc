# Defects to rectify

Open items from the 2026-10-22 architectural review of `5983696`
("Drop dead scroll helpers and keep the day-tag suffix.").
Line numbers are that tree. Re-read the citation before editing; these
files move.

Fix these in Bend. C may keep owning OpenSSL, file admission, and paint
of `List<DrawOp>`. Do not parse IRC in C. Do not add a Session, Buffer,
or WsLoop field. Do not add a persistent per-line wrap cache. Do not
unify `read_pace`. Do not rewrite `columns.bend` without a new census.
Do not paint a one-notch scroll neighborhood as the viewport.

Each item is one change. A comment fix does not change behavior. A
deletion removes an uncalled definition and the comment that names it.
Checked items stay in this file with the commit that closed them.
Closed in 95a32e0.

## Behavior

- [x] **D1. Live-tail admission is taller than the painted pane while a send is unconfirmed.**
  Paint at `ScrollAt{0,0}` spends viewport rows on optimistic sends.
  `paint_bottom.edge` (`src/bend/view.bend:2253`) prepends
  `rev_new(pending_for_buf(opt_pends(boxed), name), Nil{})` onto `newest`
  and `paint_recent_go` keeps `height` expanded rows, including day bars.
  `paint_body_buf.bottom` (`view.bend:2284`) uses that path for every
  non-`*preview*` live bottom.
  Scheduling does not. `session_observe_visible_media.gated`
  (`src/bend/session.bend:3313`) and `session_observe_visible_cards.gated`
  (`session.bend:3365`) call
  `visible_anchored_panes_media_cards_iso`, which crops
  `window_media_cards_iso` (`view.bend:2198`). That window is the history
  spine only. `session_accept_media_result` (`session.bend:3334`) uses the
  same iso candidates. The Session match already binds `pends`
  (`session.bend:3322`) and drops them.
  While those pending rows occupy the pane, the history row they push out
  is still inside the admission crop, so its image or card can be fetched.
  `ws_view_quiet` is false while any pending list is nonempty
  (`src/bend/wsnet.bend:2112`), so those frames rebuild this window.
  Scrolled paint uses `paint_bottom.away` (`view.bend:2264`) and does not
  overlay pending rows.
  The pending line itself must stay unscheduled. It is `Cl.Pending` with
  id 0 (`view.bend:1328`). `live_kind` rejects `Cl.Pending`
  (`src/bend/media.bend:831`). That policy stays.
  `session.bend:3356` says scheduling consumes the exact painted rows.
  That sentence is false on these frames. Card rows are already in both
  windows. Optimistic rows are only in the paint window.
  Rectify: on `ScrollAt{0,0}` only, build the admission window from the
  same newest-first list paint uses: pending lines for that buffer, then
  history `newest`. `viewport_end` at `{0,0}` keeps the last `height`
  rows (`view.bend:1592`), which is the set `paint_recent_go` keeps.
  Leave scrolled windows on the history spine. Leave `Cl.Pending`
  ineligible so the overlay occupies rows and its URLs stay unscheduled.
  Do not add a field. Add a Bend case: one pending row at the live tail
  pushes a history image out of an 8-row pane, paint omits that image,
  and admission does not enqueue it; with an empty pending list the same
  image is admitted.

- [x] **D2. The negotiated PING arm would emit a second PONG.**
  `fold_step.ping_at` (`src/bend/session.bend:131`) matches a PING and
  returns `FoldAcc{cl, pongs, now_ms}`. `fold_step.ping_at_with`
  (`session.bend:193`) conses `Irc.pong_for(h)` onto that list.
  Live PINGs do not hit the second arm today. `live_is_dynamic`
  (`session.bend:4017`) omits PING, so `live_split_step.ready_branch`
  (`session.bend:4132`) calls `live_step.registered` → `fold_step.got_at`
  → `fold_step.ping_at`. The reader owns the wire PONG
  (`src/bend/actor.bend:129`–`142`) and posts it ahead of the chunk.
  The comment at `session.bend:148` says the negotiated chain has
  identical ping handling. It does not.
  Rectify: the `True` arm of `ping_at_with` returns
  `FoldAcc{cl, pongs, now_ms}`, same as `ping_at`. Rewrite the sentence
  at `session.bend:148` to say both arms skip the feed and emit no PONG,
  and the reader owns the wire reply. Leave the reader path alone.
  Add a Bend case that a PING folded through `fold_step.got_at_with`
  appends no outbound line.

## Comments

Rewrite the comment. Leave the arithmetic and the control flow alone
unless the item says a dead arm goes with it.

- [x] **C1. Begin is described as a first-paint barrier. The live entry sends it before the loop.**
  `ws_start.live` (`src/bend/wsnet.bend:3768`) calls `ws_begin_all`, then
  `ws_begin(..., True{})` at `:3771`. Both direct and deferred startup
  enter the loop already begun. `ws_frame.begun_after` (`wsnet.bend:2400`)
  therefore takes the `True` arm and does not send another Begin.
  Stale text:
  - `wsnet.bend:2375` — "sent exactly once from the first paint" and
    "the direct policy never arms the barrier (begun starts true)".
  - `wsnet.bend:2391` — "the deferred Begin fires only after the frame's
    keys are applied, never before ws_act".
  - `wsnet.bend:239` — "begun tracks the deferred first-input Begin
    barrier (direct starts it)".
  Say `ws_start.live` sends one Begin per part after load, then starts
  the loop already begun, so the frame path must not send another.
  The `False` arm at `:2402` is how `ws_supported` would send Begin.
  That entry is Y1. After Y1 is gone, and a grep shows no test enters
  the loop with `begun=False`, delete the `False` arm. Until that grep,
  only the comments change.
  First-frame quit stays `ws_start.keyed` (`wsnet.bend:4005`), before
  boot. That part of the old story is still the product order: the first
  paint and its keys run before settings, archive load, and Begin.

- [x] **C2. Workspace history extract is not the raw pre-step client.**
  `ws_history_save.go` (`src/bend/wsnet.bend:1827`) sets the extract
  client with `ws_history.floor_cl` (`:1616`). When this part's queued
  hold is above `log_seq`, the diff starts at that raised sequence.
  A channel accept is not a failed save: `ws_history.hold_queued`
  (`:1545`) raises `hold` and leaves the live `log_seq` on the new
  client. The failure checkpoint is still `old_st` via `ws_history.kept`
  (`:1272`). The accurate sentence is already at `:1534`.
  Stale text:
  - `wsnet.bend:1258` — "The save baseline is the pre-step workspace
    client, exactly like the single-server loop." Single-server passes
    the pre-step client straight through (`src/bend/net.bend:1615`).
  - `wsnet.bend:1402` — "the extract baseline stays at `ckpt` until
    WsHistAck."
  Say the extract client is the pre-step client raised to this part's
  queued hold, and a channel accept moves that floor immediately.
  Do not change save bytes, the hold floor, or the rewind on append
  failure.

- [x] **C3. The actor header says the UI feeds and paints every PING.**
  `src/bend/actor.bend:96`: "The UI still frames, feeds, and paints every
  line, but never answers PING." The chunk still reaches the UI framer.
  `fold_step.ping_at` (`src/bend/session.bend:134`) returns the client
  unchanged, so the line never reaches `Feed.feed` and is not painted.
  The reader answers it (`actor.bend:129`).
  Say the UI framer still sees the line, the client feed skips it, and
  the reader owns the wire PONG. Land this with D2 so the two PING
  comments agree.

- [x] **C4. `paint_body_of` overstates who calls the full painter.**
  `src/bend/view.bend:2715`: "False is the only call to the full painter."
  The same claim sits on `paint_hold.opts` at `:2688` ("the False arm is
  the only full painter"), but that function's false arm returns `False`,
  not a paint.
  The miss arm of `paint_hold.use` (`view.bend:2713`) is the only full
  painter on the reuse path. `paint_body_buf` is also called from
  `body_of.buf_media` (`view.bend:2297`) and from
  `tests/bend/day_bar.bend` and `tests/bend/scroll_demo.bend`.
  Say a miss on this path calls `paint_body_buf`, and other painters call
  it directly.

- [x] **C5. A scroll-reuse miss does not drop the stored walk.**
  `src/bend/view.bend:2417`: "a miss paints the full window and drops
  them." `paint_hold.use` (`:2712`) full-paints and returns `False`.
  `view_model` (`:3805`) keeps the `ViewModel` and drops the row list
  from that paint. The labels cell is untouched. `tests/bend/scroll_reuse.bend`
  flips joins, nicks, mutes, server, and theme after the walk is stored
  and still reads that walk.
  `view.bend:2747`: "hold_buf drops it." `hold_buf` (`:2435`) returns the
  buffer field. `scroll_active_put` (`:3548`) installs that buffer and
  returns `hold <> Nil{}`. Callers that keep only `hold_buf`'s result
  discard the walk.
  Say a miss full-paints and leaves the stored hold unchanged, and
  `hold_buf` only projects the buffer.

- [x] **C6. Pending-row overlay comments name the wrong bottom.**
  `src/bend/view.bend:2256`: "Live and non-live bottoms both overlay
  local pends via edge." `paint_bottom.live` (`:2258`) always calls
  `edge` and has no live flag. The only non-live name is `*preview*`
  (`spine_live`, `view.bend:1957`). `paint_body_buf.bottom` sends that
  name through `paint_display_lines` (`:2282`), which appends pending
  lines oldest-first. `paint_preview_row` (`:2245`) runs only when the
  painted row count is still short of `height` and the name is
  `*preview*`. Nothing calls `paint_bottom` (`:2269`); live callers use
  `.live` and `.away`.
  The comment at `:1955` is the one that matches: pending sends overlay
  at the live bottom through `paint_bottom.edge`, and only `*preview*`
  leaves the scroll spine.
  Say live bottoms overlay through `edge`, and `*preview*` bottoms
  overlay through `paint_display_lines`. Delete `paint_bottom` with Y3
  and point `:2408`'s sibling notes at the functions that remain.
  `view.bend:1328` (id 0 stays out of admission) stays, and D1 must keep
  that policy.

- [x] **C7. Live admission is the iso walker, not the cm walker.**
  Stale text:
  - `src/bend/view.bend:3526` — "Bottom and scrolled paths share
    `window_media_cards_cm`." `visible_media_cards.from_rows` (`:3529`)
    calls `visible_media.rows` only.
  - `view.bend:3544` — "callers already hold
    `visible_anchored_panes_media_cards_cm`." Session passes iso rows
    into `visible_media_candidates_from_rows`.
  - `src/bend/cards.bend:561` — "the same cm-aware anchored owner the
    live paint path uses (`V.visible_anchored_panes_media_cards_cm`)."
  - `src/bend/net.bend:404` — sidecar paint uses "the same `_cm` row
    set the scheduler uses." `paint_base.body` (`net.bend:188`) calls
    `view_draft.state_typing_media_cards_iso_themed`.
    `wsnet.bend:1940` calls `C.visible_candidates_cards_iso`.
  Production observe is `visible_anchored_panes_media_cards_iso`
  (`session.bend:3313`, `:3365`).
  Point these sentences at the iso owner. Keep the cm walker.
  `visible_candidates` (`cards.bend:593`) and `LAWS.bend` still call it.
  `visible_media_candidates_cards_cm` (`view.bend:3538`) has no caller
  outside its definition; Y3 deletes that wrapper, not
  `window_media_cards_cm` (`view.bend:2195`).

- [x] **C8. `split.body_box_h` is not the lay body box, and the subtracted rows are not the border.**
  `src/bend/split.bend:68`: "The full body box is rows-2 on normal
  terminals (tabs plus the box border)."
  `view.lay` builds the body box as `rows-1` for `rows>1`
  (`src/bend/view.bend:2924`, `:2973`). The status row is off-screen
  (`status_y` returns `rows`, height 0). `screen_body_h`
  (`split.bend:89`) is that box. `body_box_h` (`split.bend:76`) returns
  `rows-2` for `rows>=4`, which is `hist_h(screen_body_h)`: the tab and
  the composer are gone, and the border is still inside. `inner_extent`
  drops the border. For the heights this client paints, including 12,
  24, and side-by-side `page_height` (`split.bend:115`),
  `inner_extent(body_box_h(rows))` equals `rect_vis_h` of that single
  pane. `page_height_ok` stays 20 at 24 rows.
  Say `body_box_h` is the history rect before the border, and it is the
  height `page_height` feeds to `inner_extent`. Leave the arithmetic.
  The 12×60 Off golden stays height 8 and width 40.

- [x] **C9. `visible_bottom` does not match `paint_recent`'s row budget.**
  `src/bend/view.bend:3425`: "Stop once the viewport rows are filled,
  matching paint_recent." `visible_bottom.more` (`:3430`) charges
  `paint_body_rows` only. `paint_recent_more` (`:1916`) also charges
  `day_rows_visible`. A day bar fills a paint row and can drop the next
  history line from this walker.
  The walker is reached from `visible_media.spine` /
  `visible_media_candidates` (`view.bend:3479`, `:3523`). Those have
  tests (`tests/bend/media_history.bend`, `tests/bend/g3_traversal.bend`)
  and no `src/` caller. Production admission is the cards window in D1,
  which does charge day bars.
  Say this walker counts wrapped body rows and leaves day bars
  uncharged. Leave the walker. Do not retarget production admission onto
  it.

- [x] **C10. `history.merge` no longer takes two endpoint strings.**
  `src/bend/live_context.bend:256`: "Callers must not pass the same
  string twice for both arguments." `history.merge` (`:257`) takes
  `snapshot_ep` only. `current_ep` is derived from the session at `:258`.
  The line above ("current_ep from Session; snapshot_ep is the archive
  claim") is still true. Delete the second sentence.

- [x] **C11. Preferences load is not a shared queue.**
  `src/bend/wsnet.bend:3488`: "the shared queue keeps the first prepared
  context". Each part calls `Headless.prepare` on its own fiber
  (`ws_load.part`, `:3482`). `ws_load.keep2` (`:3495`) plus the slot-order
  fold (`:3816`) keeps the lowest slot's context. The fail-closed `known`
  conjunction is real.
  Say the slot-order join keeps the lowest slot's prepared context.
  `:3773` already says the join applies parts in slot order.

- [x] **C12. Workspace and cards headers still say the integrator has not wired them.**
  `src/bend/workspace.bend:7` — "FROZEN at parent HEAD". `:556` — "Pure
  demux checks for the (future, IO-side) actor fan-out." `wsnet.bend`
  calls `W.live_step_keys`, `W.live_on_msg`, and `W.writer_done_acked`.
  `:47` is still true: this file does not own Net/Actor IO.
  `:27` — "v6 refines at dial-plan time by the integrator." `:47` still
  lists native `Af/inet6` sockets and DNS as unwired. `actor.bend:1103`
  and `:1198` call `Dns.dial_dual`. Bracketed endpoints still fail in
  `Endpoint.parse` (`src/bend/endpoint.bend:2`). IPv6 literals stay
  unsupported on the IRC endpoint. That is the product rule.
  `src/bend/dns.bend:13` and `:633`, and `src/bend/dns_query.bend:6`,
  still say the integrator wires `dial_begin` to `dial_dual`. Delete
  those integrator sentences. `dns.bend:6` ("Brackets stay at
  `parse_any`") can say bracketed IRC endpoints are rejected by
  `Endpoint.parse` before connect; `ipv6.parse_any` remains the parser
  that accepts `[::1]:port` for the non-IRC tests.
  `src/bend/dns_wire.bend:70` — "IPv4-only resolver." The next sentence
  is the real contract: `is_ipv6` refuses to query a colon string.
  Names take AAAA in `dns.bend` before A. Drop "IPv4-only"; keep the
  colon-reject sentence. The first nameserver read stays IPv4.
  `src/bend/session_cards.bend:35` — the net loop wiring is "out of
  scope", and `:8` freezes `cards.py` as the product signature.
  `net.bend:1319` calls `CN.cards_stage_session`. `net.bend:1405` calls
  `CN.on_card_session`. The default helper is native. Drop the
  unwired-loop sentence and the `cards.py` product-signature sentence.
  `open_full` / `close_full` key bindings are still laws and
  `tests/bend` only; that sentence can stay if a grep still shows no
  product caller.
  `src/ffi/dns_ffi.c:238` says callers strip `parse_any` brackets first.
  IRC connect does not pass brackets. Make that comment match whichever
  caller still reaches the FFI, after reading it. Do not teach the FFI
  to accept bracketed text.

- [x] **C13. Mention colours are the C constants. The Bend palette functions are unused.**
  `src/ffi/timui_ffi.c:123` says `Theme.tab_mention_bg` / `tab_mention_fg`
  own the palette and paint still passes constants because `OpTabs` lacks
  the words. `tab_mention_bg` and `tab_mention_fg` (`src/bend/theme.bend:186`,
  `:192`) have no caller. The constants in that C file are the palette.
  Activity stays reverse video.
  Say the constants are the palette. Delete the two Bend functions with
  Y4. Do not add `OpTabs` fields.

## Dead code

No caller outside the definition, including `tests/` and `LAWS.bend`,
unless the item says otherwise. Deleting these does not add a `src/`
file, so the concern table in `Agents.md` stays. Do not delete a cm
walker that `visible_candidates`, a test, or a law still calls.

- [x] **Y1. Uncalled tty startup that skips the load and Begin.**
  `src/bend/wsnet.bend:3561` `ws_watch.win`, `:3573` `ws_open.tty`,
  `:3580` `ws_supported`. Nothing calls `ws_supported`. `run_ws` enters
  through `ws_start` → `ws_start.prepared`. The dead chain opens a tty
  and calls `ws_begin` with the caller's `begun`, with no first-frame
  load and no `ws_begin_all`.
  Delete the three functions. Leave `ws_begin`. `ws_start.live` calls it.
  Then apply the C1 grep before deleting `ws_frame.begun_after`'s
  `False` arm.

- [x] **Y2. Uncalled net paint and notify wrappers.**
  - `src/bend/net.bend:239` `paint_go.hot_base.warm`. Both the `Nil` and
    `Con` arms call the same `paint_overlay`. `:246` `paint_go.hot_base`
    only calls that warm function. `:279` `paint_go.hot_out` is only its
    definition. Live warm/cold is `paint_go.hot_use.warm` (`:365`), which
    ignores the hold, and `.cold` (`:366`), which passes it.
  - `net.bend:391` `paint_go`. Live entries are `paint_go.hint` and
    `paint_go.hot`. `paint_session` (`:400`) is live (`wsnet.bend:3706`,
    `:3945`, and the headless paints in `net.bend`). Leave it.
  - `net.bend:413` `paint_session_cards`. `wsnet` uses `.hot`. `.hint`
    is the real hint entry. Leave both of those.
  - `net.bend:39` `net_notify_init`, `net_notify_observe`,
    `net_notify_complete`, `net_notify_seed_postrestore`. One-line
    aliases. `wsnet.bend:629` calls `Sess.notify_live_init_ep` directly.

- [x] **Y3. Uncalled view and cards wrappers.**
  - `src/bend/view.bend:2393` `shift_anchor_of`. The live call is
    `shift_anchor_of.after` at `:2492`. `:2408` names the dead wrapper.
    Point that comment at `.after`.
  - `view.bend:2347` `shift_at_top` and `:2350` `shift_at_bottom`.
    `:2373` already says top-snap does not branch on `shift_at_top`.
    Leave `shift_at_top.go` only if something still calls it after
    `shift_at_top` is gone; today only `shift_at_top` calls it.
  - `view.bend:2269` `paint_bottom`. Painters call `paint_bottom.live`
    and `.away`. Pair with C6.
  - `view.bend:1389` `day_bar_row` and `:1475` `anchor_reached`. Live
    zero-source detection is `recon_row` (`:1395`). The live anchor is
    `AnchorBest`. `:1482` already rejects the first-match `rt<=wt` rule
    that `anchor_reached` implements.
  - `view.bend:3128` `composer_ops`. The frame calls `paint_composer`
    (`:3749`). `:3073` still calls `composer_ops` the `body_ys_case`
    oracle. Delete the function and that sentence.
    `tests/bend/theme_ws_render.bend:313` mentions the name in a comment;
    update the comment if it claims the function runs.
  - `view.bend:3707` `paint_view_kept.go` returns `ops` on both arms.
    `:3716` (the cheat-sheet row is gone) is accurate. Drop the `empty`
    match and the unused `sr` / `st` arguments on `paint_view_kept`.
  - `view.bend:3532` `visible_media_cards.buffer_cm` and `:3538`
    `visible_media_candidates_cards_cm`. `visible_media_cards.panes_cm`
    (`:3535`) is called only from `:3539`. Delete those three. Keep
    `window_media_cards_cm` (`:2195`). The cards cm chain still uses the
    anchored cm owner.
  - `src/bend/cards.bend:554` `visible_crop`, `:577`
    `visible_buffer_cards_iso`, `:587` `visible_buffer`, `:590`
    `visible_panes`. `visible_candidates` (`:593`) has callers. Delete
    the four. Keep `visible_candidates` and the cm/iso functions it and
    session call.
  - `src/bend/session.bend:3037` `nav_focus.drop`. `Nil` and `Con` both
    call `nav_focus.pair`, which returns `hold_nil()`. The caller is
    `nav_focus.go` (`:3045`). Call `nav_focus.pair` from there.

- [x] **Y4. Unused mention-palette functions.**
  Delete `tab_mention_bg` and `tab_mention_fg` with C13. Do not add
  `OpTabs` words.

## Settled, leave them

These came up in the same review and are not open defects.

- Day-tag `CoverRest` filters each taken line once, includes the visible
  line that exhausts the budget (`view.bend:1798`), and seeds
  `older_day.scan` from `rest` (`view.bend:1836`). The "no second
  reverse" note inside `day_tag.go` (`:1821`) describes that function.
- Scroll reuse: a covered page crops in `paint_body_of`. Live `{0,0}`
  and a one-notch walk stay uncovered and paint through `paint_body_buf`.
  Joins, nicks, mutes, server, and the media box miss. The walk stays in
  the existing labels cell. Enter and focus store an empty walk. Dial
  and autoreconnect drop it.
- `live_step.next.keep` does not take the previous client
  (`net.bend:1570`). `fold` computes the repaint bit and `log_seq` before
  the append (`:1567`). `save` still names both clients until it calls
  `keep`. That is the split. It is not a measured RSS win.
- Two `read_pace.step` definitions, `history.bend` and `replay.bend`.
  No third caller. `read_chunk` and `ws_start.loaded` / `l1`–`l4` are
  gone. `ws_start.boot_dial_equivalent` stays.
- `columns.bend` matches the TimUI cluster, width, RI, ZWJ, and VS16
  rules checked in this review. `Bool.pick` there stays until a new census.
- `List.drop` to the anchor inside `window_anchored` (`view.bend:2188`)
  stays. A finger would be a new Buffer field.
- `endpoint.bend` rejects IPv6 literals. `Dns.dial_dual` is already what
  `dial_begin` calls for names. Do not treat either as unfinished work.
- `*preview*` is the only name that leaves the live scroll spine.
- History append, replay's fail-closed early EOF, the first paint before
  settings, and one generation-scoped Begin after that load match their
  current product comments aside from the items above.
- `paint_view_single` / `paint_view_split` call `paint_body_of`. A miss
  there is a full paint of the same buffer, not a wrong buffer.
