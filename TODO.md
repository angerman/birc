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
- [x] **M7.3** Repeatable, bounded ASan gate for the project UTF-8 bounds helper. On
      Darwin arm64, LLVM ASan hangs during interceptor startup (LLVM #58503), so
      the gate reports an explicit unsupported skip; it does not claim coverage.
- [x] **M7.4** Full generated application under UBSan with the hostile pty corpus.
- [x] **M7.5** Default-off production frame phase profiler plus repeatable idle,
      paint-wake, join-latency, and 8-buffer x 256-line scale gates. Measurement
      found terminal backpressure in the profiler, not the product: continuous
      drain reduced mean `timui_end` from 7.2-13.7 ms to 0.7-2.0 ms. Five final
      scale runs reached first paint in 72-86 ms and completed in 1.18-1.21 s;
      no product optimization was justified.
- [x] **M7.6** Broader file and live pty adversarial corpus: tags, NOTICE, empty
      trailing params, unknown numerics, IRC line boundaries, bare CR, Latin-1
      fallback, C0 sanitizing, fragmented input, cap floods, bursts, resize,
      PONG recovery, paint recovery, and tty restoration.

The original history has only the combined M7.3-M7.6 label above. These four
items reconstruct it in that label's category order; no older expanded list was
found in reachable commits, reflogs, or repository documentation.

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
      Bend expands logical chat lines into visible rows from the live pane
      width. C still clips each emitted row at `maxx` as a final guard.
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
- [x] **K2** Implemented K1. Deleted `birc_wait_fds`, the Ui self-pipe,
      `wake_poke`, `fd_hint`, `wait_ms` / `wake_fd`, and the hot window.
      `input_poll_ms` stays 0 (still read by `timui_begin`). Added
      `Socket.shutdown`, `Socket.dup`, non-blocking `recv_nb`, the tty dup,
      and the `SIGWINCH` pipe. C lines before (`f34bbc9`): 666 + header 15.
      After: `clock_ffi.c` 22, `dns_ffi.c` 149, `timui_ffi.c` 629 = 800,
      header still 15. `timui.h` vs `ac97be1` is 207 insertions and 56
      deletions; K2 does not edit it. `gen_eof.py` and the parked `--demo`
      CPU sample (`tickrate.py`) each passed three times. `/connect` while
      `Connecting` does not wait out a parked `TCP.connect`.
      `Tty.ready` and `Winch.ready` are one C function (`fd_ready`).
      `recv_octets` / `recv_nb` already share `recv_try`. `timui_frame_run`
      has no dead wait loop; the 50 ms poll is the lone-Esc timeout.
      Lines stay clock 22, dns 149, timui 629 (800) + header 15. The old
      `birc_wait_fds` / `wake_poke` were smaller than the dup, the winch
      pipe, and that Esc poll, so the total is still above 666.
- [x] **K3** `recv_octets` is `io_eff(..., IO_READ)`. DNS keeps `recv_nb`
      (`io_eff` flags 0); `wait_ans` calls `recv_nb` and not
      `recv_octets`. No timer actor. Peer check is `Wire.peer_ok` (host
      equals the nameserver and port 53), still covered by `dns_demo`
      (`peer_ok`, `peer_ip`, `peer_port`, `take_peer`). `recv_try`
      clamps `max` to 4096 and treats `EINTR` like `EAGAIN` (park again,
      or `None` on the DNS path). `dns_timeout.bend` looks up
      `example.test` at `192.0.2.1` and prints `dns_timeout=ok` in
      3.915 s (`timeout` from fuel 80). `timeout 15` wraps it in check.
- [x] **K4** Pty numbers, before `f34bbc9` and after `a4f30e5`. Load was
      about 30. Idle gate is the marginal sample (not cpu_pty's cumulative
      rusage, which includes process start).
      Before: `--demo --frames 20` drained in 20.70 s = 0.97 frames/s,
      0.53% CPU. A quiet window still wrote 13254 / 25945 bytes.
      `tickrate_pty.py 600` hit its 120 s kill; its printed 5 ticks/s
      uses the requested count, so it is not a measurement.
      cpu_pty idle 0.5% / 0.7%, flood 33.4% / 50.1%. ratecpu 1 msg / 1.5 s
      1.1%. Key min 4.1 ms. Resize min 542 ms. join 33.7 ms, paint 42.5 ms,
      redial min 90.1 ms.
      After: quiet window 0 bytes and 0.00% at 30x100 and 82x159 (0 frames,
      process stayed up). tickrate marginal 0.00% / 0.01%. cpu_pty idle
      0.6% / 0.5% cumulative, flood 17.9% / 33.2%. ratecpu 0.7%. Key min
      10.2 ms. Resize min 6.2 ms. join 1.2 ms, paint 8.1 ms, redial 1.6 ms.
      Gates: idle ≤ 0.3% and 0 frames, traffic ≤ 1%, latencies ≤ 100 ms,
      resize ≤ 1.1 s. The 100 line/s flood is not that traffic gate.
      Full pty set after: `build/review/wo3/fdready-check.log` exit 0
      (includes many_eof, bpaste 300, paste50 300, composer, rst, tinyquit,
      tall_rows, gen_eof, close_then_quit).
- [x] **K5** UBSan: `clang -fsanitize=undefined -fno-sanitize-recover=undefined`
      then `build/review/review77/hostile.py ./build/birc_ubsan`.
      `exit=0 killed=False restored=True`. No `build/ubsan.log*` file,
      so 0 reports. `make lint-ffi` in `fdready-check.log` printed no
      compiler warning. `AGENTS.md`, `docs/FFI.md`, and `README.md`
      describe the parked frame, not `wait_ms` / `wake_fd` / `fd_hint` /
      `wake_poke`.

---

## Milestone 12 — C FFI review

Same rules as M11 (TDD red on `c10b967`, one item per commit, `make check`
green, GOLDEN CHANGE, three consecutive pty runs, never push). Review:
`build/review/reports/ffi2.md`. Repros: `build/review/ffireview/`.

### Part 1 — bugs

- [x] **F1** Stalled terminal must not freeze the loop. Frame write gets a
      deadline; on timeout drop the frame and full-redraw next. `stall.py`:
      PONG while the tty is stalled, then a correct screen after drain.
      On `c10b967` the PONG did not arrive (`PONG while tty stalled: False`).
- [x] **F2** Esc split across reads must not apply keys twice. Remove the
      lone-Esc block; park the tty watcher 50 ms when Esc is pending.
      Lone Esc still quits. `\x1b` then `[A` after 10 ms is one Up.
      `esc_up.py` three times inside the test.
- [x] **F3** Paste: invalid UTF-8 before CR must not swallow Enter. Stash a
      tail only when every remaining byte is a continuation.
- [x] **F4** Paste: expanding invalid bytes to U+FFFD must hold, not drop.
      Also held focus events, a lost stashed prefix, and `paste_skip_lf`
      in the vendored-patch list. `paste_harness.c` in `make check`.
- [x] **F5** URI buffer matches TimUI's 256. Longer URLs are a plain span.
- [x] **F6** SIGWINCH saves errno and sets `SA_RESTART`. `Winch.close`
      clears the write fd before `close`. `send_octets` reports errno,
      `EMSGSIZE`, or `EINVAL`. `winch_open` saves errno before `close`.
      `birc_str_list` drops names past 16. `watch_go` closes Winch if
      `Timui.tty` fails. `timui_open` returns the TimUI result code.
- [x] **F7** Lint stub covers the seven watcher CIDs and `IO_READ`.
      `-Wconversion -Wsign-conversion -Wcast-qual -Wshadow` stay clean.
      The stub says it is syntax-only.

### Part 2 — shrink the C

- [x] **S1** Lone-Esc block removed with F2.
- [x] **S2** `UiKeys.more` replaces `birc_input_left`. Bend posts `Key{}`
      when `more` is set.
- [x] **S3** C returns the raw key, mods, and wheel. Bend maps tab, page,
      history, and quit (`Sess.key_pol`, locked by `key_pol_ok`). The
      `page` argument of `Timui.frame` is gone.
- [x] **S4** Timestamp is an ordinary `OpText`. `OpLine` drops `ts`.
      A stamp wider than the line is clipped to the line (`line_ts_ok`).
- [x] **S5** Dead `CID_CON` / `CID_UIKEYS` guards, `io_cstr` NULL checks,
      duplicate focus, the no-op composer fit, and the `INT32_MAX` recv
      clamps are gone. `birc_frame_out` is `birc_uikeys`. The tab `sel`
      clamp stays: Bend does not prove `sel < len(names)`.
- [x] **S6** No tty `dup`. `Timui.tty` returns the Ui read fd. `Tty.close`
      does not close it.
- [x] **S7** `docs/FFI.md` matches close order, watcher lifetime, and
      the tty fd. The `timui_ffi.c` header no longer claims budget/config.
      The vendored-patch list names `paste_skip_lf` and held `paste_len`.

---

## Milestone 13 — DNS Fault-Tolerance & Architectural Hardening

- [x] **D1** Treat non-matching or malformed DNS UDP packets (`bad id`, `bad dns`, `short`) as `Miss{}` so extraneous traffic does not fatally abort resolution (V-02).
- [x] **D2** Fail closed with a clean error when no nameserver is available instead of leaking queries to 1.1.1.1 (V-11).
- [x] **D3** Add `/close` command to cleanly close query tabs without sending invalid `PART` to IRC daemon (V-09).
- [x] **D4** Trigger immediate redraw on `SIGWINCH` resize to prevent stale viewport rendering (V-06).
- [x] **D5** Handle temporary unavailability (437) registration rejections by retrying with nick_ (V-08).
- [x] **D6** Alert active tab when incoming private messages are dropped due to buffer capacity limit (V-03).
- [x] **D7** Rewind DNS Answer traversal upon encountering CNAME records to handle out-of-order A records and self-loop guards (V-10).
- [x] **D8** Use non-intercepted loopback (127.0.0.2) in DNS fuel timeout test to prevent false rcode failures under VPN/Tailscale MagicDNS.
- [x] **D9** Immediate redraw on view-changing keys/clicks (Shift-arrows, tab clicks, PageUp/Dn, history, enter) so 1 press/click switches tabs and updates views without lag (`tests/pty/tab_switch.py`).
- [x] **D10** Drop artificial background color fill on panels, nicks, messages, hints, and composer by resetting theme slot backgrounds to `TIMUI_COLOR_DEFAULT`, letting the terminal's native background show through cleanly.
- [x] **D11** Move channel headline/topic to the top border of the main text window (`br`), using the channel name (`#channel`) on the nick list header (`nr`), eliminating header truncation.

---

## Milestone 14 — Enhanced IRC Client Capabilities

- [x] **M14.1** Nick coloring: deterministic hash palette for nicknames in chat lines (`<nick>`), actions (`* nick`), and sidebar nicklist.
- [x] **M14.2** Nick mute / ignore: `/mute <nick>`, `/unmute <nick>`, `/mutes`, per-channel/server scoping, dynamic view-time filtering (messages reappear on `/unmute`), and settings dashboard integration.
- [x] **M14.3** Configurable scrollback expansion: raise `SCROLL_CAP` to 1,000 lines and default `hist_cap` to 500 lines (~50–100 KB).
- [x] **M14.4** `/reconnect` command: re-establish connection to the saved server and port with the saved nick/channel after disconnect.
- [x] **M14.5** Status indicator colors: render "online" in green and "offline" in red in header bar.
- [x] **M14.6** Auto-reconnect: live connections default to a cancellable two-second reconnect on the saved server and port, with a configurable settings toggle (`autoreconn: ON|OFF`). Reconnect-off closes the actor's writer socket immediately, so the next heartbeat cannot produce a second `send failed` error.
- [x] **M14.7** Query / Private message buffers: `/query <nick> [text]` to initiate private 1-on-1 chats in dedicated tabs, send initial messages, and `/close` to dismiss.
- [x] **M14.8** Mentions & highlights: highlight messages mentioning own nick in Gold (`#FFD700`), with configurable terminal bell (`bell: ON|OFF`) in `/settings`.
- [x] **M14.9** Unread activity badges: visual activity (`*`) and mention (`!`) indicators on background tabs, automatically cleared upon switching to the tab.
- [x] **M14.10** SASL PLAIN authentication: plaintext base64 SASL authentication on connection handshake (`CAP REQ :sasl`).
- [x] **M14.11** IRCv3 `server-time`: parse message tag timestamps (`@time=...`) for accurate bouncer/scrollback timing.
- [x] **M14.12** Link opener (`/open [n]`): open detected URLs via external system launcher (`open` / `xdg-open`).

---

## Milestone 15 — Everyday Ergonomics & Quality-of-Life

- [x] **M15.1** Nick & Slash-Command Tab Completion: `Tab` in composer cycles completions for nicknames from active channel nicklist and `/commands`.
- [x] **M15.2** Interactive URL Picker (`/links` or `Alt-O`): pop-up HUD listing extracted URLs from recent chat with author/timestamp context to quickly select and open.
- [x] **M15.3** Live Server Latency / Lag Meter: heartbeat `PING`/`PONG` round-trip latency counter displayed in status bar (`online · 34ms`).
- [x] **M15.4** In-App Mouse Selection & System Clipboard: pane-scoped drag selection in body and nick list with reverse video highlight, automatic copy to OSC 52 and `pbcopy` on release, Esc dismissal without quitting, and mode 1002 button-motion tracking (`tests/pty/mouse_select.py`).
- [x] **M15.5** Parley Server Compatibility & Polish: `CAP LS 302` initial handshake, default nick alignment to `--sasl-user`/`BIRC_SASL_USER`, silent handling of server `CAP` replies, gold `#FFD700` `❯ ` composer prompt, and dynamic Unicode `─` centered reconnect divider.

---

## Milestone 16 — Next-Gen Terminal Visuals & Advanced Capabilities

- [x] **M16.1** Original Kitty Graphics Protocol Image Viewer checkpoint:
      `/preview <local-path>` opened local PNGs, with a two-image cache and
      explicit HTTP(S) rejection. M18 supersedes these limits with general
      local formats, bounded remote fetching through the provisioned helper,
      an eight-image cache, inline layout, and terminal-side animation.
      IRC remains plaintext; the C edge does not perform image networking.
- [x] **M16.2** Split-Screen Dual Buffer View: side-by-side or stacked dual-channel tiling (`/split`) using TimUI split panes.
      `/split`, `/vsplit`, `/split-off`, `/unsplit`, and `/focus` use existing
      buffers only. F6/Ctrl-W changes the focused pane; send, scroll, nick list,
      status, page size, and mouse selection follow that focus. Bend owns split
      state and absolute drawing geometry. C interprets `OpSplit` through TimUI
      and keeps mouse selection within the selected pane.
- [x] **M16.3** Parallel Scrollback Search / Fuzzy Grep: Bend parallel tree-search over message history across all buffers (`/search <query>`).
      `BIRC_SEARCH_PROFILE=serial|parallel tests/perf/search_profile.bend`
      times tree build and scan separately at the production maximum
      (16 buffers x 1,024 lines). Five alternating warm runs measured
      serial 24-25 ms vs parallel 6-7 ms before fuzzy matching, then
      serial 21-22 ms vs parallel 5-7 ms after it. The parallel hypothesis held.
- [x] **M16.4** IRCv3 Live Typing Notifications (`+typing`): request
      `message-tags`; parse `active`, `paused`, and `done` `TAGMSG` events;
      render active participants above the composer; expire active state at
      6 s and paused state at 30 s with wrap-safe Bend clock arithmetic; clear
      on messages (including muted messages), PART, KICK, QUIT, and NICK; and
      cap transient state at 32 participants. Pure boundary/lifecycle tests,
      laws, and a non-vacuous loopback PTY test cover the live path.
- [x] **M16.5** Terminal notification alerts: background activity tabs use
      reverse video; mentions and private messages use a gold tab; each
      high-priority event advances a Bend-owned sequence that emits one BEL
      when `bell` is enabled. Repaints never replay a bell.
- [x] **M16.6** Interaction and wrapping follow-up: activating a buffer clears
      its `*`/`!` unread state; clicking a rendered chat link returns its exact
      URL through `UiKeys` for Bend to open; and Bend soft-wraps visible chat
      rows with a timestamp/nick hanging indent and resize-time reflow.

---

## Milestone 17 — Adversarial review remediation

Review baseline: `a0a8941`. A checked item means the fix and its regression
tests passed. Work is local; no upstream push is authorized. Keep existing
laws and test expectations. Prefer one canonical operation over parallel
implementations. Every changed PTY test must pass three consecutive runs.

### Runtime and shutdown

- [x] **R01 — Bounded, cancellable outbound work (P1).** Break the cycle
      between a full command queue, a blocked TCP writer, and a full event
      queue. Keep `/quit` and disconnect usable when a peer stops reading.
      Test normal sends, a non-reading peer, queue saturation, and shutdown.
- [x] **R02 — One terminal output deadline (P1).** Apply the bounded frame
      transport to BEL and OSC 52 as well as ordinary painting. Move blocking
      clipboard work outside the shared IO loop. Test an unread full PTY with
      alerts and selection; network PONG and shutdown must still proceed.
      Include an already-full PTY before TimUI opens, with shared and
      independent output descriptions; initial screen writes must be bounded.
- [x] **R03 — One frame-result handler (P2).** Handle clicked URLs and keys
      from every paint, including resize, incoming chunks, EOF, and redraws.
      Test clicks with and without concurrent resize/inbound traffic.
- [x] **R04 — Reconnect registration identity (P2).** Carry the current nick
      into a new connection instead of the actor's startup nick. Test an
      acknowledged `/nick`, reconnect, and normal initial registration.
- [x] **R05 — Reap URL launcher children (P2).** Own launcher lifetimes and
      report launch failure without blocking painting. Test repeated opens,
      failed launches, and absence of zombie children.
- [x] **R06 — Real outbound cap and simpler actor (P2).** Enforce `SEND_CAP`
      per actor tick and preserve pending lines through close/fuel exhaustion.
      Remove dormant `Tick`/`Handoff` and obsolete merge paths if unused.
      Test exact cap boundaries, FIFO order, and delivery of `/quit`.
- [x] **R07 — Coalesced UI continuation wakes (P1).** Keep synthetic input
      continuation wakes separate from real tty-watcher acknowledgements.
      The UI must not synchronously send to its own full event queue. Coalesce
      pending continuation work and preserve paste/network fairness without
      adding Session fields. Test normal acknowledgement, two synthetic wakes,
      a full event queue, mixed incoming chunks/paste, PONG, and quit.
- [x] **R08 — Recover refused terminal frames (P1).** A bounded write may
      leave the display incomplete. Wake the UI when output can proceed;
      do not park forever or spin while output remains full. Keep typing
      expiry and network work independent. Test partial output, recovery,
      unchanged typing lifecycle, PONG, and shutdown under backpressure.

### DNS and startup

- [x] **D01 — DNS-over-TCP framing (P1).** Read the two-byte length and the
      complete bounded payload across arbitrary receive boundaries. Reject
      false lengths, premature EOF, and trailing/malformed data. Test a split
      prefix, split body, valid packet, and bad length.
- [x] **D02 — DNS deadlines and one startup lookup (P1).** Bound DNS connect,
      send, and receive; a silent peer must not park startup forever. Remove
      duplicate preflight resolution and show failure through normal session
      startup. Test silence, refusal, success, and UI responsiveness.
- [x] **D03 — Truncation fallback and CNAME bounds (P2).** Fall back to TCP
      when a truncated UDP answer has no usable A record. Keep compressed
      CNAME reads within their declared RDATA. Test complete A answers,
      truncated CNAME-only answers, zero-length and overrun RDATA.
- [x] **D04 — Await the headless startup result (P1).** Non-tty input EOF
      must not turn a pending or refused connection into exit-zero success.
      Keep tty startup responsive. Test healthy registration, refusal,
      pending startup, and the existing headless termination fixture.

### State, history, and rendering

- [x] **S01 — Canonical bounded logging (P1).** Route buffer-cap warnings
      through the same capped append as all other logs. Test more than 1,024
      rejected remote buffer creations and ordinary accepted creation.
- [x] **S02 — Read the latest history (P2).** Read to EOF with bounded retained
      state rather than stopping after the first MiB. Test a file above one
      MiB, its newest record, empty files, and malformed records.
- [x] **S03 — Persist stable log events (P2).** Stop inferring events
      from equal capped snapshots. Preserve duplicate messages with identical
      timestamps at the cap, without replaying old records. Test duplicates,
      no-op paints, purges, and buffer renames.
- [x] **S04 — History endpoint identity (P2).** Prevent one server's history
      from entering another server's buffers. Define and test legacy-file
      handling, distinct endpoints, and reconnect to the same endpoint.
- [x] **S05 — Explicit reconnect marker (P2).** Give reconnect dividers a
      distinct kind instead of recognizing arbitrary `Reconnected:` text.
      Test real markers and ordinary chat containing that text.
- [x] **S06 — Structured line authors (P2).** Store author identity instead
      of reparsing display prefixes. Use IRC case folding for mute/purge.
      Test messages, notices, actions, mixed case, and unrelated authors.
- [x] **S07 — Typed unread levels (P2).** Replace `!`-prefixed buffer-name
      encoding with explicit alert state. Test a real `!ABCDEroom` channel,
      mention escalation, and clearing only the selected buffer.
- [x] **S08 — Query rename collisions (P2).** Merge or otherwise uniquely
      identify queries after NICK changes; update nick lists and focus.
      Test an old query colliding with an existing query and normal rename.
- [x] **S09 — Legal nick `server` is not the control buffer (P2).** Keep
      index zero's role separate from the query's display name during NICK,
      QUIT, unread handling, and history serialization. Use the invalid IRC
      nick `*server*` as the persisted control target. Test both buffer roles,
      rename collisions, and history isolation without a new role framework.
- [x] **S10 — Preserve anchors through edits (P2).** Purging newer messages
      or merging queries must not move a retained viewport anchor. Recompute
      its message position from stable IDs, preserve its character position,
      and keep the active query's viewport. Test older/newer purge, both merge
      directions, and removal of the anchor itself.
- [x] **S11 — Visible history IO failures (P2).** Keep an absent optional
      history file silent, but report other open, size, and read failures.
      Preserve completed records and close the handle before reporting.
      Document the pinned size API's 4-GiB boundary. Test ordinary files,
      metadata-only sparse overflow, read failure, and missing-file success.
- [x] **S12 — Split pane identity for legal nick `server` (P2).** Use the
      invalid nick `*server*` as the internal control-pane key. Keep a private
      query's pane contents, focus, and send target consistent. Retain the
      `/split server` control alias only when no such query exists. Test
      query/control panes, both focus directions, normal channels, and removal.
- [x] **S13 — Canonical mute targets and channel boundaries (P2).** Normalize
      status-prefixed targets before mute lookup. Use the shared channel-type
      rules for generated mute patterns, restored history, and removal. Test
      muted/unmuted `#`, `&`, `+`, and `!` channels, `@#room`, unmute, and a
      different nick that shares the muted nick's prefix.
- [x] **S14 — Preserve split panes through query rename (P2).** A remote NICK
      renames a still-open query; it does not close that pane. Update pane keys
      before normalization, preserve focus, and keep control identity distinct.
      Test focused/unfocused panes, rename chains and IRC case folding, real
      close, and rename collisions that coalesce two panes.
- [x] **U01 — Token-aware, column-aware wrapping (P2).** Tokenize a logical
      line once; preserve complete URL targets and formatting across rows.
      Wrap using terminal column widths, including wide/combining text.
      Test split URLs, Markdown spans, CJK, narrow widths, and resize.
- [x] **U02 — One scroll coordinate system (P2).** Make clamping, view slicing,
      arrival anchoring, and resize use consistent coordinates. Test one long
      wrapped line, reaching its first row, new arrivals, and width changes.
- [x] **U04 — Source-length anchors for replaced clusters (P2).** A one-column
      placeholder can represent several source codepoints. Keep source length
      separate from rendered length so widening a paused view does not move
      into a later emoji cluster. Test one-column replacement, unchanged-width
      navigation, and widening with the preceding character anchored.
- [x] **U03 — Stable URL enumeration (P2).** Use one URL tokenizer for links
      and opening. Keep `/links` output out of its own source collection and
      preserve numbering. Test repeated listing, `/open 1`, code spans, and
      punctuation boundaries.
- [x] **U05 — Preserve UTF-8 across partial terminal writes (P2).** A frame
      deadline can stop inside a scalar. Finish that scalar before accepting
      a later escape sequence or payload. Bound any retained transport suffix
      and share the rule with teardown. Test short writes at each byte boundary,
      blocked recovery, ordering, and the unchanged Unicode tab fixture.
- [x] **U06 — Signal-safe suffix ownership (P2).** A signal can arrive after
      write accepts bytes but before accounting owns their missing suffix.
      Prevent the handler and normal writer from claiming the same bytes or
      emitting escapes past unknown debt. Keep handler work async-signal-safe
      and bounded. Test staging, pending flush, returning handlers, concurrent
      delivery, and preservation of nonblocking descriptor flags.
- [x] **U07 — Final status cannot bypass terminal debt (P2).** TimUI can close
      with a retained suffix when its teardown budget expires. Final success
      or error text must not follow that incomplete scalar after Ui is freed.
      Preserve stream identity and the existing final-output budget; test
      blocked/drained output, redirected output, and descriptor reuse.
- [x] **U08 — Literal unmatched formatting markers (P2).** Preserve source
      order when an unclosed `*`, `_`, or backtick falls back to plain text.
      Test each opener, prefixed text, empty/trailing markers, and normal closed
      formatting. Keep the documented literal fallback rather than copying
      upstream's unterminated-style behavior.
- [x] **U09 — Keep code-span dim styling (P2).** Recognizing backticks must
      produce the dim attribute promised by M8.2.4 and upstream IRC parity.
      Test tokenizer spans, wrapped DrawOps, and actual native style emission;
      do not add a new theme or Markdown framework.
- [x] **U10 — Bound local PNG decoding before allocation (P2).** File size
      and IHDR dimensions do not bound declared IDAT allocations or zlib
      expansion. Check chunk availability before allocation and cap inflated
      data using supported PNG depth, channels, filters, and Adam7 geometry.
      Avoid repeated work for permanently malformed data. Test normal and
      interlaced images, malformed chunks, expansion beyond the declared
      image, allocation failure, cache behavior, and cleanup. Scope is explicit
      local Sixel preview, not remote fetching or a measured frame-time breach.
- [x] **U11 — Free PNG intermediates on allocation failure (P2).** A failed
      16-to-8-bit conversion leaks its owned input. Keep cleanup with existing
      owners rather than adding a separate resource layer. Deny each allocation
      in small valid images, require zero retained bytes, and verify a later
      successful decode.
- [x] **U12 — Safe loaded-handler lifetime across close (P2).** Clearing
      the global signal context does not revoke a handler that already loaded
      Ui on another thread. Prevent use of freed storage and reused borrowed
      descriptors without an unbounded close wait. Test a real paused handler
      across close, a returning handler, and ordinary restoration/cleanup.
- [x] **U13 — Re-arm bounded output after a returning signal (P2).** A handler
      can restore a shared descriptor to blocking between bounded payloads,
      including during memory-only frame capture. Re-borrow nonblocking output
      before the next physical write and preserve its original flags. Test
      two payloads on a nearly-full pipe, capture-phase delivery, separate
      descriptions, prompt completion, and final flags.
- [x] **U14 — Charge successful short writes to the shared deadline (P2).**
      A writer must not retry indefinitely just because every syscall accepts
      some bytes. Check the unchanged deadline between retries and between
      serialized-frame drain calls. Preserve one immediate nonblocking attempt
      for zero-wait callers. Test advancing time with successful short writes,
      a future-deadline control, and finite frame progress across later ticks.

U12 checkpoint (`c2e6b59`, source `6090abe`): a lock-free lifetime claim precedes
the installed handler's Ui load and ordinary close/free. The restore owner
holds stable CLOEXEC input/output references. A busy close retains at most one
complete Ui/BircUi owner; final exit never waits, uses its existing deadline,
and suppresses same-stream status if ownership remains unresolved. Immutable
host restoration uses saved flags and termios without freeing the active Ui.
Actual paused-handler controls cover storage/fd reuse, returning and late
handlers, bounded unresolved exit, and redirected output.
The same probes found two remaining U06/U07 seams: short resync/sync-end writes
cleared debt, and a short title-pop cleared title ownership. Accepted-count
guards now retain those obligations on refusal/partial write; complete writes
discharge them and close does not double-pop a title. No retry or new budget
was added. Root `make proof test-output-shutdown test-output-progress
test-output-utf8 test-ubsan-native lint-ffi` passed in the locked shell.
The agent's fresh `make build-ui test-ui test-pty-restore test-pty-tabcut` also
passed. This is signal-versus-close safety, not generic concurrent Ui support.

### Commands and authentication

- [x] **C01 — Parsed, stateful SASL (P1).** Recognize CAP/AUTHENTICATE/numerics
      from parsed IRC messages and only in the expected authentication phase.
      Test protocol success/failure plus chat containing `AUTHENTICATE +` or
      ` 903 `; chat must remain chat and cannot trigger credentials.
- [x] **C02 — UTF-8 and SASL chunks (P2).** Encode PLAIN credentials as UTF-8
      bytes with the existing encoder. Send at most 400 Base64 characters per
      AUTHENTICATE line and a final `+` for an exact multiple. Test ASCII,
      non-ASCII, 399/400/401 boundaries, and IRC line limits.
- [x] **C03 — Local commands while offline (P2).** Classify commands once by
      whether they need a connection. Allow settings, search, preview, buffer
      controls, and disabling auto-reconnect while offline/connecting. Test
      both states and reject actual wire commands there.
- [x] **C04 — No wire targets for synthetic buffers (P2).** Use one sendable
      buffer predicate for plain chat and `/me`/related commands. Test settings
      and other synthetic buffers plus valid channels and queries.
- [x] **C05 — Remove proven redundant plumbing.** Remove repeated empty-arg
      guards and duplicate marker/URL/command operations as their canonical
      replacements land. Do not add abstractions without a second real use.
- [x] **C06 — Keep the requested demo identity (P2).** Demo welcome data
      hard-codes `me` and replaces the requested `--nick`. Generate demo data
      for the requested nick while retaining the default fixture for existing
      goldens. Test default and custom demo nicks and later registration.
- [x] **C07 — Complete CTCP ACTION envelopes (P2).** Reserve the whole `/me`
      envelope before fitting UTF-8 body bytes. Never clamp away the final SOH.
      Echo only the transmitted body and reject a target whose empty envelope
      already exceeds the line limit. Test short, exact, overlong, multibyte,
      partial-scalar, control-stripped, and oversized-target cases.

### Verification and build driver

- [x] **V01 — Honest proof scope and preservation laws.** Separate concrete
      examples from quantified guarantees in README/law comments. Strengthen
      useful preservation/boundary laws without weakening existing laws.
      Run `bend PROOF.bend`; report the independent kernel gate separately.
- [x] **V02 — Golden tests check process status.** Replace `binary | grep`
      checks with a common bounded runner that checks both exit status and
      the expected token. Test token+exit-42 rejection and token+exit-0 success.
- [x] **V03 — Complete incremental dependencies.** Track FFI helper headers,
      the lock file, and effective compiler flags/toolchain identity. Test
      `make -n -W src/ffi/birc_utf8_fit.h build-ui` and changed build flags.
- [x] **V05 — Portable source links.** Replace developer-specific `file:///`
      links in README with repository-relative paths. Check each target exists.
- [x] **V06 — Current architecture and test claims.** Remove stale source/test
      counts, name canonical URL/auth/column modules, and separate Bend checks
      from the independent kernel gate. Make warning lint fail on warnings
      rather than only claiming it does. Replace unsupported whole-client,
      zero-poll, and production-hardening claims with the actual bounds and
      one-second maintenance behavior. Verify the documented lint flags.
      Final docs review also corrected `/part [channel]` and `/close [buffer]`
      scope, listed existing link/settings commands, and stated total image
      frame-pixel and envelope bounds from the helper constants.
- [x] **V07 — Isolate desktop helpers in selection tests.** Existing mouse
      and split-selection tests inherit PATH and can call the desktop
      clipboard helper. Use a fixture-only helper path without changing test
      expectations. Run each changed PTY three times before commit.
- [x] **V08 — Run the existing server-time integration guard.** The standalone
      `server_time_demo.bend` was absent from Make/check; direct tag-extraction
      laws did not exercise `Irc.parse`→`msg_time`. Add `test-server-time` to
      the central driver and review gate. Its unchanged time/multi-tag/no-tag
      assertions pass in the locked shell.
- [x] **V09 — Bound legacy terminal-test recipes.** Forty older scripts had
      no outer deadline, even though some use unbounded drain/cleanup loops.
      Add a 150-second recipe bound without changing their assertions. A new
      dry-run guard rejects missing, zero, and nonfinite timeouts and accepts
      direct/Nix/shell-wrapped bounds. It was red on the old driver and is
      green for all 63 commands at that checkpoint (64 after P21). This is a
      missing test bound, not a claim that a program hang was reproduced.
- [x] **V04 — Integrated verification and handoff.** Run the full pinned
      `make check`, sanitizer checks, and three runs of every changed PTY test.
      Record exact commands, outcomes, limits, and local commit IDs here.

Final-tree checkpoint at `829d9ce`: locked `timeout 3600 make -k check`
completed with exit 0 on 2026-10-01, from 06:05:42 to about 06:24:23 UTC.
Proof, all model/native/network guards, all 64 planned PTY commands, warning
lint, and paste checks pass. Log:
`build/review-final-check-wake-20261001.log`. App SHA-256:
`e841f1caa67e017f5bb0cf827d3af5d4b96f6a797ea638f85585fa498930d9dc`;
output-limit fixture binary:
`f7e3fdc34e24d3cf36c05fb7aae98ef05b015fbdc2383033f4ce537ad5b6b51c`.
This is whole-PTY round one. Round two also passes: locked
`timeout 1500 make -k -o build/birc -o build/birc-output-limit test-pty`,
06:26:09–06:33:42 UTC, exit 0. All 64 commands match the dry-run plan in order;
HEAD and both binary hashes are unchanged. Logs:
`build/review-final-pty-2-20261001.log` and
`build/review-final-pty-2-coverage-20261001.log`.
Round three uses the same command and passes with exit 0,
06:34:42–06:42:13 UTC. Log: `build/review-final-pty-3-20261001.log`.
Its HEAD and binary hashes remain unchanged; no pins or existing assertions
changed.
Independent coverage comparison confirms all 192 planned recipe executions:
64 commands per round, with exact order in all three. Evidence:
`build/review-final-pty-three-coverage-20261001.log`.

Final locked sanitizer/hardening command:
`timeout 2400 make -k -o build/birc -o build/birc-output-limit -W build/birc_bend.c test-sanitizers check-hardening`.
It starts at 06:49:22 UTC; exit 0 is confirmed at 06:54:40 UTC, with the last
raw output at 06:53:18 UTC. The forced fresh UBSan app
build uses current generated C and FFI; production binaries stay unchanged.
UBSan app SHA-256:
`576c1f74b172cd841cc435eb1a1454c743a4950bc5eaa1dd5a54ee52320908fb`.
Full-app hostile input, native UTF-8/shutdown/progress, PNG bounds and allocation
cleanup, media cache/animation/FFI, proof, protocol parity, and performance gates
pass. Idle CPU is 0.00% at both sizes; paint/JOIN are 5.9/0.7 ms against their
unchanged 100-ms limits. The 8-buffer, 256-line scale replay is ready in
351.1 ms and completes in 1441.9 ms. Log:
`build/review-final-hardening-locked-20261001.log`.
The first attempt failed only because the reconstructed PATH lacked
`dsymutil`; its log is `build/review-final-hardening-environment-20261001.log`.
Adding `/nix/store/chm6n1f020n71ykanbpbxya4izw3pzc0-llvm-21.1.8/bin`
from the exact locked Clang closure fixes that environment without changing
flags, tests, source, dependencies, or pins.

Verification limits remain explicit. ASan's compiled probe reports
`unsupported` on Darwin arm64 because its runtime hangs during startup;
this is not ASan coverage. Separate `timeout 310 make proof-kernel` returns
exit 2: Lean is absent from PATH, and Bend requires Lean v4.34.0 or a built
`BENDTT` kernel. The locked nixpkgs offers v4.30.0; no toolchain was installed
or pin moved. Log: `build/review-final-proof-kernel-20261001.log`.
The normal Bend checker reports `ALL PROOFS CHECK`, not an independent-kernel
verdict. All required M17/M18 implementation and supported verification gates
are complete; optional parity work remains unselected below.
The final documentation-only handoff also passes `timeout 240 make proof`
and `git diff --check`. Proof log:
`build/review-final-handoff-proof-20261001.log`.

Earlier verification checkpoints (locked tools, no pin updates):

- `make test-auth test-commands test-submit test-base64 test-frame test-args`
  passed, including red-before-fix credential and offline-command cases.
- `make test-dns test-dns-timeout test-dns-tcp test-socket-deadline` passed.
  DNS fixes: `eed535e`, `5b8ad51`.
- `make test-history test-state test-links test-auth test-commands test-net proof`
  passed. State/history foundations: `b1f0d6f`, `778f04a`, `900f2fb`.
- `make test-golden-runner test-build-config` passed. Exit 42, absent token,
  and timeout are rejected. Unchanged flags preserve the dependency timestamp.
- `make proof` reports `ALL PROOFS CHECK`. The separate kernel check is not
  available in the current shell: Bend requires Lean v4.34.0, while the locked
  nixpkgs offers v4.30.0. No dependency pins were moved.
- R02 (`2515445`): `tests/pty/output_stall.py` passed three consecutive runs
  before commit (ordinary, bell, slow clipboard, independent stdout fd).
  The integrated `make test-pty-output-stall` also passed. Successful shutdown
  uses bounded output plus `_Exit` after terminal restoration; the old runtime
  `IO.die` writes an unbounded stderr newline.
- R01 (`3e98e27`): normal and saturated-peer `send_stall.py` cases passed
  three consecutive runs; the runtime worktree's full `make test-pty test-net`
  also passed before the later history/wrapping integration.
- R04 (`fe558b9`): unchanged and acknowledged-renamed nick reconnect cases
  passed three consecutive runs. `make test-pty-autoreconnect test-pty-redial
  test-submit proof` passed in the runtime worktree.
- U01 (`692a659`): ten pure wrapping cases, exhaustive scalar-width parity,
  and `wrapped_spans.py` passed. The new PTY test passed three consecutive
  runs and fails against the old binary.
- S02/S04 (`5ffb06e`): streaming tests retain the latest records beyond one
  MiB, including a UTF-8 record split across reads. Endpoint/port mismatch and
  ambiguous legacy records are rejected. UI-edge reload is covered below.
- U03 (`77b7e84`): repeated `/links` and `/open 1` do not amplify or reorder
  results. Listing/open echoes have explicit provenance and are not saved.
- U02: `make test-scroll test-split test-history test-history-io
  test-link-commands test-auth proof` passed. The new first-wrapped-row case
  failed against the old implementation. `make test-pty-scroll-wrap` passed
  three consecutive runs. The character anchor also handles one-column views
  and muted arrivals. Authentication is reset only on a new connection's Up.
- C05: empty-arg guards, command parsing, URL recognition, body-height math,
  and text-based marker/event inference now use their canonical operations.
- S08/S09 (`50ff73f`): query merges use global event order, retain IDs, keep
  the 1,024-line cap, and preserve focus and typed alerts. The control buffer
  is not renamed by a peer named `server`. Canonical history is sorted before
  appending, so interleaved buffers retain arrival order after restart.
  Integrated `make proof test-state` passed. `make test-feed` exits 2 at the
  unchanged `tab_collide` expectation described below; S09 remains unchecked
  until that existing regression guard has an approved correction.
- R06 (`b674331`): all ten native queue cases and the PTY QUIT-cap test passed
  three consecutive runs. The old implementation failed the one-frame
  checkpoint by emitting nine lines. Integrated `make test-actor
  test-actor-queue test-submit test-net proof` passed. Pending traffic is never
  replayed on a different endpoint; finite credits survive Dial and Drop.
  Pure queue rules now live in `outbound.bend`, shared by actor and proofs.
  Two quantified laws prove that zero credit cannot emit or discard any queue.
  `make proof test-actor test-actor-queue test-net` passed after that separation.
- `make test-review-pure lint-ffi` passed after the initial state/history merge.
  `make test-sanitizers` passed its UBSan hostile corpus. ASan explicitly reports
  `unsupported` on Darwin arm64 because its runtime hangs before the probe;
  this is not ASan coverage. These gates must run again on the final tree.
- V05: all repository-relative README link targets exist; no developer-specific
  `file:///` paths remain.
- R03/R05 (`6b4d0f4`): one frame handler replaces duplicated key/resize paths.
  The worker's five frame cases and five launcher cases passed three times,
  including an exact 879-byte URL decoded from a legal Latin-1 IRC record.
  Launcher completion is owned/reaped while the client runs; a helper already
  launched may outlive client quit. There is no kill/join-on-quit guarantee.
  The integrated fixture's first-paint race was reproduced and fixed with
  bounded render polling, without changing click assertions. All five frame
  cases passed three consecutive runs against the integrated root binary.
  Frame/link/clipboard tests now use fixture-only launcher paths.
- S10 (`9fc22e2`): `make test-scroll-edits` passes retained/removal/all/live
  anchors, both query-merge directions, and repeated `/links`. Purging a newer
  message and replacing link results both failed before the canonical
  reanchor operation was added. No Buffer fields were added.
- S11 (`a2f7985`): `make test-history-errors test-history-io test-state proof`
  passed. Sparse metadata probes accept 4,294,967,295 bytes and reject
  4,294,967,296 without reading gigabytes. Open/read errors are visible; a
  missing optional file remains silent and retained prefix IDs survive errors.
- U04 (`95c8fee`): source characters are counted separately from replacement
  glyphs. `make test-wrap test-scroll test-history build-ui proof` passed;
  wrapped-spans passed three consecutive runs, and scroll-wrap/softwrap/linkclick
  passed. A focused resize case anchors `c` in a one-column view and still
  anchors the preceding `abc` row after widening past a three-codepoint emoji.
- U03 runtime follow-up: a fresh integration review found Session's `/open`
  echo still used System instead of LinkResult. Pure Submit tests missed that
  path. The one-line runtime fix and Session-path non-duplication/history guards
  passed. The fake-launcher PTY passed three consecutive runs before commit.
- D02 (`c2902ef`): ordinary and blocked startup PTYs passed three consecutive
  runs before commit. Queued-Dial actor tests cover initial success and refusal;
  stale/fresh initial-failure messages are checked separately. Integrated
  `make test-startup-actor test-actor test-net build-ui test-pty-startup-connect
  test-pty-frame-links test-pty-launchers proof` passed. The UI opens before
  connecting; initial refusal remains nonzero. Obsolete startup timer/stop
  plumbing and dummy Up fd payload were removed. Setup-error teardown is
  bounded after terminal restoration (`880d858`).
- S12 red reproduction: `/query server` then `/vsplit #t` displays control
  history while still sending to the query. Two focus toggles then select
  control and reject chat. The canonical pane-key fix is `5d8904e`; pure
  split tests and three quantified pane-key laws passed, with existing display
  expectations unchanged. The new PTY passed three consecutive runs and the
  existing split PTY passed. Internal lookup never falls back from a missing
  query to control; only the user command supports the legacy alias.
- V06: `make lint-ffi proof` passed with `-Werror` enabled. README no longer
  claims a fixed FFI line count or PTY scenario count, and names the shared
  URL lexer, authentication state machine, and terminal-column module.
- S04 UI-edge reload: the current event is saved under its endpoint, then the
  new endpoint's history is loaded, then that loaded client becomes the next
  checkpoint. Imported rows are never appended as new events. The endpoint
  PTY passed three consecutive runs before commit: initial A/B isolation,
  same-port restore, and in-process A→B→A reload before either new welcome.
  Original chat/control rows remain single records; markers are not persisted.
- R02 startup follow-up: native final review found that TimUI screen entry
  still calls its default unbounded fd writer before the first frame. The
  normal startup control passed, but an unread terminal filled before launch
  prevented even the loopback listener accept. A deadline-only candidate also
  failed: raw-mode entry's `TCSAFLUSH` drains output first. The final fix uses
  TimUI's existing `TCSANOW` + `TCIFLUSH` pattern with rollback, and the existing
  output arm/disarm pair around screen entry. All seven startup/runtime cases
  passed three consecutive runs, including independently reopened stdout,
  PONG before draining, clean quit while full, and restored ICANON. Existing
  headless UI, terminal-restore, warning lint, and proof gates passed.
- R07 red evidence: a deterministic fixture importing the actual
  `Net.handle_more` passes the ordinary acknowledgement control. Two synthetic
  completions fill the one-slot ack channel and then fail with Bend's deadlock
  diagnostic. Posting a continuation to an already-full 64-message event queue
  fails with the same diagnostic. The fix reuses the otherwise redundant
  live-loop Bool for one scheduled continuation instead of adding Session state.
- R07 green: the actual-Net fixture covers a full 64-message queue, 100
  coalesced requests, exactly one continuation, FIFO tail order, and one real
  ACK with no synthetic ACK. The new mixed-traffic PTY passed three consecutive
  runs: 300 submitted lines, concurrent inbound/resize, bounded PONG, one QUIT,
  and exit zero. Its baseline did not reliably reproduce the deadlock; the
  deterministic channel fixture is the red evidence. Existing paste50,
  mixburst, bracketed-paste, endpoint-history, startup, and headless UI gates
  passed. No new Session field or FFI ownership was introduced.
- V07: mouse and split-selection tests now use a fixture-only PATH and one
  builtin-only fake `pbcopy`. Empty, unterminated, multiline, and UTF-8 helper
  input checks passed. Each changed existing PTY passed three consecutive
  Make runs; their assertions were not changed. Other link/launcher/stall
  fixtures already isolate their helper paths.
- First combined run: `timeout 1800 nix --extra-experimental-features
  'nix-command flakes' develop --no-update-lock-file . --command make -k check`
  exited 2. Full output is in `build/review-check.log`. Proof, pure/native
  review gates, warning lint, and all new review PTYs passed. The two
  approval-blocked expectations below failed. Four additional failures were
  `test-pty-demo-nick`, `test-pty-linger`, `test-pty-tabcut`, and
  `test-pty-typing`; their existing assertions remain unchanged.
- C06 red evidence: `--demo --nick bob` connects with `NICK me`. The demo's
  numeric 001 replaces Client.nick before Dial correctly snapshots it.
- D04 red evidence: the linger accept timeout did not repeat in three isolated
  runs. A deterministic refused-port headless case nevertheless exits zero
  with `birc=ok`: input EOF shuts down before the actor's startup result.
- U05 red evidence: TabCut detects the prefix `e2 94` of a box-border scalar
  immediately followed by a new cursor escape. Its label-width checks pass;
  the bounded terminal transport, not label fitting, tears the UTF-8 scalar.
- R08 red evidence: typing state is retained after a partial frame, but the
  loop parks without an output recovery event. Sending only SIGWINCH paints
  that same state and lets the unchanged typing lifecycle pass. Three isolated
  failures occur at the first active TAGMSG, not at its expiry calculation.
- The unchanged feed benchmark now has a separate `test-feed-bench` target.
  A failing feed golden must not prevent that existing bound from running.
  `timeout 300 nix --extra-experimental-features 'nix-command flakes' develop
  --no-update-lock-file . --command make proof test-feed-bench` exited 0:
  `ALL PROOFS CHECK` and `feed_bench=ok`.
- C06/D04 (`001e051`): demo data uses the requested nick; existing default
  goldens still use the exact `me` wrapper. Client is the only offline identity,
  with unused nick plumbing removed. Headless startup awaits actor Boot;
  tty startup still paints immediately. Existing demo-nick and linger fixtures
  passed three consecutive worker runs. New headless checks passed three runs
  (refusal plus eight healthy registrations each); the actual App demo-identity
  guard passed and fails against the baseline. No existing assertion changed.
- U05 (`cbfa541`): native transport owns at most three accepted suffix bytes,
  completes them before later output, and does not replay canceled payloads.
  Native short-write/cancel/restore/signal tests, strict lint, proof, headless
  smoke, and terminal restore passed. Unchanged TabCut plus all seven output
  stall cases passed three consecutive worker runs.
- R08 (`510351c`): maintenance ticks retry a short frame only when output is
  writable. `UiKeys.more` remains input-only. A slow reader proved that the
  former two-second repair blocked PONG. An always-40-ms repair candidate was
  rejected because unchanged typing status could still remain incomplete.
  The final writable repair allows 200 ms, ordinary frames 40 ms, and still-full
  repairs zero waiting. Unchanged typing and new ordinary/unread/slow-reader/
  quit-during-repair cases passed three consecutive worker runs; output-stall,
  strict lint, proof, and maintenance-paint guards passed.
- Combined U05/R08 worker check: native gate, lint, proof, TabCut and typing
  passed. One first TabCut run lacked `full39` body text despite valid UTF-8;
  its cause remains unknown. Six subsequent TabCut runs passed, including three
  consecutive paired with typing. Root must verify the final combined tree.
- Root follow-up gate on the merged source exited 0: `timeout 600 nix
  --extra-experimental-features 'nix-command flakes' develop
  --no-update-lock-file . --command make proof build-ui test-output-utf8
  test-demo-identity test-headless-startup test-pty-demo-nick test-pty-linger
  test-pty-tabcut test-pty-typing test-pty-output-recovery lint-ffi`.
  Full output is in `build/review-followup.log`. The four first-run failures
  now pass; native regression, custom demo identity, eight healthy headless
  registrations, refusal, and all four recovery modes also pass. Full combined
  verification and the two approval-blocked expectations remain open.
- Second combined `make -k check` on `ad81bc4` exited 2; output is in
  `build/review-check-final.log`. All review pure/native gates, feed benchmark,
  initial four corrected fixtures, and every new review PTY passed. In addition
  to the two approval-pending expectations, EOF, stalled-display, split-Escape,
  tab-switch, and settings fixtures failed. EOF passed three isolated unchanged
  reruns; its cause is unknown. The stalled-display failure repeated: PONG and
  clean quit succeed, but STALLEND/WAKE do not paint at 50x200 after draining.
  R08 is reopened until that existing recovery contract passes. Other failed
  fixtures require bounded reruns and cause evidence, not expectation changes.
- U06/U07 red evidence: isolated native probes interrupt successful short
  writes before accounting, reproducing duplicated/misordered continuation
  bytes with a returning SIGTERM handler. A separate actual-close/final-status
  probe frees Ui with three bytes retained, then emits `birc=ok` after a lone
  `f0` lead byte. No existing test assertion was changed.
- U08/U09 red evidence: offline exact-span checks show `*unclosed` becomes
  `unclosed*` (same for underscore/backtick), and Code becomes `Spn{0,text}`.
  Existing no-Bold checks miss the source-order error. The documented plain
  fallback and dim code style provide the intended behavior.
- Fresh-context review at the 50-commit boundary verified S13: a muted sender's
  normal `#room` message is suppressed, but `@#room` enters history and advances
  BEL. Scoped `&room` muting hides new traffic but not restored authored rows,
  and unmute leaves that generated pattern active. Isolated normalization
  guards establish both failures; fixes are in progress.
- Fresh-context review also verified C07: a valid 511-byte composer action
  produces a clamped 510-byte wire line ending in `x`, not SOH. S14 reproduction
  keeps the query open as `bob` after `alice` renames, but changes its split
  state from `stacked:alice:#room:0` to `off`.
- Root merged S13 (`d27081b`), C07 (`121b54b`), and U08/U09 (`de48675`). Worker
  guards passed: 15 mute cases, nine action-budget cases, rich-text model and
  actual native painter (three passes), strict lint, and proofs. Existing
  state/command/submit/wrap/link/scroll controls also passed. No existing test
  expectation changed. Root aggregate guard wiring is in progress.
- Root `timeout 420 nix --extra-experimental-features 'nix-command flakes'
  develop --no-update-lock-file . --command make proof test-mute-scope
  test-action-budget test-richtext-model` exited 0. The merged proof set and
  all three new focused model guards pass.
- Bounded standalone reruns in `build/review-pty-isolated.log`: EOF passed
  three more times; split-Escape still failed intermittently. Tab-switch and
  settings consistently fail only their hard-coded `me` text assertions: they
  do not specify a nick, while `Args.cfg0` correctly defaults to `birc` and
  demo now preserves it. Approval was requested to add explicit `--nick me`
  to those two fixtures without changing their assertions.
- Rejected R08 candidate: removing FFI's extra full-redraw call did not restore
  STALLEND/WAKE at 50x200. It remains only in an isolated experiment, not root.
  Repair needs finite progress, not another timeout chosen from intuition.
- S14 (`e6f2f77`): parsed arrival-order NICK operations update pane keys before
  client-based normalization. Control identity, focus, actual close, duplicate
  pane coalescing, partial input, and rename chains are guarded. Worker proof,
  compiled 15-case guard, and existing split/state tests passed. Root
  `timeout 240 nix --extra-experimental-features 'nix-command flakes' develop
  --no-update-lock-file . --command make proof test-split-rename test-split
  test-state` exited 0. No existing assertions or PTY tests changed.

Approved fixture corrections (`5b5c093`): the user explicitly approved all four.
History restoration now reuses the original host:port; distinct-port isolation
has a separate `history_endpoints.py` guard. `tab_collide` expects `server!`
for the unread private query, not the control buffer. Tab-switch and settings
pass `--nick me` explicitly, preserving every assertion; the real CLI default
is `birc`. Root `timeout 360 nix --extra-experimental-features 'nix-command
flakes' develop --no-update-lock-file . --command make proof test-feed`
exited 0. Three consecutive serial runs of the three corrected PTYs passed
via `make -o build/birc test-pty-tabswitch test-pty-settings test-pty-history`
inside the locked shell (`build/review-approved-fixtures.log`). Those runs
reused the previously built application binary; repeat them on the final
combined source before claiming integrated verification.

Open integration work remains unchecked above. Checkmarks are not a claim that
the final combined runtime/PTY/sanitizer gate has already passed.

- U10 red evidence: a reachable fake-transport Sixel draw of a 3,132-byte,
  1x1 PNG expands to 3 MiB and requests a 5,242,880-byte inflater buffer.
  An invalid filter repeats all 20 allocation requests on the next draw.
  A 70-byte truncated PNG declaring a 32-MiB IDAT requests that allocation
  before checking source availability; the counting allocator denies it.
  Normal 1x1 PNG decoding caches successfully, all tracked memory is freed,
  and signature/dimension rejection allocates nothing. Seven bounded synthetic
  cases passed. No large actual allocation or private URL fetch occurred.
  The 3-MiB case took 624 microseconds here; this is a prevalidation-bounds
  finding, not evidence of a 40-ms frame-time breach.
- U11 red evidence: denying the 16-to-8 conversion allocation retains its
  8-byte input in a small valid fixture. A suspected second format-conversion
  leak was retracted: its old early-return probe retains zero bytes because
  successful parsing already frees IDAT/expanded data and conversion frees
  its input. OOM classification at that site is still needed to allow retry.
- U10/U11 (`3d0455e`): memory-backed PNG chunks are checked before allocation;
  the existing fixed-buffer inflater gets the exact scanline/Adam7 bound.
  One image-local bit caches malformed data, while per-load allocation status
  allows transient OOM retry. Failed 16-to-8 conversion frees its owned input.
  Root gate exited 0: `timeout 360 nix --extra-experimental-features
  'nix-command flakes' develop --no-update-lock-file . --command make proof
  test-png-bounds test-png-bounds-ubsan`. It passed 61 supported layout variants,
  malformed/cache/owner-denial controls, and 32 decoder-allocation failures
  that recover with zero retained bytes. Declared 32-MiB IDAT now makes no
  decoder allocation; the 3-MiB expansion is rejected with maximum request
  4,096 bytes and is not decoded again on the next draw. Full combined app
  verification remains open.
- U06/U07/U13 (`daf6376`): lock-free output ownership defers a busy handler
  instead of guessing a UTF-8 suffix. Returning handlers preserve deferred
  flags; each later physical write re-borrows nonblocking output, even after
  capture-phase delivery. Final output retains one owned stream descriptor
  plus identity and settles scalar/framing/sync debt before status. A verified
  red probe reached a blocking second 64-KiB payload after a returning signal;
  shared/separate-description and capture controls now pass. This does not
  settle whole-Ui handler lifetime (U12).
- R08/U14 (`c006a19`): one bounded serialized frame plus accepted offset makes
  finite progress instead of restarting prefixes. Capture refusal emits none
  of that capture and exits through the existing actor/Ui shutdown path with
  nonzero status. Existing BEL, OSC 52, and image retirement share ordering.
  A coalesced repaint bit preserves a latest model refused while an old frame
  drains. Successful short-write retries and both drains share one deadline;
  failed captures retain physical framing/sync debt. The deterministic old
  200x50 renderer never reached LAST-ROW under 100 31-byte quotas; resumable
  output does. The new large PTY passed the old binary once, so it is not
  claimed as a baseline-red test. Worker fresh normal/capped builds, proof,
  native/UBSan/lint, and three serial runs of progress, capture failure,
  unchanged stall, recovery, split-Escape, typing, and output-stall passed.
  Evidence: `runtime-progress.OziUzu/build/output-progress-gates.log`.
- Combined root checkpoint (`8e84ef3`) exited 0: `timeout 420 nix
  --extra-experimental-features 'nix-command flakes' develop
  --no-update-lock-file . --command make proof test-formatting
  test-output-progress test-output-shutdown test-output-utf8 test-ubsan-native
  test-media-image lint-ffi`. All proofs, shared formatting model, three
  native output guards (ordinary and UBSan), strict FFI lint, and synthetic
  media helper controls passed. Full application/PTY gates remain open.
- P01/P02/P03 (`8e84ef3`): one shared parser replaces the duplicate View
  scanner; production net +138 lines. Seven new laws and existing laws passed.
  Worker model/link/wrap/scroll/submit guards passed. The nested styled-URL
  painter was red on the earlier binary, then green after rebuild; the final
  pipe-based painter passed three runs. No native transport changes and no
  raw-to-rendered provenance state were needed.

## Milestone 18 — TimUI example parity audit

Current feature status: formatting, remote image fetching, inline layout,
terminal playback, and the diagnostic log are implemented and verified.
V04 records the final combined checks and their explicit platform/tool limits.
The user selected animated GIFs where supported, with a
still-frame fallback. Optional parity items below are not M17 correctness
findings or approved feature requirements.

Read-only reference: local `timui.h` master `2be19558`, `examples/irc.c` and
`examples/chat.c` plus `chat_text.h`. The richer chat demo is not the IRC parity
contract. No reference files were changed. No supplied image URL was fetched.
The user now authorizes richer formatting, view-only emoji aliases, explicit
remote previews, and automatic inline image previews, including JPEG and GIF
as well as PNG. These are feature work after the M17 correctness fixes.
Cards, RTL shaping, multiline composer, and fullscreen media are separate
options, not implicit requirements of the image/formatting choice.

Original parity baseline: plaintext IRC, tabs/topics/nicks, timestamps and line kinds,
navigation/composer, single-marker `*bold*`, `_italic_`, backticks, exact HTTP(S)
links, raw Unicode emoji/CJK, and explicit local-PNG `/preview`. U08/U09 track
the two existing formatting defects. Birc adds history, wrapping, alerts,
search, split panes, typing state, and bounded actor/shutdown behavior.

- [x] **P01 — Double-marker formatting.** The shared Bend scanner recognizes
      paired `**bold**` as well as `*bold*`. Unmatched markers remain literal;
      source/history are intact. Runs longer than two use greedy double then
      single tokens, not general Markdown triple-marker semantics.
- [x] **P02 — Escapes and nested styles.** Bold/italic bits compose; backticks
      are opaque dim spans, including inside bold. Escapes cover markup,
      backslash, and colon only. URLs remain lexically opaque: styled URL
      closers must be at the URL token end. Parsing, exact URL, wrap, anchor,
      raw-source, and actual native painter guards pass. The user approved
      exactly the two old double-bold/nested-italic expectations.
- [x] **P03 — Emoji shortcodes.** All 22 exact, case-sensitive aliases from
      the chat example expand in view text only, not code or URLs. Unknown
      names remain literal. Existing rendered-character anchors need no new
      raw-source mapping; narrow replacement/resize/cluster guards pass.
- [ ] **P04 — Optional IRC wire formatting.** Current control sanitization removes
      styling controls rather than interpreting them; the IRC example also
      lacks a style decoder. Numeric color parameters are stripped; hex-color
      digits remain after their control introducer is removed. Any decoder
      needs an explicit safe style/reset model and hostile-control tests.
- [x] **P05 — Remote image previews.** The original client rejected HTTP(S)
      `/preview` and did not fetch chat links. Direct live image links now
      expand without changing their exact URLs. The chat reference routes bare
      image URLs through OpenGraph; its direct-image path is `![alt](URL)`.
      The approved implementation uses a provisioned Python/Pillow helper:
      HTTP(S) public addresses only, standard ports, pinned resolved addresses,
      checked redirects, normal certificate checks, and no cookies/proxies.
      Download/decode/frame/output limits and an eight-second helper deadline
      are explicit. Its bounded base64 envelope avoids temporary files; Bend
      owns scheduling and stale-result checks, and Ui owns decoded cache bytes.
      Automatic fetch applies to new live image links, not saved history.
- [x] **P06 — Inline image layout and animation.** The original client previewed
      local PNG only in `*preview*`; chat additionally has Markdown image badges, inline
      images, and fullscreen viewing. Inline image rows and explicit remote
      previews are authorized. GIFs use terminal-side Kitty/iTerm animation
      where supported and a first-frame fallback elsewhere; fullscreen is
      a separate optional input feature.
- [ ] **P07 — Optional cards, fenced code, and composer styling.** OpenGraph cards,
      fenced syntax highlighting, multiline rich composer, and RTL shaping
      belong to chat, not IRC. Keep each independent; do not import a general
      rich-document framework for simple IRC parity.
- [ ] **P08 — Optional exact code foreground color.** DIM is restored by U09. The IRC
      example additionally uses a code foreground color; matching that palette
      is optional, not a reason to introduce a new theme model.
- [x] **P09 — Diagnostic log buffer.** Add a lazy, read-only `*log*` buffer and
      offline `/log` command. Preserve errors at their current locations,
      retain timestamps, and do not steal focus. Reserve one of the existing
      16 buffer slots; bound diagnostic rows and text, exclude them from chat
      history, and redact credentials and URLs. Report previously hidden
      clipboard-helper, history-save, and socket-read failures. Test failure
      and success paths, full capacity, offline use, privacy, and cleanup.
- [x] **P10 — Reject explicit port zero.** Default the image port only when
      omitted. `:0` previously became 80/443. Fake-resolver negative guards
      reject zero for both schemes; omitted and explicit standard ports pass.
- [x] **P11 — Preserve finite animation plays.** GIF stores repeats, while
      APNG/WebP store total plays. Add one only for GIF. Clear inherited loop
      metadata before encoding a once-only GIF. Synthetic loops 0/1/2 verify
      the envelope and normalized GIF, including the formerly wrong extra play.
- [x] **P12 — Skip APNG's separate default image.** It is a static fallback,
      not an animation frame. Seek to the first real frame and keep the
      fallback in the source decode-work bound. Green-default/red-blue-frame
      fixtures verify frame count, first RGBA, duration, and bound controls.
- [x] **P13 — Keep diagnostic bounds independent of chat history.** Generic
      reconnect markers grew a full log to 129 rows; a chat history cap of two
      trimmed it to three. The new model guard reproduced `129,3` instead of
      `128,128`. Skip chat markers and chat caps for the app-session log;
      connection stages use its bounded append. Ordinary chat markers pass.
- [x] **P14 — Do not replay archived errors into the log.** Endpoint restores
      duplicated old errors as new diagnostics (one retained row became two,
      then three). Restore original server/query rows through the same
      timestamp/sanitization/ID path without diagnostic mirroring. Repeat
      A→B→A guards preserve the log, metadata, and live-error mirroring.
- [x] **P15 — Keep paused manual-image anchors on diagnostics.** A failed
      completion appended a raw error before the synthetic last image, but
      advanced the anchor as if after it. The reproduced `0:2`→`1:2` jump
      removed the visible image. Put the manual image before raw diagnostics;
      failure/completion, ordinary-inline, resize, and exact distinct-token
      side-by-side/stacked split-clip guards now pass.
- [x] **P16 — Preserve installed image-helper overrides.** The installed Nix
      wrapper previously used unconditional `--set`, contradicting the documented
      `BIRC_MEDIA_HELPER` override and bypassing synthetic test helpers.
      Default only an unset variable; retain a nonempty executable path and
      the existing empty-value `birc-image` PATH fallback. Verify installed
      wrappers, local formats/bounds, and offline CA trust with owned fixtures.
      The actual old package built successfully from `102bdd3`:
      `/nix/store/dvayvzmrhb7rfgw1zif3djylxfxvq6nk-birc-0.1.0`.
      `make test-package` reproduces both rejected overrides (exit 2), after
      passing installed provenance, default-helper, local PNG/JPEG and bounds,
      offline CA, help/headless, preview paint, quit, and tty-restore controls.
      The fixture uses no HTTP URL. Replacing only `--set` with `--set-default`
      produces `/nix/store/rffm2057y0fy1jca501zi1nqyvd6fydy-birc-0.1.0`.
      Both packages use identical source and helper derivations. The unchanged
      `make test-package` passes three consecutive serial runs, including all
      three local-preview PTYs per run. Its SHA-256 is
      `81ddf0a56e757232ce6d5a29f68b4857358d97a7dfaafc55d9a35b4d6fa559ef`.
      Raw fixture logs: `build/review-package-old-red-20261001.log` and
      `build/review-package-green{1,2,3}-20261001.log`. Installed helper paths
      with spaces and an explicitly empty variable are preserved. Pins stay
      unchanged; final integrated verification is recorded under V04.
      After P21's wake fix, the final installed `829d9ce` package is
      `/nix/store/7rbrlx1s2s15c0qpka22i9gh7kgmvfnn-birc-0.1.0`.
      Its FFI source is byte-identical to the committed checkout. The same
      fixture again passes three consecutive serial Make runs; source and
      lock pins are unchanged. Logs:
      `build/review-package-final-{build,green1,green2,green3}-20261001.log`.
- [x] **P17 — Select rendering branches before building their rows.** Default-off
      View timing was committed in `cfbab9a` before measurement. Three serial
      output profiles attribute 98–99% of recorded frame-phase time to View,
      with PONG delays of 5–6 seconds. Consumed, warmed component batches show
      empty-media wrapping taking about 2.16 times ordinary wrapping, and a
      128-line media body taking 2.67 times the ordinary body. The pinned Bend
      library and compiler confirm that `Bool.pick` builds both alternatives.
      A valid 457-byte IRC line with 16 links also takes 125 ms to partition,
      versus 1 ms with eight links. Replace only these measured eager branches
      with parameter matches; preserve rows and remeasure before claiming a fix.
- [x] **P18 — Keep reserved buffers outside wire routing.** A new full-log
      fixture reproduced `TOPIC/JOIN isolation topic=bad join=bad`: server
      events could mutate `*log*` without its privacy and row-limit checks.
      Guard protocol buffer names and nickname renames, not local UI lookups.
      Verify TOPIC, JOIN, PART, KICK, MODE, 332, 353, and NICK attacks, including
      an absent/closed log, alongside ordinary channel/query/NOTICE controls.
      The bounded new fixture is now green, as are unchanged feed, split-rename,
      diagnostic-buffer, and diagnostic-session controls. Full proofs pass.
      Normal NICK/QUIT preserve log focus; local search/log still work.
- [x] **P19 — Measure the remaining lexer latency.** Lexer instrumentation
      was committed in `2caffee` before measurement. Consumed warmed plain-text
      batches take 121/133 ms in `Links.render` alone, versus 156/165 ms for
      full wrapping. Eight-link lexer batches take 82/95 ms; sixteen take
      277/207 ms. This isolates parsing as a major residual cost, not an exact
      additive phase percentage (wrapping also strips the nick prefix).
      Test the hypothesis that eager finished/continuing branches rebuild
      intermediate output and continue after end-of-source. Preserve scanner
      results and remeasure; keep original PONG limits unchanged.
      Baseline log: `build/review-lexer-baseline-20261001.log`; benchmark
      SHA-256 `66cf6172a3eba231ae6a1dba157999eca23f6d0e6f0ac292f59561a7586489e1`.
      The narrow candidate selects finish or continuation with a parameter
      match. After batches retain all run/row counts: plain lex 32/31 ms,
      full wrapping 63/63 ms; eight-link lex 35/36 ms and wrapping 47/46 ms;
      sixteen-link lex 85/82 ms and wrapping 106/111 ms. Log:
      `build/review-lexer-lazy-after-20261001.log`; source hash
      `b7f85a64393c26902be48cc3e04e012d96123d63`, benchmark SHA-256
      `4b0f2c0d5d671328db72b4650eec28be926c17838ffb96cdf4e27d1c26d0be51`.
      This supports the lexer branch hypothesis. Full proof, unchanged links,
      link commands, wrapping, rich text, formatting, and media guards pass.
      Three unchanged app profiles on SHA-256
      `260d10f4b2bcb62277a6e763e1aa181cb097a1951d631838761ecc2105a51c37`
      report median stall PONG 451.580 ms and progress PONG 1378.875 ms. The
      unchanged output-stall gate passes all seven cases once; progress still
      fails its first 1000-ms PONG assertion. Stall and RST remain green.
      Later progress cases did not execute. Logs:
      `build/review-output-profile-lexer-three-20261001.log` and
      `build/review-output-gates-lexer-after-20261001.log`. Keep the remaining
      regression open and measure actual IRC-prefix viewport construction.
- [x] **P20 — Build only visible rows at the live bottom.** Whole-body and
      viewport instrumentation was committed in `e38fe2f` before measurement.
      The fixture uses the production 50×200 geometry: 180 inner columns and
      45 visible rows, with IRC nick prefixes and timestamps. Two warmed,
      fully consumed baseline batches at 128/512/1024 lines take 79/81,
      321/341, and 623/717 ms for the viewport, always consuming 45 rows.
      Full-body controls take 80/78, 328/317, and 663/647 ms. This supports
      testing whether the default viewport unnecessarily formats older rows.
      At anchor `0:0`, the candidate walks newest lines until 45 expanded
      rows are available. It counts actual rows, preserving muted and empty
      media lines, wrapped text, and clipped image metadata. Paused anchors
      retain the complete legacy path. The reference fixture compares every
      row/span field across geometry, timestamps, mutes, settings, Unicode,
      pending/ready images, manual diagnostics, and paused anchors.
      After batches take 33/27, 34/33, and 40/32 ms, still yielding 45 rows.
      Full-body controls are slower in this batch (85/88, 428/402, 793/850 ms),
      so these samples do not establish an exact speedup factor. Source hash
      `a25e49201ce90d90f0e4a7e206cf8613c72cb6d1`; benchmark SHA-256
      `ca79993b23f237982c2306bcf1d35a3acb45a88e54ec297ad341baa704bc4e5a`.
      Logs: `build/review-viewport-baseline-20261001.log` and
      `build/review-viewport-tail-after-20261001.log`. Exact reference,
      media-view, manual-anchor, and full proof gates pass.
      The combined app now builds successfully (SHA-256
      `13139c35d4eb8cfb6eea194901559b77f286812af6383b2f741d492aad960b3c`).
      Three serial profiles meet the original PONG limits in all six cases:
      stall 27.177/25.406/24.269 ms; large-frame progress
      674.731/860.798/638.779 ms. Median View times are 21,346 and 28,174 us;
      stall frame counts changed, so this is not an exact per-call speedup.
      The added live-bottom image-crop assertion preserves image row 5 plus
      both raw diagnostic rows. Profile log:
      `build/review-output-profile-viewport-three-20261001.log`.
      All four unchanged output-stall, output-progress, terminal-stall, and
      RST targets pass three consecutive serial batches on that same binary,
      with no concurrent builds or assertion changes. Logs:
      `build/review-output-gates-viewport-{1,2,3}-20261001.log`.
      The measured hypothesis holds for the components and app; the full
      integrated verification is recorded under V04.
- [x] **P21 — Verify pending input after non-key paints.** The clean `7474983`
      integrated run reproduces a killed Esc-after-resize case in the unchanged
      `test-pty-tinyquit`: `1x1`→`24x80`, lone Esc, still alive after six seconds,
      exit `-9`, no restoration. Its seven preceding tiny-window cases pass;
      unchanged lone-Esc/split-sequence controls also pass. Read-only reviews
      find a possible lost wake: a non-key frame can read Esc after the tty
      watcher has armed an infinite wait with parser state zero. The resulting
      pending parser does not change that wait or request a continuation, and
      idle maintenance ticks do not paint for parser state alone. The failing
      run has no scheduling trace, so this is not yet its established cause.
      Add a controlled ordering guard and preserve normal idle, output-repair,
      split-Esc, and ordinary key controls before choosing a narrow fix. Raw
      integrated evidence: `build/review-final-check-20261001.log`.
      `timeout 3600 make -k check` finished with exit 2 (no timeout) on
      2026-10-01, about 22½ minutes after start. The Esc-after-resize case is
      its only unexpected failure; every proof/model, other PTY, media/log,
      native-painter, mock-network, strict lint, and paste gate passes. This
      is not a final green integrated result. The isolated controlled input
      wake investigation follows on the same frozen production source.
      Three unchanged isolated tinyquit runs reproduce the same final-case
      failure, with all seven controls green. An instrumented trace probe
      instead passes (resized Esc exits in 257 ms), so it does not establish
      the original scheduling trace or invalidate the unchanged failures.
      The deterministic actual-FFI guard reproduces the missing wake after
      its idle/output/timed-Esc/split-sequence controls pass:
      `state=1 key=0 more=0 watch_deadline=0 output_pending=0 ready=0`.
      The behavioral `ready == 1` assertion fails, not compilation or an
      absent API. Old FFI blob: `c643fbcab6003f76b0e25de9ac9fb051156ae934`.
      Logs: `build/review-tinyquit-unchanged-{1,2,3}-20261001.log`,
      `build/review-esc-resize-wake-baseline-20261001.log`, and
      `build/review-input-wake-red-20261001.log`. Test the narrow fallback
      through existing maintenance readiness, excluding untimed partial
      UTF-8 and keeping normal idle/output repair behavior unchanged.
      The narrow FFI candidate adds timed states 1–3/5/6/7 and paste to the
      existing readiness predicate, independent of output writability. It
      adds no API, fields, watcher, timer, or hot continuation. The same guard
      is green, including a physically full output pipe with held Esc. Idle
      and partial UTF-8 remain false; normal timed Esc, split Up, and timed
      CSI/SS3/X10/control-string/paste cleanup controls pass. Unchanged native
      output, media, View-profile, and strict-lint gates also pass. Logs:
      `build/review-input-wake-green-20261001.log` and
      `build/review-input-wake-native-controls-20261001.log`.
      FFI blob: `c81e68a0ffab75c39d0d61882aaec45c31eb8e57`. Rebuilt-app
      confirmation and full integrated verification were still required at
      that checkpoint; their successful results follow.
      Full proof and combined app build pass (SHA-256
      `e841f1caa67e017f5bb0cf827d3af5d4b96f6a797ea638f85585fa498930d9dc`).
      All seven tinyquit, split-Esc, idle-CPU, output-progress, output-stall,
      FIN/RST, and new resize-diagnostic targets pass three consecutive serial
      batches without concurrent team builds, assertion changes, or rebuilds.
      The unchanged tinyquit's previously red case now exits zero and restores
      the terminal in all three runs. The new diagnostic requires exact tty
      restoration and never counts its rescue as success; resized Esc exits
      in 220.236/229.428/226.878 ms, with no rescue. Logs:
      `build/review-input-wake-gates-{1,2,3}-20261001.log`.
      This confirms the controlled fix and resolves the repeated symptom;
      it does not invent a scheduling trace for the original failing process.
      The driver now bounds all 64 planned PTY commands. Final V04 results
      are recorded above.

P17 component checkpoint (not a whole-app latency claim): all 20 warmed,
fully consumed after-batches completed serially with 15-second child bounds.
Empty-media wrapping is now 158/162 ms versus ordinary 158/161 ms, with 384
rows in both. The 128-line body is 580/587 ms with media versus ordinary
606/614 ms, consuming 1536 rows. Sixteen-link partitioning fell from 125 to
2 ms with a known image and from 41 to 1 ms without one. Eight-link ready
wrapping fell from 286/303 to 94/102 ms, retaining all 1280 rows. Source View
hash: `cce7c3b7d79b3a14fb97fede8b6562a37b8398a1`; benchmark SHA-256:
`e206aad927853ca14ec1956b105e3410833dbfecccac84816e1a5a1ad8568fed`.
Raw log: `build/review-media-component-after-20261001.log`. Branch selection
uses parameter matches and one lazy recursive continuation, with no new state.
Exact-row characterization, existing media-view/manual-anchor guards, full
proof, and the combined application build pass. Three serial same-scenario
app profiles on SHA-256
`b9fae4b18a4953af9368ddebbc79586903de68481de960e17117dd45cb1d5bcf`
reduce median recorded View averages from 356786 to 91600 us (stall) and
428335 to 129100 us (progress). Stall frame counts change from 31 to 46–47;
progress remains 16, so this is not an exact per-call speedup claim. Median
unread PONG is 979.244/1901.794 ms, still above the original 800/1000-ms
limits. View still accounts for 97.69%/95.85% of recorded phase time. The
unchanged after-gate batch exits 2: both output latency gates fail, while
ordinary stall and FIN/RST controls pass. Logs:
`build/review-output-profile-after-three-20261001.log` and
`build/review-output-gates-after-20261001.log`. The branch hypothesis is
supported, but it does not fully explain the latency regression. Instrument
the remaining lexer stage before the next fix. This historical checkpoint
prompted P19; P20 later restored the unchanged app gates. V04 records the final
combined verification.

Final combined run at `1ed6cb6`: `timeout 1800 make -k check` finished with
exit 2 (no timeout) on 2026-10-01. Proof, media, diagnostics, IO, history,
formatting, and most terminal tests passed. Raw log:
`build/review-check-media-log-20261001.log`. The run exposed six failures:
search's approved capacity targets, split's compiler capture limit and approved
lazy-log counts, missing reset-socket disconnect wording, and three stalled
output checks. Unchanged bounded reruns passed `test-pty-stall`, but reproduced
`test-pty-output-stall` and `test-pty-output-progress` twice at their PONG
assertions. Logs: `build/review-output-gates-rerun-20261001.log` and
`build/review-output-gates-repeat-20261001.log`. The tested binary SHA-256 is
`dc5c5dec075a0dac45ace49ade41f238bdb857600c0c01f361f1ecc76014f835`.
This historical checkpoint predates P17's measured rendering fix. Search and
split corrections are committed in `5691079`; the output cause and remaining
verification are tracked above rather than inferred from this first run.

The read-failure diagnostic now retains the visible `disconnected` prefix
before its safe numeric cause. On the frozen `b9fae4b…` binary, unchanged
`test-pty-rst` passed three consecutive serial runs: both FIN and reset remain
alive for four seconds, show the disconnect, quit with zero, and restore the
terminal. First pass: `build/review-output-gates-after-20261001.log`; repeats:
`build/review-rst-after-repeat-20261001.log`. Full proof and read-error controls
also pass; no existing test expectation changed.

Log checkpoint: the lazy model and approved four submit-buffer count updates
are integrated in `adc0055`. Root IO now reports read, history-save, clipboard,
and opener errors with safe numeric results. `*log*` survives endpoint changes;
ordinary connection/auth stages append only once it exists. Save errors remain
log-only and use one coalesced repaint, preventing a recursive save/error loop.
Pinned buffer/submit/session/restore/IO and reader/history-save/clipboard guards
pass; `c7a581c` commits the IO/retention fixes and negative/positive controls.
`f4bc5a8` adds a synthetic-helper, loopback-only PTY; it passed three
consecutive runs against the combined root binary before commit. Tests retain
timestamps, check URL/credential redaction, no focus change, local-only commands,
close/recreate, endpoint retention, one save failure under idle/PONG, and quit
plus complete terminal restoration. Fatal pre-UI startup still exits with a
diagnostic rather than an interactive buffer.

P10–P12 were independently reproduced before the narrow fixes. Reference
semantics: [PNG animation control](https://www.w3.org/TR/png-3/#acTL-chunk),
[WebP animation](https://developers.google.com/speed/webp/docs/riff_container#animation),
and [Pillow APNG sequences](https://pillow.readthedocs.io/en/stable/handbook/image-file-formats.html#apng-sequences).
The final persistent locked-shell `timeout 300 make proof test-media-image
test-diagnostic-io test-reader-errors test-history-save-errors
test-clipboard-errors` passed. Nix shell entry had delayed earlier attempts;
those outer timeouts occurred before Python started, not in the decoder.
The packaged helper now provides the locked CA bundle by default, respecting
an explicit `SSL_CERT_FILE`; no dependency pins changed.

Terminal limits: OSC 8 and italic/dim visibility depend on terminal/font support.
Image rendering uses detected Kitty/iTerm2/Sixel capabilities and normalized
bounded frames; unsupported data/protocols show `[img]`. Multiplexers can suppress
image capabilities. The chat transcript's auto-inline path requires Kitty.
Broader image APIs in the header do not imply automatic remote expansion.

Image-helper checkpoint: `make test-media-image` in the locked shell passes
synthetic PNG/JPEG/GIF/WebP/BMP/TIFF/AVIF decoding, GIF/APNG/WebP frame timing,
normalization/output bounds, malformed inputs, private/mixed/transition-address
rejection, redirects (including same-host DNS rebinding), and exact pinned
connect/TLS-host identity. A red NAT64 probe showed that `is_global` alone
accepts a loopback-mapping address; IPv6 automatic fetch now requires native
global unicast rather than transition/site-local aliases. A red fragment
probe is corrected: the displayed URL stays exact, while HTTP omits its
fragment as required. No real remote host was contacted. Nix adds Pillow and
an absolute packaged helper from the existing locked nixpkgs; no pins move.
The existing test/check targets default to `BIRC_IMAGES=off`; the new media
integration fixtures must explicitly enable it and use a synthetic helper.
An added hard-deadline probe swallowed Python exceptions and outlived the old
alarm callback. The helper now uses SIGALRM's terminating disposition, so the
deadline does not depend on Python regaining control from a decoder/DNS call.
The synthetic blocked-helper probe must terminate at one second; its parent
has a three-second test bound and kills/reaps a failed fixture.
The same decoder also accepts explicit `--local PATH` for general local-format
`/preview`; chat URLs cannot enter this path. Local reads use a nonblocking,
CLOEXEC descriptor, require a regular file, retain the existing 16-MiB local
input ceiling, and reject a changed length. Remote downloads stay at 8 MiB.
Synthetic spaces-in-path, missing file, FIFO, directory, and sparse oversized
file controls cover this path without reading user files.
The PNG decoder's existing metadata limits are tightened to 64 KiB per text
or compressed profile chunk and 256 KiB total text. Red compressed-text and
aggregate-text controls previously decoded despite these preview limits;
normal boundary text still decodes. No second PNG parser/inflater is added.

Initial parity evidence preserved the supplied encoded URL through tokenizer/
link extraction, showed no inline image, and rejected remote `/preview`.
The user approved the changed remote-preview expectation. Current policy and
layout guards cover exact direct/Markdown URLs and local/remote manual intent;
native and synthetic-helper PTYs cover playback without fetching real URLs.

## Milestone 19 — Fresh defect review follow-up (2026-10-01)

Review base: `fc756fd`. The user requested implementation of every verified
defect and the concrete style/DRY cleanup. Preserve existing test assertions;
add failing-case and normal-case guards. No source pins or upstream pushes.

### Correctness checklist

- [x] **F01 — Canonical wire identity.** Normalize before reserved-name
      validation and lookup. Prevent control-prefixed synthetic identities,
      duplicate logs, redaction bypass, and slot exhaustion; retain `NOTICE *`.
- [x] **F02 — One local image acceptance path.** Pending or helper-rejected
      local PNG/APNG data must not reach the raw-image fallback or terminal.
- [x] **F03 — Outbound/echo agreement.** Prepare the fitted message body once
      for plain input, `/msg`, and `/query`; echo/history must match the wire.
      Cover ASCII, multibyte boundaries, and oversized target envelopes.
- [x] **F04 — Recent history targets.** Bound target selection separately
      from per-buffer rows. Recent conversations must displace obsolete targets.
- [x] **F05 — Complete replay.** Read the initial capture snapshot in bounded chunks;
      cover records below, across, and beyond the old one-MiB boundary.
- [x] **F06 — Channel identity.** `/msg` and `/query` channel targets retain
      channel membership semantics when JOIN reuses the buffer.
- [x] **F07 — Explicit nickname precedence.** Preserve explicit `--nick me`
      and `--nick birc` with CLI/environment SASL settings in either order.
- [x] **F08 — Native Unicode fidelity.** Preserve combining marks, modifiers,
      ZWJ, and variation selectors through painting and selection ownership.
- [x] **F09 — Exact native hyperlinks.** OSC8 must never emit a truncated
      target. Keep short/long in-app and terminal-native link behavior exact.
- [x] **F10 — Synthetic send policy.** All send paths reject local synthetic
      targets, while no-text local focus and ordinary nick/channel sends work.
- [x] **F11 — Reconnect intent.** Preserve dividers through automatic/manual
      `Offline -> Connecting -> Up`; initial connection has no divider.
- [x] **F12 — Close/focus unread transition.** Clear the replacement tab's
      unread state when closing the active tab.
- [x] **F13 — Selection dismissal paint.** Escape clears the visible highlight
      immediately, without quitting or invoking clipboard helpers.
- [x] **F14 — Absolute DNS names.** Accept one terminal root dot consistently
      in question encoding/comparison; reject interior/repeated empty labels.

### Cleanliness checklist

- [x] **C01 — Target policy.** Share canonical identity, synthetic-target,
      and channel classification predicates across routing and submission.
- [x] **C02 — Message preparation.** Remove duplicated fit/echo ordering.
- [x] **C03 — Configuration.** Resolve nickname defaults once, after options
      and environment values; do not infer explicitness from string contents.
- [x] **C04 — Image ownership.** Remove raw local-image loading from the
      production preview path; retain proof adapters only when required.
- [x] **C05 — Dead forwarding/getters.** Drop unused callback `frames`
      parameters and duplicated active-buffer getters; retain actual loop fuel.
- [x] **C06 — View representations/geometry.** Map lexical Runs directly to
      production SpanOps and share repeated wrapping metrics.
- [x] **C07 — Proof fixtures.** Move View fixture builders/assertions into a
      proof-facing module without weakening any law.

### Integration gates

- [x] **V01 — Regressions and proofs.** Add central Makefile targets and law
      guards; run each focused regression and `make proof lint-ffi`.
- [x] **V02 — Native/terminal integration.** Run new or changed PTYs three
      consecutive times; run full `make check` on a stable source/binary.
      Closed by the clean M20 full run recorded below, not by changing the
      earlier failed M19 result.
- [x] **V03 — Safety and package.** Run supported sanitizer/native ownership
      checks, prebuild the Nix package without changing pins, and record limits.
- [x] **V04 — Recoverable handoff.** Commit verified semantic changes and
      record exact commands/results here. Never push without permission.

Verification evidence so far: all three new state regression groups failed
on the review base, then passed after fixes. The existing focused state,
submit, commands, history/IO, action-budget, and diagnostic suites passed.
Runtime DNS/reconnect/argument regressions and `args_demo` also passed;
the replay/nickname binary regressions reproduced their old failures.
The user approved only the parser's `--sasl-user alice` nickname expectation
change (`alice` to unresolved `birc`); final runtime defaults must remain `alice`.
Moved View test calls preserve their assertions.

`timeout 300 make proof lint-ffi` passed with 17 added laws, including
quantified explicit-nickname and new-endpoint rules. Log:
`build/fresh-fix-proof-lint-20261001.log`. Native cross-review caught and fixed
two new Unicode-boundary errors before integration: wide-cluster allocation
failure needed a one-column replacement, and FFI span clipping still used
scalar widths. Both now have actual native paint regression guards.
All three subsystem cross-reviews found no further verified issue. The
first `timeout 600 make build-ui` passed; final integration gates below must
use the later binary with the hyperlink allocation-multiplication guard.

Verified code checkpoints: `d36bc06` (state/target/send/history), `00b09a4`
(runtime/config/replay/DNS), and `b72fe3c` (native text, View, preview acceptance,
proofs, and central regression targets). The final build/proof/strict-lint/native
and UBSan batch passed via `timeout 600 make build-ui proof lint-ffi
test-ui-review-native test-ui-review-native-ubsan`:
`build/fresh-fix-build-gates-20261001.log`. App SHA-256:
`6a8d6c78f4c516f4577c5efadc7c97e60e747cd7ce5b31482cf4225b3050ce2f`.

`timeout 240 make -o build/birc test-cli-nick test-replay-stream
test-ui-review-output` passed every final-nickname, replay-boundary/error, and
native-output control. Log: `build/fresh-fix-app-regressions-20261001.log`.
Both new PTYs and existing local preview, mouse selection, and frame-link
controls passed three consecutive rounds on that same frozen binary (15
commands total). Log: `build/fresh-fix-pty-three-20261001.log`. The PTY source
files predate every round. No original assertion or timeout was weakened.
At this checkpoint full `make check`, supported sanitizers, and the installed
Nix package remained pending. Their final results follow below. Heavyweight
builds stayed separate from the full suite's latency/CPU threshold jobs.

The first full `timeout 2400 make check` stopped at the unchanged `feed_demo`
`join_us` negative assertion (exit 2, 09:07:40–09:23:25 UTC). Canonicalizing
generic `buf_find` made raw aliases appear resident, although storage was
correct. Restore generic lookup's stored-name semantics; normalize explicitly
at wire, creation, and history boundaries. Add raw-identity and full-capacity
history-alias guards without changing the existing expectation. Log:
`build/fresh-fix-check-20261001.log`.

Corrective checkpoint `d3ca435` restores the boundary contract. The added
raw-name negative guard was red first (`build/test-logs/golden.lo6s3S`).
Proof, expanded identity/send/history guards, original `feed_demo`, diagnostic
wire, history, submit, and command tests then passed. All original assertions
remain intact. The final full run is `timeout 2400 make -k check`, started
09:31:15 UTC; log: `build/fresh-fix-check-final-20261001.log`.
Independent runtime cross-review accepts the correction: wire/history checks
remain canonical, NICK focus uses stored/canonical names, and live typing/split
updates receive sanitized framed lines. No further verified issue was found.

Independent `timeout 310 make proof-kernel` returns exit 2 because Lean is
absent; Bend requires Lean v4.34.0 or a built `BENDTT`. No toolchain or pin
was changed. Log: `build/fresh-fix-proof-kernel-20261001.log`. Normal
`make proof` passes; this is not an independent-kernel verdict.

Final M19 verification (locked tools, source `d3ca435`):

- `timeout 2400 make -k check` completed at 10:03:25 UTC with exit 2. All
  66 planned PTY commands executed; 65 passed and local preview retry failed.
  Scroll-edits timed out at its unchanged 30-second golden deadline, and DNS
  TCP timed out at an unchanged five-second child deadline. All other proof,
  model, native, network, strict-lint, and paste gates completed successfully.
  This is not a clean full-suite pass. Log:
  `build/fresh-fix-check-final-20261001.log`.
- The exact three failing commands then passed three isolated repeats each,
  without changed arguments, assertions, or deadlines. The bounded batch
  returned 0; log: `build/fresh-fix-isolated-three-20261001.log`. Their earlier
  failures remain unexplained. In particular, the preview fixture retries
  after 0.5 seconds without observing the first helper's completion; this is
  a synchronization gap, not proof of this run's cause. V02 remains open for
  a clean uninterrupted full run or a verified explanation.
- Both new PTYs passed two more rounds after their full-suite round, on the
  same final source and binary. Log:
  `build/fresh-fix-final-new-pty-three-20261001.log`. Final app SHA-256:
  `e485a917cf264a2e608000e575253a2bf6adc659ee4e16cd8ca4e7c4cb4d3387`.
- `timeout 1200 make test-sanitizers` returned 0. Full-app hostile input,
  output/native, PNG, media, and cluster-arena UBSan guards passed. ASan
  explicitly reported unsupported Darwin arm64 startup, not coverage. Log:
  `build/fresh-fix-sanitizers-20261001.log`. UBSan app SHA-256:
  `10485469b45782cde651c7d8cd8049cdd975e65dcd7a045e3a27ef5034bccabd`.
- `timeout 1000 make build-package` returned 0 without pin updates. Three
  subsequent `make test-package` rounds returned 0. Installed package:
  `/nix/store/r7cwzq1z1b39qxyi4aaxdia3nynf21b6-birc-0.1.0`, linked at
  `build/package-birc`. Logs: `build/fresh-fix-package-build-20261001.log` and
  `build/fresh-fix-package-three-20261001.log`.

Documentation handoff also passes `timeout 240 make proof` and
`git diff --check`; log: `build/fresh-review-handoff-proof-20261001.log`.
The four semantic code checkpoints are recorded above. No push or pin update
was made. At this checkpoint V02 remained open and M20 was a read-only review.
The M20 implementation and its final integration evidence follow below.

## Milestone 20 — Fresh whole-tree review (2026-10-01)

The user requested another deep defect and cleanliness review while M19
verification was running. Three review lanes covered runtime/infrastructure,
protocol/state, and UI/media, including changed vendored seams. The initial
pass was read-only. The user then requested concurrent fixes. Four lanes
implemented the initial 15 findings and three more confirmed during the fix
pass. These are separate from the 14 implemented M19 fixes.
P2 denotes user-visible correctness; P3 denotes lower impact or a dormant path.
All guards below require failing-case and normal-case controls before a fix.
Locations and defect descriptions refer to the reviewed baseline. Checked
items are now fixed; their guards and verification results are recorded below.

### Active correctness findings

- [x] **N01 (P2) — One cluster-width contract.** `columns.bend:48` sums scalar
  widths, while native paint/FFI clip use whole clusters. `👩‍💻` is Bend width
  4/native width 2 and becomes `�` at a two-column wrap. `❤️x` is placed on
  one two-column row, then native clipping loses `x`. Native tab sizing at
  `timui.h:30579` also sums scalars: padded ZWJ width is 6 instead of 4;
  VS16 heart width is 3 instead of 4. Share the existing cluster contract.
  Guard ZWJ/VS16 wrap, tight-tab paint/hit geometry, ASCII, combining marks,
  modifiers, and one-column fallback. `wrap_demo.bend:81` encodes old scalar
  behavior; changing that existing expectation needs user approval.
- [x] **N02 (P2) — Native/Bend image cache coherence.** `media.bend:169,275`
  replaces manual H while retaining seven live inline results A–G. Native
  `birc_media.h:148` evicts oldest A on H2 insertion instead of obsolete H.
  `timui_ffi.c:414,432` then refuses/retires A, but Bend still emits its token
  and suppresses another automatic request. Guard seven inline + manual
  refresh at capacity, ninth distinct insertion, failed refresh, and stale
  targets. Let retained Bend tokens govern native payload ownership.
- [x] **N03 (P2) — Canonical synthetic identities.** Lookup is case-insensitive,
  but `client.bend:905` excludes only exact `*search*` from search. Create
  `/query *SEARCH*`, then repeat `/search hello`: prior results become search
  inputs and acquire nested prefixes. `/query *PREVIEW*` similarly breaks
  exact-name preview checks (`media.bend:220`). Guard equal upper/lower search
  and manual-preview behavior, normal queries, and literal wire rejection.
- [x] **N04 (P2) — JOIN arguments are not buffer identity.** `submit.bend:128`
  passes all remaining text to `buf_get`. `/join #room ` and `/join #room key`
  create identities with a space/key; self JOIN `#room` creates another tab.
  Parse channel identity separately from wire arguments. Guard both cases,
  plain JOIN, and valid key handling without exposing a key in a tab name.
- [x] **N05 (P2) — Reset volatile roster on reconnect.** `session.bend:1070`
  retains channel nicks, and fresh NAMES (`client.bend:562`) only appends.
  Reconnect from `me alice` to `me bob` yields `me alice bob` indefinitely.
  Guard actual reconnect with departed members, fresh multi-line 353/366,
  retained chat history, and changed endpoint behavior.
- [x] **N06 (P2) — AUTH is a legal private-message target.** `client.bend:219`
  treats any target `AUTH` as a server broadcast for both NOTICE and PRIVMSG.
  Own nick `AUTH` receives Alice's private message in the server buffer and
  loses private-message alerts. Restrict authentication broadcast handling.
  Guard private own/peer nick AUTH and genuine pre-registration NOTICE AUTH.
- [x] **N07 (P2) — Split rename must share client validation.** `split.bend:206`
  applies NICK parameters before Client's reserved-name rejection. `alice →
  *server*` leaves Alice's query unchanged but replaces its pane with server.
  Guard rejected reserved/empty renames, ordinary/collision renames, and
  unchanged focus. The suspected C0-prefixed ordinary-name variant was
  retracted: framing sanitizes it and the executed positive case is correct.
- [x] **N08 (P2) — Validate DNS response opcode.** `dns_wire.bend:847` checks QR
  but not OPCODE. Mutating a valid response's first flags byte 129→137 still
  returns `1.2.3.4` for the opcode-zero query. Guard mismatched opcode rejection
  and the unchanged valid response; retain source/port/ID/question checks.
- [x] **N09 (P3) — Validate empty truncated DNS before TCP fallback.** The same
  header checks return `tc` before QDCOUNT/RCODE/question validation when TC
  is set and ANCOUNT is zero. Wrong QNAME, zero questions, and error RCODE all
  trigger TCP instead of their validation failures. Guard those mutations,
  valid truncated fallback, and usable complete-A-with-TC behavior.
- [x] **N10 (P3) — Print each CLI diagnostic once.** `app.bend:144` calls
  `IO.print_err(msg)` then `IO.die(..., msg)`, which also prints. Invalid
  `--frames xyz` emits the same error twice and exits 2. Guard one exact stderr
  diagnostic, unchanged exit status, and successful ordinary demo startup.
- [x] **N11 (P3) — Query role is not nickname spelling.** `buffer.bend:660`
  suppresses nick seeding for every buffer named `server`, including a legal
  peer query. Completion stays empty even after rename. Construct the control
  server separately; guard ordinary/server peer seeds and control isolation.
- [x] **N12 (P3) — Complete every supported slash command.** `/log` exists in
  `Sub.slash_rows` but is missing from `session.bend:894` completion metadata.
  Guard `/lo` completion, accepted `/log`, and existing aliases/order.
- [x] **N13 (P3) — Do not omit selected clusters.** `timui_ffi.c:1075,1091`
  silently skips a glyph that does not fit its 2048-byte row staging buffer.
  An accepted local-history cluster `e` + 1200 combining marks followed by X
  paints in two columns, but selection copies only X (1 instead of 2402
  bytes). This is not a legal 512-octet wire message. Guard complete large
  and boundary-size selection, ordinary Unicode, and allocation failure.

### Dormant vendored paths (not reached by birc today)

- [x] **N14 (P3) — Code widget must pass complete clusters.** `timui.h:29865`
  sends isolated code points to labels, so combining marks/ZWJ/modifiers are
  lost before cluster-aware paint. Iterate clusters with style at their start.
  Guard attached glyph bytes and ASCII syntax styling. The widget is unused
  by birc; this is not a new arena-ownership regression.
- [x] **N15 (P3) — Decoder 16-bit conversion OOM ownership.** `timui.h:19608`
  returns on failed allocation without freeing original decoded bytes. Its
  caller at 19706 can vertically flip the null result. Guard forced conversion
  failure with flip enabled and successful conversion. This predates M19;
  birc explicitly takes the inspected 8-bit path at 26777.

### Additional implementation-review findings

- [x] **N16 (P3) — Preserve attached final spaces in selection.** The first
  growable-copy fix still trimmed raw trailing space bytes. Native `e + ZWJ +
  space` is one attached glyph, so trimming changed its bytes. A new native
  guard failed before the correction. Track the last non-padding cell end;
  trim only a separate one-byte space cell. Ordinary padding, large clusters,
  cross-row copying, and allocation refusal remain covered. Normal and UBSan
  gates pass in `build/m20-selection-cache-final-20261001.log`.
- [x] **N17 (P2) — Reader EOF cannot acknowledge writer shutdown.** A real
  loopback peer `SHUT_WR` with a gated writer produced exit 0 and no queued
  NOTICE/QUIT bytes. The open-peer control sent both. Add current-generation
  `WriterDone` after FIFO flush and Socket close; ignore reader EOF and stale
  completions while shutting down. Preserve ordinary EOF notifications. Real
  open/half-close/stale-ack and Demo/Offline idle-writer controls now pass.
  Evidence: `build/m20-shutdown-{red,green}.log`; driver
  `make test-shutdown-ack test-shutdown-flush`. Connecting/Reconnecting still
  bypass a pending dial. Cross-review found no ownership or consumer gap.
- [x] **N18 (P3) — Preview retry fixture must observe completion.** The old
  fixture slept 0.5 seconds then retried an identical manual request. A local
  helper that delays a known failure by 1.5 seconds makes that request an
  intentional in-flight duplicate and reproduces the retry-test failure.
  Wait for the visible failure completion, with a finite two-second bound,
  before creating the file and retrying. Keep no-upload, upload, placement,
  FIFO nonblocking, exit-status, and existing two-second upload assertions.
  Add `make test-pty-preview-retry` as the delayed control. Three consecutive
  normal/delayed passes on the new binary passed. This proves a fixture
  race, not the cause of the earlier full-run failure.

### Concrete cleanliness work, not speculative optimization

- [x] **K01 — Consistent build deadlines.** Older Makefile test recipes at
  206/216/241/246/251/262/384/402 still invoke the compiler without a wall-clock
  timeout. Apply the existing bounded convention; preserve all test deadlines.
- [x] **K02 — One command catalog.** Derive completion from dispatch metadata
  with explicit aliases/order instead of maintaining a second command list.
  N12 demonstrates actual drift; avoid a new command framework.
- [x] **K03 — Share scanning, preserve remainder policy.** `Sub.take_verb`,
  `Sub.take_word`, and `Irc.take_until_space` repeat the same space scan but
  deliberately keep/drop one/drop all separator spaces. Share the scan with
  small explicit wrappers; characterize all three policies first.
- [x] **K04 — Keep fixture-only compatibility out of production modules.**
  `Args.copy_fin2` is production-unused and explicitly retained by synthetic
  tests. Move it to test/law helpers if imports/assertions can be preserved.
  Do not remove useful compatibility or weaken tests to reduce line count.
- [x] **K05 — Correct stale explanations.** Session's header still says no
  reconnect/backoff. `net.bend:63` says receive-after-close deadlocks, although
  the pinned runtime returns None. Keep the real actor-ack ownership reason.

### Evidence and unresolved checks

Ignored fixtures `build/review_{state,session,ui,runtime}_edges.bend` include
normal-case guards and print the reproduced behavior. The final bounded batch
returned 0; raw output is `build/fresh-review-probes-final-20261001.log`.
It demonstrates JOIN identities, uppercase search recursion, AUTH routing,
reserved split rename, reconnect roster, server query seeding, Bend wrapping,
retained cache tokens, DNS mutations, and duplicated CLI errors. Native cache
FIFO was covered by existing executed cache guards. At that review stage its
cross-layer manual-refresh scenario was source composition; the implementation
pass added an actual live Bend-to-C terminal reproducer and regression guard.

The actual native fake-transport probe `build/review_native_edges.c` compiles
under strict C11 warnings. Its short-Unicode control passes; tab metrics are
6 vs 4 and 3 vs 4; large-cluster selection is RED with only X copied. The
expected negative exit is 1. Log: `build/fresh-review-native-red-20261001.log`.
At that initial read-only stage, N03 preview casing, N12 completion, and
N14/N15 were source proofs. The implementation pass added executed red/green
guards for each; new production/test behavior is now covered below. No upstream push, source-pin update, real IRC connection, remote image
fetch, or desktop helper was used for these probes.

The shutdown candidate is now confirmed and fixed as N17. The delayed-helper
control confirms N18's fixture race, but does not prove the old full-run failure
cause. The earlier scroll-edits and DNS TCP timeouts remain unexplained; preserve
their assertions/deadlines. DNS_TCP_TRACE=1 now records fixed stages/timestamps,
and failures report the case plus last child/peer stage without child text.

### Implementation and verification (2026-10-01)

Four lanes (root plus three agents) implemented the 18 findings and five
cleanliness items, then cross-reviewed the ownership and test boundaries.
Only one old expected value changed: the user explicitly approved the
four-column ZWJ wrap correction. The argument helper and FFI fixture argument
updates are mechanical and preserve assertions. No source pins, upstream
pushes, real IRC endpoints, supplied private image URLs, or desktop helpers.
No performance optimization or speedup claim was made.

- [x] Red/green and ordinary controls for every confirmed defect. New state
  modes each failed before the fix; native code/decoder guards included exact
  attached bytes, allocation denials, and a null-flip crash. N02's actual live
  test failed after full-cache manual refresh on the old app, then passed on
  the rebuilt app without refetch. N17's real half-close lost queued QUIT
  before the fix, then passed open/half-close/stale/idle controls afterward.
- [x] `timeout 600 make proof test-m20-state test-ui-review-columns
  test-dns-validation test-m20-media lint-ffi`: exit 0; ALL PROOFS CHECK and
  all named guards pass. Log: `build/m20-integrated-pure-20261001.log`.
- [x] Existing state/runtime regressions pass unchanged. Commands and outputs
  are in `build/m20-state-regressions.log`; DNS/args checks retain the old
  compound-error diagnostic precedence and all original assertions.
- [x] New native normal/UBSan, strict C99/C11, 204-case cluster parity,
  exhaustive scalar parity, and approved wrap controls pass. Logs:
  `build/m20-ui-guards-20261001.log` and
  `build/m20-selection-cache-final-20261001.log`.
- [x] `timeout 650 make build-ui`: exit 0. Native binary SHA-256 is
  `b8e757694db05b3f65bc1e427c3c139767728e2df9c87fb56a188f71666b4c54`.
- [x] `make test-cli-diagnostics`, then three consecutive rounds of
  `make test-pty-m20-media-cache test-pty-preview test-pty-preview-retry`:
  all pass on that unchanged hash. Log:
  `build/m20-terminal-three-20261001.log`.
- [x] `timeout 300 make proof test-build-deadlines test-pty-deadlines`:
  exit 0; ALL PROOFS CHECK, 63 bounded compiler recipes, 68 bounded terminal
  commands. Log: `build/m20-final-law-driver-gates-20261001.log`.
- [x] `timeout 2700 make -k check`: exit 0 on frozen source `ba48c67`,
  completed at 11:59:01 UTC. All 68 planned terminal commands executed and
  passed, as did the proofs, model/native/network regressions, strict FFI
  lint, and paste harness. The app retained the SHA-256 above. The earlier
  scroll-edits and DNS TCP checks passed without deadline/assertion changes;
  their earlier timeout causes remain unknown. Log:
  `build/m20-full-check-20261001.log`.
- [x] `timeout 1200 make test-sanitizers`: exit 0. Full-app hostile input,
  output/native, PNG, media, selection/cache, code-widget, and 16-bit OOM
  UBSan guards pass. UBSan app SHA-256:
  `acfa8ffe070d7ce8392ef5bec2d352750738a4a6b873578c4cef6e3226833dc7`.
  ASan explicitly reports unsupported Darwin arm64 interceptor startup;
  this is a skip, not ASan coverage. Log: `build/m20-sanitizers-20261001.log`.
- [x] `timeout 1000 make build-package`: exit 0, with the driver's existing
  900-second Nix deadline and `--no-update-lock-file`. Installed M20 package:
  `/nix/store/05ys4c0cld55m37nsx782br4scsiy9q5-birc-0.1.0`, linked at
  `build/package-birc`. Three consecutive `make test-package` rounds passed
  inside a 900-second batch; the store path stayed identical after every
  round. Checks cover helper-source provenance, overrides, local image
  decoding, trust settings, and clean-environment startup. Logs:
  `build/m20-package-build-20261001.log` and
  `build/m20-package-three-20261001.log`.

Independent `timeout 310 make proof-kernel` returned exit 2 on this tree:
Lean is absent, and Bend requires Lean v4.34.0 or a built `BENDTT`. The normal
proof checker passes; it is not an independent-kernel verdict. No toolchain
or source pin was changed. Log: `build/m20-proof-kernel-20261001.log`.

Implementation checkpoint: `ba48c67`. Final documentation handoff passes
`timeout 240 make proof` (ALL PROOFS CHECK) and `git diff --check`; log:
`build/m20-final-handoff-proof-20261001.log`. All confirmed M20 defects and
cleanup items are implemented and cross-reviewed. No push was made. The
earlier intermittent timeout causes remain unknown, despite this clean run.

## M21 — Review follow-up: correctness and word-boundary wrapping

Reviewed baseline: `771beab`. Findings were reproduced with owned synthetic
probes under `build/`; no private chat URLs or live IRC endpoints were used.
Implementations must retain all existing laws and assertions unless a specific
expectation correction receives user approval. Add failing and passing controls.

- [x] R01 — Private history append: new files are `0600` independent of umask;
      repair owned regular files via descriptor, reject unsafe paths/files, and
      never change the global umask. The user explicitly approved the repair.
- [x] R02 — GIF source bounds: validate each canvas and count actual cumulative
      source pixels, including an APNG fallback; preserve valid animations.
- [x] R03 — DNS name identity: preserve wire label boundaries during comparison.
- [x] R04 — DNS error identity: validate header/question before terminal RCODE.
- [x] R05 — Styled clusters: keep common graphemes whole across style runs;
      cluster-leading style owns paint, and Bend retains wrapping policy.
- [x] R06 — Hidden header: honor zero-sized rectangles and constrain both runs.
- [x] R07 — JOIN lists: keep individual channel identities and matching keys;
      never create the phantom comma-list buffer.
- [x] R08 — Status targets: preserve wire audience prefixes, normalize only
      local buffer identity consistently across send/query/inbound routing.
- [x] R09 — Color commas: consume a comma only when background digits follow.
      The user approved the existing `irc_show` expectation correction.
- [x] R10 — Reconnect: distinguish missing configuration from valid `s`/`demo`
      hostnames; retain manual/automatic reconnect state and port controls.
- [x] R11 — Unicode header: allocate and clip in terminal columns, not scalars.
- [x] R12 — Final replay: sanitize the unterminated record like framed records.
- [x] R13 — Nix preflight: run the CTCP Python fixture guard through `NIXRUN`.
- [x] R14 — Prefix fallback: preserve the original text on parse failure,
      including an accepted history row such as `<alice>oops`.
- [x] R15 — Preserve real `+#room` channel identities through JOIN, history,
      send/PART, inbound routing and typing; normalize STATUSMSG only at message
      audience boundaries, preferring an exact resident channel.
- [x] R16 — Measure the complete nickname prefix as painted; a trailing joiner
      can join the closing `>` into a cluster. Retain ordinary/combining guards.
- [x] W01 — Prefer word boundaries across style runs; hard-wrap oversized
      words/URLs, retain clusters and hanging indents, and count hidden boundary
      spaces in resize-safe source anchors.
- [x] C01 — Move legacy tokenizer-law adapters into the existing View law module;
      mechanically update references without changing assertions.
- [x] C02 — Share the SASL CLI-or-environment resolver without changing precedence.
- [x] C03 — Replace redundant empty-list helpers with `List.is_empty`.
- [x] C04 — Share `/images` argument acceptance for status and state mutation.
- [x] C05 — Share buffer-key normalization and reconnect eligibility predicates.
- [x] U01 — Clip tab labels only at complete common-cluster byte boundaries.
- [x] U02 — Preserve bounded, synthetic package-failure evidence with wrapper
      case and paint phase; do not change assertions, deadlines, or add retries.
- [x] P01 — User chose directed server NOTICE routing to the read-only server
      buffer; preserve private user notices and ambiguous bare nicknames.
- [x] T01 — User-approved ASCII media-fixture projections (`media_anchor`,
      `media_branches`) restore consumed hidden boundary spaces. Keep all
      expected strings, image and anchor assertions. Share one test-only helper;
      guard word/hard wrapping, non-ASCII output and invalid source counts.
- [x] T02 — User-approved settings PTY assertion: `--demo` without a selected
      endpoint reports no configured server on `/reconnect`; it must not dial
      the demo placeholder. Earlier settings assertions remain unchanged. The
      changed test passes three consecutive runs; configured-host models and
      loopback reconnect guards remain positive.
- [x] V01 — Cross-review integrated fixes, proofs, focused guards, strict FFI,
      full `make check`, supported sanitizers, and installed Nix package.

Concurrent ownership: state/protocol/history, runtime/DNS/replay, native/media,
and root View/wrapping/driver/proof integration. No dependency pins may move.

User approved two existing expectation corrections: a literal color comma is
preserved (`irc_show`), and malformed DNS flags report `bad dns` instead of
`rcode` (`parse_fffd`). Other existing assertions are unchanged; legacy adapter
references and one history-save import were mechanically moved.

Focused model/native checks and actual terminal-painter controls pass. New
wrapping guards retain source anchors across hidden spaces and width changes.
Eight new View/DNS/color laws plus target/reconnect/notice/JOIN/image-switch
laws pass. Cross-review caught and fixed a new allocation-failure argument
ownership leak and preserved legal masked JOIN names. Full verification and
package qualification remain before the final handoff.

The final concurrent cross-review found R15 and R16 after checkpoint `91edf88`.
R16 is reproduced by `m21-prefix-red-20261002.log` (five columns versus four)
and passes with existing wrap/scroll controls in `m21-prefix-green-20261002.log`.
The first broad run was deliberately stopped (exit 143), not treated as a pass.
Its checkpoint package passed `make build-package test-package`; final package
and full-suite qualification must be repeated after the follow-up changes.

R15 has native failing/passing guards for actual `+#room` identities and
typing. The ordered Session fold resolves events before each command, then
retains only open-buffer typing state. A second failing guard caught stale
peer typing across a same-chunk self-PART/rejoin; the final focused binary
passes all actual-channel, status-audience, membership, batch, private, and
depart/rejoin controls. All earlier typing APIs and assertions stay unchanged.
The frozen state diff received an independent all-clear cross-review.

Installed-package qualification initially timed out waiting for a paint; the
old guard discarded the wrapper case, phase and temporary evidence. Its cause
remains unknown: three unchanged reruns passed. U02 now records the case/phase
and bounded output/helper-call tails under ignored `build/package-failure-*`.
Controlled startup and preview failures check these diagnostics. The changed
PTY guard then passed three consecutive runs without deadline or assertion
changes (`m21-package-diagnostic-{1,2,3}-20261002.log`). The driver rerun
`timeout 1000 make build-package test-package` also passes; log:
`build/m21-package-qualified-20261002.log`. The qualified installed package is
`/nix/store/hqdzy4p3r790k6lvgnf1halkz4afzjn3-birc-0.1.0`.

`timeout 1200 make test-sanitizers` passes all supported UBSan gates, including
the full-app hostile PTY corpus. ASan explicitly reports an unsupported
Darwin-arm64 interceptor-startup runtime (LLVM #58503); this is not ASan
coverage. Log: `build/m21-sanitizers-final-20261002.log`.

Pre-approval broad run: `timeout 2700 make -k check` completed with exit 2; log:
`build/m21-full-check-final-20261002.log`. All gates except the three T01/T02
fixture cases passed, including the remaining PTY corpus, formatting/emoji and
image painters, pending/stale image policy, preview retries, diagnostic log,
reconnects, exact links, UTF-8, scroll/resize, strict FFI and paste harness.
T01's existing helpers concatenate visible rows without restoring consumed
word-boundary spaces; their underlying raw text and anchor guards remain intact.
T02 expects an implicit network dial from an offline demo. Both proposed
corrections needed explicit user approval; no old test was changed in that run.

`timeout 310 make proof-kernel` fails closed (exit 2): Lean is absent; the
independent verdict needs Lean v4.34.0 or a built `BENDTT`. No toolchain or pin
was changed. Log: `build/m21-proof-kernel-20261002.log`. Normal proof checks,
including six further channel/prefix/typing laws, pass. Implementation commits:
`91edf88`, `ebcfbac`; package diagnostic checkpoint: `040937a`. The remaining
work at that checkpoint was T01/T02 approval, their focused guards and a clean
aggregate check.
No build/test process or external connection started by this review remains.
No push was made.

The user subsequently approved all three fixture corrections. The focused
`timeout 240 make -k test-media-anchor test-media-branches` first reproduced
both failures (exit 2); after the shared ASCII projection correction,
`timeout 240 make test-media-anchor test-media-branches` passes (exit 0).
The changed `timeout 180 make test-pty-settings` passes three consecutive
runs: `build/m21_t02_settings_round{1,2,3}.log`. Steps 1–9 and clean shutdown
are unchanged; no real IRC endpoint is dialed. `timeout 220 make proof`
passes; log: `build/m21-approved-fixtures-proof-20261002.log`. Only tests and
this checklist changed; fixture checkpoint: `cb89d0c`.

Final aggregate verification on that checkpoint: `timeout 2700 make -k check`
passes (exit 0), including all three approved fixture cases, all pure/model and
PTY gates, original laws, strict FFI lint and the paste harness. Log:
`build/m21-approved-full-check-20261002.log`. Tests use `BIRC_HISTORY=none`
and `BIRC_IMAGES=off` in the exact locked Nix-provisioned environment; no pins
changed, and synthetic preview tests use owned local fixtures/helpers.
Independent review found no further defect in the fixture changes. Production
sources and packaging inputs are unchanged since the qualified package;
`git diff ebcfbac -- src nix flake.nix flake.lock` is empty, and the installed
image helper matches the checkout byte-for-byte. The prebuilt package and
supported UBSan results above therefore still apply.
The final pre-commit `timeout 220 make proof` also passes (exit 0); log:
`build/m21-final-handoff-proof-20261002.log`.

All M21 fixes, cleanup and approved fixture corrections are complete. Remaining
coverage limits are explicit: ASan is unsupported on this Darwin-arm64 runtime,
and independent kernel verification needs Lean v4.34.0 or `BENDTT`. The earlier
isolated package paint timeout is unreproduced and its cause remains unknown;
diagnostics now retain evidence, but this is not a claim that its cause was
fixed. No owned build/test process remains. No push was made.

## M22 — Authentication profiles and Keychain launcher

User scope: macOS `keychain-birc`, SASL, explicit trusted NickServ fallback,
save prompted credentials only after actual success. IRC remains plaintext;
the user approved per-launch unsafe opt-in. No TLS implementation, real
credential access, Keychain writes, or public IRC probes are part of testing.

- [x] Keep passwords out of profile TOML, child argv/environment, temporary
  files, diagnostic logs, and authentication chat/history.
- [x] Add explicit `sasl`, `nickserv`, and `sasl-nickserv` modes. Fallback
  accepts phase-gated CAP NAK or valid server 421 CAP, never bad passwords.
- [x] Bind credentials to initial host AND port. Clear them permanently on
  endpoint changes. Preserve same-endpoint reconnects.
- [x] Require exact full NickServ identity before sending a password: harmless
  HELP probe, trusted directed NOTICE, IDENTIFY, exact confirmation.
- [x] Track a monotonic phase-gated success sequence. Do not count registration,
  duplicate/forged replies, manual commands, printed output, or exit status.
- [x] Pass EOF-framed bounded UTF-8 through owned inherited pipes; CLOEXEC
  prevents helper inheritance. Emit a separate one-shot success frame.
- [x] Prompt without terminal echo; refuse echoed fallback. Versioned Keychain
  envelopes preserve Unicode/spaces. Store through `security -i` stdin, never
  secret argv, with no update/overwrite flag.
- [x] Require a declared trusted IPv4 loopback relay by default. Accept
  plaintext only with explicit `--allow-insecure-auth` per launch.
- [x] Redact manual service credential echoes and exclude composer history.
  Suppress own credential wire echoes. Manual typed drafts remain visible;
  no native input-mask redesign is claimed.
- [x] Add nonsecret profile examples, limits, failure behavior and Make targets;
  add the `keychain-birc` Nix app without changing shell inputs or pins.
- [x] Qualify focused pure/native tests, proof laws, and strict FFI lint.
- [x] Run the new real-loopback authentication PTY three consecutive times.
- [x] Run full `make -k check` and retain its failures and focused reruns.
- [x] Run supported sanitizer gates and installed-package qualification;
  prebuild the updated default Nix package.
- [x] Independent final review and semantic implementation checkpoint.
- [ ] Resolve the repeated one-second burst-PONG miss, which also occurs on
  the verified pre-auth package. Do not weaken the existing deadline or claim
  that authentication caused it without supporting measurements.
- [x] Repeat preview-retry unchanged three times and retain the original miss.

Initial evidence: old host-switch test leaked `[secret]` in
`build/auth_profile_scope.red.log`; new profile interpreter passes. Manual
privacy had a native RED before the new classifier; focused native privacy
now passes. Fake Keychain wrapper guards passed three consecutive runs in
`build/m22-keychain-wrapper-green-{1,2,3}-20261002.log`. New fixture assertions
were added. Initial old-test edits were trailing constructor-pattern wildcards
for the new Args auth-options field. The later two expectation corrections
were separately approved by the user, as recorded below.

Root qualification: `timeout 250 make proof lint-ffi test-auth-bridge
test-auth-bridge-ubsan` passes; log `build/m22-proof-native-20261002.log`.
The integrated application and flag/privacy/actor-scope checks pass in
`build/m22-integration-build-20261002.log`. Real-client SASL, NickServ, fallback,
bad-password refusal, same-endpoint reconnect, and changed/returned endpoint
guards passed three consecutive runs:
`build/m22-auth-pty-green-{1,2,3}-20261002.log`. No real secrets were used.
Final review also reproduced a wrapper exit/select success race and corrected
it with a retained RED and three GREEN runs. NickServ metadata now rejects
core-invalid channel/colon/multi-target service names before lookup or prompt;
its retained RED and three GREEN runs are in
`build/m22-keychain-prefix-{red,green-1,green-2,green-3}-20261002.log`.
Two independent final reviews report no further confirmed defect. The first
aggregate/package attempts were deliberately
stopped (exit143) to add the final diagnostic guard and stage new Nix source
files; neither is counted as a pass.

Implementation checkpoint: `5b9dd7e`. `timeout 2700 make -k check` completed
with exit 2; log: `build/m22-full-check-20261002.log`. It found two obsolete
expectations: credentials surviving a changed endpoint, and CLI help omitting
the new auth flags. Both corrections received explicit user approval. The
diagnostic test preserves its log/content, focus, history-cap, nickname, and
event-ID checks, and adds same-endpoint credential retention plus changed-port
isolation. `timeout 450 make proof test-diagnostic-session test-args` passes
(exit 0); log: `build/m22-approved-fixtures-final-20261002.log`.

Four PTY gates also failed: connect, stall, output-progress, and preview-retry.
Connect passed four unchanged reruns, including three consecutive; stall
passed three consecutive independently checked reruns. Logs:
`build/m22-connect-repro-{1,2,3}-20261002.log` and
`build/m22-stall-repro-{2,3,4}-20261002.log`. Their original misses remain
unexplained; no assertion or deadline was weakened. Output-progress's PONG
miss repeats. Existing committed phase timers show 1497/1639/1973 ms PONGs
and 72/78/106 ms average View phases in the first three current-binary runs.
The verified pre-auth Nix package also misses the unchanged line-52 deadline.
Isolated interleaved progress comparisons have PONG medians 1088 ms (old)
and 1099 ms (new), with CPU medians 1.18 s and 1.22 s and overlapping ranges.
View accounts for 90.06% and 91.27% of the recorded frame-phase totals; that
does not establish the whole PONG critical path. There is no measured evidence
that M22 caused the delay. Logs: `build/m22-output-progress-baseline-control.log`
and `build/m22-output-profile-paired-*`. All other aggregate gates passed, including auth,
proofs, strict FFI lint and the paste harness. The aggregate is not green.

Preview-retry passed three consecutive unchanged bounded reruns (exit 0):
`build/m22-preview-retry-rerun-{1,2,3}-20261002.log`. No source, assertion,
or deadline changed. Its original cause remains unknown; the failed raw-output
substring alone cannot establish that the helper completion was lost.

The final read-only audit confirms that the repeated output-progress failure
is a socket-wire assertion, not a rendered substring. Its default `ordinary`
case fails first, so that aggregate invocation does not execute `large`,
`slow`, or `quit`. Existing profile exit 0 means diagnostic completion, not a
passing one-second gate. The smallest next diagnostic is a committed,
bounded, default-off numeric trace from inbound delivery through UI dequeue,
feed/PONG enqueue, and writer send; use timestamps/counts only, never chat
text. Reuse the View timer, then measure the unchanged case serially after
builds stop. Do not optimize from whole-frame averages or weaken the deadline.

`timeout 1200 make test-sanitizers test-auth-bridge-ubsan` passes all supported
UBSan gates, including the full-app hostile corpus; log:
`build/m22-sanitizers-20261002.log`. Full-app authentication PTY also passes
under UBSan: `build/m22-auth-pty-ubsan-20261002.log`. ASan again reports the
known unsupported Darwin-arm64 interceptor-startup runtime (LLVM #58503), not
ASan coverage. No real Keychain or public-network tests were run.

The first package command reached its 900-second build bound (inner exit124,
Make exit2). Compiler samples showed advancing CPU time, but the cause of the
slow build is not established. A fresh output-selected retry built the same
derivation with unchanged pins/flags (exit 0), bounded at 1800 seconds; log:
`build/m22-package-build-continuation-output-20261002.log`.
Derivation: `/nix/store/0bs7xcprx3f08kscmj7lzpzq2c2vyg9k-birc-0.1.0.drv`.
Use `nix build '…drv^*'` to build its outputs. A bare `…drv` diagnostic returned
the derivation path itself and is not counted as a successful package build.
`timeout 1000 make test-package test-keychain-package` passes (exit 0); log:
`build/m22-package-qualified-20261002.log`. The installed auth PTY passes too:
`build/m22-installed-auth-pty-20261002.log`. The qualified output is
`/nix/store/gijifqaakdrx5wgwnhxcf6x13kxsr1wd-birc-0.1.0`.
`timeout 180 nix --extra-experimental-features "nix-command flakes" build .
--no-update-lock-file --no-link --print-out-paths` returns that cached output
without rebuilding (exit 0); log: `build/m22-default-nix-cached-20261002.log`.
Only approved tests and documentation changed after the package qualification;
production sources and packaging inputs are unchanged.

Runtime `/set`, `/toggle`, mutes, and image switches remain session-only.
Auth profile TOML and Keychain credentials persist separately from chat
history. UI settings persistence was asked about, not requested as a change.

## M23 — Confirmed file uploads and measured startup

User scope: file drops (images and other regular files) through 0x0.st,
confirmation before each upload, and investigation of the long `nix run`
initialization delay. No real files are uploaded during tests.

- [x] Verify the primary 0x0.st API and privacy terms with a descriptive UA.
  Evidence: `build/m23-0x0-api-20261002.html`. Multipart `file` plus an empty
  `secret` field requests a harder-to-guess public URL. This is not private
  storage; the service retains the source IP and UA. Client limits are policy,
  not claims about the server.
- [x] Add and qualify bounded, default-off startup instrumentation before
  measuring. The instrumentation checkpoint precedes app/Nix measurements.
- [x] Measure cached Nix launch separately from installed-client first paint;
  use demo, loopback IRC, and owned synthetic history only.
- [x] Report the measured split and its limits. No slow app initialization was
  reproduced, so no app optimization or additional startup seam is justified.
  After the user clarified tens of seconds, bounded evaluation-only controls
  reproduced a 29.87 s project lookup and a 34.54 s direct locked derivation
  lookup. Owned evaluator samples show waits for store protocol replies;
  why those replies are slow remains unknown. Do not infer a cause from code
  inspection or mix cold builds with warm launches.
- [x] Add a bounded HTTPS uploader with strict URL output, streaming limits,
  safe numeric diagnostics, and offline failing/passing controls.
- [x] Recognize exact local dropped paths and `/upload PATH`, without shell
  evaluation, raw-path IRC output, or composer-history leakage.
- [x] Require F8 confirmation per file; Esc cancels. Pasted text cannot
  authorize an upload. Keep ordinary chat, completion, history, and navigation
  usable while one worker owns the pending request.
- [x] Bind completion to the confirmed endpoint and target; reject stale or
  overlong URL sends without truncating them.
- [x] Add driver/package/usage support, fixed Python/CA provisioning, helper
  qualification, and a shell-reload notice without changing dependency pins.
- [x] Qualify pure policy/session/helper-IO/status hints, native cancellation,
  mocked helpers, and three consecutive actual-loop PTY runs.
- [x] Qualify the installed uploader, trust defaults/overrides, clean PATH,
  and the actual loop against fake helpers, not the public upload service.
- [x] Independent review, proof/lint, supported sanitizer checks, and updated Nix cache.

Startup harness self-tests passed three consecutive controlled runs, including
raw/visible/profile capture, early exit and bounded timeout with child reaping:
`build/m22-startup-profile-selftest-final-{1,2,3}-20261002.log`.
`timeout 250 make proof test-startup-profile test-build-config` passes (exit 0);
log: `build/m23-startup-instrumentation-check-20261002.log`. Instrumentation
does not change production sources and refuses to benchmark an unbuilt Nix
output. First-visible timestamps mean observed mode-label paint, not complete
physical-frame delivery.

Instrumentation was committed before measurements (`01d7130`). The bounded
cached comparison passed all 16 cases (four separately reported warm-ups and
three settled samples for each installed/Nix demo/live mode), with no app
build running. Log: `build/m23-startup-cached-nix-20261002.log`. The already
built output was `/nix/store/gijifqaakdrx5wgwnhxcf6x13kxsr1wd-birc-0.1.0`.
The first evaluator lookup took 2592.004 ms, not compilation. Settled first
visible-paint medians were 13.326 ms installed versus 94.815 ms `nix run` for
demo, and 12.309 ms versus 85.874 ms for loopback IRC. The paired launch-cost
medians were 81.489 ms and 73.165 ms. Raw-mode-to-visible paint was about
1.0–1.2 ms. These controls did not reproduce a long app initialization delay
and do not explain the first evaluator lookup.

After the controlled reset-on-quit guard was corrected and committed
(`ff8158a`), the same installed app with an owned private 1024-row synthetic
history had settled first-visible times 55.156/55.171/53.026 ms (median
55.156 ms). Median raw-mode-to-visible paint was 43.341 ms and loopback
registration 13.864 ms. Log:
`build/m23-startup-synthetic-history-green-20261002.log`. No real history,
Keychain, credentials, or public IRC traffic were used.

The later frontend investigation used the committed external monotonic timer,
default Nix settings, exact locked input sources, and no app builds. Minimal
`nix eval --offline --expr 1` took 121.690 ms; the locked nixpkgs platform took
1635.112 ms, app name 610.728 ms, and filtered app source path 1374.826 ms.
Log: `build/m23-nix-frontend-source-phases-20261002.log`. An earlier project
program lookup and direct locked app derivation lookup each hit their 40 s
bounds; each owned evaluator was killed and reaped. Those timeouts are not
verification passes. Log: `build/m23-nix-frontend-phase-warmup-20261002.log`.

The next direct locked `app.drvPath` lookup completed in 34544.660 ms (exit 0),
without compilation; log: `build/m23-nix-owned-drv-phase-20261002.log`. A
one-second sample of that owned evaluator placed 613 of 749 main-thread
samples (81.8%) in store protocol response processing, mostly kernel reads.
Stacks include `RemoteStore::addTempRoot` and `isValidPathUncached` under
`derivationStrict`. This fraction describes only the sampled second, not the
full 34.54 s; idle GC-thread waits are excluded. Raw evidence:
`build/m23-nix-owned-drv-sample-20261002.log`.

The actual project app-program lookup also completed without a build in
29873.954 ms (exit 0); log:
`build/m23-nix-owned-project-program-phase-20261002.log`. Its one-second owned
evaluator sample placed 702 of 758 main-thread samples (92.6%) in store reply
processing; 695 ended in kernel reads. Raw evidence:
`build/m23-nix-owned-project-program-sample-20261002.log`. An application
compile overlapped this last measurement, so it is not an isolated performance
comparison. Both samples locate a wait before birc starts; neither establishes
why the store replies are delayed. No daemon, global setting, source pin, or
per-invocation tuning change was made as a fix. A safe bounded reproduction is
`timeout 60 nix --extra-experimental-features 'nix-command flakes' eval --offline
--no-update-lock-file --raw .#apps.aarch64-darwin.default.program`; it evaluates
only. Further store/daemon investigation needs separate scope. The fast
installed-app controls above remain evidence against an app startup fix, not
a claim that the frontend delay is solved.

The independent immutable upload-helper review found no confirmed defect in
the helper, pure consent/worker state, or helper IO boundary. Sixteen offline
helper tests passed in 2.606 s; log:
`build/m23-upload-independent-helper-review-20261002.log`. Integration must
still guard exact one-line URL fit, F8 authorization against a pre-existing
painted prompt, and permanent invalidation after target or connection changes.
The new package guard checks installed source/Python/CA provenance and refuses
invalid sources before network setup. The package PTY uses owned fake helpers
and loopback IRC only. This is not yet a claim that M23 or the full aggregate
passes. The previous full `make -k check` exited 2; its repeatable one-second
burst-PONG miss also occurs on the verified pre-auth baseline.

The uploader-only Nix build passes without building the app; log:
`build/m23-upload-helper-only-build-20261002.log`. Its nixpkgs store source
was resolved from the exact locked revision and independently hashed to
the locked NAR hash (`build/m23-upload-nixpkgs-source-hash-20261002.log`).
The installed output is
`/nix/store/gnc97rsiznqrnnqhyzzph5df9df5mdz5-birc-upload`.
The offline `tests/upload_package.py --helper` guard passes source/Python/CA
provenance, unset/empty/custom CA trust, fixed usage/source diagnostics,
and invalid regular/symlink/FIFO/directory inputs with an empty PATH; log:
`build/m23-upload-installed-helper-green-20261002.log`. The same package
guard correctly rejects the old client package without an uploader default;
log: `build/m23-upload-package-pre-feature-red-20261002.log`.
The final decoded-source client package build passes (exit 0):
`build/m23-upload-decoded-final-nix-build-20261002.log`. Its output is
`/nix/store/vrv9r7m3x9sggjwzkwlbzia4j1bwmgw2-birc-0.1.0`.
Installed image, Keychain-wrapper, and upload guards all pass (exit 0):
`build/m23-final-installed-{image,keychain,upload}-package-20261002.log`.
They cover source/Python/CA provenance, unset/empty/custom trust, clean PATH,
headless startup, local helper overrides, and pre-Keychain refusal. No public
service or real Keychain is used. Installed-client upload PTY passes three
consecutive unchanged runs, all twelve cases (exit 0):
`build/m23-final-installed-upload-pty-{1,2,3}-20261002.log`.
The immutable installed app hash is
`f6fe033ae8cc2954f68713f864d995018d38a7c992ae1dbf20906af1d1b5a3fc`;
the unchanged PTY script hash is
`1564bfce1bcc9ce51c180e01a800b3856f1b8bc78741212190730e19ca95d010`.

Final integration review findings and guards:

- [x] Preserve the real draft when a batch advances. Put the warning in the
  status row, never the composer. Session and actual-loop controls retain
  drafts, history, completion, and normal chat while the worker is busy.
- [x] Reject authorization before a completed warning frame. Coalesced
  Enter/F8 cannot stage and approve a new request. Every next file resets
  presentation, including duplicate paths. Pure guards cover deterministic
  state ordering; queued-key PTY cases do not force scheduler ordering.
  This is a completed-frame barrier, not proof of physical screen delivery
  when terminal output is stalled.
- [x] Restore native Enter-cleared drafts after ordinary key processing when
  an upload key suppresses submission. The actual-loop draft guards pass.
- [x] Keep malformed local-drop intent after quote/backslash decoding.
  `fi''le:///tmp/private%FF.jpg` previously reached IRC and local history;
  the failing actual-loop capture is
  `build/m23-upload-normalized-uri-red-20261002.log`. Reuse the same literal
  path lexer for intent, including partial malformed EOF and case-insensitive
  file-URL refusal. Valid local URLs, ordinary prose, known commands, and
  explicit `/msg` remain positive controls. Pure RED/GREEN logs:
  `build/m23-upload-decoded-{policy,session}-{red,green}-20261002.log`.
- [x] Keep one worker owner after cancellation, without send permission.
  Scope invalidation is permanent across away-and-back transitions. Validate
  exact helper response syntax and complete IRC line fit before ordinary
  echo/send; reject failures without forwarding helper text.
- [x] Keep fatal native output failures distinct from cancelable Escape.
  Native failure returns F10 for mandatory shutdown. Ordinary Escape still
  quits; selection consumes the first Escape before upload cancellation.
  Native guards, UBSan guards, and unchanged Escape/resize controls pass.
- [x] Apply only approved existing fixture changes: append `/upload` to the
  command catalog and return three native Escape events without C-owned quit.
  Other assertions are unchanged; compatibility guards pass.

Final pure policy/session guards pass. Root proof, helper-IO, hint, and strict
FFI lint pass (exit 0):
`build/m23-upload-decoded-final-proof-lint-20261002.log`.
The final repeated checkpoint also passes proof, lint, build-input/deadline
guards, all sixteen offline helper tests, pure policy/Session/helper-IO/hint,
and native upload guards:
`build/m23-upload-final-checkpoint-20261002.log`.
The final app built successfully; SHA-256 is
`b25a07a8f13581cab2d2d4f88f91d11eb44a1a295500033e33107ffdec91608c`.
All twelve upload PTY cases passed three consecutive runs with no test or
binary edits between runs:
`build/m23-upload-pty-decoded-final-run{1,2,3}-20261002.log`.
The unchanged Escape/resize control also passed without rescue wakes and
restored the tty:
`build/m23-upload-decoded-ordinary-esc-control-20261002.log`.

The first full-app UBSan compilation hit its 300-second compiler bound before
runtime qualification. Log: `build/m23-upload-sanitizers-qualification-20261002.log`.
The compiler bound is now 600 seconds; runtime test bounds and assertions are
unchanged. The final `timeout 1200 make build-ui test-sanitizers` retry passes
(exit 0): `build/m23-upload-decoded-final-sanitizers-20261002.log`.
Supported UBSan guards include the full-app hostile PTY, upload keys, native
output/cluster/history/media/selection/widgets, and bounded PNG decoding.
ASan explicitly reports unsupported Darwin-arm64 interceptor startup
(LLVM #58503); this is not ASan coverage. The normal rebuild retains the same
qualified app hash. The twelve actual upload PTY cases also pass under UBSan
(exit 0): `build/m23-upload-decoded-final-pty-ubsan-20261002.log`.
Upload implementation checkpoint: `33e1783`.

Final compatibility guards also pass (exit 0):
`build/m23-upload-decoded-final-compat-20261002.log` checks bounded compiler
recipes, the approved command-catalog expectation, submit, commands, and
frame behavior. The prior full aggregate remains non-green for the unresolved
burst-PONG gate; no aggregate success is claimed.

The explicit default app cache check passes (exit 0):
`timeout 180 nix --extra-experimental-features 'nix-command flakes' build .
--no-update-lock-file --no-link --print-out-paths`. Log:
`build/m23-final-default-nix-cache-20261002.log`.
It returns the same final `vrv9r7m3x9sggjwzkwlbzia4j1bwmgw2` package with
no rebuild. No dependency pins changed. The final proof and startup-harness
self-test also pass (exit 0):
`build/m23-final-handover-proof-startup-20261002.log`.

## M24 — Mixed UTC and local timestamps (diagnosed)

User reported chat timestamps about nine hours behind local join/reconnect
rows. Source confirms a mixed-time-zone defect; individual wire tags were
not supplied, so each reported row's origin is not independently verified.

- [x] Trace IRCv3 `time` parsing, log selection, local clock, View, and history.
  `irc.bend` extracts only eight clock characters after `T`.
  `client.bend` passes that clock to PRIVMSG/NOTICE logs; `buffer.bend` prefers
  it over `Client.now`. `clock_ffi.c` uses `localtime_r` for local/system rows.
  View paints timestamps unchanged. The IRCv3 server-time specification
  explicitly defines the tag as UTC:
  https://ircv3.net/specs/extensions/server-time.
- [x] Confirm history cannot safely be bulk-shifted. Current stored rows carry
  only HH:MM:SS, not source date or time-zone origin. Tagged and locally
  stamped rows are indistinguishable after storage.
- [x] Normalize valid server timestamps to the machine's local time zone,
  using the event date for daylight-saving rules, without changing receipt
  times or the exact wire message. Add UTC/local, day-rollover, DST, missing
  tag, and invalid-tag controls. Implemented with focused pure/native guards in
  M27; its final three-run terminal qualification remains open below.

## M25 — Native verified IRC TLS

Explicit user request supersedes the original plaintext-only scope. Port 6697
is the registered/common IRC-over-TLS port, not specific to Libera:
https://www.rfc-editor.org/rfc/rfc7194.html. TLS uses provisioned OpenSSL, not
hand-written cryptography. The timestamp defect in M24 remains separate.

- [x] Capture a red CLI guard: the old parser rejects `--tls`.
- [x] Add order-independent `--tls` defaults. Explicit ports are retained;
  port 6697 always requires TLS. Legacy default port 6667 is unchanged.
- [x] Add pure TLS policy laws without importing foreign transport IO.
- [x] Introduce one affine connection type for plaintext and TLS; gate IRC
  registration on verified TLS completion using the original hostname.
- [x] Qualify nonblocking OpenSSL chain/hostname/IP SAN verification, SNI,
  handshake/write deadlines, buffered reads, retry ownership, and shutdown.
- [x] Qualify Keychain TLS profiles and CLI selection before credential lookup;
  store synthetic prompted passwords only after actual authentication success.
- [x] Qualify app and installed-package loopback TLS with trusted/untrusted,
  wrong-host, expired, invalid-CA, non-TLS, stalled, reconnect, fragmentation,
  buffered-read, and private-auth controls. Three consecutive unchanged PTY runs.
- [x] Run proof, pure/legacy compatibility, strict native lint, sanitizers, and
  auth/upload regressions. Record exact outcomes; do not claim aggregate success
  from focused checks.
- [x] Build the final Nix app without changing pins and verify the hot cache.

Implementation, qualification, and the clean-tree cache check pass.
User approved the appended help option and mechanical socket/config fixture
adapters. Existing assertion values and deadlines stay unchanged.

Additional adversarial findings and evidence:

- [x] Explicit CA precedence: pinned Nix OpenSSL's default-path loader can
  prefer `NIX_SSL_CERT_FILE` over `SSL_CERT_FILE`. An explicit CA file now takes
  precedence and malformed custom trust fails closed. Native strict/UBSan guards
  pass; final app/package qualification is recorded below.
- [x] Buffered-read wake contract: pinned Bend `io_wait` detaches all parked
  work into local `todo`. A reader with buffered TLS plaintext must become due
  even when it is not in the global parked queue. New guard was red, then green
  after the narrow owned-item deadline marker. Retry deadlines and unrelated
  queue entries are preserved. This is a contract defect, not a reproduced
  public-server starvation report.
- [x] Explicit CA FIFO: an owned FIFO blocked the single IO loop before the
  original handshake deadline was installed. Owned regular CA control registered,
  painted, and quit; the FIFO control remained unresponsive and was killed/reaped
  within three seconds. The red guard is now green: a descriptor-owned regular
  file snapshot is capped at 8 MiB and parsed by OpenSSL without password prompts.
  AUX trust, CRLs, duplicate entries, symlinks to regular files, and exact-cap
  controls pass. Setup consumes the original handshake budget. Do not attribute
  the user's separate Nix delay to this synthetic configuration. Regular remote
  filesystem calls and CA-directory lookups still lack hard cancellation.
- [x] Absolute DNS compatibility: DNS accepts one terminal root dot, but native
  TLS rejected it. One final DNS dot is normalized for verification/SNI only;
  endpoint credential scope stays exact and malformed multiple dots are rejected.
  Exact 254-byte dotted/253-byte normalized boundary and overlength guards pass.
- [x] Baseline actual client: all 14 TLS cases passed three consecutive runs on
  unchanged `c33acc51b76534116bb118bbd7bcaba6f00d1a53ba875272f1611c5d57c79670`.
  Existing auth (6), upload (12), headless refusal/healthy (8), and CLI diagnostics
  also pass. These baseline greens do not replace final post-hardening runs.
- [x] Mechanical compatibility: network, actor FIFO/drop/redial, writer shutdown
  flush/half-close, auth scope, legacy CLI, and proof checks pass. Full FFI lint
  passes after its approved socket-to-connection close adapter.
- [x] Final native/app/package hashes, strict/UBSan, and unchanged PTY triples.
  New package guard is red on the old M23 package (no pinned TLS CA wrapper).
  It checks readable trust objects, custom CA preservation, primary OpenSSL
  linkage, clean PATH, and fixed safe failure diagnostics against owned peers.

Frozen native source: `src/ffi/tls_ffi.c` SHA256
`ba864b1fa768c4962eea3e0d2333dc2253d54072d0a619518b7aab3c258887d3`.
`timeout 240 make test-tls-native test-tls-native-ubsan lint-tls` passes with
pipefail (`build/m24-tls-ca-dot-final-round2-20261002.log`). Final regenerated
app SHA256 is `9c2404b67a617e4114d175f6163344deb17e9d1ab7ead37c2066e06174773973`.
Tooling passes: `timeout 90 make test-keychain-tls test-build-tls
test-keychain-wrapper test-build-config test-build-deadlines`
(`build/m25-final-tooling-corrected-20261002.log`). An earlier mistyped target
`test-keychain` stopped after two green TLS guards; it is not a qualification.

Final qualification (all listed commands exit 0; locked tools, pipefail, and
bounded wall time):

- `timeout 240 make proof lint-ffi test-tls-args test-args test-runtime-args`:
  `build/m25-precommit-proof-lint-cli-20261002.log`.
- `timeout 1200 make test-sanitizers`: all supported UBSan guards and hostile
  full-app PTY pass (`build/m25-final-sanitizers-20261002.log`). ASan explicitly
  reports unsupported Darwin-arm64 runtime startup, LLVM issue 58503; not an
  ASan success claim. UBSan app SHA256
  `a9ce17a9f5c4a623aea7e94263361509011aba1b2b8b9b1e69e24d1123e731c7`.
- `timeout 120 python3 -u tests/pty/tls.py BIN OPENSSL`: 14 cases pass three
  consecutive runs on each final normal and installed app, plus one UBSan run.
  Normal logs `build/m25-tls-pty-final-wake-run{1,2,3}-20261002.log`; installed
  logs `build/m25-tls-pty-installed-run{1,2,3}-20261002.log`; UBSan log
  `build/m25-final-ubsan-tls-pty-20261002.log`. Unchanged PTY script SHA256
  `dc17ebddb30a52d8bd61ce04f1328cfcf8f5a33eca290602c6e43a74c4428625`.
- Existing final app auth (6), upload (12), refused/healthy headless (8), and
  CLI diagnostics pass. Logs `build/m25-final-focused-{auth-profile,upload,
  headless-startup,cli-diagnostics}-20261002.log`; outer bounds 60/120/30/30 s.
- `timeout 960 make build-package` succeeds with its inner 900 s Nix bound and
  `--no-update-lock-file` (`build/m25-final-nix-package-build-20261002.log`).
  Installed output `/nix/store/s35pnc3y0hig1s42ylcnw04k5bmaa57y-birc-0.1.0`;
  unwrapped binary SHA256
  `fc25db85292d58f5264d2ba6ae6d99c38adebe0617fd5a3f57c5d3fc7b97c1cf`.
- `python3 tests/{package_tls,package,keychain_package,upload_package}.py
  ./build/package-birc` passes each with bounds 45/75/30/30 s (TLS guard also
  receives the pinned OpenSSL library path). Logs
  `build/m24-final-installed-{tls,image,keychain,upload}-package-20261002.log`.
  No public IRC, real Keychain, private chat URL, or public upload was tested.
- `git diff --check` and `git diff --cached --check` pass; `flake.lock` is
  unchanged. No full `make check` success is claimed from these focused gates.

Committed as `80de433` (`feat(net): add verified native IRC TLS`). Clean-tree
`timeout 900 nix build . --no-update-lock-file --no-link --print-out-paths`
exits 0 and reuses the exact installed output without a build
(`build/m25-clean-default-nix-cache-20261002.log`). `/usr/bin/time -p` reports
real 21.58 s, user 2.49 s, sys 0.78 s. Thus the package is cached, but the
separate Nix lookup delay is not fixed or explained. All test children were reaped.
The M24 timestamp defect also stays open. Next work should address those
existing diagnoses, not repeat TLS implementation or invent a cause.
The changed devShell adds OpenSSL/CA inputs; reload existing development shells.

## M26 — secure defaults and endpoint shorthand

Approved scope: verified TLS by default; explicit `--plain`; mutually exclusive
`--tls`/`--plain`; DNS/IPv4 `HOST:PORT` in the CLI, `/connect`, and Keychain
profiles. Explicit ports never select transport. No IPv6 or plaintext fallback.

- [x] RED: `/connect irc.example.net:7000` previously dialled the unsplit host
  on 6667. The new Session guard failed with the exact malformed Dial
  (`build/m26-connect-endpoint-red-20261002.log`).
- [x] Share pure endpoint syntax and numeric port-conflict checks between Bend
  CLI and slash commands. Preserve host spelling and terminal DNS root dots.
- [x] Resolve CLI defaults once: TLS/6697, explicit plaintext/6667, or an
  explicit port. Reject conflicting selectors and differing explicit ports
  regardless of order; matching numeric values remain valid.
- [x] `/connect HOST` inherits the Session port. Demo/replay initialization
  receives the parsed port; the actor retains the launch transport. No new
  Session fields, port-based mode inference, or hidden flag bits.
- [x] Keychain profiles default TLS. `tls=false` explicitly selects plaintext;
  wrapper selectors override the profile. Resolve shorthand before credential
  lookup, pass the exact selected mode to the child, and preserve existing
  plaintext credential safety gates. Both offline wrapper suites pass.
- [x] Adapt existing plaintext mock launches with `--plain`; retain their
  original assertions and deadlines. Extend owned-peer TLS coverage to default
  mode, inline ports, conflicts, and saved-port inheritance.
- [x] Keep the legacy upload fixture's explicit 6667 request scope by setting
  its Session port explicitly. Its old implicit default failed the existing
  duplicate-path guard after the approved secure-default change; the original
  assertions remain intact.
- [x] Keep the existing reconnect fixture's explicit 6667 endpoint by using
  `session_demo_at(..., 6667)`. Its original manual/automatic reconnect checks
  fail with the new implicit default and pass with the explicit fixture port
  (`build/m26-m21-session-{red,green}-20261002.log`).
- [x] Independent review: reject wrapper frame counts above the core's 65535
  cap before Keychain access. New negative/positive offline controls pass.
- [x] Repair verified live/CPU harness cleanup gaps on accept/send failures.
  Owned fake-child negative/positive controls pass three consecutive runs;
  original timing and measurement assertions remain unchanged.
- [x] Fix the deadline-plan guard that skipped `python3 -u` PTY launches.
  New bounded/unbounded and malformed invocation controls fail before the fix
  and pass afterward (`build/m26-pty-deadlines-option-verified-green-20261002.log`).
- [x] Existing diagnostic PTY exposed unknown slash commands being intercepted
  as uploads. Both the old installed and new default-mode clients reproduce
  the defect. Command-shaped bare `/name` now keeps command priority; explicit
  `/upload /name` handles root files. Path quoting/escaping or another slash in
  the verb keeps literal drop consent; embedded `://` does not mark path intent.
  Sixteen negative/positive controls are RED then GREEN, with no filesystem
  probes or changed diagnostic assertions (`build/m26-upload-dispatch-{red,green}-20261002.log`).
- [x] Integrated `make proof`, endpoint/submit guards, upload/diagnostic/auth
  scope guards, wrapper checks, compiler deadline guards, and FFI lint pass.
  CLI/headless/nickname/replay checks pass on the final normal app. Logs:
  `build/m26-pure-proof-final-20261002.log` (proof/endpoint/submit green; ends at
  the preserved upload-fixture RED), `build/m26-remaining-pure-20261002.log`,
  and `build/m26-final-app-cli-headless-20261002.log`.
- [x] `timeout 720 make build-ui build/birc-output-limit` passes
  (`build/m26-app-build-20261002.log`). Normal app SHA256
  `5236dce860126af02a589b42c39ae2e367e34cc8b278524df63f4d0813919279`;
  output-limit app SHA256
  `99190750275bd029a1fa648a3050e258d2105711f5f9919a69f9a512ab929585`.
  These are pre-dispatch-fix qualification tags, not the final release tags.
- [x] Post-dispatch `timeout 1200 make proof test-upload-dispatch
  test-upload-session test-upload-policy test-connect-endpoint test-perf-cleanup
  test-pty-deadlines test-build-deadlines lint-ffi` passes; the fake-child cleanup
  metrics are characterization evidence, not a performance benchmark
  (`build/m26-dispatch-final-proof-pure-20261002.log`).
- [x] Post-dispatch rebuild passes with the same 720 s group bound. Frozen
  normal app SHA256 `ee4bad83b6f4290c8c0a3cf16400f450b6601aff578380d00c990d2b28e184ec`;
  output-limit app SHA256 `f4aae19add3ea63a47cf5e816e08683a547cb28df457b749bf35a84837d34231`
  (`build/m26-dispatch-final-app-build-20261002.log`). The C TLS source hash stays
  unchanged from M25. Session dispatch and wrapper sources are frozen too.
- [x] Unchanged diagnostic PTY passes three consecutive final-app runs with
  original assertions/deadlines (`build/m26-diagnostic-final-run{1,2,3}-20261002.log`).
- [x] All 21 owned-peer TLS cases pass three consecutive final-app runs with
  exact before/after source/test/binary hashes
  (`build/m26-tls-final-run{1,2,3}-20261002.log`).
- [x] Final UI group: 21 suites pass three consecutive runs each on the frozen
  normal/output-limit apps (`build/m26-group-a-final-*-run{1,2,3}-20261002.log`).
  The unchanged full link suite also passes three runs; this does not resolve
  the retained asynchronous-opener fixture finding below.
- [x] Final connection group: 23 suites pass three consecutive runs each, with
  unchanged script/app hashes and original bounds/assertions
  (`build/m26-group-b-final-triple-20261002.log`).
- [x] Final independent read-only review of the production delta finds no new
  confirmed correctness/security defect or needless structural complexity.
- [x] The four changed live/CPU/output/startup harnesses pass three runs each
  in a quiet lane, without builds or other PTY groups
  (`build/m26-quiet-live-perf-triple-20261002.log`). One output progress sample
  reports PONG 1043.354 ms and `original_limit_met=false` for its 1000 ms marker;
  the broader characterization assertion still passes. Do not treat that as
  a strict latency green or infer a cause. Startup measurements use the binary,
  not `--nix-run`, and do not diagnose the separate Nix lookup delay. Settled
  direct-startup medians are 7.366 ms (demo) and 6.522 ms (live), with warmup
  samples kept separate; no optimization claim. Script/app hashes are unchanged
  and all owned children are reaped.
- [x] Quiet strict group completes 22 variants with three greens each, then
  stops at `output_progress` run 2: its slow case misses the unchanged six-second
  end-marker guard (`bytes=28928`). Run 1 passes all four modes; run 2 passes
  ordinary/large and the slow case's PONG checks. This is not the historical
  PONG-deadline miss. Frozen hashes match and all owned children are reaped.
  Retain `build/m26-group-c-final-output_progress-run{1,2}-20261002.log`;
  do not call the interrupted strict aggregate green or infer a cause.
- [x] A final clean reset of the original four-mode `output_progress` guard,
  with observer tracing disabled, passes three consecutive runs. Original
  per-run/group bounds are 45/180 s; app/fixture/imported-helper hashes match
  before/after and all owned children are reaped
  (`build/m26-output-progress-full-final-clean-triple-20261002.log`). Earlier
  failures remain unexplained; these greens do not establish a fix or cause.
- [x] Three consecutive greens for every changed PTY script on frozen source.
  The independent inventory maps all 64 changed `tests/pty` scripts to 69
  parameter invocations. All six changed PTY users outside that directory also
  pass three runs: package, live mock, CPU/output/startup profiles, and the
  fake-child cleanup controls. This is combined per-guard qualification, not
  a claim that the interrupted strict runner or a new full `make check` passed.
- [x] Remaining strict `output_failure` positive/negative controls and two
  unchanged media delegates (`m20_media_cache`, `preview_retry`) each pass
  three consecutive runs with original 30/45/40 s bounds and the pinned image
  helper. All script/app/source/helper hashes match and owned jobs are reaped
  (`build/m26-c-remaining-final-*-run{1,2,3}-20261002.log`). Together with A/B,
  TLS, and the clean output-progress reset, this covers the complete 70-command
  Make PTY plan plus the extra `wrapped_spans` guard. No full-check/ASan claim.
- [x] `timeout 960 make build-package` succeeds with its inner 900 s bound and
  unchanged lock file (`build/m26-final-nix-package-build-20261002.log`). Installed
  output `/nix/store/71axidj8nisxkn03gnhwfaj76a6zcc37-birc-0.1.0`; unwrapped app
  SHA256 `49b106924b7bef51cfc251cecb9b8b3f2894cc17548ed1b6f761cdd4eed57aab`.
  Installed Keychain source matches the frozen wrapper hash exactly.
- [x] Installed TLS/helper/Keychain/upload package guards pass with original
  bounds 45/75/30/30 s. The changed local-image package harness passes three
  consecutive runs (`build/m26-installed-*-package*-20261002.log`). All 21
  installed TLS cases pass three consecutive runs with matching source/test/app
  hashes (`build/m26-tls-installed-final-run{1,2,3}-20261002.log`).
- [x] `timeout 240 make proof` passes immediately before the implementation
  commit (`build/m26-precommit-final-proof-20261002.log`). This is the standard
  checker result, not an independent `--verdict` mathematical-validity claim.
- [x] Implementation committed as `c774c75`. Clean-tree
  `timeout 900 nix build . --no-update-lock-file --no-link --print-out-paths`
  exits 0 and reuses `/nix/store/71axidj8nisxkn03gnhwfaj76a6zcc37-birc-0.1.0`
  without a build (`build/m26-clean-default-nix-cache-20261002.log`).
  `/usr/bin/time -p` reports real 2.72 s, user 1.12 s, sys 0.35 s. This verifies
  the cached package; it does not explain the older variable Nix lookup delay.

The separate M24 timestamp defect and unexplained cached Nix lookup delay stay
open. This change does not claim to fix either issue. Tests must not use public
IRC, real Keychain entries, private chat URLs, or the public upload service.

Retained test evidence: the pre-dispatch upload suite's first run passed; its
second run timed out during ordinary-message history recall. Isolated target
runs passed on current/old apps (three each), then the unchanged full upload
suite passed three quiet consecutive runs. The original timeout remains
unexplained; no CPU/scheduling cause is claimed. A separate link fixture's
0.2-second drain is not an asynchronous-opener completion fence: a controlled
0.35-second opener yields false failures on current/old apps, with all 11 exact
URLs arriving shortly afterward. Its original 10-of-11 group failure was not
reproduced in the immediate-opener paired controls; that cause remains open.

Strict-output evidence: isolated alternating slow cases pass 2/3 on the current
app and 3/3 on the prior installed app; the current miss is again the unchanged
six-second end-marker guard, with all PONG checks passed
(`build/m26-output-progress-slow-paired-20261002.log`). A bounded standalone
pre-assertion observer then passes current 3/3 and baseline 1/1, so it does not
capture or explain the failure. Two observed passes contain old-layout
`ESC[47;15H` marker output after the requested resize to 45 rows. The reused
screen parser does not clamp CUP coordinates; its secondary missing marker
cannot prove physical invisibility. Preserve the raw/metadata artifacts under
`build/m26-progress-*`. No production change, expectation change, optimization,
or root-cause claim follows from these inconclusive observations.

## M27 — approved recovery and feature roadmap

Implement in bounded phases. Keep credentials bound to the exact server
endpoint. Do not silently substitute a feature subset for this roadmap.

### Phase 1 — recovery, settings, commands, and timestamps

The first eight items are implemented and have focused regression guards.
Final terminal and package qualification remains separate and open below.

- [x] Track the full desired channel set, including later `/join` commands and
  transient JOIN keys; remove intent on accepted PART/close or self-KICK.
- [x] Reset authentication on every connection and rejoin only after welcome
  and verified authentication success when credentials are configured.
- [x] Add positive and negative reconnect, trusted NickServ, SASL, and endpoint
  isolation guards. Do not weaken trusted-prefix checks or invent a fallback.
- [x] Save UI preferences, mute rules, image preference, and per-endpoint
  autojoin channel names in a private, versioned file. Never save passwords or
  JOIN keys there. Preserve malformed, unknown, or unsafe existing files.
- [x] Add optional saved autojoin channels to Keychain auth profiles.
- [x] Add `/whois`, `/who`, `/list`, `/names`, `/topic`, `/mode`, `/kick`,
  `/invite`, `/away`, `/notice`, `/raw`, and `/quote`, with strict wire bounds,
  argument validation, and secret-safe logs and composer history.
- [x] Split long ordinary messages and notices without losing Unicode clusters
  or text. The user approved `/me` splitting and its old truncation expectation.
- [x] Convert live UTC server-time tags to date-aware local time. Invalid tags
  use local receipt time; retain raw wire lines for protocol and auth checks.
- [ ] Add Make targets, laws where applicable, documentation, proof, bounded
  pure/native tests, three consecutive changed PTY runs, and a Nix prebuild.

### Later phases — remaining approved features

- [ ] Multiple simultaneous servers and IPv6 endpoints/transport/DNS.
- [ ] Server `005 ISUPPORT`, channel modes, and nickname privileges.
- [ ] Per-buffer drafts and multiline composition.
- [ ] Full disk-history search and paging; server history where supported.
- [ ] IRCv3 account/away notifications and outgoing typing.
- [ ] Native IRC wire formatting and colors in the view.
- [ ] Fullscreen images and OpenGraph cards.
- [ ] Themes, desktop notifications, and a larger view-only emoji alias set.
- [ ] Investigate remaining PONG/output-progress timing misses and variable
  cached Nix lookup delay. Instrument and measure before changing performance.

Later-phase dependency order (verified against current source):

- ISUPPORT/roster policy, wire-format parsing, and emoji/palette data can start
  as separate pure modules. Coordinate Client/Buffer and View/FFI integration;
  current `005` is omitted, nickname sigils are fixed, and input strips styles.
- A per-buffer draft store and multiline send policy can be built separately;
  one Session owner must integrate focus, rename, close, and modal input.
- General CAP policy and bounded disk-history query/cursor work are orthogonal.
  Account/away, outgoing typing, and server history follow CAP integration;
  they must not compete with SASL for `CAP END` ownership.
- Fullscreen projection and bounded OpenGraph policy/helpers can reuse media
  ownership. Themes and notifications should use stable renderer/event seams.
- IPv6 syntax/native sockets precede AAAA DNS integration. A pure Workspace and
  ServerId model can proceed separately; multiserver routing needs one Net and
  Session integration owner. Current network events carry generation, not a
  server identity. These are plans, not implemented features.

Current owners: separate agents handle reconnect/auth, commands/splitting,
and preferences. The root handles live timestamp normalization, shared build
and runtime integration, documentation, and final qualification. A fresh
adversarial review must precede completion. Existing test expectations change
only with explicit approval; mechanical type adapters preserve assertions.

Phase-1 evidence and handoff:

- Recovery baseline REDs show launch-only JOIN and premature JOIN next to
  NickServ HELP. New pure guards are GREEN for the full desired set, runtime
  keys, repeated authentication, and trusted-success gating. Reset itself was
  already correct; do not claim that as a repaired defect.
- Commands and ordinary/ACTION splitting have RED-to-GREEN guards. The user
  approved the command catalog, ACTION, and older `state_review_send`
  truncation expectations. The latter now checks complete text, every wire
  bound, ordered echoes/history, zero-budget rejection, and a fitting target.
- Adversarial review found a service credential verb created at a later split
  boundary. Planned-chunk checks now reject the entire send and suppress
  composer retention. Ordinary-user positive controls remain intact.
- Incoming channel key MODE and numeric 324 replies previously leaked keys
  into chat/history. `test-mode-privacy` now passes while non-key MODE and
  arbitrary message text remain unchanged.
- New UTC/calendar, local-clock, and native UBSan guards pass. Additional RED
  guards cover non-chat event stamps, invalid leap-second locations, and
  leading-space tag bypass; fixes retain receipt time and original wire lines.
  The existing pure `server_time_demo` UTC parser expectations stay unchanged.
- `timeout 240 make proof` passed once during integration
  (`build/m27-proof-first.log`), the standard checker only. Rerun after the
  source freeze. This does not certify the final app or mathematical validity.
- Private preference helper and initial pure/IO/Keychain-channel tests pass.
  Async edit-wins, scope distinction, and bounded quit drain are integrated;
  final terminal qualification remains pending. The user approved the four changed absent-endpoint `scope 0`
  expectations. Canonical saved endpoint wire expectations stay unchanged.
- Nix now provisions `birc-preferences`; lock inputs were not moved. Reload
  the development shell for its PATH. Explicit helper paths allow the current
  checks to continue. The final native app is rebuilt; the default installed
  package still points to M26 until the new Nix build succeeds.
- HTML upload diagnosis uses owned fixtures: synthetic HTML succeeds with a mock
  HTTP 200 URL; 403/415/418 and invalid replies all produce code 5. Live HTTP
  status was discarded, so the user's precise failure is not known. A new
  numeric-only diagnostic envelope now preserves valid HTTP rejection codes;
  malformed envelopes/body/path/OS text remain hidden. Actual-app integration
  still needs qualification. Official
  service sources have configurable MIME/UA/network filters; no real upload
  or blanket HTML-ban claim was made.
- Fresh independent review reproduced two membership echo races: a delayed
  self-JOIN revived accepted PART intent; FIFO old PART then new JOIN erased
  the newer key. Desired membership now belongs to accepted local/raw commands,
  not their inbound echoes. Self-KICK still removes intent. New guards pass.
- RFC-valid short or absent connection-server prefixes formerly blocked welcome
  and SASL CAP handling. Shared server-source syntax now accepts those forms;
  auth phase/current-recipient and exact NickServ notice identity stay intact.
- Preference review reproduced lost pre-read endpoint edits, same-value explicit
  settings overwritten by late reads, and bare channel-prefix acceptance.
  Regressions guide a bounded deferred-scope queue, explicit accepted-intent
  mask, and consistent nonempty channel names. Runtime qualification remains.
- Launch-channel review reproduced a valid CSV list producing no JOINs. Args
  and JoinPlan now share one strict, all-or-nothing names-only parser. Empty
  input means no channels; malformed members and lists above 14 are rejected.
  Helper/profile channel bounds match the 505-byte individual JOIN budget.
- Case-only endpoint changes previously retained runtime keys and old chat
  state. Session now uses exact host spelling and port, as credentials and
  preferences do. History keeps its existing case-equivalent hostname lookup;
  its explicit fixture is unchanged. Archive lookup does not restore keys or
  credentials.
- A startup characterization confirmed that history loaded before preferences.
  A later `history off` did not undo that read; a later smaller cap did not trim
  restored rows. Settings-before-history ordering is now implemented with
  lower-level guards; final terminal qualification remains.
- The chosen correction gates only preference-enabled live startup: paint and
  process local input, resolve settings once, read an auth-free bounded archive
  on a worker, merge without trimming local rows or evicting local tabs, then
  send one generation-scoped Begin to the deferred actor. Unknown-policy reads
  fail closed for history; `none` preserves direct startup. Retained startup
  status rows flush under the resolved policy before archive checkpointing.
  Cap/history changes invalidate the completed request and requeue after that
  worker releases. Headless preparation calls the helper once before history
  and registration. The frozen native app now builds; final terminal checks remain.
- New review counterexamples reproduced active-plus-pending preference scopes
  exceeding the 16-scope bound, and returned endpoints staying held forever.
  Runtime/Live ES guards now pass; once-only global policy also survives an
  initial failed read and later endpoint changes.
- ACTION review reproduced a zero-body-budget send and a malformed leading-
  colon target. Shared target validation and strict positive budget now pass
  nine new guards, without changing existing assertions. Mixed UTF-8 cluster
  and complete long-message controls also pass.
- Raw JOIN review reproduced sending a 15th desired channel that reconnect
  would omit. Admission is now atomic; refused commands keep prior keys,
  revision, buffers, and membership, report the limit, and send no wire. New
  negative and positive capacity controls pass.
- Candidate app generation completed, but its original 300-second C compile
  timed out. A separate bounded 600-second C retry succeeded. BUILD_TIMEOUT is
  now configurable (default 300) for a bounded central-driver retry; no compile
  bottleneck or optimization cause is claimed. The candidate passes one actual
  loopback run each for local timestamps, upload diagnostics, and three-
  connection manual/automatic recovery. These are not the final startup build
  or the required three changed-PTY runs.
- The new local-time test initially treated incremental terminal output as
  plain text. The captured screen showed the correct timestamp; its observer
  now checks screen cells with unchanged expected text and deadlines.
- A quiet standard proof run passed (`build/m27-proof-quiet-after-startup.log`).
  An earlier run reached its 180-second inner deadline; no cause is inferred.
- Standard proof checks also passed after the recovery laws were added
  (`build/m27-proof-second.log`). The integrated Net module has no type errors;
  its direct checker rejects foreign/unsafe dependencies as expected. The new
  candidate app build is not final qualification or a Nix prebuild.
- Final startup guards pass through the root Make targets, including the
  facade, single-read headless preparation, owned worker completions, archive
  admission, and new refusal laws (`build/m27-startup-snapshot-frozen-guards.log`,
  `build/m27-startup-laws-final-check.log`). The native facade and canceled/held
  actor guards passed before the narrow snapshot/divider delta. Final app
  qualification remains pending.
- An owned 1024-record worker fixture reproduced a temporary divider removing
  the oldest allowed archive row. Snapshot reads now spend their row budget
  only on archive records. Startup adds fresh-ID dividers only to imported
  targets with spare capacity; local-only and diagnostic-only targets remain
  unchanged. The 1023/1024, failed-read, legacy-reader, and divider controls pass.
  Eight now-unused forwarding functions were removed; the ordinary entry and
  existing injected-error test seam stay intact. No old assertion changed.
- The final Nix build reached buildPhase but hit its 900-second outer deadline
  (`build/m27-nix-final-prebuild.log`). No new package was installed. Its final
  log does not distinguish Bend from Clang time. A separate frozen-source C
  generation succeeds in 97.61 seconds (`build/m27-final-app-codegen-diagnostic.log`).
  The bounded native compile also succeeds in 223.69 seconds
  (`build/m27-final-native-app-compile.log`). Do not infer a
  bottleneck or claim the default app is hot-cached from this evidence.
  New terminal tests can select an app via `PTY_APP`; native and terminal checks
  run serially in the central build lane. The private helper/provisioning was
  committed as `e635c5d`; no push occurred. Final app qualification is pending.
- Eleven frozen-source ES fixture goldens pass; the existing submit fixture
  needed only a `Begin` command type adapter, with all assertions unchanged.
  Standard proof, strict FFI lint, native/UBSan local clock, private helper,
  and fake Keychain checks pass. The first final terminal pass reaches a new
  preferences observer failure after local-time, recovery, and upload greens.
  That new observer now avoids redundant commands and carries partial ANSI/UTF-8
  input; both preferences scripts pass their seven native cases. Assertions for
  durable settings, scope, privacy, deadlines, and cleanup remain intact.
- Further redraw review found a production guarantee gap: the second immediate
  frame can accept the final command with no remaining input, but its changed
  state is not scheduled for repaint. The captured screen stayed old while the
  durable setting changed. The original `-O2` app reproduces this twice with one
  physical settings/bell burst; single-command, idle, and halt controls pass,
  including failure-path terminal restore/reap. The actual callback guard is
  RED for drained-hot input and passes all eight assertions after the narrow
  `more || (hot && !halt)` coalesced-continuation correction. One immediate
  redraw, ACK/output/generation, and halt policy remain unchanged. The exact
  success-token newline adapter and all eight native callback guards pass
  (`build/m27-final-repaint-build-and-pty.log`). The final `-O2` app builds and
  all six terminal suites pass three consecutive runs, including the four-case
  drained-redraw guard. Its native hash is
  `d0de07407f253132f6da1c0da0df16acb32437bff7251b9bacee770d189be239`.
  Children are reaped and terminal state is restored. Do not count the observer
  correction as fixing the app gap. Default-package qualification remains open.
- The pre-repaint native app and five new terminal scripts pass three quiet
  consecutive runs (`build/m27-final-pty-three-runs-corrected.log`), with native
  hash `021fbca83bbb8ddac8d06ac5fc462aa4fb91d5547fe68279e4c2e69a105a609a`.
  This is baseline evidence, not qualification of the later repaint change.
  The new callback fixture needs the established unexecuted App retention arm
  for complete FFI constructor IDs. Its initial native `-O2` stage reached the
  300-second bound; diagnostic `-O0` generation/runtime and actual `-O2` app
  terminal tests are separate checks, not an optimization or bottleneck claim.
- Default-off Nix codegen/native stage instrumentation has six synthetic
  success/failure guards. Its profiled derivation is separate and cannot
  establish default-app hot-cache status. No optimization or bottleneck claim
  follows before measuring the package stages.
- Final core checks: standard proof passes with `PROOF_TIMEOUT=600` after the
  default 180-second attempt times out. Strict FFI lint, golden-runner controls,
  build configuration/TLS flags, 102 compiler deadlines, 76 terminal deadlines,
  and native clock UBSan pass (`build/m27-final-pre-core-commit-checks-retry.log`).
  No law or assertion was changed for the retry. The same batch then stops at
  the package timer test's 45-second Nix evaluation deadline, before its fake
  compiler cases run. Its earlier six-case GREEN remains separate evidence;
  do not describe this final batch as wholly GREEN. The Make proof deadline is
  configurable and rejects nonpositive values; the ordinary default stays 180.
- Final read-only reviews find no blocker in repaint/ACK/output ownership,
  startup archive admission/checkpointing, headless ordering, recovery auth,
  or preference/history/burst observers and bounded terminal cleanup. No
  independent proof kernel or full aggregate `make check` was run.
- Core integration is committed as `df95f2c`; no push occurred. The profiled
  package attempt stops at its 900-second limit with `codegen begin` as its
  last stage marker, no completion/native marker, and clean cancellation
  (`build/m27-profiled-package-measurement.log`). The default installed link
  still points to M26 and lacks the preferences-helper default. Do not reuse
  its older package checks as qualification of this source.
- Scoped follow-up controls: pinned compiler startup with a fresh private
  cache takes 0.85 seconds; the second pass takes 0.25 seconds. A separate
  fresh-cache C-generation control reads the exact packaged source and finishes
  in 51.27 seconds outside Nix. Its generated C hash
  `2603d5dae14e54f802adc50c2b54307b232021db5bfecd48463e9714f5350f79`
  exactly matches the file compiled into the final native app. No Clang or app
  ran; `BEND_NO_TELEMETRY=1` disables version-check state/request. Imports are
  local files and pinned Base. The default library-root metadata was not
  isolated; future controls should set `BEND_LIB` to an owned empty directory.
  These are separately
  reported cold/warm controls, not an optimization comparison or a cache/sandbox
  root-cause finding (`build/m27-compiler-startup-cold-control.log`,
  `build/m27-cold-store-source-codegen-control.log`).
- The compiler wrapper set Bun's `DO_NOT_TRACK` but not Bend's recognized
  `BEND_NO_TELEMETRY` flag. The additional explicit opt-out has offline RED/
  GREEN source/shell guards and prevents Bend's version-check state/request.
  Its three-second request limit is not evidence for the package timeout's
  cause. The changed provisioned wrapper requires a shell reload; the captured
  wrapper can use the explicit flag while qualification continues.
- Both package targets now have independent 900-second client/builder bounds,
  with positive/negative deadline guards. The opt-in profile reports the owned
  Bend PID and waits for that exact child; default command execution is unchanged.
  Offline recipe evaluation also exceeded 45 seconds. An explicit bounded
  300-second retry reaches all six unchanged synthetic ordering/failure cases;
  they pass with the new PID/wait branch. The ordinary 45-second setup limit
  remains, and nonpositive/oversized overrides are rejected. Evidence:
  `build/m27-package-profile-pid-bounded-retry.log` and
  `build/m27-profile-timeout-refusal.log`. The next measured package attempt can
  sample only its reported owned PID; never inspect global command lines.
- The final six-case guard also validates one positive numeric compiler PID per
  profiled arm (`build/m27-package-profile-final-pid-guards.log`). Standard proof
  passes again before committing the diagnostics
  (`build/m27-pre-build-diagnostics-commit-proof.log`). The profiled target keeps
  failed temporary directories so its generated-C state can be inspected if
  it times out. No app source changed after terminal qualification.
- Diagnostics/privacy/builder bounds are committed as `f5b0b66`; no push.
  A basic offline Nix expression takes 0.54 seconds
  (`build/m27-nix-basic-eval-control.log`). A second measured package attempt
  builds the new Bend wrapper and reaches codegen with owned PID 54804
  (`build/m27-profiled-package-owned-pid.log`), but its observed UTC elapsed
  budget exceeds 900 seconds while the timeout process remains alive. The
  exact timeout/clock discrepancy is not diagnosed; do not attribute it to
  sleep, clock changes, or a compiler fault without evidence.
  Root locates only the owned log writer and its child chain, records PID/
  parent/state/CPU-time/elapsed metadata without command arguments, then stops
  verified owned Nix PID 34475. Cancellation returns, and both Nix/compiler
  PIDs are gone. One CPU snapshot is not a marginal rate or a bottleneck proof.
  No codegen completion, native stage, new birc package, or retained failed
  directory is confirmed from this canceled attempt. The default package link
  remains `/nix/store/71axidj8nisxkn03gnhwfaj76a6zcc37-birc-0.1.0` (M26).
- The new provisioned Bend wrapper exists at
  `/nix/store/vp83vc93fd31ykls5x39mjac3xjh08mw-bend/bin/bend`; its actual script
  exports both opt-out flags. This is a cached compiler wrapper, not a cached
  IRC app. Final standard proof passes again
  (`build/m27-final-handover-proof.log`). No package/default app cache or full
  aggregate-check completion follows. Reload the Nix development shell to use
  the new wrapper. All owned build/compiler processes are stopped at handoff.

Next diagnostic: keep app source frozen; add default-off load/check/emit/write
timers using the pinned compiler's exported `book_nil`, `book_load`,
`book_valid`, and `compile_book` pipeline. Retain the CLI's hole refusal and
owned output-file safety; do not run the app. Compare consumed, bounded
controls in the Nix build context, with telemetry disabled and `BEND_LIB` set
to an owned empty directory. Sample only reported owned PIDs twice to compute
CPU deltas. Reconcile UTC wall budget and process timeout before another long
attempt. Default prebuild and installed-helper/clean-PATH/TLS qualification
remain required; do not rerun the same build blindly or claim a root cause.

Before completion: freeze agent edits, run fresh proof and relevant pure/native
checks, build the app, pass changed/new PTY guards three consecutive times,
review runtime integration independently, and prebuild the Nix app. Do not
call the later phases implemented. Tests force `BIRC_PREFERENCES=none` unless
their own synthetic preference file is explicitly under test.

## Reconnect registration review (2026-10-03)

- [x] Reproduce the server-assigned nickname failure in pure Session and the
  actual native app. A trusted first `001 Guest42` changed Client identity but
  did not mark JoinPlan welcomed or start NickServ verification. Evidence:
  `build/reconnect-report-registration-red.log` and
  `build/reconnect-report-assigned-nick-red.log`.
- [x] Normalize the first valid server welcome before Auth, JoinPlan, and
  Client share it. Ignore malformed/peer/later-conflicting welcomes without
  changing live state. Keep generic `fold_lines` and SASL `903` policy unchanged.
- [x] New native Session regression passes, including full keyed automatic
  SASL recovery and current-recipient NickServ verification
  (`build/reconnect-report-registration-green-5.log`). Final expanded native
  guards also pass for partial frames, malformed welcome parameters, collision
  retries, and held-welcome release (`build/reconnect-report-final-pure-and-proof.log`).
- [x] Obtain explicit approval and correct the three existing first-welcome
  expectations: two JOIN replies and one NickServ probe. Peer/service-identity
  and later-wrong-recipient guards remain unchanged.
- [x] Rebuild the final `-O2` app and pass three consecutive expanded recovery
  PTYs: nine cases and 27 owned connections cover manual/automatic SASL and
  NickServ, automatic assigned nicknames, full surviving keyed rooms, actual
  private settings, terminal restoration, and helper cleanup. Evidence:
  `build/reconnect-report-app-build.log` and
  `build/reconnect-report-final-pty-three-runs.log`. Native app SHA256:
  `360c0ad980e8ef14fb5796d04e0534cf33888a240f532f6dac04332da8231298`.
  No Nix package hot-cache status follows from this native build.
- [x] Run final expanded native registration/auth/preferences guards and
  standard proof: `make test-reconnect-registration test-reconnect-auth
  test-reconnect-preferences proof PROOF_TIMEOUT=600` passes
  (`build/reconnect-report-final-pure-and-proof.log`). No independent kernel
  or full aggregate `make check` was run.
- [x] Rerun the approved recovery/echo fixture corrections. The original
  recovery compilation reached its 180-second limit without running assertions
  (`build/reconnect-report-approved-existing-fixtures.log`). Both native suites
  pass with a 900-second compiler bound and unchanged 15-second execution
  bounds: `make test-reconnect-recovery test-reconnect-echoes`
  (`build/reconnect-report-approved-existing-fixtures-retry.log`). The Make
  recipes retain literal positive bounds; `make test-build-deadlines
  test-build-config` passes. This is qualification, not a compiler performance
  diagnosis.
- [x] Resolve installed-artifact provenance: `build/package-birc` still targets
  M26 store path `71axidj8nisxkn03gnhwfaj76a6zcc37-birc-0.1.0`; its source
  `k17raik605ik2r0rs9s4m1msbw7pahx5-source` has no JoinPlan and recovers only
  the launch channel. Its Keychain wrapper defaults to that package's app;
  `BIRC_PROGRAM` can override it. The user reports `nix run birc -- birc
  --connect … --nick …`; no matching `flake:birc` entry appears in the scoped
  local registry check. Bounded offline metadata resolution also fails with
  `cannot find flake 'flake:birc' in the flake registries`. The checkout's
  direct app rejects an extra positional `birc`; its syntax is
  `nix run . -- --connect HOST --nick NICK`. The user's actual resolved source
  is not known. Do not infer that this installed link or nickname assignment
  caused their report.
  The user subsequently clarified that they use the local flake directly:
  `nix run . -- --connect irc.libera.chat:6697 --nick NICK`. The earlier
  unresolved registry reference no longer describes their reported launch.
  The source revision of the already-running process is still not established.

## Image-marker diagnosis (2026-10-03)

- [x] Trace `[img]`: queued requests, rejected previews, absent native images,
  and terminal-protocol/crop fallbacks share the marker. Helper/payload rejection
  logs `image preview unavailable`; terminal fallback does not.
- [x] Verify percent-encoded spaces are preserved by the lexer and helper.
  The image region itself means the URL was recognized. Do not fetch a private
  chat URL or put it in fixtures; use synthetic images and `.test` URLs.
- [x] Verify Ghostty is recognized as Kitty graphics. Multiplexer detection
  strips image protocols, including explicit `TIMUI_IMAGE_PROTOCOL` selection.
  The reported shell instead has `TERM=xterm-256color`,
  `TERM_PROGRAM=Apple_Terminal`, and no `TIMUI_IMAGE_PROTOCOL` override. This
  identity selects no image protocol and explains the no-error placeholder.
  A per-launch `TIMUI_IMAGE_PROTOCOL=kitty` declares the actual Ghostty protocol.
  The source of the shell's incorrect terminal identity has not been traced.
- [x] Run `make test-media-image test-media-native test-media-portable`:
  synthetic formats/URL policy, native ownership/animation/clipping, and C99
  image/no-image controls all pass (`build/image-marker-synthetic-checks.log`).
- [x] Characterize the final native app with an encoded synthetic URL through
  `make test-pty-image-marker PTY_APP=/Users/angerman/Projects/zw3rk/birc/build/birc`.
  Three consecutive final six-case runs pass: automatic Ghostty emits a
  PNG/Kitty placement and clears the pending marker; protocol `none` and
  synthetic Ghostty+tmux retain the marker without an image error; rejected
  helper output adds one image error to `*log*`. The reported environment
  (`TERM=xterm-256color`, `TERM_PROGRAM=Apple_Terminal`, empty
  `TIMUI_IMAGE_PROTOCOL`) selects no image protocol and reproduces the marker
  without an image error after successful helper output. The same identity
  with per-launch `TIMUI_IMAGE_PROTOCOL=kitty` emits a PNG/Kitty placement,
  clears the marker, and has no image error. Exact helper arguments, private
  diagnostics, helper reaping, and terminal restoration pass. Evidence:
  `build/m27-image-marker-six-final-run{1,2,3}.log`; native SHA-256 `360c0ad9…`.
  The known older `71ax…-birc-0.1.0` installed wrapper passes all six
  fake-helper controls once (`build/image-marker-installed-six-checks.log`). This
  does not identify the running app revision or test the user's image host.
- [x] Obtain the affected terminal's multiplexer status, capability environment,
  and launch reference: direct Ghostty, the Apple Terminal identity above, and
  `nix run .`. No user shell settings were changed. The running app revision
  remains unknown; no Nix package hot-cache claim follows from this diagnosis.
- [x] Run `make proof PROOF_TIMEOUT=600` and `make test-build-deadlines
  test-build-config test-pty-deadlines`: standard proof and driver guards pass
  (`build/image-marker-standard-proof.log`, `build/image-marker-driver-checks.log`).
- [x] Keep the separate placement bound explicit: native preview slots and
  TimUI image placements are capped at eight per frame, including repeated
  uses of one cached token. Additional placements can show a placeholder;
  this limit does not explain the single-image report above.

## Unsupported-terminal preview policy (2026-10-03)

- [x] Adopt the requested policy: no image helper or blank image area when no
  terminal image protocol is detected; preserve ordinary chat text and URLs.
  Report one fixed explanation in `*log*` on the first eligible preview intent.
  Keep the user's automatic-image preference separate from terminal support.
- [x] Obtain approval for unsupported-terminal PTY expectation updates and
  Media state-constructor adaptations; preserve supported/malformed assertions.
- [x] Add a read-only native capability effect and query it once before UI
  startup. Any selected Kitty/iTerm2/Sixel protocol qualifies; do not probe the
  terminal, poll each frame, or change the vendored TimUI fallback renderer.
- [x] Implement and qualify pure request suppression and one-shot diagnostics,
  including invalid commands, off/on settings, reset, reconnect, and stale work.
- [x] Rebuild the final native app; pass native/pure guards, standard proof,
  and three consecutive final PTY runs. Do not claim the Nix package is cached.
  Unsupported cases call no helper, reserve no image rows, preserve the URL,
  and report exactly once. Supported and malformed-image assertions remain.

## Cached history image previews (2026-10-03)

- [x] Accept requested scope: show saved-history images inline, reuse downloaded
  assets, and fetch cache misses asynchronously through the live preview path.
  Apply the unsupported-terminal policy and preserve `/images on|off`.
- [x] Admit only visible restored chat messages through Media's existing
  bounded queue; cover tab/scroll/import/reconnect and stale completions.
  Keep replay/demo offline and never fetch a whole archive at startup.
- [x] Cache only validated remote source files with private permissions, hashed
  URL names, 64-entry/64-MiB FIFO bounds, and best-effort safe IO. Revalidate and
  normalize hits; corruption falls back to the guarded network path. Local
  previews bypass persistence; `BIRC_IMAGE_CACHE=none` disables the disk cache.
- [x] Guard same-key replacement at capacity: refresh must not evict an
  unrelated cached asset. Guard exclusive-create collisions: failed staging
  creation must not delete a pre-existing file. Both new negative controls
  failed before their fixes and passed afterward with synthetic files only.
- [x] Guard visible-token retention against hidden live completions at capacity
  and prevent pending helper work from starting after `/quit`. Explicit manual
  previews keep their existing behavior; active workers remain deadline-owned.
- [x] Qualify cache +/- tests, shared worker and startup/history regressions,
  standard proof, and final native PTY guards three consecutive times.
  Tests use only synthetic assets, fake helpers, and owned loopback IRC peers.
- [x] Preserve failing controls: the old app did not start a helper for visible
  restored images (`build/history-images-red.log`) and retained unsupported
  image placeholders (`build/m27-image-unsupported-red.log`). Cache misses/hits,
  unsafe paths/files, corruption, FIFO limits, same-key replacement, and staging
  collisions have synthetic positive and negative guards.
- [x] Resolve two new PTY fixture preconditions without changing production
  behavior or weakening assertions. Preview admission adds rows above the
  preserved bottom anchor; the new resize fixture must scroll the URL into
  view before resizing. The new endpoint fixture must declare its desired
  channel; an explicit empty saved channel list correctly overrides launch
  intent. Add a pure anchor characterization and keep the original resize,
  rejoin, stale-result, and checkpoint assertions. Evidence:
  `build/image-history-final-pty-1.log`,
  `build/history-images-resize-debug.log`, and
  `build/image-history-final-pty-2.log`.
- [x] Verify the final source in the captured locked Nix environment
  (`sh build/m27-locked-run.sh`), with telemetry disabled and bounded commands:
  - `timeout 1260 make build-ui BUILD_TIMEOUT=900`: final `-O2` native app passes
    (`build/image-history-native-build.log`). SHA256:
    `b4d4657261dee67efa1dd71c418d0ff1de7b2dc4e98489106dd83be81cc399c1`.
  - `make test-media-terminal test-media-history`: both JS-backend pure fixtures
    pass; final expanded history guards include the resize precondition
    (`build/image-history-core-checks.log`,
    `build/image-history-anchor-pure-check.log`). An initial native fixture
    compile reached its deadline before assertions; this is not a test pass.
  - `make test-media-regressions-js`: eight unchanged media, viewport, and state
    fixture goldens pass (`build/image-history-existing-pure-checks.log`).
  - `timeout 300 make proof lint-ffi test-media-native test-media-portable
    test-media-native-ubsan test-media-image test-media-image-cache
    test-media-image-bounds test-build-deadlines test-pty-deadlines`: all pass,
    including standard `ALL PROOFS CHECK`, C99 image/no-image controls, UBSan,
    formats/animation/public-fetch bounds, and driver deadlines
    (`build/image-history-final-checks.log`). No independent proof kernel used.
  - `make test-pty-image-marker test-pty-history-images
    PTY_APP=/Users/angerman/Projects/zw3rk/birc/build/birc`: ten native cases pass
    three consecutive times against that exact final binary, with unchanged
    final fixtures. History and live traffic share one physical worker while
    navigation and PING/PONG continue. Opt-out/unsupported/stale controls,
    exact URLs, history checkpoints, terminal restoration, and helper cleanup
    pass (`build/image-history-final-pty-{3,4,5}.log`).
  No full aggregate `make check` or Nix package hot-cache qualification was run.

### Nix prebuild follow-up (2026-10-03)

- [x] Retry the current source through the central `make build-package` target,
  with visible build logs, locked inputs, independent 900-second client/builder
  bounds, and an external 960-second monotonic supervisor. Before the attempt,
  a one-second timeout control exits 124 in 1.033 seconds. No pins or build
  recipes changed. Recorded UTC and monotonic elapsed time agree for this run;
  this does not explain the earlier timer discrepancy.
- [x] Verify the packaged source snapshot matches current source files
  (ignored local `__pycache__` directories are absent from the Git snapshot).
  The updated image helper builds successfully at
  `/nix/store/2fyfxazrgs8cd7r4p7iidar3jjfncqg5-birc-image`, and its installed
  `image.py` is byte-identical to this checkout.
- [ ] Complete the default client package and installed-package qualification.
  This attempt reaches `buildPhase`, then the outer 900-second bound cancels
  Nix. Make exits 2 after 900.320 seconds; its child command exits 124.
  Evidence: `build/image-history-nix-prebuild.log`. The ordinary build log does
  not distinguish Bend from Clang time; no compiler-stage or root-cause claim
  follows. The expected output
  `/nix/store/zc2y88k3pj122dc3fhh6zsl1w0253md4-birc-0.1.0/bin/birc` is absent.
  The existing package link still points to the older `71ax…` M26 package.
  All three observed owned Make/timeout/Nix PIDs are gone after cancellation.
  The native app remains built and tested, but this is not a Nix hot cache.
- [ ] Diagnose the unresolved package build with the existing default-off stage
  instrumentation and owned-PID controls before another long retry. Complete
  installed helper, TLS, Keychain, and clean-environment tests once the default
  package succeeds. The full latest aggregate `make check` remains separate.

## Muse parallel implementation handoff (2026-10-03)

The user requests that Muse in the sibling tmux pane take over the full remaining
docket, use a maximally parallel workflow with multiple concurrent subagents,
and continue through implementation and verification. The coordinating agent
will monitor this pane, review progress, and send follow-up instructions. This
handoff is implementation scope, not a request for another plan-only review.

### Baseline and verified evidence

- Repository: `/Users/angerman/Projects/zw3rk/birc`, existing branch `master`.
  Baseline commits: `4949dad` records the bounded Nix failure; `9b4997d` adds
  cached visible-history images; `8b51c48` covers terminal identity;
  `6d30d3a` fixes reconnect recovery with server-assigned nicknames. Preserve
  these fixes and all unrelated user changes. Do not push.
- Read this repository's current `AGENTS.md`, global
  `/Users/angerman/.config/ai/AGENTS.md`, applicable `CONTEXT.md`, and (for C)
  `/Users/angerman/.config/ai/C_GUIDELINES.md`. The old initial plaintext-only
  scope has been superseded: verified TLS defaults to 6697; explicit `--plain`
  defaults to 6667. Never weaken TLS verification or authentication isolation.
- Already implemented: reconnect authentication and the full desired channel
  set; private nonsecret preferences/autojoin profiles; IRC commands and
  lossless ACTION/message splitting; date-aware local timestamps; TLS/default
  endpoint parsing; confirmed uploads; diagnostic log; local text styling and
  emoji aliases; bounded asynchronous live/history image previews and private
  remote asset cache. Later roadmap features below are not implemented.
- Final native app `build/birc` is built at `-O2`, SHA256
  `b4d4657261dee67efa1dd71c418d0ff1de7b2dc4e98489106dd83be81cc399c1`.
  Standard proof, strict native lint, relevant pure/media fixtures, helper
  bounds/cache tests, native UBSan, and three consecutive final ten-case image
  PTY runs passed. Commands/logs are in the preceding history-preview section.
  This is not a latest full `make check` or a Nix package qualification.
- Current default Nix build reached `buildPhase` and was canceled by its
  900-second limit after 900.320 seconds; the cause/stage is not known. Read
  `build/image-history-nix-prebuild.log` and preceding Nix follow-up. All three
  observed owned build PIDs were gone at handoff. The old package link is M26,
  not current source. The new image helper is cached and source-identical.
- Existing diagnostic seams: `build-package-profiled`,
  `test-package-build-profile`, `test-perf-startup`, `BIRC_FRAME_PROFILE=1`, and
  owned-PID/monotonic timing controls. A profiled derivation is not the default
  app cache. Do not blindly repeat the same long build or speculate about its
  cause. Instrument, measure, hypothesize, fix, measure again, and validate.
- `build/m27-locked-run.sh` captures a usable locked shell; explicitly set
  `BEND_NO_TELEMETRY=1`. Its compiler/helper PATH predates provisioning updates.
  Fresh `nix develop --no-update-lock-file` is preferred when available; verify
  helper provenance and flags rather than assuming the captured PATH is current.

### Full remaining implementation scope

1. Diagnose/fix the Nix package build stall and measured startup lookup delays;
   resolve the remaining PONG/output-progress timing misses without relaxing
   deadlines. Successfully prebuild the default package and qualify installed
   helpers, TLS trust/linkage, Keychain wrapper, and clean-environment startup.
2. Implement server `005 ISUPPORT`, server-defined channel/mode metadata, and
   nickname privileges. Preserve secret-safe channel-key handling.
3. Implement native IRC wire formatting and colors in the view, with safe
   reset/control handling and exact source/URL/history preservation. Existing
   local Markdown-like styles and view-only aliases must keep working.
4. Implement per-buffer drafts and multiline composition, including focus,
   rename, close, paste, modal actions, UTF-8 clusters, and wire byte bounds.
5. Implement full disk-history search and paging, plus server history where
   negotiated/supported. Keep bounded IO, private files, endpoint isolation,
   replay semantics, imported IDs, and history checkpoint guarantees.
6. Implement IRCv3 account/away notifications and outgoing typing. General CAP
   handling must share one registration/CAP-END owner with SASL; keep timers and
   traffic bounded and prevent stale/offline sends.
7. Implement multiple simultaneous servers and IPv6 endpoints, sockets, and
   AAAA DNS. Use explicit server identity and generation for event routing;
   isolate credentials, preferences, history, buffers, and reconnect intent.
8. Implement fullscreen images and bounded OpenGraph cards, reusing media
   ownership, public-destination checks, certificate verification, and cache
   safety. Preserve automatic-image opt-out and unsupported-terminal logging.
9. Implement themes, desktop notifications, and a larger view-only emoji alias
   set. Preserve source/history, cluster-aware layout, per-event notification
   identity, and credential/private-diagnostic controls.
10. Complete the full latest `make check`, relevant sanitizers, native app/PTYS,
    fresh adversarial defect/style/DRY review, updated usage/checklist evidence,
    and default Nix hot-cache verification. Fix any discovered defects.

### Parallel ownership and completion gates

- Spawn multiple real concurrent subagents immediately for independent work.
  Maximize useful concurrency within actual tool/resource limits. Announce
  owners and concrete outputs; do not substitute parallel shell commands for
  subagents or stop after writing a plan.
- Suggested initial lanes: Nix/performance diagnostics; ISUPPORT policy;
  wire-style parser; draft/multiline policy; CAP/history policy; IPv6/ServerId;
  media/cards; palette/emoji/notification policy. Queue additional lanes if agent
  limits require it, and keep unrelated lanes moving when one is blocked.
- Use isolated worktrees if supported, or explicit disjoint file ownership.
  One integrator owns shared `Client`/`Buffer`/`Session`/`Net`/`View` types and
  their adapters. Keep one heavy native/Nix build lane; do not let concurrent
  compilers overwrite shared `build/` outputs or erase failure evidence.
- Use the root Makefile, locked Nix inputs, positive wall-clock bounds, and
  visible logs. Keep important rules in `LAWS.bend`/`PROOF.bend`; run the standard
  proof before Bend commits. No independent proof-kernel work is requested.
- Add positive and negative regression tests with each fix. New/changed PTYs
  need three consecutive runs against the exact final binary before commit.
  Preserve existing assertions. If an expectation genuinely needs correction,
  report the exact change and rationale to the coordinator for user approval;
  past fixture approvals are not permission to weaken unrelated tests.
- Never use real credentials, real Keychain writes, private supplied image URLs,
  user uploads, public upload services, or global process arguments in tests.
  Use synthetic files, fake helpers, and owned loopback peers. Do not introduce
  hand-rolled cryptography, move source pins, or push upstream.
- Keep implementations direct and bounded. Prefer shared pure policies over
  speculative frameworks, duplicate paths, or unnecessary configuration layers.
  Update `README.md`, `AGENTS.md`, and this checklist with verified facts.
- Report lane progress, actual commits, exact test outcomes, and blockers to
  the coordinating pane. Do not claim completion while any requested feature,
  fresh review, full checks, or default package prebuild remains outstanding.

### Lane status (Muse pane, 2026-10-03)

- Phase 1 running (7 isolated worktrees, base `3565392`): lane1 Nix/perf
  diagnostics + heavy build; lane2 ISUPPORT; lane3 wire styles; lane4
  drafts/multiline; lane5 history search; lane6 CAP/account/typing; lane7
  multiserver/IPv6. Integrator: Muse parent session (owns shared
  `Client`/`Buffer`/`Session`/`Net`/`View` merges; workflow synthesis reports
  conflicts).
- Phase 2 queued (root pool 8/8 full, native spawn rejected
  `root_capacity_exhausted`): lane8 fullscreen images + bounded OpenGraph
  cards; lane9 themes + desktop notifications + larger view-only emoji
  aliases. Queued as entries 8-9 of the launched workflow parallel batch;
  they start automatically when a slot frees. Retry as native isolated
  spawns with fresh command IDs if the workflow queue does not admit them.
- Acceptance gates (all required before completion): measured Nix build-stall
  fix + startup/PONG timing fixes without relaxed deadlines; default package
  prebuild + helper/TLS/Keychain/clean-env qualification; all ten scope
  items implemented with positive + negative tests (new/changed PTYs 3x on
  the exact final binary); fresh adversarial defect/style/DRY review; full
  latest `make check` + sanitizers + native app/PTYs; default Nix hot-cache
  verification. No push.
- Quality follow-up: lane1 prompt contradiction corrected (lane1 IS the sole
  bounded heavy build lane; lanes 2-9 use bounded JS-backend pure fixtures
  via `bend -o build/<name>.js` + `bun`, no native compiler runs). Live lane
  messaging is unsupported: the advertised `subagent_send_message` contract
  takes a spawn-returned native handle, workflow children have none, and
  peer listing shows no alternate route; four distinct shapes (agent
  path/id x queue/followup/minimal) all returned `invalid_input`. No further
  messaging retries. The correction stands as `LANE_CORRECTION.md` in each
  running worktree root, and every clarification is carried into explicit
  follow-up requests when each lane returns. No running work is cancelled
  for messaging. Lane1 evidence paths:
  `build/image-history-nix-prebuild.log`, `build/m27-locked-run.sh` (parent
  checkout only; copy into worktree, never write back). Entries 8-9 (media
  fullscreen/cards, themes/notifications/emoji) stay explicitly pending
  until real workers are admitted; verified by watching for
  `workflow-agent/8` and `/9`; any entry resolving
  `not_admitted`/incomplete gets a native isolated replacement spawn with a
  fresh command ID and the corrected prompt. A package built on the baseline
  is only a checkpoint; final qualification runs on integrated source. All
  integration and test gates remain open.
- Verified lane state: lane3 `wire_style.bend` + tests (+ `view` mods);
  lane4 `drafts.bend` emerging; lane5 `history_search.bend` + tests; lane6
  `cap_notify.bend` + tests (also touching shared `auth`/`client`/`session`
  — integrator owns those merges); lane7 `server_id`/`ipv6` + tests. Lanes
  1-2 no code changes yet at inspection time.
- Binding lane-return review findings (read-only verified against current
  snapshots; re-verify at return; no live-regression claims while
  integration is pending). Lane6 `cap_notify.bend`: (G6.1) `cap_event`
  gates only on command `CAP` — `:alice!u@h CAP me ACK :message-tags` and
  `:s CAP other ACK :message-tags` enable Reg typing; require
  connection-server prefix + current-recipient checks with hostile
  (−) / legitimate (+) guards. (G6.2) `caps_apply` OR-only accumulates —
  ACK `-message-tags` / DEL never clear; require cap-removal (−) /
  enable (+) guards. (G6.3) `notify_event` validates nick shape only —
  `:s AWAY :maintenance` becomes user `AwayOn`; require full-prefix
  server-like (−) / user (+) guards. `Reg` is not stored/called by
  Session in the snapshot, so G6.1/G6.2 are pure-policy defects. Lane3
  `wire_style.bend`: (G3.1) per-seg first/last-run boundary check only —
  `https://x.test.` + bold control + `evil` can retain a shorter clickable
  target; require punctuation/adjacent-style (−) guards against
  glued-visible-text linkification with exact-text (+) preservation.
  (G3.2) `wire_drop` silently deletes SOH inside the catch-all, gluing
  `htt<SOH>ps://x.test` into a clickable URL against the header comment;
  require disallowed-control (−) guards with SOH as boundary. (G3.3)
  inspect actual client/history sanitization: styles currently vanish on
  the incoming/history path and lane3 touches only `view*`; incoming
  /history integration stays an explicitly open item until demonstrated,
  never silently accepted. Enforced at lane-return review or implemented
  in the parent before final gates; detailed source hashes/lines to
  follow from the coordinator.
- Review evidence hashes verified identical in current snapshots:
  lane6 `cap_notify.bend` `c9bbf23f…5d41a0`, test `9fecb03b…39b93fe`;
  lane3 `wire_style.bend` `971df74d…995b49b`, test `e5b8fa49…749b988`.
  (G6.4) `step_out(Out{"#a",True,1000},999,…,False)` emits `done` and
  clobbers `sent_ms` 1000→999; idle `Out` at 1000 with stale composing at
  999 emits `active`. Stale suppression exists only on the active-refresh
  path (`cap_notify` lines 334-362), contradicting lane6 LAWS lines
  858-861 ("stays quiet … on a stale tick"). Require: stale ticks quiet
  AND state-preserving, plus fresh refresh/completion (+) controls. No
  introduced change to SASL CAP-END/welcome/reconnect barriers (good);
  Reg Session/reset/generation/composer integration stays open. Wire:
  SOH glue at line 165 and run-index guard at 207 still present (hash
  equality). SOH survives `sanitize_in` (`irc.bend` 492-495) while view
  glues across it, so a view-created link disagrees with `/links` on
  original text. Require: SOH as lexical boundary with painted byte
  suppressed; URL source suffix + shared `Links` trimming instead of
  last-run index; (+) real URL, CTCP ACTION, punctuation-followed-by-space,
  combining-cluster, ZWJ-toggle guards. Live buffer sanitize
  (`buffer.bend` 1230) and history serialization (`history.bend` 79) still
  strip styles — incoming/history integration stays open. Lane6 also
  extended `LAWS.bend` (866 vs 838 lines) — integrator owns that merge.
  Reviewers ran checker-only (exit 0); no rendering tests or native
  qualification — repair before acceptance, then qualify.
- Returned-evidence review (lane4 `de0f716`, lane7 `3fc8b03`; 2/9 done,
  lanes 8-9 verified admitted as `workflow-agent/8-9`, pool 8/8 full).
  Lane4 returned `complete:true` with live Session/Net/View integration +
  make wiring open; lane7 with proof citation, Net/Actor threading, native
  AF_INET6, and `/connect`/UI + 3x PTY open. Neither is a complete
  user-visible feature. Ordered parent integration: `3fc8b03`
  cherry-picked clean as `6156a5f` (4 new files, zero modifications);
  in-parent suite verification pending locked-shell probe. `de0f716`
  held unintegrated pending identity repair.
- Drafts repair blockers (D1-D6, all read-only verified): (D1) name-only
  `Draft{name,text}` collides control `server` at index0 with legal peer
  query `server` across get/set/retain/rename; test covers only the
  control draft. (D2) `rename` reuses `nick_rename_allowed`, which accepts
  `#room` via `target_wire`, so channel drafts move; use the shared
  query-source predicate, keep channel drafts unchanged, test ordinary
  query rename. (D3) reuse `Split.name_at` control identity (`*server*`
  at index0, LAWS 618) consistently in lookup/retain. (D4) `focus`
  set-then-get drops rejected outgoing text while loading the next draft;
  add over-byte/over-line/full-store (−) guards and preserve rejected
  input. (D5) `submit_lines` gates only on plan readiness, bypassing
  `submit_plain` synthetic/control read-only gates (`submit.bend`
  1511-1516); keep drafts on disabled/rejected sends. (D6)
  `reject_reason` maps invalid-target/NUL plan failures to
  cluster/credential-limit strings; consolidate `plan_line`/`send_text`
  validation so causes are not misreported. Require unambiguous
  server-scoped buffer identity, control/query distinction through
  focus/retain/rename/close, and coexistence + peer-rename (−/+) guards.
- ServerId/IPv6 repair blockers (V2-V5, all read-only verified against
  `6156a5f`): (V2) `parse_any.fallback` tries IPv6 on ALL `Endpoint`
  failures, discarding bad-port errors despite its comment; route only
  bracketed input to IPv6, retain bad port for DNS/IPv4 `:tls`, `:0`,
  `:65536` (−) plus positive DNS/bracketed-v6 ports (+). (V3)
  route/admission predicates use narrowing `U32.from_nat` `eq` with no
  `valid` gate, accepting invalid ID4 (and wrap collisions); fail closed
  at dispatcher or predicates; guard ID3 current/stale generations and
  invalid/reused slots. (V4) `same_scope` case-folds hosts while
  `credential_scope_ok` is exact; secrets must keep exact endpoint
  transitions, never case-folded scope. (V5) ServerId/IPv6 laws, proof,
  and Make registration pending. Native sockets/DNS/TLS/workspace
  integration remains required. Source-review findings, not live
  regressions; repair before acceptance, then qualify with native
  evidence. Final app must actually exercise drafts, multiserver/IPv6
  transports/DNS, notifications/typing, history, styles, and media/UX.
- Lane5 history_search return-review gates (H5.1-H5.4, read-only verified):
  (H5.1) `batch_collect.msg` (lines 568-584) admits on command+target+msgid
  without requiring `@batch` equals the collect `ref`: live/other-batch
  messages pollute `ChatCollect`. Require hostile/valid batch (−/+) guards.
  (H5.2) `cursor_note.add` (720-722) never moves a nonempty `oldest` and
  unconditionally overwrites `newest`: ingesting an older page corrupts both
  ends. Require backward/forward cursor (−/+) guards. (H5.3)
  `search_loop.empty` (304-314) finishes on empty bytes regardless of
  `remaining`: early EOF with `remaining>0` returns partial `DiskFound`
  success instead of a truncation signal. Require truncated/complete-file
  (−/+) guards. (H5.4) `cap_event` (406-408) gates on command+offer without
  server/current-recipient trust (same shape as G6.1). Require
  hostile/valid CAP (−/+) guards.
- Lane9 notify return-review gates (N9.1-N9.3, read-only verified):
  (N9.1) header promises at-most-once per event id but `seen` is a 64-entry
  FIFO (`remember`, line 84) and `theme_notify` line 88 explicitly asserts
  "evicted id notifies again" after 70 events. Require old/replayed
  /historical events stay silent while new live events notify, with bounded
  state and server-scoped identity or a Workspace-owned global id (Client
  `log_seq` is per-Client, not global across future servers); the
  renotify test expectation must be corrected, not the behavior weakened.
  (N9.2) `title_of` (lines 62-69) concatenates raw author/target with no
  sanitize/redact/bound while bodies get `Diagnostic.text` + 160 cap.
  Require bounded sanitized/redacted title before metadata handoff.
  (N9.3) default desktop helper/provisioning, async delivery, and Session
  dispatch stay runtime gates, not a completed desktop feature.
- Lane5 final gates (H5.5-H5.7, hashes verified: source `fbc20616…0308fb`,
  test `81305ca7…9b38a0`): (H5.5) `before/after/around/between_line` emit
  the raw anchor with no `msgid=`/`timestamp=` prefix — wire-incompatible
  per the chathistory spec (verified `msgid=m1` / `timestamp=...`,
  `draft/chathistory` negotiation, unprefixed batch type). Require exact
  BEFORE/AFTER/AROUND/BETWEEN output and malformed-ref rejection (−/+).
  (H5.6) batch open/close check command/arity/kind/target/ref with no
  trusted full-server-prefix check; private batches need sender-vs-subject
  validation (requested `bob` must reject `charlie -> me`, not just check
  target `me`). Require hostile/valid open/close (−/+) guards. (H5.7)
  `filter_unseen` compares every item against the original cursor, so
  duplicate fresh IDs survive: require `[m1,m1]→one`, `[m1,m2]→two`.
  Cursor boundary fixes must use requested direction/page order, never
  lexical sort of opaque IDs. Still-open required gates (not proven
  regressions): disk private-file admission at bare `File.open` (line
  364), ticket+endpoint+generation admission, negotiation reset, disk-IO
  preference checks. Executed +/− tests and native live integration stay
  required.
- Lane8 cards/fullscreen gates (C8.1-C8.6, `cards.py` hash verified
  `5db0e274…9d2acc`): (C8.1) fetched HTML resolves against the final URL
  but the cache stores HTML only and cache hits re-resolve against the
  original URL: relative `og:image` changes after cross-origin/directory
  redirects. Require fake redirected-relative-thumbnail first/cache-hit
  exact-equality guards, preserving the final base or bounded normalized
  fields. (C8.2) `parse_html` calls `card_image(clean(raw,1024))` so the
  inner length check never fires: a 1025-char URL becomes an accepted
  different 1024 URL. Reject overlong, preserve exact-1024; the current
  2000-char test may only hit `MAX_TAG_BYTES`. (C8.3) HTTP is admitted in
  `cards.bend` policy (`eligible_url` + test) and helper
  `image.url_parts`/`destination`. Enforce requested public-HTTPS at
  initial and redirect policy. (C8.4) cards cache adds independent
  64-entry/16-MiB atop image 64/64-MiB (shared total 128/80-MiB). Keep one
  explicit bounded media budget; reuse cache ownership/eviction policy
  where practical. (C8.5) `FullOn` stores `(target,url,token)` with
  open-time-only support/token checks; paint re-emits the stored token
  with no Media retention/support/generation re-validation. Require
  current checks or closure on disable/reset/eviction/endpoint/source
  removal. (C8.6) `observe` scans all buffers while `visible_candidates`
  filters: integrate only bounded visible unmuted eligible scheduling.
- Build-lane note honored: parent lightweight checks use executed JS
  variants (`bend -o build/*.js` + `bun`); native qualification routes
  through the single heavy lane without overlapping lane1; the registered
  `test-server-id`/`test-ipv6` recipes keep repo-conventional native
  builds with unchanged 180s deadlines.
- V2-V5 repairs integrated and proven: bracket-gated `parse_any` with
  preserved Endpoint errors; `Nat`-compared `ServerId.eq` with fail-closed
  `current_id` on all route/admission predicates; exact
  `endpoint_exact` on the credential-retaining reconnect path; 6 new laws
  + proofs + `test-server-id`/`test-ipv6` Make targets wired into
  `test-review-pure`. `server_id_demo=ok`, `server_id_ipv6=ok` (JS + Make
  native), `make proof` ALL PROOFS CHECK (227 laws).
- Lane1 numeric-trace gates (T1-T4, stderr claim read-only verified):
  (T1) `clock_ffi.c` claims no stalled-reader parking but uses blocking
  `write(stderr)` with EINTR-only retry: a full undrained pipe hangs the
  native IO loop. Require bounded no-block instrumentation plus an owned
  full-stderr-pipe negative PONG/quit deadline guard and a normal drained
  numeric-line positive. (T2) trace helper sends `/quit` before
  reverse-selecting last5/4/3/2/1, so stage5 (every `send_line` incl.
  QUIT) pollutes PONG chains: unrelated QUIT120/130/140 changes reported
  hop2->3 from 10ms to 100ms. Capture cutoff at confirmed PONG before
  QUIT and correlate one chain; unrelated later Cont/send must not alter
  PONG measurements. (T3) Actor/Net trace AFTER `Chan.send`: a full
  channel parks the sender so receiver2/4 can precede sender1/3. Add
  pressured-channel characterization before requiring stage order or
  interpreting gaps. (T4) the pinned runtime serializes normal effects
  and `net_trace_run` does no `io_work`: no verified trace-global race —
  do not add atomics/locks speculatively. Commit correct default-off
  instrumentation, measure valid phase splits, then
  hypothesize/fix/re-measure per AGENTS performance rules.
- Lane1 final trace guards (T5): short writes/errors currently ignored
  while `seq` advances; EINTR retry is unbounded. Require finite
  short-write/EAGAIN/EINTR injection handling and reject backwards
  64-bit times including 10->8ms (`net_trace.py:138` presently permits
  backwards under 60000).
- Lane2 `e705405` return-review gates (I2.1-I2.6): `-TOKEN` removal
  missing; `STATUSMSG=` cannot clear; wrong-recipient 005 alters policy;
  strip removes interior prefix symbols (`a^b`->`ab` with `PREFIX=(o)^`,
  `a^^` gains `o`) rather than only the leading run; `CHANTYPES=$` makes
  `is_channel` true but `join_admit` via fixed `Channels.valid` rejects
  `$room`. Require minimal hostile/legitimate guards before acceptance.
  Docs note: modern `rfc1459-strict` is current standard;
  legacy `strict-rfc1459` alias compatibility is optional, not a wrong
  spelling. Numeric 324 redaction needs recipient-aware offsets before
  integrating. Final hashes/details follow.
- Native follow-ups launched (pool had 3 free): `fix-g6-return`
  (G6.1-G6.4 on `cbf6f1a`, cap_notify/auth/client only) and
  `feat-ipv6-transport` (socket/DNS/TLS adapters, transport/FFI/actor/DNS
  only). Handles: `fix-g6-return` = `main/fix-g6-return/10`
  (`01a10130-ed7c-7981-8699-58e9245efd25`); `feat-ipv6-transport` =
  `main/feat-ipv6-transport/11`
  (`01a10130-f37d-7881-a004-64b8c3c24f6c`) — messageable for follow-ups.
  `fix-i2-return` = `main/fix-i2-return/12`
  (`01a10134-cc78-7870-bd94-07a55f332cae`).
  `fix-h5-return` = `main/fix-h5-return/13`
  (`01a10135-bce3-7220-a6aa-cd3febcae324`) on `e8b66b3`;
  `fix-c8-return` = `main/fix-c8-return/14`
  (`01a10135-c05b-7a31-b87f-3a5a305a70d9`) on `4b6bfee`.
  Parent keeps D1-D6 and Session/Workspace wiring.
- Lane1 return gates (L1.1-L1.5, all read-only verified): (L1.1)
  `nix/birc.nix:25-43` unconditionally emits stage timers in the default
  `buildPhase`. Preserve default-off instrumentation. (L1.2) flake
  removes `birc-profiled` (no `profiled` reference left). Preserve the
  separate opt-in profiled path. (L1.3)
  `tests/package_build_profile.py:30-32` flips guards to assert timers in
  the default package ("must stay merged into default"). Do not change
  existing tests to waive this requirement. (L1.4) Makefile
  `PACKAGE_PLAN_TIMEOUT` 45→180 (parent baseline is 45). Restore the
  unchanged deadline; diagnose/measure the eval path instead. (L1.5)
  Makefile redirects `nix-load-warn.sh` stderr to `/dev/null`,
  suppressing its only warning, and the script infers daemon scheduling
  loss solely from host load. Retract that root-cause claim; do not
  substitute a load warning for fixing/qualifying the measured package
  stall. Full details follow.
- Lane9 final gates (N9.4-N9.7, return commit `2b1033d`): (N9.4)
  `notify-send` needs `--` before title/body (`Req{--help,B}` must stay
  literal operands). (N9.5) suffix helper-name matching admits
  `x-notify-send`/`notosascript` against the unknown-helper contract:
  compare exact basename. (N9.6) theme duplicates default kind/status
  palettes and the status branch tree in View: one canonical
  table/selector with fixed-value guards. (N9.7) incoming Feed → BIRC2
  load → production renderer emoji/style/source/URL roundtrip plus
  provisioned async desktop delivery stay required. N9 repair routes to
  a native worker when capacity frees (pool 8/8; queued after G6/H5/C8/
  I2/IPv6).
- Lane1 checkpoint `cb4e99f` is NOT an accepted package: all reviewed L1/T
  defects remain, plus final gates (verified): new build-package driver
  omits prior profiled `-L`/`--keep-failed`, hiding live stage marks and
  dropping retained failure evidence; `test-nix-eval-profile` omits
  `--full`, measuring only config/trivial/store queries while
  `app_program`/`develop_true` stay gated; `run_phase` discards stderr
  (`out, _`), buffers without a byte cap, and prints `nix_eval=ok` even
  on failure/timeout. `develop_true` includes realization, not eval-only:
  label it correctly, separate actual phases, keep bounded failure
  evidence, never infer package success from trivial probes. Positive:
  no `flake.lock`/bend pin move or binary shortcut found. N9 spawn
  attempt rejected (`root_capacity_exhausted`): lane1's agent still
  occupies its slot (running), so no slot actually freed — retry N9 with
  a fresh command ID on the next real return; when G3 returns, admit the
  L1/T instrumentation+measurement repair owner (else parent does it as
  the single heavy lane after runtime integration). Measured root-cause
  and successful integrated default package/prebuild gates stay open;
  diagnostics are never completion.
- Follow-up tool-loss re-delegation: both I2 and C8 second-review
  follow-up sessions returned terminal WITHOUT changes (successor lost
  all work tools except `web_search`/`write_todos`). Re-delegated as
  fresh scoped natives `fix-i2-second` (on `f672365`) and `fix-c8-second`
  (on `567b62d1`); handles retained on spawn return.
- G3 return `1cf9028` (lane3 done; only lane1 original still active).
  Filled both free slots: `integ-g3-wire/19`
  (`01a10152-1f30-7262-8284-3513d4d7c03a`) for G3.1-G3.3 repair + live
  /history integration, and `adapt-sess-ws/20`
  (`01a10152-2554-7aa3-a49b-b75890097c75`) for Session/Workspace
  drafts+multiserver adapters on frozen Drafts/Key/Sid/V6 interfaces.
  Parent owns all merges. Pool 8/8 again.
- H5 second review (H5.8): opaque-ID anchor mismatch in `6c858f1` —
  cursor `oldest=opaqueT…Z` emits `timestamp=` instead of `msgid=`,
  `a=b` yields None, explicit `msgid=a=b` rejected. Known-cursor fetch
  must prefix `msgid=` under the incoming contract; bare user timestamp
  parsing stays separate. Follow-up to the completed H5 handle rejected
  (pool full); fresh `fix-h5-second` queued for the next free slot. H5
  is not complete; no generic ambiguity in runtime.
- I2d privacy guard delivered to running `fix-i2-second/17` via `queue`
  mode (accepted; `followup` mode failed mapping twice). Lesson: live
  natives take `queue`; completed handles need free slots for follow-up
  successors.
- Draft follow-ups (parent): centralize the duplicated
  `Drafts.line_valid`/`Sub.send_text` check into one shared definition;
  remove the unused `Chunks` import; NUL-line whole-send rejection
  (valid line then NUL line → zero wires/self-echo) with paired two-line
  Unicode exactness; invalid ServerId + empty composer fails closed;
  nonzero `server` query stays writable (already guarded).
- Causality correction: the proof-timeout note claimed pool load as the
  cause; retry timing plus host load alone do not prove causality. The
  load hypothesis is unproven — final qualification re-runs proof on a
  quieter machine and records actual phase evidence. Performance remains
  an unmeasured hypothesis throughout.
- Lane1 64KiB review: no new correctness defect in the clamps, but
  demand plaintext+TLS >4096 bursts ending PING, equal framing across
  4096/65536/mixed CRLF+UTF8 segmentation, overlong-record-then-valid-
  PING, stalled-writer deadline, and stale-generation guards.
- IPv6 merge rule: preserve lane1 `sockaddr_storage`/family handling AND
  the 64KiB cap plus lane1 traces; no whole-file overwrite of
  `dns_ffi.c` (surgical merge with both sides' tests green).
- Returned-source fix/test gates (not new feature scope): (V6-fb)
  `8cfadf2` dns523-544 takes the first successful AAAA and skips A;
  actor304 dials only that address, `after_conn280` reports failure —
  dual-stack host with unrouted/refused IPv6 but healthy IPv4 regresses.
  Require production resolve_ns-to-actor owned dual-stack test: AAAA ok
  + IPv6 connect fails → A peer succeeds; healthy IPv6 wins. Keep
  original-hostname TLS verification; never downgrade transport or
  accept failed verification. IPv6 worker is terminal: scoped follow-up
  queued for the next free slot; V6 is not accepted until then. (G3x)
  `1cf9028` wire_style:169 SOH glue + 204-207 trailing lexeme + buffer/
  history/restoration stripping + real Feed-BIRC2-View roundtrip —
  messaged to running `integ-g3-wire/19`. (H5y) `6c858f1`
  filter_unseen954-959 truncates combined seen to 100 mid-page (100
  saved + 99 fresh then saved-tail reimports old ID): preserve immutable
  original membership + page dedup or bounded-200 union; negative
  99fresh+saved-tail→99, positive 100fresh→100. Folded into queued
  `fix-h5-second` scope. (L1Tx) `c1a3534` run_phase pipe/descendant
  defect — messaged to running `fix-l1t-trace/16`.
- IPv6 transport returned (`635abc6` FFI + `8cfadf2` DNS glue, branch
  `ipv6-transport-adapter`); H5 repair returned (`6c858f1`, worker
  reports 33 laws green + both suites ok). Both pending parent review
  against transport/H5 gates before integration. G6 `a504fca` verified
  (G6.1-G6.4 shapes + `cap_notify_demo=ok` in repair worktree); queued
  for ordered integration.
- Second-review blockers (I2/C8/D): (I2a) `join_swap` validates `#+tail`,
  not original identity: `CHANTYPES=*` lets `*log*`/`*LOG*` bypass
  reserved policy — require original `Cl.target_wire`/canonical equality
  before prefix substitution, keep advertised `$room` positive. (I2b)
  `apply_key.neg` ignores `has_eq`: `-NICKLEN=garbage` resets 31→9 —
  ignore malformed removal (primary-verified: `-PARAMETER` takes no
  value), valid `-NICKLEN` resets. (I2c) `reset_statusmsg(-STATUSMSG)`
  revives `@+`: explicit withdrawal must disable support (verified
  primary default none + modern PREFIX-subset rule); setter must require
  current PREFIX subset (`PREFIX=(o)^` + `STATUSMSG=@` must not authorize
  `@`). ISUPPORT fixtures must join the Make test/check graph on
  integration. (D-cap) repaired `set`/`set_ok` cap per supplied ServerId
  without `Key.valid`: invalid/huge IDs each admit 16 — validate public
  admission (invalid-ID set unchanged, `set_ok`/`focus_admits` false,
  valid3 positive). (D-bi) `submit_lines` checks synthetic spelling, not
  resolved `bi`: `(init,0n,"server",…)` emits while `submit_plain`
  rejects active0 — require bi0/read-only resolved-pane rejection,
  preserving real nonzero peer query `server` as positive (pure adapter
  defect). (C8d) separate locks/accounting still exceed the budget even
  sequentially; require both writer orders + interleaved/concurrent
  totals under one shared lock/accounting. (C8e) UTF-8 envelope write vs
  ASCII read breaks Unicode final-base hits — add Unicode miss/hit
  exact-equality. I2/C8 sent as native-handle follow-ups; D fixed in
  parent. Nothing here is fully repaired yet; no weakened tests.
- I2 repair returned `f672365` (5 files, +453/−21, 9 new laws, worker
  reports proof green in its worktree); pending parent review against
  I2.1-I2.6/PREFIX/324 gates before integration. N9 worker admitted into
  the freed slot: `main/fix-n9-return/15`
  (`01a10140-badb-7551-a7a7-bf6e55680c5b`) on `2b1033d` (pool 8/8 again).
  `fix-l1t-trace` = `main/fix-l1t-trace/16`
  (`01a10144-754c-7822-90e2-122468ef3e98`) on `cb4e99f`.
  `fix-i2-second` = `main/fix-i2-second/17`
  (`01a1014a-b094-78a0-be43-78cf4f712a51`);
  `fix-c8-second` = `main/fix-c8-second/18`
  (`01a1014a-b54a-7811-96e4-76e6154bda20`).
  `fix-v6-fallback` = `main/fix-v6-fallback/22`
  (`01a1015d-5d7f-7f12-8c63-a21d92dfa680`);
  `fix-g6-second` = `main/fix-g6-second/23`
  (`01a1015d-6309-7cd1-acb1-e67247a43966`);
  `fix-c8-third` = `main/fix-c8-third/24` (above);
  `fix-i2-third` = `main/fix-i2-third/25`
  (`01a10162-da20-7d60-be2f-96e496de7bbd`).
  `fix-h5-completion` = `main/fix-h5-completion/28`
  (`01a10176-3879-7f31-8593-be035acdf0b8`).
  `fix-h5-second` = `main/fix-h5-second/21`
  (`01a10154-3e5c-7011-b206-e6f3c8561637`) on `6c858f1` (H5.8+H5y).
- G6 second review (G6.5+G6-star, queued follow-up; G6 worker terminal,
  pool full): `out0` has `sent_ms=0` and `step_out441-444` globally
  treats U32 `elapsed>=2^31` as stale before any clock sample — first
  composing tick at `now=2147483648` stays `Out0` forever through that
  half-cycle. Treat uninitialized state as unobserved, not a timestamp:
  positive first step at 2147483648 emits active, negative established
  sent1000/now999 stays quiet+unchanged, positive genuine forward-U32wrap
  stays live. Shared G6 CAP owner must also preserve legitimate prereg
  `CAP * LS/ACK` (same primary spec as H5) without accepting peer prefix
  or wrong registered recipient.
- C8 parent-fd race blocks acceptance (`254a0eb`): `cache_directory`
  opens parentA then closes; `cache_write` reopens parentB for lock but
  writes retainedA/cards — parent swap under held lock exceeds the
  shared budget. Picks `922522f`/`31eba51`/`d25dfd9`/`3f772fd` remain a
  checkpoint (verified: `media_cards=ok`, `media_image=ok`,
  `cards_policy=ok`, `cards_view=ok`, existing image formats intact).
  Scoped `fix-c8-third/24` (`01a1015f-4d37-7192-9e2d-426bcb3702f7`) owns
  the one-parent-fd repair + stable-parent/parent-swap guards.
- G6 star correction delivered to running `fix-g6-second/23`: prereg
  star already supported (`cap_recipient_ok138`) — no invented fix;
  exactly-one-CAP-END STAR/SASL-fold guard only. Remaining G6 defects:
  uninitialized clock + malformed source gate (share
  `Auth.server_source` via `Endpoint.host_ok`).
- N9-second (eighth-scope FIFO eviction vs at-most-once: fail-closed
  admission or Workspace-global-ID/history seed) and L1T-second
  (pipe/orphan kill + isolated-baseline correlation) queued for the next
  free slots. N9 return `9367c05`/`758291c` and L1T `727e0c8` stay
  unaccepted until then.
- I2d FAILED in `cc7d169` (return unaccepted, fresh repair queued):
  `reset_chanmodes547-550` restores compiled `b,k,l,imnpst` without a
  certainty bit, so prior `CHANMODES=b,k,s,l` then withdrawal plus
  `+lks [s3cret,50]` yields `[s3cret,[channel key hidden]]`, exposing
  the actual key. The queued `fix-i2-third` must preserve unknown arity
  after withdrawal and conservatively hide key-bearing args until valid
  readvertisement (paired known-map exact-redaction positive). Queue
  accepted the I2d message but the return did not implement it.
- I2c lifecycle residual (folded into queued `fix-i2-third`, not a new
  feature): `STATUSMSG=@` explicitly valid, then `PREFIX=(o)^` leaves
  raw `@` authorized (`PREFIX602` updates only `pv`;
  `is_channel735`/`chan_target761` never intersect current sigils), and
  the `caret_cleared` fixture clears status first so it misses the
  order. Require negative explicit `STATUSMSG=@` then `PREFIX=(o)^`
  refuses `@#room`, positive `PREFIX=(o)^` then `STATUSMSG=^` permits
  `^#room`; effective STATUSMSG authorization stays a current-PREFIX
  subset on both changes including order-independent 005 token bursts.
  Retain exact-resident channel precedence and actual `+#room`
  identities; preserve all established baseline fixtures — new
  candidate guards characterize this transition.
- N9 replay counterexample confirmed: `s0/id1, s1..s8/id1`, then
  `s0/id1` notifies again; the `evictedid` test covers only 70 events
  on ONE scope. N9-second scope adds this cross-scope guard; bound ≤8
  and retained-scope-fresh-ID positive remain.
- Adapter parallelization plan: runtime workers (G3-wire, SessWS, V6,
  H5-second, G6-second, C8-third) keep implementing without waiting for
  every pure-policy merge. Once interfaces freeze, parallelize I2/G6/H5
  and C8/N9 Session adapters within actually available slots; parent
  owns shared types and all final merges.
- Feature-vs-policy line (no premature completion): C8 helper/cache,
  I2 metadata, G6 Reg/typing/notify, H5 disk/server paging, and N9
  theme/async/helper are NOT user features until live Session/Net/View
  wiring stores and dispatches them. Explicit runtime-adapter owners
  per scope go out as slots open (queue: C8-session, I2-session,
  G6-session, H5-session, N9-session after the in-flight repair
  rounds); parent merges all shared Session/Workspace fields and
  preserves one canonical submission/CAP/media/event-identity path.
  Final native app/PTYs + installed Nix checks run LAST on the exact
  integrated source.
- V6-fallback has `348fe16`; production fallback/native fixtures get
  reviewed on return. L1T-second and H5-completion queue stays open.
- N9-second returned (`fe9631e` + `800f893`, worker reports cross-scope
  fail-closed admission + canonical theme merge point + 12 laws, prior
  suites green); pending parent review against N9x/N9y before
  integration. Freed slot went to `fix-l1t-second/27`
  (`01a10175-6e34-7f51-9ff4-4077898ce3b0`) on `727e0c8`. H5-completion
  remains queued next.
- G6-second returned `480ec9f` (worker reports uninitialized-clock +
  shared source-gate + exactly-one-CAP-END fixes, shapes unchanged);
  pending parent review before integration. Freed slot went to
  `fix-h5-completion` (timestamp validator, `.sss` positive, early-EOF
  IO guard, prereg-star gate); handle retained on spawn return. No
  repair rounds remain queued; adapter owners (C8/I2/G6/H5/N9-session)
  go out as repair workers return.
- SessWS adapters returned (`c7f5039` session_drafts + `b04f759`
  workspace partitions, worker reports S1-S5 + laws + JS suites green,
  native/PTY left to parent); pending parent S1-S5 review + shared-type
  merge. Freed slot went to `adapt-c8-session/29`
  (`01a10176-c4b8-7263-ae47-70f3a4b5c25a`). Next adapter owners
  (I2/G6/H5/N9-session) go out as repair workers return.
- SessWS return REJECTED, not merged: independent re-review shows
  Session byte-identical (`SHAba153b85`), still direct
  `Drafts.submit_lines241`, whole-block `input_sensitive246`,
  post-submit `Drafts.focus279`, gen0 reuse213, old composer266 — all
  five negatives remain; tests cover only disconnected single-line,
  bump-without-remove/readd, and store-only reset. Reported green is
  not S1-S5 completion. Fresh `fix-sessws-s1s5` (all five + ONE seam,
  tests-first, exact negatives + paired positives) is queued
  FIRST-priority (spawn rejected `root_capacity_exhausted`; retry with
  a fresh command ID on the next free slot — the burned ID must not be
  reused). Mandatory isolation/privacy gate, not expanded scope.
- I2-third returned `52582d4` (worker reports `cm_known` certainty +
  PREFIX-subset intersection + guards); pending parent I2d/I2c-life
  review before integration. Freed slot went to `fix-sessws-s1s5/30`
  (`01a1017c-dc85-7701-a06f-980b059bfa66`) on `b04f759`.
- G3 acceptance blockers (fresh review; send in INITIAL repair task if
  running worker returns without consuming queues — queued messages
  alone are not completion): (a) styled MODE/`324` key flags bypass
  `mode_has_key` raw validation and leak keys to history — normalize
  protocol channel/mode atoms before the shared predicate; paired
  MODE/324 styled negatives + ordinary `+k` redaction / non-key
  visibility positives. (b) `credential_echo` raw author vs canonical:
  styled `:m<02>e!u@h` / `IDENTI<02>FY` evade suppression into own
  chat/history — normalize classifier author + displayed credential
  verb; peer ordinary IDENTIFY stays chat. (c) JoinPlan raw KICK
  channel/victim vs canonical — styled self-KICK keeps rejoin intent;
  one shared canonical protocol-atom seam for
  Client/Auth/Submit/JoinPlan/I2, styled nonsecret chat intact. Plus
  earlier queued mention-boundary guard (decoded-text matching). No
  acceptance on green pure style fixtures without framed
  Feed/history regressions.
- Integrated G6 chain (`ac12b39`/`1d5239f`/`5322e2f`/`d3592d6`) and N9
  chain (`deb97e3`/`d3cfb0b`/`35720b9`/`4b7e0d0`/`dce75ca`) with
  proof-junction resolutions (imports + tail laws/proofs kept both
  sides); N9 `800f893` independently confirmed clean (fail-closed
  admission, no eviction, max-advance; postrestore seed must use final
  imported fresh `log_seq` before live dispatch — N9 runtime note).
- Exact follow-up repairs FOLDED into runtime-integration initial tasks
  (no more adapter-only rounds): (I2) `52582d4` loses valid
  STATUSMSG-first declarations (`STATUSMSG=^` then `PREFIX=(o)^` ends
  empty, either order/burst) — retain declared STATUSMSG, derive
  effective PREFIX intersection on either update; paired both-order
  positives, stale-`@` negatives both orders, malformed/valueless/
  removal never authorize, `+#room` unchanged; keep `cm_known` false
  after invalid CHANMODES while withdrawn, valid readvertisement alone
  restores precision; register ISUPPORT goldens in Make. (G6) `480ec9f`
  sentinel collision — observed offline `step_out(out0,0)` resets to
  `Out{"",false,0}`, then backward `now=MAX` emits active as unseen —
  add observed bit/discriminant; negative observed0→max quiet, positive
  fresh out0-at-max + true max→4000 forward wrap.
- Runtime integration starts after toolchain proof: parent owns one
  adapter; freed slots to I2 live state, G6 CAP/typing (+sentinel fix),
  H5 disk IO/runtime, N9 View/async (+seed note); SessWS30 + C8session29
  own theirs. IPv6 `connect_dual` must actually precede TLS in Actor,
  never fallback on arbitrary TLS verification failure.
- PROCESS GATE (unqualified marks): G6 picks `ac12b39`/`1d5239f`/
  `5322e2f`/`d3592d6`, N9 picks `deb97e3`/`d3cfb0b`/`35720b9`/`4b7e0d0`/
  `dce75ca`, I2 picks `fb0cb5a`/`c3394dc`/`68d97cb`/`ab3a2bf` remain as
  source commits but are UNQUALIFIED until bounded `PROOF.bend` passes
  on the exact merged tree; no reset. Future integrations use
  `cherry-pick -n`/stage + bounded proof on the staged merge, then
  commit. No stale baseline native/PTY or cached old package counts as
  final qualification. Toolchain: bend derivation
  `jdg69smprgzqs0qi54b40g915x0r8cxb` GC'd (reviewer 127 + local
  confirm); reprovisioned locked shell yields
  `/nix/store/vp83vc93fd31ykls5x39mjac3xjh08mw-bend`; captured runner
  regeneration in progress; `bend --version` is not a flag (use
  `bend --help` + real runs for verification).
- QUALIFIED: `build/m27-locked-run.sh` regenerated from fresh locked
  env (Bend 2.0.34 verified) and `make proof` on the exact merged tree
  reports ALL PROOFS CHECK (exit 0) — G6/N9/I2 picks above are now
  qualified. L1T-second returned (`d7c39dc` nix pipe-orphan/group-kill +
  `1d7b544` trace correlation, on `repair-l1tb` from `727e0c8`);
  pending parent review before integration. Freed slot goes to I2 live
  runtime integration (folded STATUSMSG-first + `cm_known` + goldens in
  initial task); parent owns G6 CAP/typing runtime (+sentinel fix).
- L1T-second parent review: `--self-test` re-run GREEN (8/8 guards);
  measured stage-3 (Cont-enqueue) marks per fixture 1-3, stage-5 x2+ in
  multi-chain fixtures; integration DEFERRED to lane1 return (trace/nix
  is lane1 scope; `352a7c3` sits on lane1-line `c1a3534`, parent lacks
  `net_trace.py`). Fresh review adds folded L1T follow-ups for the
  build owner: correlate probe still borrows late registration stage1
  (`[2,3,4,5,1,2,3,4,5,1]` returns hops, must be uncorrelatable;
  isolated `[1..5]` positive; phase5 cutoff is not transaction
  identity); poll0+blocking-write is not hard-bounded under contention
  (prefull single-writer pipe only checks full-before-poll); `d7c39dc`
  orphan fix lacks committed paired fixture; changed PTY needs
  exact-binary 3x evidence before acceptance.
- Lane1 timing evidence (`build/nix-prebuild-merged.log`): start
  10:23:30Z, codegen 259s, native begin then NO completion before 900s
  timeout 10:38:48Z (640s native, cancelled) — narrows THAT attempt to
  native compilation, not root cause, not predictive. Build owner must
  instrument native phases (default-off) before any optimization; no
  more uninstrumented 900s builds. Latest-default-package success
  remains a gate. Runner path
  (`/nix/store/vp83vc93fd31ykls5x39mjac3xjh08mw-bend`, Bend 2.0.34)
  sent to all 6 native workers (lane1 is a workflow child: messaging
  rejected, cannot receive); merged-tree proof run via regenerated
  runner. Liveness probe timed out: verify next command receipt, never
  treat badges as qualification.
- H5 `617ad61` folded repair (H5-runtime initial task, next free slot):
  `Utc.parse` reuse still admits no-fraction/1/2/4-digit stamps; IRCv3
  chathistory line53 requires `YYYY-MM-DDThh:mm:ss.sssZ` — keep
  calendar validation + exact length24/dot19/three-digits/Z23; paired
  no-ms/`.1`/`.12`/`.1234` negatives + `.123Z` positive; do not weaken
  shared `Utc.parse`, drop wrong NEW no-ms positives. HELD for user
  approval: 4 missing-ms fixtures + 2 laws to `.000Z` with rejection
  guards.
- Pre-existing MODE key leak (main `5105ee1`, not G3-only): raw `+k` /
  unsigned `k` can fail `flag_chars` and persist synthetic keys via
  MODE/324; `/mode #room +k` opaque secret passes
  `Sub.input_sensitive=false` (raw recall). Sent to I2-live owner:
  ONE shared conservative key detector for Commands/I2/Submit +
  framed Feed->History + composer-recall guards; keep `+k`/`-k`
  redaction, `+o bob`, ordinary PRIVMSG positives. HELD for approval:
  NEW unsigned-k ISUPPORT expectation raw->hidden (no baseline
  conflict, ask-first rule still applies).
- Parent G6-sentinel fix in progress (uncommitted): `OutState` gains
  `seen` bit, `out_sentinel_ok` + law + demo `g66` guards (red
  observed, now `cap_notify_demo=ok`); merged-tree proof re-runs TIMED
  OUT (124) under high load (avg 77-87, 25 bend procs; retry measured
  real 3m0.5s user 1m16s sys 14.9s) — cause UNVERIFIED, no deadline
  change. Wording correction: high load is context, not verified
  causality. `--check-only` validation in flight; no proof-input
  writes while exact-tree proof work runs.
- I2-live P2 sent (queued): CHANMODES duplicate-letter rejection across
  combined classes via existing nodup helper; negative malformed
  readvertisement after withdrawal keeps `cm_known=false` + whole-tail
  hidden, positive unique `b,k,s,l` restores `hidden|50`; no fixture
  conflicts. (P1 key-detector + held unsigned-k edit still stand.)
- V6-fallback returned (`348fe16` dual policy + `connect_dual`, no FFI
  changes; `2a36383` guards) on `repair-v6fb`; transport line
  `635abc6` (FFI AF_INET6 dial/v6 UDP) → `8cfadf2` (AAAA-first DNS) →
  `348fe16` → `2a36383` is entirely unintegrated (parent V6 is pure
  policy `6156a5f`/`c2f8e09` only). Actor `dial_begin` wiring is
  integrator-owned: `connect_dual` must precede TLS, never fallback on
  TLS verification failure — parent follow-up after staging. FFI
  native qualification via lane1/final gates (heavy lane).
- H5 chain mapped (`e8b66b3` → `6c858f1` → `8b5000c` → `617ad61`);
  parent stages it (new `-n`/proof/commit process) then spawns
  H5-runtime (fraction exactness + disk IO/runtime) into the freed
  slot. Order: sentinel proof -> commit -> stage H5 -> proof ->
  commit -> spawn H5-runtime -> stage V6 -> proof -> commit.
- V6 fixture review (parent): `connect_dual` is TCP-connect fallback
  only (v6 -> v4 on TCP failure, socket+IP out, no TLS at that layer);
  fixtures pin v6-wins-no-fallback, AAAA-then-A order, SNI carries DNS
  hostname, wrong-host fails, owned loopback + synthetic certs with
  bounded timeouts — no residual found; coordinator independently
  reviews. Actor `dial_begin` generation-guarded wiring stays
  integrator-owned (parent, after staging).
- G3 inspection (owned worktree metadata only, no global args): HEAD
  `1cf9028` 19:14, 16 dirty files, no src/tests writes in 25+ min BUT
  `build/js` suite artifacts fresh at 20:38 (feed/diagnostic/dns JS
  runs ≤13 min old) — active at a normal slow boundary under load, NOT
  a stalled command; no cancellation. Four queued corrections await
  consumption before return; no further queued notes.
- Retained: lane1 unsafe stale/duplicate PONG acceptance blockers;
  Session since dirty-changed so final review inspects current source.
  All source commits retain proof provenance; no proof-input writes
  while exact-tree proof work is in flight (docs-only commits OK).
- `--check-only` on PROOF.bend ALSO timed out (124, 170s) under
  contention — even elaboration-check exceeds the bound; cause
  unverified (consistent with starvation, not established). Demo
  (`cap_notify_demo=ok`) still validates the cap predicate subgraph;
  only the ~10 added LAWS/PROOF lines lack mechanical validation.
  Decision: commit sentinel fix explicitly UNQUALIFIED (precedent
  pattern, provenance retained, final proof still mandatory) rather
  than deadlock all staging on contention; qualify via full proof
  when a window opens. No deadline change.
- Lane1 pins (drop old blockers): actor `af2c4fe3` gen-tagged
  Sess.Pong + writer574-577 gen gate FIXED; Session `b552db39`
  duplicate removal FIXED (current dirty source). net_trace residual:
  final QUIT stage5 misattributed to PONG (registration[1..5] +
  fastPONG[3,4,5,1,2] + QUIT[3,4,5] reports delayed QUIT hop2_3=1000ms
  vs PONG-sent 12ms); reader path no longer causally orders UI stage2
  before 3/4/5 — needs true request identity/branch semantics, late
  QUIT must not alter PING metrics; keep exact quitcap PONG counts.
  HELD for approval: two net_demo PONG->empty/JOIN-only expectations;
  acceptance needs reply + replacement current/stale, split/drop,
  5PING+chat guards. FullUIqueue is bounded-memory backpressure
  measurement limitation, never permission to drop data or add
  unbounded queues.
- V6 CORRECTION: parent earlier no-residual claim WITHDRAWN for
  fixtures. `2a36383` has two final native gates: (a) native
  collector parks only two recvs with no timer/post-receive deadline
  (1+1+3 fails, late completion succeeds, silence waits outer 20s not
  2s) — needs bounded deadline-owned loop with close + 1+1+3/2+3 vs
  open-silent/late/EOF pairs for TCP and TLS (single-read still);
  (b) UDP candidate bind failure self-reports unsupported, harness
  green-skips — independently probe host AF_INET6 UDP, then require
  candidate roundtrip on capable host. Improved resolver/TC/SNI kept;
  Actor fallback/stale-gen still pending (parent, after staging).
- G3 return reviewed (`815f1eb`/`e8c8b26`/`00c026b`/`4e209fd`/
  `bd6b6be` on `repair-g3`): independent immutable re-review confirms
  ALL FIVE blockers remain (Commands/Submit/Media/JoinPlan/Buffer
  hashes identical to defective snapshot; client MODE cleanup runs
  AFTER key classification) — parent media-consumed credit WITHDRAWN.
  NOT merged as qualified. `repair-g3b/34` (four cases) cancelled and
  respun as `repair-g3c` with ALL FIVE in its INITIAL task: (1) framed
  MODE+324 styled flags/channels never persist key (normalize BEFORE
  predicate); (2) styled self author + IDENTI<02>FY echoes silent,
  peer IDENTIFY stays; (3) media same boundary-aware URL runs as
  View/open (no SOH glue/infixed autofetch, genuine styled image
  works); (4) decoded-text mentions (m<02>e hit, me<02>ow nohit,
  color/reset pairs); (5) styled self-KICK clears membership + rejoin
  intent, peer kick preserves. One shared seam; framed guards only.
- Slot plan confirmed: V6/G3 freed slots to H5-runtime + fresh G3
  repair; parent owns G6/V6 live integration (Caps/OutState Session
  wiring + sentinel law already staged; Actor `dial_begin`
  generation-guarded `connect_dual` before TLS after V6 staging).
- V6 chain committed UNQUALIFIED (`368c854`; staged proof timed out,
  cause unverified). Process note: a docs `git commit` swept the V6
  stage into a docs message; immediately soft-split into `33106a7`
  (docs) + `368c854` (V6) with identical content — use path-scoped
  `git commit <paths>` while a stage sits in the index.
- USER APPROVALS (all three groups) RECEIVED and SENT to H5-runtime
  (`adapt-h5-runtime/33`) and I2-live (`adapt-i2-live/31`) native
  handles: (1) H5 four fixtures + two laws to `.000Z` + rejection
  guards; (2) NEW unsigned-k expectation to hidden (non-key visible
  kept); (3) two net_demo PONG expectations to empty/JOIN-only for ONE
  gen-checked reader owner + replacement exact-one/current-stale/
  split-drop/5PING+chat guards. LANE1 CORRECTION NOTE (workflow child,
  no messaging — enforce on returned source/tests): approval (3)
  applies; nothing else waived (assertions, timing, proofs, finals).
- C8 verdict: worker29 returns adapters only (`25d89ad`/`88e695b`:
  `net.bend` CardFetched pass-through, fullscreen/paint out of scope)
  — NOT the completed feature. Parent integrates the adapter chain,
  then spawns a C8-LIVE owner (free slot held) for real Net/App loop
  wiring: replace pass-through, thread retained cards/full state one
  canonical path, schedule/accept completions, paint overlay, bind
  fullscreen entry/exit, provision birc-cards in default shell/package;
  preserve media path/opt-out/unsupported-terminal behavior; no copied
  submission pipeline.
- V6 Actor wiring plan (parent, in progress): `Dns.lookup_a` is A-only
  but no public AAAA entry exists — add `Dns.lookup_aaaa` (mirror);
  `dial_begin` keeps literal dispatch (v4 direct, v6 validate-direct),
  gathers both IPs for names, `connect_dual` TCP pair, `Tr.upgrade`
  with ORIGINAL host (SNI/verify, never IP), existing continuations;
  gen stable in the sequential do-block (no Chan interleaves) so the
  fallback is inherently current-generation; pure plan helper
  JS-tested, IO glue covered by transport/native suites.
- V6 Actor wiring DONE (`283bc4b`, UNQUALIFIED): `dial_begin` via
  `dial_dual` + `Tr.upgrade(original host)`; `Dq.dial_plan` JS-pinned
  (`ipv6_transport=ok`, red-then-green); linear-Result actuation
  mirrors the table arm-for-arm; literals/DNS-error/timeout/
  continuation semantics preserved; no TLS-failure fallback, no
  downgrade. Native/live/PTY IO coverage at final qualification.
- Initial 9-lane workflow reconciled completed: lane1 FAILED no-commit
  (needs respin, no merge); lanes 2-7 READY at known commits (all
  since integrated/superseded); lanes 8-9 reports missing. No new
  integration input; lane1 heavy/build ownership unchanged.
- QUALIFIED (proof-600): `timeout 600 bend PROOF.bend` via locked
  runner reports ALL PROOFS CHECK (exit 0); Bend sources identical
  between proof tree and current HEAD (`git diff` empty, docs-only
  commits after) — lifts UNQUALIFIED from sentinel `66f6a46`, H5
  `5313e0d`, V6 `368c854`, V6 wiring `283bc4b`, V6 lazy `aba2f98`.
  Cause wording: green establishes an adequate budget ONLY; prior
  180s-timeout root cause stays UNVERIFIED (no phase/profile
  evidence); no bisect needed merely because proof succeeded. Future
  integrations: proof-600 qualifies.
- G3c return reviewed (`936c5cc` 38 guards + `baef5f4` fix): source
  fixes REAL (`proto_atom` shared seam, `mode_has_key` normalizes
  BEFORE predicate, `Ws.url_runs` shared seam) but only credentials
  traverse Fr->Session — NOT final per the production-path bar.
  Spawned `g3-traversal` top-up on `baef5f4` (Session-chunk traversal
  for MODE/mention/KICK, live media path; all 38 preserved).
- V6 final native gates SENT to `recover-l1/37` (raw evidence
  preserved): dualdnslazy resolver must stay open + fail on extra A;
  missing-AAAA/NXDOMAIN/refused6-healthy-A via real `dial_dual_at`;
  TCP two-read/unarmed deadline; UDP self-skip; superseded staleness
  check must precede registration (adoption ordering alone
  insufficient).
- C8 adapter staged (`02fc1db`: pass-through + CardFetched seams,
  `session_cards_demo=ok`) and G6 live-tick bundle committed
  (`8d2a34c`: `live_tick`/`live_composing` + accessors,
  `cap_notify_demo=ok` incl. new `live_tick_bundle`; H5-runtime/33
  concurrent `cap_notify.bend` region merges at integration).
  Proof-600 with full log capture running on `8d2a34c`
  (`build/proof-600-8d2a34c.log`); no proof-input edits in flight.
- N9 `4dc55ba` HELD: both defects unchanged (buffer-order mark loss
  `Session2409-2446`, per-request spawn `NotifyIO111-137`/no active
  state); new 263-274 tests cover pending FIFO/count only. Both gates
  already queued to worker32 (running); no respawn; enforce on return
  source. Net/App/default-helper runtime absence pending separately.
- I2 duplicate-CHANMODES reassertion gap still present at dirty source
  (known P2, already queued to I2-live; not new).
- I2 NEW P3 SENT to I2-live/31: `/mode` sensitivity fallback
  (`submit1393-1405`) special-cases only `+#` — rejected explicit
  `+room +k :s3cret` misreads signed `+room` as implicit flags,
  nonsensitive, secret enters recall (`Session1936`). Reuse
  `Commands.mode.explicit101-104`; negative rejected explicit
  +channel key stays sensitive; positives `+room +o bob`
  nonsensitive, valid signed key inputs sensitive.
- L1 `db932a5`: generation-tagged Pong + Session single-owner source
  repaired; trace still per-mark sequence (not request identity);
  blocking poll->write caveat remains known.
- Root review ACCEPTS G3 `baef5f4` all-five source repairs; final path
  qualification assigned to `g3-traversal/41` (already running).
- L1 `db932a5` ACCEPTED: generation-gated reader PONG, no duplicate
  Session owner, real `Fr.push_ex` rem/drop/None, shared FIFO/shutdown
  ownership. Trace HELD (blocking poll->write, per-mark vs per-PING
  identity). Sent worker37: dirty `server_id_demo.bend:46` paren fix +
  reader/session exactly-one guards (queue5-PONG covers writer budget
  only).
- I2 current: assertions-only, no weakening ✓; `SessIso` wrapper is a
  parent-merge instruction, NOT live binding — return gate: real state
  integration + Make registration + proof ownership at parent merge.
- Proof-600 on `8d2a34c` TIMED OUT (124; log `build/proof-600-8d2a34c.log`,
  71 bytes — bend prints verdict only at end; load 34-57 during window
  with L1-heavy active) — `02fc1db` (C8 adapter) + `8d2a34c` (G6
  helpers) are UNQUALIFIED until a green proof-600; cause unverified
  (contention vs law-cost, no phase evidence). Retry on worker drain;
  law bisection only if timeouts persist quiet.
- Spawned `recover-l1/37` (ONE heavy lane: surgical port of lane1
  dirty fixes onto `27a6fb4`, approved net_demo flips + replacement
  guards, trace identity, orphan fixture, default-off instrumentation,
  measure/fix/re-measure, latest default prebuild) and
  `integ-c8-live/38` on clean `88e695b` (real Net/App/fullscreen/
  package wiring + boundary gap on the shared URL-runs seam).
  Shared-seam requirement queued to `repair-g3c/35`.
- V6 REVISION DONE (`aba2f98`, UNQUALIFIED): lazy AAAA->TCPv6, A->TCPv4
  only on TCP failure; `DialPlan` + JS guards dropped; existing seam
  only (`connect_dual` stays tested, off production path). New native
  `dualdnslazy` mode + harness guard (exactly one AAAA, v6 echo, v4
  silent): `test-ipv6-transport` GREEN incl. `dualdnslazy=ok` (owned
  loopback, bounded); `ipv6_transport=ok` glue green.
- `integ-c8-live/38` FAILED at startup (tooling, no commits, clean
  tree at `88e695b`); respun immediately as `integ-c8-live2/39` on
  branch `c8-live2` with the identical initial task.
- USER APPROVAL: standard proof to 600s (`make proof PROOF_TIMEOUT=600`
  via locked runner); runtime/PONG/Nix/PTY deadlines unchanged; real
  `bend PROOF.bend` qualifies, never check-only. Proof-600 running on
  current tree; no proof-input edits while in flight.
- SessWS `be1bd97` NOT ACCEPTED; exact blockers (all already in
  `sessws-live/40` initial task — coverage confirmed, no follow-up
  needed): S4 `replace_reset319-322` via `session_upload_draft1598-1601`
  preserves Comp — `CompActive{"old ","/j",0n}` + host/port change +
  `comp_step.active1084-1106` revives "old /join " (same-endpoint +
  sibling positives); S3 `hist_after_lines.go235-238`/`multiline_finish277`
  splits one raw block ("aa\nbb" recalls "bb", blanks/CRLF lost;
  239-241 contains-guards not exact) — one exact item + one HistPrev,
  mixed later-line IDENTIFY absent; S2 needs exact FIFO (now count2
  only); S5 needs bare `/query alice` + rejected-composer; S1 gen1
  repaired (preserve); centralize Session-owned supplied-submit/history
  finish seam (`AD272-279`/`401-406` still copied); real runtime for
  `net255` direct `step_keys`. Worker owns session/workspace/drafts
  paths — parent does not edit them.
- Parent G6-live: pure policy complete (worker + sentinel); binding
  (Session Caps/OutState fields, tick drive, TAGMSG emission) touches
  worker-owned session/net/app files, so parent implements pure
  live-tick helpers + tests in `cap_notify.bend` (free) + exact binding
  spec here, and binds when SessWS/C8 return. No worker-path edits.
- G6 BINDING SPEC (parent, queued behind SessWS/C8-live returns):
  `CapNotify.Reg{caps,out}` + `reg0/reg_on_line/reg_out` already exist
  (worker); `reg_out` gates on `tags_ok(caps)` internally. (1) Session
  gains one `reg: CapNotify.Reg` field (`reg0()` init, reset on
  endpoint change with the other per-endpoint state). (2) Live CAP
  lines: thread `reg_on_line(reg, server, nick, line)` through the
  `FoldAcc` line fold beside `Feed.feed_at` (server/nick from the
  Client). (3) Outbound typing: on `TypingTick` (net `on_typing_tick`
  beside `session_expire_typing`) AND composer keystrokes, call
  `reg_out(reg, now, online, target, composing)` with live `online`
  (net Online), active target, nonempty-composer; queue returned
  TAGMSG wires through the existing actor send path (SEND_CAP
  budgeted). No new state path; no behavior when tags unnegotiated
  (quiet by construction, guarded). Pure helper + JS guards in
  `cap_notify.bend` first (free file), binding edits after.
- H5 chain committed UNQUALIFIED (`5313e0d`; staged proof timed out,
  cause unverified) and `adapt-h5-runtime/33` launched with exact
  .sss/descriptor/ticket/CAP gates (fixture flips held).
- G3 media-boundary defect messaged to running `integ-g3-wire/19`:
  `media68` re-lexes visible text, discarding source boundaries, so
  SOH-fabricated or style-suffixed URLs can schedule fetches for links
  that paint nonclickable (unsolicited media). Require the SAME
  boundary-aware URL runs for view/`/open`/media with image-markdown
  /code rules retained; negative fabricated URLs → no request, positive
  genuine styled URL → exact original + one request. Pure adapters are
  not full implementation until real Net/app entry points use them.
  PROOF junction fix committed with its exact green evidence (114s
  `ALL PROOFS CHECK` run covered this content; only non-Bend files
  changed since).
- Lane1 URGENT return blocker (verified in dirty worktree): reader fast
  path posts untagged `Sess.Cont` (`reader_answer`, no generation) and
  `writer_command` accepts `Cont` with no gen check while `Pump` checks
  `U32.is_eq(pgen, gen)` — old-generation PONGs leak into new endpoints
  (the lane's own comment admits it). Require generation-tagged reader
  responses + `Writer.gen` check: negative delayed-old-PING-after-
  Dial/Drop yields no new-server PONG, positive current-gen PING gets
  exactly one timely PONG, queued UI lines must not duplicate. Relayed
  via `LANE1_URGENT.md` (workflow children have no message channel) and
  recorded here as a return blocker. Shutdown fixtures: signature
  adapts only; `net_trace` needs ≥2 PONGs / ≥4 enqueue marks.
  Deadlines unchanged; before/after evidence required.
- H5-second returned `8b5000c` (worker reports H5.8 msgid-anchoring;
  H5y/H5q/IO-fixture coverage to verify in review); pending parent
  review before integration. Freed slot went to `fix-i2-third` (I2d +
  I2c-lifecycle); N9-second and L1T-second remain queued.
- H5 `8b5000c` review residuals (kept open): malformed timestamp
  validator478 unchanged, new positive test missing `.sss`, no direct
  early-EOF IO guard; prereg star stays a shared-CAP integration gate.
  Await `fix-h5-second` completion report, then fold leftovers into an
  H5-completion round.
- N9-second launched into C8-third's freed slot: `fix-n9-second/26`
  (`01a10169-8ee0-76b1-a564-af9f65f1e57e`) on `758291c` (cross-scope
  at-most-once + canonical Theme selector wiring). L1T-second and
  H5-completion remain queued in that order.
- SessWS blockers messaged to running `adapt-sess-ws/20`: (S1)
  ServerId/epoch reuse admits stale Chunk/WriterDone after
  remove-readd-redial — bounded per-slot epochs/tombstones or
  non-reused incarnation + guards. (S2) multiline submit bypasses
  `Session.can_send` in disconnected states (wires + clears) — one
  shared submission seam + guards. (S3) endpoint replace clears drafts
  but leaks Session composer/seed to the new endpoint — reset both,
  same-endpoint retains. (L1d) deliberate double-PONG consumes two
  SEND_CAP credits per PING (5 PINGs + 1 chat exceed 8): keep ONE live
  PONG owner, pure/offline seam intact; the two-PONG trace expectation
  encodes the defect and must not be accepted. Full 64-slot evt queue
  still blocks actor post before reader answer: measure first-PONG
  receipt under full/free queue, not UI-chain hops.
- C8 checkpoint proof timed out again at 180s (second occurrence).
  Deadline unchanged; diagnosing load-vs-cost with measured retries and
  quieter-machine qualification before any conclusion.
- SessWS S4/S5 + seam directive messaged to running `adapt-sess-ws/20`:
  atomic submit-driven focus (reject before commit; admitted query
  consumes command + loads destination draft) and per-line shared-Sub
  privacy (later-line IDENTIFY/LOGIN absent from history/echo;
  ordinary multiline exact). The worker MAY edit Session on its branch;
  parent merges. No more parallel Session-logic copies.
- C8 `04012db` independent checks passed (parent swaps, held/released
  locks, staged competing writer, count/bytes, Unicode hit; no
  residual): cherry-picked to parent, suite re-run in flight. Parent
  adds permanent released-lock/active-stage guards next.
- Proof discipline: no blind repeats, no deadline raise, one heavy
  lane. Proof phases get actual instrumentation (real/user/sys + load
  per run); the next full verification runs on unchanged source without
  overlapping native/Nix compilers. Current Bend source stands
  proof-green from the 114s run (`04012db` touches Python only).
  Lightweight implementation/review continues while heavy
  qualification is queued.
- G3 exact-SOH + H5-IO additions (messaged to running workers): G3 SOH
  branch is wire_style:165; whitelist-only supported style controls in
  chat text; metadata/TAB/CR/LF/NUL/ESC/OSC52 safety through BIRC2;
  controls inside e+combining and woman+ZWJ+laptop at narrow/wide wrap.
  H5 IO fixture must exercise real early-EOF files
  (remaining>contents vs exact-length), not only predicates.
- C8-second returned `254a0eb` (shared lock/accounting + Unicode
  envelope, worker reports both-writer-orders/interleaved/concurrent
  green); pending parent review against C8d/C8e before integration.
  V6-fallback follow-up still queued for the next free slot.
- Qualification refinements: (H5q, messaged to running `fix-h5-second/21`)
  phase-aware CAP `*` acceptance with the ONE registration owner (never
  global wrong-recipient acceptance) + full `YYYY-MM-DDThh:mm:ss.sssZ`
  timestamp validation reusing server-time checks, paired valid/malformed
  refs. (V6q, folded into queued V6 follow-up scope) fixture-only gaps:
  production AAAA-to-A + truncation-to-TCP paths, DNS-name TLS/SNI,
  stale actor generation guards; assert IPv6 UDP success if claimed;
  fixture must collect 5 bytes under one deadline (positive 2+3
  fragments, negative early-EOF/altered-bytes) instead of assuming first
  recv is exactly `hello`. Never weaken framer or TLS verification.
- G6 `a504fca` grounded: `cap_notify_demo=ok` executed by the parent in
  the repair worktree (not only worker-reported). Queued for ordered
  integration with the remaining returns.
- Proof gate diagnosis (D-repair commit blocked): plain `make proof`
  timed out at 180s under load 44; `--verdict` is unavailable (Lean
  kernel not in PATH — not a proof failure). Lane4's own 10 drafts laws
  passed in 46.8s in their worktree, so the timeout is load-suspect, not
  predicate-suspect. Measuring one timed plain run before any other
  conclusion; the 180s deadline stays unchanged.
- Proof green on retry: `ALL PROOFS CHECK`, real 149s / user 83s — the
  earlier 180s timeout was pool-load-induced (load 44, real >> user), not
  a predicate defect. Deadline unchanged; margin is thin under a full
  pool, so final qualification re-runs proof on a quieter machine.
- C8 repair returned (`2e8f10f1` helper + `567b62d1` policy/laws, worker
  reports scoped guards green); pending parent review against C8.1-C8.6
  before integration. Freed slot goes to the L1/T
  instrumentation+measurement repair owner now (scope is fully specified
  and orthogonal) instead of waiting for G3.
- Lane2 final gates (hashes verified: source `c408c3a8…5d418`, tests
  `922b2be4…6cb51`, `0263accc…4d47e`): `PREFIX=(oo)@+` passes validation
  (equal lengths, letters/symbols) and creates a non-inverse mapping
  (`mode_for(+) = o` but `sigil_for(o) = @` via first-match `index_of`).
  Reject duplicate modes or sigils, retain the previous valid setting;
  accept unique `(ov)@+`. Earlier `-TOKEN`/empty-`STATUSMSG`
  /wrong-recipient/interior-sigil/advertised-`CHANTYPES` gates stand.
  Integrating `chan_target` must preserve an exact resident `+#room`
  before `STATUSMSG` fallback; use negotiated casemapping consistently
  for all buffer/roster/draft identities.
- Architecture guard (applied): `server_id` imports Session and the
  repaired Drafts needs server identity, so a naive
  Session→Drafts→server_id→Session cycle must not become the design.
  Identity types live below Session in leaf `server_key.bend` (no
  imports); `server_id` routing wrappers and Drafts reuse that one
  canonical identity type; Workspace/top-level adapters own routing
  integration. No duplicated identity types, no new framework.
- Draft focus/endpoint integration gates (D7-D8, central wiring): (D7)
  `focus` preserves rejected typed text but returns no admission signal;
  tab/click/split wiring must keep the old active buffer on a rejected
  save or the old composer can be sent in the new room. Pure module
  exports the shared `focus_admits` check; Session moves focus only when
  it admits. Require negative over-byte/over-line/full-store
  active-buffer+composer preservation and positive successful-switch
  guards. (D8) clear ServerId-scoped drafts on endpoint/slot replacement
  via `replace_endpoint`, retaining same-endpoint reconnect drafts;
  ServerId alone is not an endpoint identity. Pure text-preservation
  behavior itself is not claimed broken.

## Open decisions (resolve in M0/M4)

| ID | Question | Default |
|---|---|---|
| D1 | Coarse `draw_frame(ViewModel)` vs fine-grained widget FFI? | Coarse (`Timui.frame` paints whole layout) |
| D2 | Net concurrency model A/B/C? | `IO.spawn` net actor + `Chan` Data events (Bend-native B) |
| D3 | UTF-8 TCP vs byte-exact foreign TCP? | Base `TCP.send`/`recv` strings; `Fr.push` octet laws kept |
| D4 | UI loop `@unsafe` vs fuel? | `--frames N` fuel; `frames=0` live `@unsafe` idle |
| D5 | Keep a C demo binary during transition? | No — deleted at M5.8 |
