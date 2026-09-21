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
- [x] **P5** Shutdown order: UI `Chan.close(evt)` → `Timui.close`; net actor `Socket.close` (live path).
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
- [x] **M11** PageUp/PageDown move a page (view#14). FFI sends `rows-6`.
- [x] **M12** URL tokenizer: word boundary, trim trailing punctuation (view#13).
- [x] **M13** over-long URL → plain span (view#12).
- [x] **M14** Tabs: clamp `sel`, click only on change, cut on code point (ffi A8 A9 A10).
- [x] **M15** Clip with one forward pass, O(n), code point safe (ffi A6 A7).
- [x] **M16** Decide and document who wraps long lines (view#15).
      C clips at `maxx`; Bend does not wrap. Documented in `docs/FFI.md`.
- [ ] **M17** Cap outbound lines per actor tick, carry the rest (net#12).
      tried: send_lines is one Cont list; carrying needs pending on reader_go
      evidence: on_cmd sends the whole `outs` list in one tick
      open question: thread a pending List through reader_go/idle without a second cmd
- [ ] **M18** `Timui.frame` blocks the loop up to 16 ms: measure first (net#13).
      tried: no default-off frame timer in the tree
      evidence: net#13 is a 16 ms poll/draw bound; changing it without a split is intuition
      open question: add a default-off phase timer, then re-measure before touching the 16 ms path
- [x] **M19** `pack_spans.cons` empty-means-first; bare `JOIN` must not create `""` (view dead#7).
      Empty JOIN does not open a buffer. pack_spans first-span is still `is_empty(acc)`.
- [x] **M20** Small C fixes: `timui_full_redraw`, dead stores, `tlen`, feature macro, `localtime` (ffi A14–A17).
      `timui_full_redraw`; dropped unused `w` store; deleted dead `_POSIX_C_SOURCE` and `localtime` fallback.
      `tlen` vs `strlen(typed)` left (same value today).

### Phase I — idiomatic Bend
- [x] **I1** Delete `natutil.bend`; `body_h` to `session.bend`; drop `ticks_of` (idiom top10#1, proto dead#4).
      `body_h` / `live_fuel` live in `session.bend`. `ticks_of` still aliases `live_fuel` (law `live_fuel_alias`).
- [ ] **I2** `dns_wire` Data cursor + `do Maybe`; nested patterns; drop shims (dns#17–#23 #28–#30).
      - [x] Data `Cur`/`Got` + `do Maybe` header/RR/ip4 (idiom §4#1); dead `skip_name`/`answers_go`/`parse_*_p` path deleted; test-only `octets` moved (dns#19).
      - [ ] nested `_p` leftovers / `List.drop` / error Data / phase constructors / remaining `Dns.*` shims.
      tried: cursor rewrite landed in C7
      evidence: live parse is `parse_q` + `Cur`; leftover shims are naming only
      open question: delete remaining `Dns.*` aliases in a no-behaviour pass
- [ ] **I3** `List.modify` at the 10 buffer-update sites (idiom §4#6, client#17).
      tried: get_buf/set_buf would touch every feed arm
      evidence: ten near-identical Client rebuilds in client.bend
      open question: introduce get_buf/set_buf then rewrite arms in a dedicated pass
- [ ] **I4** Table-driven dispatch: `cls_*`, `args_opt.*`, `slash_*`, `feed_numeric` (idiom §4#2–#5).
      tried: chains are Bool-parameter match (legal Bend)
      evidence: 14-deep cls_* and slash_* still sequential
      open question: List.find table vs balanced parallel tree
- [ ] **I5** Base `U32.read` replaces `parse_u32` (idiom top10#5).
      tried: args.parse_u32 still used for --frames/--port
      evidence: U32.read exists (dns_wire octet_ok)
      open question: whether U32.read matches parse_u32 overflow rules
- [ ] **I6** Remove fuel from structural walkers and phase machines (idiom §5a §5b).
      tried: UTF-8 decode needs fuel; termination checker rejects Utf8Acc.rest
      evidence: `bend` "expected a decreasing self-call" on utf8_decode.go without fuel
      open question: remaining walkers (drop_spaces, tokenize) in a dedicated pass
- [ ] **I7** `client.bend`: replace `*Acc` folds; delete `strip_cr` copy; `cycle_tab` enum (client#12 #13 #18 #19).
      tried: Acc folds still compile and match goldens
      evidence: FindAcc/HasAcc/DelAcc/RenAcc/QuitAcc/NickAcc remain
      open question: List.contains + structural nick_del in a no-behaviour pass
- [ ] **I8** Decode `UiKeys` into Data at the FFI edge (idiom §7, net#14 #19).
      tried: UiKeys is still a 9-field U32 product
      evidence: session.step_keys unpacks U32 flags
      open question: TabDir/HistDir/Maybe click at the FFI boundary
- [ ] **I9** Remaining Base reimplementations (idiom §1 table).
      tried: several already replaced (U32.to_nat, U32.read in DNS)
      evidence: idiom.md §1 still lists has_prefix, parse_u32, Acc folds
      open question: one file per remaining row
- [ ] **I10** `view.bend`: `String.concat`/`join`; saturating `Nat.sub`; tokenizer helpers (view idiom#2 #3 #6 #8).
      tried: pack_body is still foldl ++
      evidence: view idiom#2 measured as quadratic in the review, not re-measured here
      open question: String.concat rewrite after I13 measurement
- [ ] **I11** `net.bend`: delete `poll_pass`; `or_halt` → `Bool.or`; factor loops; `send_go` pure (net#15 #17 #18 #20).
      tried: SLPh send_lines still two-phase (H8 only fixed fuel 0)
      evidence: net.md #16 has a compiling fuel-free send_lines
      open question: replace SLPh without changing send semantics
- [ ] **I12** `frame.bend`: one state machine (after H7); no `List.append` inside loops (proto idiom#5 #6 #7).
      tried: octet push still uses PushPhase + fuel
      evidence: H7 added utf8_decode beside the existing phase machine
      open question: merge decode into emit_line only, leave push.go for I12
- [ ] **I13** Parallelism: rebalance `view_draft`; measure `pack_body` (idiom §6).
      tried: no default-off pack_body timer
      evidence: review claims pack_body is the balanced map; not re-measured
      open question: instrument then decide; do not claim speed
- [ ] **I14** Dead code: 15 defs, `irc.bend:243-249`, stale tags, `Net` alias (idiom §3 §8).
      tried: LAWS still imports session as Net
      evidence: live_fuel_alias uses that alias
      open question: rename after T7
- [ ] **I15** Split `client.bend` below ~1000 lines (client#25).
      tried: file grew with M1–M8 tests
      evidence: still one feed+buffer module
      open question: buffer.bend vs client_laws.bend split
- [ ] **I16** Move in-src test predicates that no law cites into `tests/` (net#21, client#24).
      tried: many *_ok stay in client.bend because LAWS imports them
      evidence: feed_demo also calls in-src predicates
      open question: move only uncited ones without breaking PROOF.bend

### Phase R — remove C
- [x] **R1** Delete `tests/ffi/` and the `ffi-smoke` target.
- [ ] **R2** Fix Bend colour constants; pack colour from Bend; delete `birc_kind_fg` (ffi A5).
      tried: live wire still sends kind_digit; C has birc_kind_fg
      evidence: style_of disagrees with C on 4 of 6 kinds
      open question: pack style_of U32 in the wire, then delete C table
- [ ] **R3** `Clock.hhmmss` → local seconds-of-day as `U32`; Bend formats (ffi B).
      tried: Clock.hhmmss still formats in C
      evidence: fmt_hms already exists in Bend
      open question: new effect returning U32 seconds-of-day
- [x] **R4** = C8.
- [ ] **R5** One effect taking `List<DrawOp>`; delete the packed-wire interpreter.
      tried: C still interprets k|ts|spans
      evidence: handover default is List<DrawOp>, no per-widget effects
      open question: DrawOp Data + one FFI list walker
- [ ] **R6** Draw ops carry rects; panel layout moves to Bend.
      tried: layout is still C inside Timui.frame
      evidence: depends on R5
      open question: after R5
- [ ] **R7** `recv_octets`: `IO_READ` parking and peer address (with C7).
      tried: IO_READ park skipped in H7 (would block Ticks)
      evidence: non-blocking recv_octets + Tick on EAGAIN keeps the UI alive
      open question: park only when the UI loop can multiplex Ticks

### Phase T — laws and tests
- [ ] **T1** Quantified laws (`line_ok(clamp_line(s))`, no CR/LF in `strip_ctl`, …).
      tried: point laws exist; `for s: String` proofs are out of reach
      evidence: handover rule 7: keep the point law, add a test
      open question: leave quantified forms for a proof pass
- [x] **T2** Delete or repair laws/tests that cannot fail (`live_fuel_alias`, `kind_code_ok`, `feed_id`, …).
      GOLDEN CHANGE: `kind_code_ok` pins `kind_digit`; `feed_id` compares `show_client`;
      deleted tautology `live_fuel_alias`.
- [ ] **T3** Feed fixtures through `File.read` + `replay_lines`; real `\x01` ACTION (proto T6, client#23).
      tried: proto_parity greps fixtures; ACTION soh test exists in proto_parity
      evidence: fixtures/action.irc still lacks \x01
      open question: rewrite the fixture vs keep the Bend-built ACTION line
- [ ] **T4** `dns_demo`: hostile packets as − tests; live address set (dns#25 #26).
      tried: C7 added parse checks; dns_demo has identity tests
      evidence: hostile fixtures live in build/review/dns (gitignored)
      open question: lift those fixtures into tests/ without make clean
- [x] **T5** Client −/+ tests: NICK, QUIT, PART, KICK, MODE, TOPIC, 4xx (client#20).
      Query NICK/QUIT, MODE, non-member PART, 433 covered. KICK-other and TOPIC command still thin.
- [x] **T6** Goldens for draw ops, args (port range, >64 argv), submit (LF paste, `/part` server, 600-byte UTF-8).
      Port range, copy_fin extra argv, /part server, clamp_utf8, echo_nolf.
- [ ] **T7** Net: rename `Net` alias; live mock − cases (net#23–#25).
      tried: live_mock is under a pty; split-line is utf8_split_pty
      evidence: session is still imported as Net in LAWS/net_demo
      open question: rename import in a no-behaviour pass
- [ ] **T8** `main.bend` uses `tests/bend/expect.bend` (proto T8).
      tried: main.bend still has its own must()
      evidence: proto_parity already uses expect.bend
      open question: switch main.bend without duplicating proto_parity

### Phase D — docs
- [x] **D1** Delete `docs/INVENTORY.md`.
- [ ] **D2** `docs/FFI.md`: real type names, draw-op contract, `lint-ffi`.
      Wrap/clip contract added. DrawOp (R5) not written.
      tried: packed wire is still the live contract
      evidence: FFI.md M8 packing section
      open question: expand after R5
- [x] **D3** `README.md`: `birc_bend.c`, no "shim", list every FFI file.
- [x] **D4** `AGENTS.md`: clock, 512-byte, shutdown, Bend match notes, pty.
- [x] **D5** `Makefile`: delete the dead `CFLAGS` block.
- [x] **D6** `TODO.md`: no `Timui.events`; list `clock_ffi.c`; M9 ticked or annotated.

C line count before: 662 (`src/ffi` + `tests/ffi`). Do not run `make clean` (repros live in `build/review/`).

---

## Open decisions (resolve in M0/M4)

| ID | Question | Default |
|---|---|---|
| D1 | Coarse `draw_frame(ViewModel)` vs fine-grained widget FFI? | Coarse (`Timui.frame` paints whole layout) |
| D2 | Net concurrency model A/B/C? | `IO.spawn` net actor + `Chan` Data events (Bend-native B) |
| D3 | UTF-8 TCP vs byte-exact foreign TCP? | Base `TCP.send`/`recv` strings; `Fr.push` octet laws kept |
| D4 | UI loop `@unsafe` vs fuel? | `--frames N` fuel; `frames=0` live `@unsafe` idle |
| D5 | Keep a C demo binary during transition? | No — deleted at M5.8 |
