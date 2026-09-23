# birc — Bend migration checklist

Goal: move as much of the IRC client as possible into Bend 2. End state:
**Bend owns `main`, protocol, client state, networking, and the frame loop**;
C is only thin TimUI FFI.
Plaintext IRC only. No ncurses. Laws stay green.

Current split (approx):

| Location | Role |
|---|---|
| `src/bend/**/*.bend` | Protocol, client, submit, framer, net, view, `main` |
| `src/ffi/timui_ffi.c` | Thin `Timui.open` / `frame` / `close` / `events` (+ TimUI impl) |
| `src/ffi/dns_ffi.c` | UDP `recv_octets` (A rdata is not a String) |
| `src/ui/timui.h` | Vendored header only |
| ~~`birc.c` / `irc_proto.h`~~ | **Deleted** |

---

## Principles (do not skip)

- [x] **P0** Pure first: every Bend move lands as pure functions + golden tests before any FFI.
- [x] **P1** One live parser: C no longer parses IRC; `irc_proto.h` deleted.
- [x] **P2** Laws before cutover: extend `LAWS.bend` / `PROOF.bend` for each pure module; `make proof` stays green.
- [x] **P3** Fail closed: Makefile targets that are not ready exit nonzero (`BLOCKED:`), never pretend.
- [x] **P4** Handles stay opaque: TimUI / sockets are Bend handles or foreign handles — never stuff pointers into `U32`/`Nat`.
- [x] **P5** Shutdown order: actor `Socket.close`, then `Chan.close(cmd)`, drain Eof, `Timui.close`. Do not `Chan.close(evt)` — a recv after close deadlocks.
- [x] **P6** Live path uses Base `TCP.send` (String) and `recv_octets` + `Fr.push`. Lines are UTF-8, Latin-1 if invalid.
- [x] **P7** Fuel for open loops: UI/net loops take `Nat` fuel (`--frames`; `frames=0` live is `@unsafe` idle).

---

## Milestone 0 — Inventory & contracts

- [x] **M0.1**–**M0.6** Documented; `docs/FFI.md`; TimUI hello spike; `make ffi-smoke`.

**Exit:** `make ffi-smoke` PASS; FFI.md reviewed.

---

## Milestone 1 — Client state in Bend (pure)

- [x] **M1.1**–**M1.6** `client.bend` + `feed` + `tests/bend/feed_demo.bend`
- [x] **M1.7** Laws: feed empty identity; PING nbuf unchanged (scroll cap via `SCROLL_CAP` take_last)
- [x] **M1.8** Parallelize pure work: `view` uses `h t = …` / `b n = …` (Bend parallel bind)

**Exit:** `make test-feed` + `make proof` PASS.

---

## Milestone 2 — Submit + outbound formatting in Bend (pure)

- [x] **M2.1**–**M2.6** `submit.bend` + `tests/bend/submit_demo.bend`
- [x] **M2.7** Laws: `submit_ok` / empty submit

**Exit:** `make test-submit` + proof PASS.

---

## Milestone 3 — Delete the C protocol twin

- [x] **M3.3** / **M3.4** Deleted `irc_proto.h` and `birc.c` (Bend UI path).
- [x] **M3.1**–**M3.2** Fixture corpus (`fixtures/*.irc`) + `make proto-parity` (Bend golden tags; C twin gone)

---

## Milestone 4 — Networking in Bend

- [x] **M4.1** CRLF framer in Bend (`frame.bend`)
- [x] **M4.2** Laws: roundtrip; overlong drop in framer
- [x] **M4.3** Registration lines + JOIN (`net.register`)
- [x] **M4.4** Live send/recv via Base `TCP.send` / `TCP.recv` (no `tcp_*.c`)
- [x] **M4.5** PONG via `Irc.pong_for` in the fuel loop
- [x] **M4.6** `IO.spawn` net actor + `Chan(NetEvt)` / `Chan(NetCmd)` event loop with `Timui.frame`
- [x] **M4.7** `make test-net` loopback goldens
- [x] **M4.8** `make run HOST=…` connects (plaintext)
- [x] **M4.9** Reconnect / backoff: dropped (no reconnect loop; unused `next_backoff` / `backoff_double` law removed)

**Exit:** `make test-net` + live connect path.

---

## Milestone 5 — View model + TimUI draw FFI

- [x] **M5.1**–**M5.2** `view.bend` ViewModel + scroll math / bounds law
- [x] **M5.3** Rich-text tokenization: `TextSpan` Plain/Bold on `*…*` (`tokenize` / `show_spans`)
- [x] **M5.4** Coarse draw: whole layout painted inside one `Timui.frame` (D1)
- [x] **M5.5** Quit path: `UiKeys.quit` / `/quit` halt via `step_keys` (no separate `Timui.events` IO)
- [x] **M5.6** Frame keys as Data: `Timui.frame` returns `Ui & UiKeys` (same shape as `Window.frame`: handle beside Data). Bend unpacks in a helper (`with_tick.got`). Quit is `UiKeys.quit`, not a second latch IO. Fine-grained `begin`/`draw`/`end` is optional later (D1 still one begin/draw/end in C). The old note that Bend cannot unpack a handle & product was wrong — Base already does `Window & Image & List<Event>`. Do **not** wrap the pair in `Result` (handle stays beside `Result`, never inside).
- [x] **M5.7**–**M5.9** `--demo` in Bend; `make test-ui` uses Bend binary; C feed/submit deleted

---

## Milestone 6 — Main loop in Bend (FFI into TimUI)

- [x] **M6.1** / **M6.4** `app.bend` main; `bend src/bend/app.bend` → `build/birc`
- [x] **M6.2** / **M6.5** / **M6.6** Fuel via `--frames`; `TIMUI_IMPLEMENTATION` once; `-pthread -Isrc/ui`
- [x] **M6.3** Argv `--demo`/`--frames`/`--connect` via Bend `IO.args` (`src/bend/args.bend`)
- [x] **M6.7** Live connect path (`Net.run_live` + `App.is_demo` / host/port/nick/channel)
- [x] **M6.8** Thin FFI: `Timui.open` / `Timui.frame` / `Timui.close` — Bend owns iteration
- [x] **M6.9** / **M6.10** C `main` removed; README/AGENTS updated

**Exit:** `make check` green; Bend fuel loop; no C outer frame while-loop.

---

## Milestone 7 — Hardening & proofs

- [x] **M7.1** LAWS for feed/submit/framer/view scroll (+ parse/pong)
- [x] **M7.2** Adversarial: `Fr.overlong_drop_ok` + `Cl.flood_buffers_capped` (+ `fixtures/adversarial.irc`)
- [ ] **M7.3**–**M7.6** Sanitizers / perf / broader adversarial corpus — **deferred** (out of scope for migration cutover; laws+fixtures cover the critical caps)

---

## Milestone 8 — TimUI example parity (idiomatic Bend)

Reference: `timui.h/examples/irc.c` (and `draw_rich` / tabs / composer in that file).
Goal: the **same user-visible client**, implemented as **pure Bend + thin TimUI FFI**.
Do **not** port the C model, worker thread, or `irc_submit` into C. Do **not** put `Socket` on a `Chan`. Do **not** `@unsafe` parsers, `feed`, or `push_text`.

**D6 (new):** drop the coarse body `String`. The example paints per line (kind colour, timestamp, rich spans, OSC 8). A single `body: String` cannot do that. Target view model:

```
type Span is Data: Plain{…} / Bold{…} / Italic{…} / Code{…} / Link{url, text}
type BodyLine is Data: BodyLine{kind: LineKind, ts: String, spans: List Span}
type ViewModel is Data: header, tabs: List Tab, body: List BodyLine, nicks, status, …
```

C `Timui.frame` becomes an interpreter of that Data (still one begin/draw/end). Laws stay on the Bend types.

TDD for every item: red golden (`−`) + correct golden (`+`) in `tests/bend/*` (and a law when the claim is a tiny equality). `make check` is the gate. Never weaken laws.

Order: **pure view/client first**, then FFI draw, then keys that only latch what Bend already understands.

---

### M8.0 — Contracts (do first, one PR)

- [x] **M8.0.1** Freeze `BodyLine` / `Span` / `Tab{name, active}` in `view.bend`. Live paint is the packed wire (one representation).
- [x] **M8.0.2** Law: `visible_lines` on `List BodyLine` is oldest→newest, bottom-aligned when `count < height` (already true for `Line`; keep it).
- [x] **M8.0.3** FFI sketch (no behaviour yet): `Timui.frame` takes structured fields **or** a packed `List` of draw ops. Decide one packing (nested tuples / parallel `List`s). Document in `docs/FFI.md`. **Do not** send IRC kinds as C enums — send Bend `LineKind` as a `U32` tag the FFI already knows (`0=Msg … 5=Error`), with a law that the tag table is 1-1 with `LineKind`.
- [x] **M8.0.4** Keep `kind_tag` **out** of the user body (already dropped). Chrome is colour + timestamp, never `S:`/`Y:`.

**Exit:** `make proof` green; live path still works with a temporary “join spans as one string” shim if the new FFI is not ready.

---

### M8.1 — Line chrome (pure)

The C example: `HH:MM:SS` dim + kind colour + `draw_rich`.

- [x] **M8.1.1 Timestamps (pure).** `Line` gains `ts: String` (`""` in tests is fine). Live fill via `IO.now` (or a small `Clock.hhmmss` foreign) **only at `buf_log`**, so `feed` stays pure if the clock is an argument. Prefer: `buf_log(b, kind, ts, text)` and pass `""` from goldens, real `ts` from the IO layer. Law: `feed` with `ts=""` still matches current goldens.
- [x] **M8.1.2 Kind → style (pure table).** `style_of(kind) -> U32` (fg). Msg=text, Self=success, System=dim, Action=purple `0xC792EA`, Notice=blue `0x82AAFF`, Error=orange `0xF78C6C`. Law: six 1-1 cases, no default-swallow.
- [x] **M8.1.3 FFI paints `ts` dim, then spans in `style_of(kind)`.** Newest at the bottom of the body rect (already padded). Golden: demo transcript shows a timestamp column width of 8 (`HH:MM:SS` + space) in the layout math.

**Exit:** `make test-feed` still green; a view golden that `style_of(Self{}) != style_of(Msg{})`.

---

### M8.2 — Rich text (pure tokenize → FFI draw)

C `draw_rich`: `*bold*` `_italic_` `` `code` ``, `http://` / `https://` as OSC 8, UTF-8 width per glyph.

- [x] **M8.2.1 Extend `TextSpan`:** `Italic`, `Code`, `Link{url, text}`. Keep `Plain`/`Bold`. Tokenizer is fuel-first, no `match f(x)`. Unclosed delimiter → `Plain` including the opener (already the Bold rule).
- [x] **M8.2.2 Goldens (`view` / `feed_demo`):**
  - `hello *bold* text` → has `Bold`
  - `_em_` → `Italic`
  - `` `code` `` → `Code`
  - `see https://timui.dev x` → one `Link` with url=`https://timui.dev`
  - unclosed `*foo` stays plain
  - nested / interleaved: last-delimiter-wins or documented non-nesting (match C: toggles, LTR, no nest)
- [x] **M8.2.3 Law `tokenize_has_bold` stays.** Add `tokenize_has_link` / `tokenize_roundtrip` only if roundtrip is still defined (links may not roundtrip to the same source — **do not** invent a lossy `==` law).
- [x] **M8.2.4 FFI `draw_rich`:** walk spans; `timui_label` for text; `timui_label_hyperlink` for `Link`; bold/italic/dim attrs. Wide runes: `timui_utf8_width`. **C does not tokenize.**
- [x] **M8.2.5 Stop flattening Bold back to `*…*` in the live path** (`show_spans` may remain for tests).

**Exit:** demo line `morning — *bold* and \`code\` render` plus a URL render in `--demo`; `make test-feed` asserts spans, not paint pixels.

---

### M8.3 — Layout chrome (FFI interpreter of Bend layout)

C: `timui_split_v` header/tabs/body/composer; `split_h` scrollback|nicks; rounded `timui_border`; topic in the body title; nick table.

- [x] **M8.3.1 Header string from Bend:** `nick@server · bufname · state` where `state` is a Bend `NetState` (`Demo{}` / `Connecting{}` / `Online{}` / `Offline{}`) stored on `Session` (Data). Law: demo path is `Demo{}`; after `Ready{}` boot it is `Online{}`.
- [x] **M8.3.2 Tabs as `List Tab`.** FFI calls `timui_tabs` with names + `active` index. Click updates `active` (see M8.4). Bend remains source of truth: FFI returns the widget’s selected index; `step_keys` / a new `step_ui` applies `set_active`.
- [x] **M8.3.3 Body panel:** `timui_border` rounded; title `name — topic` (channel) or `name`. Fill panel slot, not default-empty cells (already filling root).
- [x] **M8.3.4 Nick list:** Bend already has `nicks: List String`. FFI: `timui_table_ex_mut` or a simple column of labels. Channels only; query/server show an empty “nicks” panel. Golden: 353 fills nicks; `nicks_of` length law already covered by `names_1459` — keep it.
- [x] **M8.3.5 Composer chrome:** rounded border; hint line from Bend (`/connect /join /part /msg /nick /me /quit · ↑↓ history · Shift+←/→`). Prompt glyph in FFI. Keep `timui_input_field` (edit stream), not last-key-wins.
- [x] **M8.3.6 Theme:** `TIMUI_THEME_MODERN_DARK` (example) **or** keep DOS_BLUE but take **all** colours from `timui_theme_style` slots (TEXT, TEXT_DIM, SUCCESS, WARNING, PANEL, STATUS). No more hardcoded `0x59ee3f` except the kind table in M8.1.2.

**Exit:** `--demo --frames 3` still `birc=ok`; layout uses widgets; no `S:` tags; no `lines=scroll=h=`.

---

### M8.4 — Navigation (keys as Data, Bend applies)

C: click tabs; Shift+←/→; PgUp/PgDn; mouse wheel; snap scroll to 0 on send.

- [x] **M8.4.1 `UiCmd` Data:** `Noop{}` / `TabNext{}` / `TabPrev{}` / `TabSet{i}` / `ScrollBy{n}` / `HistPrev{}` / `HistNext{}` / `Submit{}` / `Quit{}`. FFI returns **one `UiKeys` product per `Timui.frame`**. Prefer a small product of counters (`tab: U32`, two scroll `U32`s, `hist: U32`) over a C-side state machine.
- [x] **M8.4.2 Tabs:** Shift+Left/Right already cycles (`cycle_tab`, law `cycle_tab`). Wire **click** from `timui_tabs` selected index → `TabSet`. Law: `cycle_tab` wrap already exists; add `set_active` clamp `i < nbuf`.
- [x] **M8.4.3 Scroll:** `Buffer.scroll` already exists. Latch `TIMUI_KEY_PAGE_UP/DOWN` and `timui_mouse_wheel` as `scroll_delta`. Bend: `clamp_scroll`. Enable `TIMUI_FLAG_MOUSE` on open. Goldens: `scroll_bounds_ok` stays; add `scroll_page_ok(height)` = delta `height-1`.
- [x] **M8.4.4 Snap to newest on submit.** After successful `submit` (non-empty outs or echo), `scroll = 0` on the active buffer. Test: scrolled buffer + enter → `scroll==0`.
- [x] **M8.4.5 F10 and Escape both `Quit{}`.** Keep Escape; add F10 latch in FFI.

**Exit:** `make test-feed` + a tiny `keys_demo` or session golden for tab/scroll; live: Shift+arrows and PgUp work.

---

### M8.5 — Composer history (pure ring)

C: 64-slot `history[]`, ↑/↓ recall, `hist_pos = hist_count` after send.

- [x] **M8.5.1 `Hist` Data** on `Session`: `lines: List String`, `pos: Nat` (`pos == length` means “live empty draft”). Cap 64 via `take_last` **in original order** (do not reintroduce the reverse bug; law `log_chrono` is the pattern).
- [x] **M8.5.2 On submit of a non-empty line:** append, `pos = length`, clear draft. On `HistPrev`/`HistNext`: copy into draft, move `pos`. FFI: Up/Down **without Shift** (Shift+Up is not a tab). Input field cursor → end of recalled line (FFI after Bend returns new draft, **or** C-owned field is replaced by Bend draft each frame — pick one: **Bend owns draft**, FFI paints `input_field` from the string Bend sent and writes back on submit only; history recall then just changes `Session.draft` and the field is re-seeded next frame).
- [x] **M8.5.3 Goldens:** three submits + two Up → second line; Down past end → empty draft. Law: `hist_cap_ok` length ≤ 64.

**Exit:** `make test-submit` or a `session` golden; live ↑/↓ works.

---

### M8.6 — Commands the example has that we do not finish

Already in Bend: `/join` `/part` `/msg` `/nick` `/me` `/quit` (QUIT line only).

- [x] **M8.6.1 `/quit` shuts down the UI.** Today we send `QUIT :reason` and keep painting. After submit of `Quit{}`, `step_keys` should set `quit=True` (or return a `Halt`) so `live_go` takes the P5 path (`Chan.close(cmd)` → drain → `Timui.close`). Golden: submit `/quit` ⇒ `outs` contains `QUIT` **and** a `halt` flag. Live: `/quit` exits `birc=ok`.
- [x] **M8.6.2 `/connect host [port]`.** Example starts the worker from the composer. Idiomatic Bend: `NetCmd` already exists; add `Dial{host, port}` **Data** on the cmd Chan (never a `Socket`). Actor already owns dial. If already online: echo error on server buffer (golden). If offline/demo: actor_boot. Default port 6667. Parse in `submit.bend` (pure). Law: `connect_parse_ok("irc.example.net 6668")`.
- [x] **M8.6.3 `/quit` reason default `"birc"`** already. Keep.
- [x] **M8.6.4 Unknown slash** already echos error. Keep.
- [x] **M8.6.5 `/join` offline demo nick echo** (example adds self to nicks without a server). Demo path should `nick_add` self so the nick list is non-empty without 353. Golden: `--demo` nicks contain `me`.

**Exit:** submit goldens for `/quit` halt + `/connect` parse; live `/quit` actually leaves.

---

### M8.7 — Connection state + `/connect` UX

- [x] **M8.7.1 `Session.net: NetState`.** Boot `Connecting{}` until `Ready{}` → `Online{}`; timeout/fail → `Offline{}`; demo → `Demo{}`. Header uses it (M8.3.1).
- [x] **M8.7.2 `--replay FILE`.** Pure: `File.read` lines → `feed_all` (already have fixtures). Arg in `args.bend`. Golden: `make proto-parity` stays the corpus; replay is just `feed_all` + TimUI. Fail closed if the file is missing.

**Exit:** header shows `demo` / `connecting` / `online`; `--replay fixtures/demo.irc` paints.

---

### M8.8 — Mouse + flags

- [x] **M8.8.1** `TIMUI_FLAG_MOUSE` (and keep `ALT_SCREEN | RESTORE_ON_EXIT`). Wheel → `scroll_delta` (M8.4.3). Click tabs (M8.4.2). Click does **not** steal composer focus: after widgets, `timui_set_focus(composer)` every frame (already true).
- [x] **M8.8.2** Optional `TIMUI_FLAG_BRACKETED_PASTE` so paste is one edit-stream burst into the input field.

**Exit:** wheel scrolls the active buffer; click a tab switches; composer stays focused.

---

### M8.9 — Screen integrity (started; finish)

- [x] **M8.9.1** Keep CSI `2J`/`H` on open + per-frame `timui_draw_fill` of `root` with `TIMUI_SLOT_PANEL` (already landed). Add a comment/test note in `docs/FFI.md`.
- [x] **M8.9.2** On resize (`rows` change), fill still covers; no leftover nick-column glyphs. Manual: shrink tmux pane, confirm no artifacts.
- [x] **M8.9.3** First demo frame has no host-terminal text in the body (visual; `--demo --frames 1` in a dirty pane).

**Exit:** dirty tmux pane → `make run-demo` is a clean panel.

---

### M8.10 — Polish the example still has

- [x] **M8.10.1** Snap composer field to empty after submit (C field already clears; Bend `draft` already `""`). Re-seed field from Bend if history recall changes draft (M8.5.2).
- [x] **M8.10.2** Self-echo stays `Self{}` (green), `/me` stays `Action{}` (`* nick text`), never `S:` prefixes.
- [x] **M8.10.3** Status line is hints + nick count (already). Keep it in Bend `status_of`.
- [x] **M8.10.4** `docs/FFI.md` + `Agents.md`: structured `ViewModel`, `UiCmd`, no Socket-on-Chan, no `@unsafe` in view/tokenize.

---

### Idiomatic Bend (non-negotiable)

This milestone is a **Bend** client, not a C clone with Bend glue.

- **Data + match**, not Phase machines, when Base can do it (`List.foldl`/`get`/`set`/`take`/`drop`, `String.eq`/`split`, `Bool` match after a bound). Phase+fuel only where `match f(x)` is illegal and both `Bool.pick` arms would run on the C lane.
- **Pure first.** `view` / `tokenize` / `style_of` / `cycle_tab` / `Hist` / `submit` have no IO. Clock is an argument to `buf_log`, not a hidden effect.
- **One recursive def** per loop (fuel first) or a continuation helper that does not name the recursive function. No mutual recursion. No `@unsafe` except unbounded live wait (`frames=0`), already in `net.bend`.
- **Copyable Data on Chans** (`NetEvt` / `NetCmd` / `UiCmd` / `Dial{host,port}`). Never `Chan(Socket)`. Actor owns the fd.
- **Parallel packs** (`a b = f g`) where two independent pures run. `+T` for reused Data.
- **C is an interpreter** of Bend Data inside one `Timui.frame`. C does not tokenize, classify IRC, or own composer history.
- Prefer **less code**. Live paint is one packed wire (`k|ts|spans`); C interprets it. `TextSpan` stays the tokenize law type.

### Parallelism (local workstreams, ff-only merge)

No GitHub PRs. No push. Independent **local branches** (worktrees if overlapping files must not collide). When a stream’s `make check` (or the smallest gate that covers it) is green, **fast-forward it onto `master`**:

```
git checkout master
git merge --ff-only <stream-branch>
```

If `--ff-only` refuses, rebase the stream onto current `master` and try again. Never merge with a merge commit for these streams. Never force-push.

This tree may not have `.git` yet. If so: `git init -b master`, one initial commit of the current tree, then branch. Default branch is **`master`**, never `main`.

| Stream | Items | Touches | Depends on |
|---|---|---|---|
| A | M8.0 + M8.1 timestamps/kind table (shim paint) | `view` `client` `LAWS` | — |
| B | M8.2 tokenizer + goldens (FFI draw can wait) | `view` `feed_demo` | — (conflicts A on `view.bend`: rebase) |
| C | M8.3 layout widgets + theme + fill | `timui_ffi.c` `view` | A’s `BodyLine` |
| D | M8.4 keys product + scroll/tabs click | `timui` `session` `net` `client` | C’s widgets (scroll can land earlier) |
| E | M8.5 history | `session` `submit` | — |
| F | M8.6–M8.7 `/quit` halt, `/connect`, `NetState`, `--replay` | `submit` `args` `net` `session` | — |
| G | M8.8 mouse flags | `timui_ffi.c` | D’s `scroll_delta` |

A/B/E/F can start in parallel (B rebases on A if both edit `view.bend`). C waits for A. D/G wait for C’s widgets. After each stream: ff-only onto `master`, tick the M8 boxes, continue.

### Explicitly out of scope (do not sneak in)

- TLS / DCC / SASL / ident
- C worker thread, `timui_post` IRC lines (Bend actor already owns the socket)
- Replacing Bend `feed`/`submit` with `irc_proto.h`
- Weakening `log_chrono`, `scroll_bounds_ok`, `tokenize_has_bold`, `cycle_tab`
- `Chan(Socket)`

### Milestone 8 exit

- [x] `make check` green.
- [x] `--demo` shows timestamps, kind colours, bold/italic/code, a live URL, nick table, rounded panels, tab bar.
- [x] Live: Shift+←/→, click tabs, PgUp/wheel, ↑/↓ history, `/quit` exits, `/connect` from composer if started in demo.
- [x] No `S:`/`Y:`/`M:` in the body. No `lines=scroll=h=`.
- [x] Laws for tokenize, cycle, scroll, hist cap, `/quit` halt, connect parse.

---

## Done definition (whole migration)

- [x] `make proof` PASS with laws covering parse, pong, feed identity/PING, submit `line_ok`, framer roundtrip, scroll bounds.
- [x] `make check` runs **only** Bend-built `build/birc` for UI.
- [x] No `irc_proto.h`, no C `irc_feed`/`irc_submit`.
- [x] TimUI used only through foreign effects; Bend `main` owns frame iteration (thin `open`/`frame`/`close`).
- [x] README/AGENTS describe Bend-first + TimUI-FFI. Live TCP is Base `TCP.send`/`recv`.
- [x] Live TCP net + Bend fuel loop (D3: Bend strings; octet `Fr.push` kept for laws).

---

## Milestone 9 — review 2026-09-21

Work order: `build/review/HANDOVER.md`. Base `ac97be1`. Branch `review-fixes`. Never push.

### Phase S — setup
- [x] **S1** Branch `review-fixes`.
- [x] **S2** This M9 checklist (one box per ID).
- [x] **S3** Tracked pty test harness (`make test-pty` in `make test`). Confirmed red on `ac97be1`: `deadlock=True birc_ok=False` at 200 chunks.
- [x] **S4** `make lint-ffi` in `make check` (ffi A12).

### Phase C — critical
- [x] **C1** Channel deadlock: one `NetCmd` per `NetEvt`; `Dial` arm emits an event (net#1 #10).
- [x] **C2** Restore the terminal on every exit path (net#2).
- [x] **C3** Body rows: one source of truth; packed lines ≤ drawable rows (view#2, ffi A2).
- [x] **C4** Inbound control bytes and wire injection (view#1 #6 #7, proto#4 #8, ffi A1 A13).
- [x] **C5** Framer CR flood: count every byte; remainder ≤ 510 (proto#1).
- [x] **C6** 512-byte cap in UTF-8 bytes; clamp in `send_line`; unify `LINE_MAX` (proto#2 #3, view#3 #8, net#8).
- [x] **C7** DNS hardening (dns#1–#14). Answer-only + CLASS + QD + TC + QNAME + 255-octet name; peer/EINTR/clamp; wrong-id keep-listening; resolv.conf; re-send; IPv6 reject; 14-bit txid documented (no send_octets: would exceed the 25-line C budget).
- [x] **C8** Composer: typed sized to field, explicit seed flag, state on `Ui` handle (ffi A3 A4 A11, view#4).

### Phase H — high
- [x] **H1** Buffer cap: `buf_get` returns `Maybe`; create only on self-JOIN; error at cap (client#1 #2 #14, view#5).
- [x] **H2** Numerics log last param; 433 retries `NICK <nick>_` only when param 1 `ieq` Client.nick (client#4, net#11).
- [x] **H3** Disconnect: `Eof` → offline + idle loop; non-Online echo "not connected" (net#5 #4).
      UI respawns the idle actor on fresh channels. Actor never calls UI.
- [x] **H4** `/connect` must not freeze the UI (net#3).
      Dial runs in a spawned job; the idle actor keeps Tick/cmd so the UI paints.
      After `Timui.close`, `IO.die(Unit, 0, "")` halts so a parked `TCP.connect` cannot keep the process.
- [x] **H5** `--demo --nick bob` registers as `bob` (net#9).
- [x] **H6** `boot_clock` must not keep the process alive 8 s after quit (net#7).
      Sleep is 100 ms × 80; a send on a stop chan closed from `boot_ui` aborts.
      Same halt as H4: `shutdown` ends with `IO.die` so leftover sleeps cannot outlive the UI.
- [x] **H7** Byte-safe TCP read; octet framer; delete `push_text` (proto#5, net#6, ffi B).
      Live read is `recv_octets` (non-blocking so idle still Ticks). Remainder is
      `List U32`. Completed lines decode as UTF-8; invalid lines fall back to
      Latin-1. `push_text` deleted. IO_READ park skipped: it would block Ticks.
- [x] **H8** Fuel that returns a wrong value: `U32.to_nat`, `parse_params`, `copy_args`, `send_lines_go` (idiom §5c, proto#6 #7, view#16).
      `u32_to_nat` deleted (Base `U32.to_nat`). `parse_params` fuel is `1+4*len`.
      `copy_args` fuel 0 with leftover argv is `Bad{"birc: too many arguments"}`.
      `send_lines_go` fuel 0 returns `(sock, False{})`.

### Phase M — medium
- [x] **M1** NICK renames a query buffer (client#3).
- [x] **M2** QUIT shows in a query (client#6).
- [x] **M3** MODE goes to the channel with all params (client#7).
- [x] **M4** PART only for members (client#8).
- [x] **M5** nick `server` must not merge into the server buffer (client#9).
- [x] **M6** RFC 1459 casemapping in `ieq` (client#10).
- [x] **M7** self-sourced PRIVMSG keys the buffer on the target (client#11).
- [x] **M8** Clamp the scroll offset on write (client#5, view#9).
      Clamp to `List.length(lines)`. `scroll_page_ok` / `snap_ok` expected the
      unbounded offset; they now expect the clamp.
- [x] **M9** `/part` in the server buffer → usage error (view#10).
- [x] **M10** `--port` range 1..65535 (view#11).
- [x] **M11** PageUp/PageDown move a page (view#14). FFI sends `Sess.body_h`.
- [x] **M12** URL tokenizer: word boundary, trim trailing punctuation (view#13).
      Trailing set includes `)` `.` `,` `"` `]` `;`. `]8;;` keeps `]8` (digit).
- [x] **M13** over-long URL → plain span (view#12).
- [x] **M14** Tabs: clamp `sel`, click only on change, cut on code point (ffi A8 A9 A10).
- [x] **M15** Clip with one forward pass, O(n), code point safe (ffi A6 A7).
- [x] **M16** Decide and document who wraps long lines (view#15).
      C clips at `maxx`; Bend does not wrap. Documented in `docs/FFI.md`.
- [x] **M17** Cap outbound lines per actor tick, carry the rest (net#12).
      `SEND_CAP` is 8. `reader_go`/`reader_idle` carry leftover lines.
      Pty: `tests/pty/paste50.py` (50 PRIVMSGs). X2: cmd close and fuel-0
      flush `pending` so `/quit` behind a full cap still reaches the wire
      (`tests/pty/quitcap.py`).
- [x] **M18** `Timui.frame` blocks the loop up to 16 ms: measure first (net#13).
      Superseded by **P1**: idle wait is 1000 ms, 16 ms only while Connecting,
      for 50 ms after actor events, or if the composer is non-empty.
      Historical `cpu_pty.py` numbers (16 ms always): idle 6.6–7.4%. After P1:
      `tickrate.py` ~0.4–0.6% idle; with-traffic `ratecpu.py` ~1.0%.
- [x] **M19** `pack_spans.cons` empty-means-first; bare `JOIN` must not create `""` (view dead#7).
      Empty JOIN does not open a buffer. pack_spans deleted with the packed wire.
- [x] **M20** Small C fixes: `timui_full_redraw`, dead stores, `tlen`, feature macro, `localtime` (ffi A14–A17).
      `timui_full_redraw`; dropped unused `w` store; deleted dead `_POSIX_C_SOURCE` and `localtime` fallback.
      `tlen` vs `strlen(typed)` left (same value today).

### Phase I — idiomatic Bend
- [x] **I1** Delete `natutil.bend`; `body_h` to `session.bend`; drop `ticks_of` (idiom top10#1, proto dead#4).
      `body_h` / `live_fuel` live in `session.bend`. `ticks_of` still aliases `live_fuel` (law `live_fuel_alias`).
- [x] **I2** `dns_wire` Data cursor + `do Maybe`; nested patterns; drop shims (dns#17–#23 #28–#30).
      Data `Cur`/`Got` + `do Maybe`. Wire shims in `dns.bend` deleted; live
      path and `dns_demo` call `Wire.*` directly. P7: `Cur` carries the
      remaining suffix; `byte_at` is the head of `rest`.
- [x] **I3** `List.modify` at the 10 buffer-update sites (idiom §4#6, client#17).
      `buf_modify` walks the buffer list; join/part/kick/topic/log/scroll
      pass a `Buffer -> Buffer`. `set_nth_buf` deleted.
- [x] **I4** Table-driven dispatch: `cls_*`, `args_opt.*`, `slash_*`, `feed_numeric` (idiom §4#2–#5).
      `cls_rows` / `slash_rows` / `num_rows` / `flag_rows` + Bool.pick lookup.
      Goldens unchanged.
- [x] **I5** Base `U32.read` replaces `parse_u32` (idiom top10#5).
      `parse_u32` is a `Num` wrapper over `U32.read` (identical on the 7 t18
      probes including overflow). `submit` no longer imports `args`.
- [x] **I6** Structural walkers are fuel-free (`take_until_space`, `strip_ctl`,
      `nick_strip`, `show_*`, octet/string eq, `send_lines_go`, …). Remaining
      `fuel: Nat` first params keep one comment quoting the decreasing-self-call
      checker error (`tokenize.go`, `utf8_decode.go`, `push.go`, `sanitize_in`,
      `clamp_line.go`, DNS/net loops).
- [x] **I7** `client.bend`: replace `*Acc` folds; `cycle_tab` enum (client#12 #13 #18 #19).
      `strip_cr` copy deleted. `nick_has` is `List.contains` + `nick_eq`.
      Find/Has/Del/Ren/Quit/Nick Acc gone. `cycle_tab` takes `TabDir`.
      X1: `buf_find.go` had a recursive call in both `Bool.pick` arms (eager →
      exponential in buffer count). One recurse per step; `tests/bend/feed_bench.bend`
      (15 JOINs + 20 PRIVMSGs) finishes under 2 s. Other `Bool.pick` lookups in
      `src/` are linear-eager (`cls_lookup` / `slash_lookup` / `num_kind` /
      `take_until_space`); not shorter to rewrite.
- [x] **I8** Decode `UiKeys` into Data at the FFI edge (idiom §7, net#14 #19).
      `with_keys` builds `Sess.Keys` (`TabDir`, `HistDir`, `Maybe` click).
      `step_keys` takes that record. C `UiKeys` packing unchanged.
- [x] **I9** Remaining Base reimplementations (idiom §1 table).
      `String.starts_with` (has_prefix gone), `Char.to_u32`, `List.drop` for
      take_last, `Maybe.default` for str_get, `Char.is_digit`. Keep `is_space`
      as RFC 1459 SP-only. Identity `nth_buf`/`str_eq` stay as typed wrappers
      used from tests. Acc folds are I7.
- [x] **I10** Remaining in-src `show_*` use `String.concat`/`join` (view idiom#2).
      `show_nicks`/`show_bufs`/`show_spans` concat chunks (trailing space/`;` kept).
      `show_buf` / `show_client` / `show_netcmd` concat a mapped list of pieces.
- [x] **I11** `net.bend`: factor loops; `send_go` pure; SLPh (net#16 #18 #20).
      `poll_pass` deleted. `send_go` is pure `Socket & Result -> Socket & Bool`.
      `SLPh` gone; `send_lines_go` matches the pair then the list.
- [x] **I12** One framer (H7). Unreachable CR strip in `emit_line`/`payload_n` gone.
      `push_param` and `join_lines` cons then reverse once. P5: a bare CR
      drops the whole line (RFC 1459); CRLF still ends a line.
- [x] **I13** Parallelism: rebalance `view_draft` (idiom §6).
      Same measurement as M18 (`tests/perf/cpu_pty.py`, 15 s): idle 6.6–7.4% of one
      core, flood 10.9–17.7%. Parallel packing is not justified at these
      totals. Decision: no change.
- [x] **I14** Dead code: 15 defs, `irc.bend:243-249`, stale tags, `Net` alias (idiom §3 §8).
      Deleted unused `is_online`/`is_busy`/`session_offline`/`session_rows` and the
      `header_of`/`body_of`/`nicks_of`/`status_of`/`active_buf`/`view`/`show_vm`/`pad_*`
      wrappers. `nick_of` is live. Session import is `Sess` (T7). Stale F*/D2 tags
      in comments now say what they mean.
- [x] **I15** Split `client.bend` below ~1000 lines (client#25).
      I15a: inspectors/`*_ok` in `client_laws.bend`. I15b: types+container in
      `buffer.bend`. `wc -l`: client 636, buffer 597, client_laws 339.
- [x] **I16** Uncited `*_ok`/`show_*` moved to `tests/bend/` (net#21, client#24).
      Cited law helpers stay (`show_client`/`show_spans`/`show_netcmd`, `submit_ok`,
      framer/view/session/clock predicates). Production `*_ok` (DNS/net/args) stay.

### Phase R — remove C
- [x] **R1** Delete `tests/ffi/` and the `ffi-smoke` target.
- [x] **R2** Fix Bend colour constants; pack colour from Bend; delete `birc_kind_fg` (ffi A5).
      Wire is `fg|ts|spans` with `style_of` RGB. C no longer maps LineKind.
- [x] **R3** `Clock.hhmmss` → local seconds-of-day as `U32`; Bend formats (ffi B).
      `local_secs` returns U32; Bend `fmt_sod`/`fmt_hms`. strftime gone.
- [x] **R4** = C8.
- [x] **R5** One effect taking `List<DrawOp>`; delete the packed-wire interpreter.
      `Timui.frame` walks `List<DrawOp>`. Packed k|ts|spans interpreter is gone.
      Test-only packers deleted under T6 (DrawOp goldens replace them).
- [x] **R6** Draw ops carry rects; panel layout moves to Bend.
      DrawOp is OpBox/OpText/OpTabs/OpLine. Bend assigns each body line its y
      (bottom-aligned). C paints as it walks — no lns[64], no count, no
      bottom-align. Pty: `tests/pty/tall_rows.py` at 40 and 90 rows.
      Law: `body_ys_ok` for rows 24, 90, 200.
- [x] **R7** `recv_octets`: `IO_READ` parking skipped; peer already returned (C7).
      `io_eff(CID_RECV_OCTETS, recv_octets_run, 0)` is non-blocking. `None` is
      EAGAIN/EINTR; the actor Ticks (`net.bend` `after_poll` hit=False).
      `IO_READ` park would freeze Ticks (H7). Peer is host+port beside octets.

### Phase T — laws and tests
- [x] **T1** Quantified `strip_ctl_clean`: `for s: String`, `has_crlf(strip_ctl(s))`
      is False. Proved by induction on `s`; the step case-splits `is_crlf(h)` and
      rewrites with `%e : P`. Point laws `clamp_samples` / `strip_ctl_nocr` stay.
- [x] **T2** Delete or repair laws/tests that cannot fail (`live_fuel_alias`, `kind_code_ok`, `feed_id`, …).
      GOLDEN CHANGE: `kind_code_ok` pins `kind_digit`; `feed_id` compares `show_client`;
      deleted tautology `live_fuel_alias`.
- [x] **T3** Feed fixtures through `File.read` + `replay_lines`; real `\x01` ACTION (proto T6, client#23).
      All five fixtures go through `File.read` + `replay_lines`. `action.irc`
      has real SOH; `action_feed_ok` asserts `* alice waves` after self-JOIN.
- [x] **T4** `dns_demo`: hostile packets as − tests; live address set (dns#25 #26).
      Hostile packets already in dns_demo (C7). Live path asserts 1.1.1.1 or
      1.0.0.1; Fail allows timeout/bind/send/recv/random/bad id/bad dns/no A/
      short/tc/rcode/ipv6. Dropped the dead `"dns"` token.
- [x] **T5** Client −/+ tests: NICK, QUIT, PART, KICK, MODE, TOPIC, 4xx (client#20).
      Query NICK/QUIT, MODE, non-member PART, 433 covered. KICK-other and TOPIC command still thin.
- [x] **T6** Goldens for draw ops, args (port range, >64 argv), submit (LF paste, `/part` server, 600-byte UTF-8).
      Port range, copy_fin extra argv, /part server, clamp_utf8, echo_nolf.
      DrawOp goldens: draw_line/link/hostile/tabs/nicks. Packers gone.
- [x] **T7** Net: rename `Net` alias; live mock − cases (net#23–#25).
      LAWS/PROOF/net_demo import session as `Sess`. `tests/pty/live_minus.py`:
      refused (exit 1), 433 → `NICK probe_`, close mid-line keeps the UI,
      split line paints, Latin-1 `0xE9` paints.
- [x] **T8** proto harness uses `tests/bend/expect.bend` (`tests/bend/proto_demo.bend`).

### Phase D — docs
- [x] **D1** Delete `docs/INVENTORY.md`.
- [x] **D2** `docs/FFI.md`: real type names, draw-op contract, `lint-ffi`.
      `UiKeys.typed` is a String; `Timui.frame` takes `List<DrawOp>`.
      `recv_octets` (not `TCP.recv`); `-w` build vs `make lint-ffi`.
      Packed-wire section replaced by the OpBox/OpText/OpTabs/OpLine contract.
- [x] **D3** `README.md`: `birc_bend.c`, no "shim", list every FFI file.
- [x] **D4** `AGENTS.md`: clock, 512-byte, shutdown, Bend match notes, pty.
- [x] **D5** `Makefile`: delete the dead `CFLAGS` block.
- [x] **D6** `TODO.md`: no `Timui.events`; list `clock_ffi.c`; M9 ticked or annotated.

C line count before: 662 (`src/ffi` + `tests/ffi`). After C trim: 599
(`clock 26`, `dns 63`, `timui 510`). Do not run `make clean` (repros live in
`build/review/`).

---

## Milestone 10 — open points (work order 2)

Base: `1d9e5bd`. Same rules as M9. Boxes P1–P9 from `build/review/HANDOVER2.md`.

Idle baseline (supervisor, `build/review/lead/tickrate_pty.py`, `--demo --frames 600`,
no input): 55 ticks/s, 7.8% of one core at 30x100 (9.2% at 82x159). Cause: 16 ms
`timui_begin` poll.

- [x] **P1** Idle CPU: `wait_ms` + tty/`wake_fd` poll before `timui_begin`; Bend
      chooses 16 ms vs 1000 ms; actor sends socket fd as a wake hint (`fd_hint`).
      Baseline (`tickrate_pty.py`, `--demo --frames 600`): 55 ticks/s, 7.8% of a
      core at 30x100. After: `tests/pty/tickrate.py` 20 frames, 0.97 ticks/s,
      0.46% (30x100) / 0.54% (82x159). Paint cost ~5 ms/tick keeps CPU% near
      0.5% at a 1000 ms wait. `paint_wake.py`: incoming line in 28 ms after 3 s
      idle (27–71 ms across five runs). TimUI `input_poll_ms=0` so begin does
      not sleep again. C after P1: clock 26, dns 74, timui 562 (662). The
      initial `--connect` path now posts `Up{fd}` so idle poll sees the socket.
      Handshake: UI stays at 16 ms while `Connecting` and for 50 ms after
      Up/Chunk/Fail/Eof (`IO.now`, not frame count; poke already wakes). A
      2000 ms window cost 5–6% of a core at one inbound line every 1.5–5 s
      (`ratecpu.py`); 50 ms is 0.9–1.0% (period 2.0 s: 0.9%; 1.5 s: 1.0%)
      next to idle `tickrate.py` 0.52% (30x100) / 0.59% (82x159). Self-pipe
      `wake_poke` wakes the poll when the actor posts those events.
      `tests/pty/join_latency.py` and `redial.py` require 001 → JOIN ≤ 100 ms.
      C after handshake fix: clock 26, dns 74, timui 605 (705).
- [x] **P2** 16-bit DNS txid via `send_octets` (≤ 25 lines C; total C < 662).
      `txid_of` is `U32.and(n, 65535)`, never 0. Query encode is `List U32`.
      `send_octets` is the outbound twin of `recv_octets`. C: clock 22, dns 99,
      timui 537 (658). `txid_of(0x8080)` keeps bits 7 and 15.
- [x] **P3** `make check` offline: live DNS lookup moves to `test-dns-live`.
      `test-dns` is identity + parse only; `! grep one.one.one.one` on
      `dns_demo.bend`. `make test-dns-live` is documented and not in `check`.
- [x] **P4** Split `net.bend` into `actor.bend` + `net.bend` (both < 1000 lines).
      `actor.bend` 780 (reader/idle/dial/send); `net.bend` 518 (UI/shutdown).
      Goldens unchanged modulo the net_demo import.
- [x] **P5** Bare CR inside a line drops the whole line (RFC 1459).
      `"abc\\rdef\\r\\nhello\\r\\n"` yields only `hello`. Split CRLF still
      emits. `bare_cr_drop` law.
- [x] **P6** Server tab reserved label so a nick/channel `server` cannot collide.
      Tab strip uses `*server*` for buffer 0; a query named `server` stays
      `server`. `tab_names_ok` / `tab_collide_ok`.
- [x] **P7** `dns_wire` cursor carries the remaining packet suffix (no `List.drop` per byte).
      `Cur{pkt, rest, off}`; `byte_at` is `at_xs(rest)`; jumps use `at_off`
      once. `dns_demo` unchanged.
- [x] **P8** Two quantified laws by induction (`push` rem bound; `nbuf` cap or DNS `parse_id`).
      Quantified `for xs. rem ≤ 510` is FALSE, not unprovable: `push.go` tests
      `is_cr` before `over`, so a CR at a chunk boundary is held at 511
      (`rem(510a+CR)=511`). Bound restated as `LINE_OCTET_MAX+1`. Point laws
      `push_rem_510` / `push_rem_511` / `parse_id_short` / `parse_id_bad`
      (`sample_bad_id()`, a full packet with a wrong id). Checker output for
      the quantified attempt stays in PROOF.bend.
- [x] **P9** `--die-after-open` (test-only) exercises atexit restore.
      Env `BIRC_DIE_AFTER_OPEN=1` (test-only) `exit(1)`s after `Timui.open`
      so atexit restore runs. `restore.py` checks ICANON after that path.

---

## Milestone 11 — structural framer and input actor

Base: `master` at `f34bbc9`. Branch `wo3`. Boxes from `build/review/HANDOVER3.md`.
Same rules as M9/M10 (TDD, one item per commit, `make check` green, GOLDEN
CHANGE, three consecutive pty runs, never push).

### Part A — structural framer

- [x] **Q1** `push.go` is structural: one byte per recursive call. `FrSt` +
      `step` (no recursion) + `walk` (no fuel). No behaviour change.
      `feed_bench` real 0.55 s before, 0.52 s after (`/usr/bin/time -p`).
      1_000_000 `a` octets through `push`: rem length 0 (dropped at octet
      511, same before and after). user 0.02 s + sys 0.06 s both, five
      runs; wall after warmup 0.21–0.28 s before, 0.09–0.25 s after.
      No cost regression.
- [x] **Q2** Quantified law: `for xs`, `rem` of `push(Nil, xs)` has length
      `≤ LINE_OCTET_MAX+1`, proved by induction (pattern `strip_ctl_clean`).
      `law push_rem_bound`. Invariant: Normal and AfterCr keep `n ≤ 510`
      and `n = length(rem)` (the held CR is the +1); Drop keeps rem empty.
      Point laws `push_rem_510` / `push_rem_511` stay.
- [x] **Q3** Quantified `parse_id` mismatch. Q2 is proved. Not cheap, so
      not attempted. `parse_id` is `parse_q(want, "a", xs)`: `parse_hdr`
      is a `do Maybe` of seven `take16`/`take8` steps, then
      `first_fail(hdr_chks)` (the id check is the first `Chk`), then
      `read_name` and `walk_an_go` (fuel phases `AwLeft` / `AwSkip` /
      `AwA`). The mismatch fact is "header id ≠ want ⇒ not `Done`", but
      tying `xs_id(xs)` to `hdr_id(parse_hdr(xs))` for every list means
      proving the cursor (`at_off` / `rest_drop` / `take16`) inside
      `do Maybe`, plus the short-packet `None` case. That is another
      induction, not a lemma on the Q2 pattern. Point laws stay:
      `parse_id_short` (`Nil`) and `parse_id_bad` (`sample_bad_id()`,
      id 2 vs want 1).

### Part B — input actor

- [x] **K1** Design note in `docs/FFI.md`. Writer owns the `Socket` and
      blocks on `NetCmd`; reader owns a dup and parks in `recv_octets`
      (`IO_READ`). UI sends `Cont{outs}` when it has lines. Every `FromNet`
      carries a generation; the UI bumps it on each `Dial` and drops a
      stale `Eof`. DNS keeps non-blocking `recv_nb` so its fuel timeout
      still runs. `Socket.shutdown` then the writer closes `sock` and the
      reader closes only the dup. Watchers run in every UI mode. `gen_eof.py`
      locks the redial race.
- [ ] **K2** Implement K1. Delete `birc_wait_fds`, self-pipe, `wake_poke`,
      `fd_hint`, `wait_ms` / `wake_fd`, hot window, and `input_poll_ms` if
      unused. Report C line counts and the `timui.h` diff against `ac97be1`.
- [ ] **K3** `recv_octets` parks with `IO_READ`. DNS timeout/resend still works.
- [ ] **K4** Pty measurements before (`f34bbc9`) and after: idle ticks/CPU,
      traffic CPU, latencies, key latency, full pty set. Targets: idle ≤ 0.3%
      and ≤ 1 frame/s, traffic ≤ 1%, latencies ≤ 100 ms, resize ≤ 1.1 s.
- [ ] **K5** UBSan hostile pty: 0 reports. `make lint-ffi` clean. Update
      `AGENTS.md`, `docs/FFI.md`, `README.md`.

---

## Open decisions (resolve in M0/M4)

| ID | Question | Default |
|---|---|---|
| D1 | Coarse `draw_frame(ViewModel)` vs fine-grained widget FFI? | Coarse (`Timui.frame` paints whole layout) |
| D2 | Net concurrency model A/B/C? | `IO.spawn` net actor + `Chan` Data events (Bend-native B) |
| D3 | UTF-8 TCP vs byte-exact foreign TCP? | Base `TCP.send`/`recv` strings; `Fr.push` octet laws kept |
| D4 | UI loop `@unsafe` vs fuel? | `--frames N` fuel; `frames=0` live `@unsafe` idle |
| D5 | Keep a C demo binary during transition? | No — deleted at M5.8 |
