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
| `src/ffi/birc_main.c` | `main` → `bend_main` (argv is Bend `IO.args`) |
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
- [x] **P6** Live path uses Base `TCP.send` / `TCP.recv` (`String`). ASCII IRC, including SOH, is one byte per codepoint. `recv` parks until data. `frame.push` stays the octet framer for laws; live framing is `push_text`.
- [x] **P7** Fuel for open loops: UI/net loops take `Nat` fuel (`ui_loop_trust`; `--frames` / `App.budget`).

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
- [x] **M4.9** Reconnect / backoff: `next_backoff` (double+cap) + fuel-bounded `dial` retries with `IO.sleep`

**Exit:** `make test-net` + live connect path.

---

## Milestone 5 — View model + TimUI draw FFI

- [x] **M5.1**–**M5.2** `view.bend` ViewModel + scroll math / bounds law
- [x] **M5.3** Rich-text tokenization: `TextSpan` Plain/Bold on `*…*` (`tokenize` / `show_spans`)
- [x] **M5.4** Coarse draw: whole layout painted inside one `Timui.frame` (D1)
- [x] **M5.5** Minimal Quit event path: `Timui.events` → `List UiEvent` (`Quit{}`); `ui_loop` folds via `has_quit`
- [ ] **M5.6** Full begin-event Key list / fine-grained fold — **deferred**: returning `Frame & List<UiEvent>` from `Timui.begin` needs multi-handle IO binds Bend cannot unpack cleanly today; Quit latch covers Escape/should_quit.
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

- [x] **M8.0.1** Freeze `BodyLine` / `Span` / `Tab{name, active}` in `view.bend`. `show_vis` becomes a test-only debug dump, not the live paint path.
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

- [x] **M8.4.1 `UiCmd` Data:** `Noop{}` / `TabNext{}` / `TabPrev{}` / `TabSet{i}` / `ScrollBy{n}` / `HistPrev{}` / `HistNext{}` / `Submit{}` / `Quit{}`. FFI latches **one product per frame** (already `Timui.keys`); extend it or return `UiCmd` list. Prefer a small product of counters (`tab: U32`, `scroll_delta: I32` or two `U32`s, `hist: U32`) over a C-side state machine.
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
- Prefer **less code**. A `List BodyLine` that C walks beats a second stringly layout language.

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

## Open decisions (resolve in M0/M4)

| ID | Question | Default |
|---|---|---|
| D1 | Coarse `draw_frame(ViewModel)` vs fine-grained widget FFI? | Coarse (`Timui.frame` paints whole layout) |
| D2 | Net concurrency model A/B/C? | `IO.spawn` net actor + `Chan` Data events (Bend-native B) |
| D3 | UTF-8 TCP vs byte-exact foreign TCP? | Base `TCP.send`/`recv` strings; `Fr.push` octet laws kept |
| D4 | UI loop `@unsafe` vs fuel? | `--frames N` fuel; `frames=0` live `@unsafe` idle |
| D5 | Keep a C demo binary during transition? | No — deleted at M5.8 |
