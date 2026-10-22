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

- [x] **D3. A later MODE flag group still logs the channel key.**
  `mode_has_key` (`src/bend/irc_commands.bend:230`) looks only at
  parameters 0 and 1. The comment at `:227` says key arguments never
  enter logs or history. `feed_mode.params` (`src/bend/client.bend:822`)
  logs `Irc.msg_params(m)` when that check is false.
  `MODE #room +o alice +k secret` has `+o` in parameter 1, so the key
  stays in the channel buffer. `input_sensitive.mode_wire`
  (`src/bend/submit.bend:1720`) uses the same check, so the typed line
  stays recallable.
  Rectify: walk every flags parameter with `mode_key_tail`, and treat
  the line as keyed when any flags word has a following argument. Point
  the composer check at that walk. Keep the `[channel key hidden]`
  collapse.
  Add a case: `:alice!u@h MODE #room +o alice +k opaque-secret` does not
  store `opaque-secret`, and the same `/mode` line is not recallable.
  A `+k` in the first flags word stays hidden.

- [ ] **D4. A TLS write that wants a read is followed by SSL_read.**
  The comment at `src/ffi/tls_ffi.c:407` says `WANT_WRITE` forbids other
  TLS IO until that write finishes. The loop at `:409` retries only
  while `writer->want == POLLOUT`. `SSL_write` returning
  `SSL_ERROR_WANT_READ` sets `want` to `POLLIN`, the loop stops, and
  `:422` calls `SSL_read_ex` with the write unfinished. Reader and
  writer share one SSL object.
  Rectify: while the writer is unfinished, retry `birc_tls_write_step`
  for both `POLLIN` and `POLLOUT`. Park on the writer's `want` until
  that write finishes. Call `SSL_read_ex` only after the writer is
  finished or gone.
  Add a case: a verified write whose next `SSL_write` returns
  `SSL_ERROR_WANT_READ` must not call `SSL_read_ex` from the read step.
  After the write completes, the following plaintext read succeeds.

- [ ] **D5. Echo-message revert keeps one body and drops the rest.**
  `pend_restore_text` (`src/bend/session.bend:2186`) keeps
  `pend_restore.one(h)` and ignores the tail. `pend_draft` (`:2194`)
  writes that string only when the composer is empty. Timeout, failure,
  and autoreconnect all use this restore. A second unconfirmed body is
  not in the buffer (`PendSend` is overlay-only) and is not put back.
  Rectify: restore every reaped body, oldest first. An empty composer
  receives them. A non-empty composer stays, and the bodies are logged
  on the server buffer. Cap eviction uses the same restore. Do not add
  a Session or Buffer field.
  Add a case: echo-message, enter `one` then `two`, age both to the
  timeout with an empty composer. Both bodies remain recoverable. Today
  the draft is `two` and `one` is gone. A non-empty composer still
  shows the reaped bodies. The 33rd unconfirmed send still shows the
  evicted oldest body.

- [ ] **D6. An over-cap history retry cannot be admitted again.**
  `ws_history.on_fail.go` (`src/bend/wsnet.bend:1665`) prepends the
  failed blob onto the stored pending with no size check. The comment
  at `:1661` says the next admission retries it.
  `ws_history.write_chan.send` (`:1416`) answers
  `Some{"history queue full"}` and returns the same `hot`, so it never
  sends a pending that is already over the cap. Later saves take that
  arm, and the blob stays queued.
  Rectify: when the stored pending is already over cap, send that
  pending and clear it on accept. Keep the "history queue full" result
  only when the stored pending still fits and this growth would not.
  Do not add a field.
  Add a case: pending of 40000 bytes, then `on_fail` of a 40000-byte
  retry. The next `write_chan.send` into a channel with room returns
  no notice and leaves pending empty. Today the notice is
  `history queue full` and the pending length stays 80000.

- [x] **D7. A reused high preview slot skips free slots below it.**
  `src/ffi/timui_ffi.c:528` sets `preview_count = idx + 1` when an
  existing token is reused. A new token is stored only at
  `previews[preview_count]` (`:524`). Reusing slot 7 makes
  `preview_count` 8, so a free slot underneath is never chosen and the
  new token draws `image_placeholder_` (`:535`).
  Rectify: on a miss, use a slot whose token is 0. Do not raise
  `preview_count` past a hole. Keep the match that reuses one slot for
  a second `OpMedia` of the same token.
  Add a case: eight filled slots, slots 0–6 pruned, slot 7 still live.
  Paint slot 7, then one new token. The new token draws its image.
  Today it is a placeholder.

- [ ] **D8. Workspace card admission ignores live-tail pending rows.**
  `visible_candidates_cards_iso` (`src/bend/cards.bend:583`) walks
  history `newest` through `visible_anchored_panes_media_cards_iso`
  (`:580`). It does not take the pending prefix paint uses at
  `ScrollAt{0,0}`. `ws_cards.sized` schedules that list, so a pending
  row can push a history card out of the pane while the card is still
  fetched. `Cl.Pending` stays ineligible.
  Rectify: at `{0,0}` only, admit from the same newest-first list paint
  uses: that buffer's pending lines, then history `newest`. Leave
  scrolled windows on the history spine. Do not add a field.
  Add a case: one optimistic pending row in an 8-row live-tail pane
  pushes a history card URL out of the painted rows.
  `visible_candidates_cards_iso` still returns that URL. The pending-aware
  window does not. With an empty pending list, both return it.

- [x] **D9. apply_history with cap 0 deletes existing chat rows.**
  `apply_history.capped` (`src/bend/history.bend:529`) and the iso twin
  at `:537` call `apply_history.cap` when cap is 0.
  `take_last` (`src/bend/buffer.bend:1184`) drops `length - n` lines, so
  n = 0 drops every row, and `apply_history.cap` (`history.bend:525`)
  also replaces `now`. The file loader does the opposite:
  `read_prepare.mode` (`:710`) returns `cl` unchanged. Its comment at
  `:707` says cap 0 leaves the client unchanged.
  Rectify: the cap-0 arm of both `apply_history.capped` and
  `apply_history_iso.capped` returns `cl`. No trim, no reconnect
  marker, no `now` change.
  Add a case: a client with server text `keep`, passed to
  `apply_history` and `apply_history_iso` with cap 0, still shows
  `keep`, the same `log_seq`, and the same `now`. Today the buffer is
  empty and `now` is the restore clock.

- [x] **D10. An enabled /history search still logs the refusal Error.**
  `submit_history.search` (`src/bend/history_search.bend:1855`) echoes
  `live_only()` (`:1835`, "disk history search runs in the live
  session") when history is on, and returns no wire. The live key path
  then starts the search anyway: `step_keys.history_search_on`
  (`src/bend/session.bend:3679`) calls `history_search_begin` on that
  same session. The comment at `session.bend:579` still says search
  reports `live_only` until the live loop runs it. The loop runs it,
  and the Error stays.
  Rectify: on the history-on arm, do not append that Error. Leave the
  history-off echo "disk history is disabled".
  Add a case: default history, Enter `/history search needle`. The
  result command is `Search`, and the active buffer does not gain that
  Error. History off still echoes "disk history is disabled" and does
  not search.

- [x] **D11. An accepted Search command reseeds the composer.**
  `step_keys.stayed_enter` (`src/bend/session_drafts.bend:311`) clears
  the draft for `OpenUrl` and puts the typed line back on every other
  command (`:312`, `session_upload_draft(st2, typed, 1)`). `Search` is
  that other command. It is what `:3679` returns for an enabled
  `/history` search, and the active buffer does not change, so the
  composer shows the command again.
  Rectify: treat `Search` like `OpenUrl`: `after_submit_cm`, and do not
  reseed `typed`. Do not add a field.
  Add a case: history on, Enter `/history search needle` on an unchanged
  buffer. The composer and that buffer's draft are empty. History off
  stays a `Cont` plus the disabled Error and still keeps the typed
  command.

- [x] **D12. Upload open of a FIFO blocks before the regular-file check.**
  `birc_up_open` (`src/ffi/upload_ffi.c:441`) uses
  `O_RDONLY | O_NOFOLLOW | O_CLOEXEC` and only then rejects a
  non-regular file (`:444`). A FIFO `open` waits for a writer, so
  `S_ISREG` never runs and the upload deadline is not consulted. The
  CA open in this file already uses `O_NONBLOCK`.
  Rectify: add `O_NONBLOCK` to this open. A FIFO fails at once and the
  run returns the existing source error. Keep the `fstat` regular-file,
  size, and stamp checks.
  Add a case: `mkfifo` a path with no writer and call the upload run.
  It returns the source error without blocking.

- [x] **D13. Startup history read follows symlinks and can block in open.**
  `history_read_kept_call` (`src/ffi/history_ffi.c:979`) opens with
  `O_RDONLY | O_CLOEXEC` and then only rejects a negative or oversized
  `st_size` (`:992`). A FIFO blocks inside that `open`. A symlink is
  followed and its target is restored. `birc_history_append` opens with
  `O_NOFOLLOW | O_NONBLOCK` (`:75`) and rejects a non-regular file or a
  file not owned by the euid (`:82`). The search open already does the
  same (`src/ffi/history_search_ffi.c:129`). An empty startup client
  takes this reader: `history_snapshot_client.route`
  (`src/bend/history_io.bend:216`) calls `history_file.load`, and
  `HistoryLoaded` is sent only after that load returns
  (`src/bend/history_startup_io.bend:23`). `Begin`, the dial, is sent
  only from that completion (`src/bend/live_context.bend:266`).
  Rectify: open with `O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC`,
  then fail the load at stage 2 unless `fstat` shows a regular file
  owned by the euid. Keep the size check. A missing file stays stage 1.
  Add a case: `mkfifo` a path with no writer and call the kept reader.
  It returns stage 2 without blocking. A symlink to a regular history
  file also returns stage 2 and restores no rows. A regular file owned
  by the euid still restores.

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

- [x] **C14. The frame-entry comment says False is the only full wrap.**
  `src/bend/view.bend:4036` says "True means that walk was cropped;
  False is the only full wrap." `paint_view_split_rects.rest`
  (`view.bend:3904`) returns `flag_or(r1ok, r2ok)`. `flag_or`
  (`:2543`) is true when either pane cropped. The other pane can take
  the full painter while the returned Bool stays true.
  Say True means at least one pane cropped its walk, and False means
  every pane took the full painter. Leave `flag_or` and the painters
  alone.

- [ ] **C15. The cards comment says one worker per part.**
  `src/bend/wsnet.bend:959` says scheduling runs "with one worker per
  live part." `ws_cards.spawn_ok` (`:1227`) also requires
  `ws_clease.free(lease)`. The comment at `:1224` says a taken lease
  blocks every part until that worker is done.
  Say one global cards worker, gated by `ws_cards.spawn_ok`, with
  per-part sidecar state. Leave the lease and the spawn gate alone.

- [ ] **C16. The live-import comment names apply_history_iso.**
  `src/bend/history_startup.bend:266` says negotiated live imports use
  `History.apply_history_iso`. `history.merge`
  (`src/bend/live_context.bend:258`) calls `install_startup`.
  Say live merges go through `install_startup` and the default RFC1459
  map. Leave that call on `install_startup`.

- [x] **C17. The OpTabs comment still waits for colour fields.**
  `src/ffi/timui_ffi.c:1154` says mention colours belong in `f[8]` and
  `f[9]` once `OpTabs` grows. The next call (`:1157`) paints
  `BIRC_TAB_MENTION_BG` and `BIRC_TAB_MENTION_FG`. C13 already fixed
  the palette sentence at `:123`. This sentence is still the old story.
  Say the constants are the palette and `OpTabs` stays eight fields.
  Do not add colour words.

- [x] **C18. The casemap comment says the shared modules are untouched.**
  `src/bend/isupport.bend:53` says full `cm_eq` adoption in
  Client/Buffer lookup, roster compare, draft identity, and View
  completion still needs Client-carried state, and that those modules
  are intentionally untouched. Those paths already take a
  caller-supplied mapping.
  Say the caller supplies the mapping and Client does not store one.
  Do not add a Client field.

- [ ] **C19. The notify header still calls N9.3 a merge point.**
  `src/bend/notify.bend:28` says threading `Notify.State` through the
  live loop and default helper provisioning stay parent merge points.
  `ws_notify.done` (`src/bend/wsnet.bend:953`) already loads
  `T.Sys.notify_default()` and `NIO.program_or_default`.
  Say `ws_notify.fire` and `ws_notify.done` provision the platform
  helper and thread per-part notify state. Leave that wiring alone.

- [x] **C20. The search header says net.bend stores the import seed.**
  `src/bend/history_search.bend:17` says `net.bend` captures the
  Session import seed as the history checkpoint before live dispatch.
  `on_search.rest` (`src/bend/net.bend:1370`) matches
  `(_, +imported)` and drops that `Nat`.
  Say the completion loop discards the returned `log_seq` because a
  `*search*` import does not mint event ids. Leave the match alone.

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
