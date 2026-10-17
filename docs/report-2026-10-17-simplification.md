# birc simplification review — outcome report

**Date:** 2026-10-17
**Baseline:** `208f7c9` (pre-review master)
**Final:** `7f9af38` (all five waves integrated)
**Plan:** `docs/plan-2026-10-16-simplification.md`
**Method:** 16 tasks across 5 waves, each implemented by an isolated `cursor-agent`
in its own git worktree, reviewed and merged by hand. Every wave was verified on a
remote `aarch64-darwin` lane, never on the development laptop.

This report answers the three questions the review was commissioned with, in order:
build/iteration speed, UI responsiveness, and the Bend↔C split. Numbers are measured,
not estimated; where a number could not be measured, that is stated.

---

## 1. Verdict

The three commissioned goals were met, with one structural exception that is not
fixable from this repository.

- **Build and iteration speed: substantially improved.** Editing a source file no
  longer rebuilds the entire test corpus. `63.3%` of rebuild edges are gone, and the
  app binary now rebuilds from a content cache in under a second instead of `177s`.
- **UI responsiveness: improved and now gated.** The paint path was **quadratic in
  line length and is now linear**, and keystroke-to-glyph latency is gated by a test
  that did not exist before.
- **Bend↔C split: moved the right way, and one proposed move was correctly refused
  on measurement.** Three C effects became one; a fourth proposed migration was
  measured at ~210× slower in Bend and declined.
- **Exception: `make check` cannot pass, and could not at baseline either.** Its
  `proof` prerequisite does not complete in bounded time on any host. This is a
  Bend/Bun property, not a regression. See §8.

One **real product defect** was found and fixed (§6): `/quit` in multiserver mode
silently quit only the focused server while still exiting 0 and printing `birc=ok`.

**No test was weakened to produce any of this** (§7 audits all ten test-only commits).

---

## 2. Build and iteration speed

### 2.1 The dominant win was the build system, not the refactor

At baseline, `Makefile:120` read:

```make
BEND_SRC_DEPS := $(wildcard src/bend/*.bend)
```

and every build rule depended on it — `$(BLDDIR)/%: tests/bend/%.bend $(BEND_SRC_DEPS)`.
So **touching any one of 77 source modules rebuilt all 196 test binaries**, regardless
of whether that binary imported the module.

Now each rule depends on a generated per-program dep file:

```make
$(BLDDIR)/%: tests/bend/%.bend $(BLDDIR)/%.bend.d
```

`scripts/bend-deps.sh` computes each program's real transitive import closure (and,
because Bend inlines C via `import "../ffi/*.c"`, the C files and headers too). One
`.bend.d` drives all four output forms (`X`, `X.js`, `X.c`, `X_review.js`). The
wildcard remains only as a fail-closed fallback until the dep file exists.

**This is worth stating plainly: the source refactors did not meaningfully change the
dependency graph.** The real closure fan-in for `app.bend` was already 6 at baseline;
the build system was simply ignoring it. Measured on both trees with
`fanin.py`, the real fan-in is essentially unchanged:

| module | real fan-in at baseline | real fan-in at final |
|---|---|---|
| `app.bend` | 6 / 196 | 6 / 196 |
| `replay.bend` | 8 / 196 | 8 / 196 |
| `view_laws.bend` | 11 / 196 | 11 / 196 |
| `wsnet.bend` | 15 / 196 | 15 / 196 |
| `irc.bend` | 183 / 196 | 183 / 196 |

What changed is that make now *consults* it:

| | baseline | final |
|---|---|---|
| binaries rebuilt on touching `app.bend` | 196 | **6** |
| binaries rebuilt on touching `replay.bend` | 196 | **8** |
| binaries rebuilt on touching `wsnet.bend` | 196 | **15** |
| binaries rebuilt on touching `timui_ffi.c` | 196 | **20** |
| binaries rebuilt on touching `tls_ffi.c` | 196 | **29** |
| binaries rebuilt on touching `irc.bend` | 196 | 183 (irreducible hub) |
| aggregate rebuild edges | 15,092 | **5,611 (−63.3%)** |
| median fan-in across modules | — | 40 / 196 |

Reproduce with `python3 fanin.py <tree>`; it parses the same import graph
`bend-deps.sh` does.

**Honest caveat:** the eight hub modules (`irc`, `links`, `emoji`, `diagnostic`,
`buffer`, `dns_wire`, `endpoint`, `wire_style`) still have fan-in 155–183 of 196.
Touching those still costs nearly a full rebuild. Splitting them was attempted and is
the right next lever, but it did not happen in these five waves.

### 2.2 Content-keyed UI build cache

`build-ui` is now cached by content hash:

| | time | artifact |
|---|---|---|
| cold (`BIRC_UI_CACHE=0`), final tree, quiet lane | **177s** | `build/birc` |
| warm (`BIRC_UI_CACHE=1`), same tree | **<1s** | byte-identical |

Measured in the Wave 5 gate on the integrated tree, not extrapolated.

### 2.3 Parallelism default

`make` with no `-j` now derives `-j⌈ncpu×2/3⌉` instead of running serially or
oversubscribing. This matters because each Bend compile is itself multithreaded
(measured 117–165% CPU); naive `-j$(nproc)` oversubscribes and *increases* wall time.
Fixing this alone took `test-goldens-io` from 4 failures to 2; bounding two
pathological compiles (`live_context`, `net_demo`) at 360s took it from 2 to 0.

### 2.4 Structural size

| | baseline | final | delta |
|---|---|---|---|
| `src/bend` modules | 77 | 78 | +1 |
| `src/bend` lines | 44,774 | **43,642** | **−1,132** |
| `tests/bend` lines | 29,043 | 29,174 | +131 |
| total Bend lines in a full test build | 4,052,124 | **3,864,863** | **−187,261 (−4.6%)** |
| `view.bend` | 3,295 | **2,534** | **−761** |
| `client.bend` | 1,555 | **1,151** | **−404** |
| `session.bend` | 5,254 | **4,938** | **−316** |
| `wsnet.bend` | 2,742 | 2,835 | +93 |
| `workspace.bend` | 1,989 | 2,035 | +46 |

Modules added: `helper_io.bend` (51, shared bounded helper-process spawn),
`net_msg.bend` (137). Removed: `workspace_isolation_arithmetic.bend` (47).

Whole-repo churn from baseline to the gated tree `4f75027`: **99 files,
+7,650 / −7,068, 109 commits.** The commits after it are documentation and the
read-only review tooling in §10; they touch no build input.

The `−4.6%` in total compiled lines is the honest headline for "less work per build";
the `−1,132` in `src/bend` is the honest headline for "less code to read". The test
corpus grew slightly because three test files had to be restructured around the C
backend's 247-word continuation cap (§8.3).

---

## 3. UI responsiveness

### 3.1 The paint path was quadratic in line length; it is now linear

This was the substantive responsiveness find. `tests/perf/long_lines.py` (new) sweeps
line length at fixed line count and reports `view_us`:

```
long_lines bytes=64  lines=96 view_us=1700   view_us_per_line=17.71
long_lines bytes=128 lines=96 view_us=4239   view_us_per_line=44.16
long_lines bytes=256 lines=96 view_us=10323  view_us_per_line=107.53
long_lines bytes=510 lines=96 view_us=13280  view_us_per_line=138.33
long_lines shape=linear
```

64 → 510 octets is **×7.97** in length and **×7.81** in time. Quadratic would be
**×63.5**. The test asserts `shape=linear` and fails otherwise.

Root cause was `columns.bend` deriving cluster-walk fuel from `String.length(rest)`,
i.e. a per-cluster length scan. Also fixed: `pending_display_lines` now short-circuits
when nothing is pending, and the live-bottom path builds a bounded newest-first suffix
instead of reversing the whole scrollback.

An earlier short-line sweep could not distinguish linear from quadratic and said so;
this sweep is the one that settles it.

### 3.2 Keystroke-to-glyph latency

`tests/perf/key_latency.py` (new) gates this on a real pty:

```
key_latency samples=24 p50_ms=1.28 p95_ms=1.94 max_ms=2.37
            proposed_p95_ms=16 budget_ms=80   -> key_latency=ok
```

Earlier quiet-lane runs of the same gate measured p50 `1.17→0.87ms` and p95
`1.46→1.18ms` before/after the Wave 1 paint work. The Wave 5 numbers above were taken
at load `3.21/3.38/2.24` on 8 cores, so they are **not** directly comparable to those
quiet-lane figures — they are higher because the host was busier, not because the code
regressed. All of them sit far inside the 16ms proposed budget.

The durable win is the gate itself: latency was previously unmeasured and unasserted.

### 3.3 Frame profile

```
hardening_profile buffers=8 lines=256 bytes=89408 frames=36
                  ready_ms=560.7 wall_ms=1679.5
                  prepare_us=8 begin_us=29 draw_us=358 end_us=1371
```

`view_us` at fixed line counts halved across the review (128 lines 5482→2563,
256: 5785→2658, 512: 5057→2900, 1024: 6300→2973), and is now flat in scrollback depth
where it previously grew.

**Still open:** scrolled-away frames call `List.length` over the whole line list
(`view.bend:1236` and siblings), and `rev_tail` recursion depth still follows
scrollback. Recorded in `BACKLOG.md`.

---

## 4. The Bend↔C boundary

The brief was to do as much as possible in Bend and offload only what must be. Two
moves were evaluated; one landed, one was refused.

### 4.1 Landed: three C effects became one

`CID_SYS_OPEN_PROGRAM`, `CID_SYS_CLIPBOARD_PROGRAM` and `CID_SYS_NOTIFY_DEFAULT` each
existed only to hand Bend a platform-dependent program name. They were replaced by a
single `CID_SYS_PLATFORM` returning an enum (1 = Apple), with the name selection done
in Bend. The resulting names (`open`/`xdg-open`, `pbcopy`/`""`, `osascript`/
`notify-send`) were verified **byte-identical** to the C originals.

`io_eff` registrations: **44 → 42**, verified with no duplicates and no
unregistered names. (Distinct `CID_` tokens in `src/ffi` went 60 → 58; that larger
count includes marshalling tags such as `CID_CON` and `CID_UNIT`, which are not
effects.) Reproduce with `sh scripts/review-baseline-diff.sh`.

Also extracted: `src/ffi/birc_utf8_valid.h` (50 lines) shared by two callers that held
verbatim 1,341-byte copies, with a `header_copy()` `memmem` assertion that fails if
either copy drifts; and `src/bend/helper_io.bend`, which unifies four near-identical
bounded helper-process spawns behind `Spec{env_var, default_name, out_cap,
deadline_ms}`. All bounds were verified byte-identical (notify 512/2000, prefs
4096/5000, upload 2048/35000, search 30000, media 2800000/11000).

`src/ffi` C/H lines went 4,116 → 4,245 (+129). The C surface grew slightly in lines
while shrinking in *effects* — the added lines are the shared UTF-8 header and the
platform enum, which remove duplication at the boundary rather than adding capability
to C.

### 4.2 Refused on measurement: base64/`BIRCIMG1` decode in Bend

Moving the image-payload base64 decode from C to Bend was proposed and **declined**,
because it was measured first: C decodes in `3.76ms` where the equivalent Bend
cons-list walk over 2,097,150 `U32`s takes `0.79s` — roughly **210× slower**.
`base64.bend` also has no decoder, so this would have been new code, not a move.

This is the correct outcome for the brief: "offload only as much as we have to" is a
statement about which things *must* be in C, and bulk byte decoding is one of them.

### 4.3 Not achievable: `net`/`wsnet` unification

Merging `net.bend` and `wsnet.bend` (~2,000 lines of near-duplicate actor loop) was
planned and is **impossible as planned**: `wsnet.bend` imports `net.bend`, so the
reverse import yields `an import cycle through .../net.bend`. The achievable parts
were delivered instead — `WsLoop` threaded through 42 internal continuations
(`0600a0c`), and `media_stage.effects` (`net.bend:1032`) now shared by
`media_stage.job` and `ws_media.applied` (`a4fff85`).

A real unification needs the shared loop extracted into a third module that both
import. That is a design change, not a refactor, and was left alone.

---

## 5. Wave 5 integration gate

Run on the integrated tree at `4f75027` on a quiet 8-core lane
(`aarch64-darwin-1`, load `3.21/3.38/2.24`), full log in
`/tmp/birc-cursor-reports/wave5-final.log` and `-tail.log`.

**The target was never "make check passes"** — that is impossible (§8.1) and was
impossible at baseline. The target was: nothing that was green went red, and every red
is red for the same recorded reason as at baseline.

### Green (20 targets)

`lint-ffi` (13s) · `test-build-deadlines` · `test-nix-preflight` ·
`test-golden-runner` · `build-ui` cold (177s) · `build-ui` warm (<1s) ·
`test-reader-errors` · `test-actor-queue` · `test-media-history` · `test-cards-view` ·
`test-split` · `test-theme-ws-render` · `test-paint-slope` · `test-session-cards` ·
`test-goldens-io` (bins=15, 318s) · `test-runtime-helpers-package` (200s) ·
`test-keychain-package` · `key_latency` · `long_lines` · `hardening_profile` ·
`server_multiserver`

Eight of these were **red before the review** and are green now: `reader-errors`,
`actor-queue`, `media-history`, `cards-view`, `split`, `theme-ws-render`,
`paint-slope`, and `goldens-io`.

One clarification on `paint-slope`, because its sub-second runtime looks like a
no-op and is not: `test-paint-slope` is the *deterministic verdict-logic check* for
the footprint probe (no binary, no pty). The measurement target is separate —
`paint-footprint`, documented in the Makefile as "not in check" — and it was **not**
part of this gate. `bed58de` repaired its source (`tests/perf/paint_footprint.bend`
was missing the `+pends` argument and could not compile at all), and it first
produced a number, `delta_kb=832`, when run during the review. Treat that figure as
a review-time measurement on a lane, not a Wave 5 gate result.

### Red (all verified pre-existing)

| target | reason | pre-existing? |
|---|---|---|
| `test-media-anchor` | `stacked distinct clips` geometry | yes — byte-identical `got`/`want` at `208f7c9` |
| `test-state` | `query_collision` | yes |
| `test-state-review-identity` | `MODE routes normalized target` | yes |
| `test-media-view` | `new live message schedules got=[0] want=[1]` | yes |
| `test-goldens-proto`, `test-goldens-view` | both blocked by one binary: `session_cards_demo` `Error: an arity over 247` | yes |
| `test-pty` | one target only: `test-pty-m20-media-cache` | **yes — recompiled and rerun at `208f7c9`, identical assertion at identical line** |
| `test-orphans` | `notify_binding_gates.js` compile error | quarantined set, never passed (§8.4) |
| `proof` | `Error 124` after 602s | yes — does not complete anywhere (§8.1) |

**No target that was green at baseline is red at final.**

The `test-pty` result deserves emphasis because it initially looked like a regression
from the new `src/media/_cache.py` extraction, which is exactly the code path it
exercises. It was run at baseline on a pinned `208f7c9` lane and fails identically —
same assertion, same line 89. Every other PTY case is green (`link_click`, `launchers
failed/absent/slow/slowquit`, `media kitty/iterm/pending_quit/unread_recovery`,
`cycles=12/12`, `many_eof`).

---

## 6. A real product defect, found and fixed

`/quit` in multiserver mode reached **only the focused server**. With two loopback
peers, the focused part's socket received `QUIT :birc`; the other part's wire ended at
`JOIN #t` / `PONG` and never received `QUIT` — yet the process **exited 0 and printed
`birc=ok`**. Peers saw a socket close, not a clean quit.

Cause: `/quit` enqueued on the focused part only, so the other writer's pending FIFO
was empty and `ws_shutdown.drop` acknowledged its `WriterDone` without a line ever
being sent.

This was latent because **no test had ever executed the `--server` path**. Before this
review, `--server` appeared in `tests/` only inside a usage string in `args_demo.bend`.
`tests/pty/server_multiserver.py` (430 lines) is the first test to run it, and it found
the defect immediately.

Fixed in `0962849`: `quit_broadcast` (`workspace.bend:1400`) copies every
`QUIT `-prefixed line onto the other live parts as `Cont`, skipping the focused part,
with **no generation bump**. `step_keys.routed` / `step_keys.routed.pick` are
untouched, so `route_transport`'s `{==}` definitional-equality mirror still holds.
Verified `server_multiserver=ok`, exit 0, second peer's wire now ends
`…PONG :beta-routed\r\nQUIT :birc\r\n`, and re-verified after the `wsnet` continuation
refactor that also touched this path.

---

## 7. Test-integrity audit

The instruction was explicit: never weaken a test, never change product code to make a
test pass. Ten commits since baseline touched `tests/` without touching product code,
so each was audited individually.

| commit | verdict |
|---|---|
| `909f490` split `session_cards_demo` main | structural split for the 247 cap; assertions unchanged and in order |
| `c12f560` box `media_anchor` fixtures | boxing only; fixed the native compile, which then *exposed* a previously masked geometry failure |
| `d1f237f` match Session's 24-field shape | repair — product had added a `pends` field, test still destructured 23 |
| `bcc98e9` sweep view time across long lines | **new** test (`long_lines.py`) |
| `bed58de` give paint footprint its pending-send arg | repair — missing argument |
| `9b5bd55` expect the composer prefix | **oracle correction**, justified below |
| `a48959a` match registration to capability order | **strengthened** — gained five exact `CAP REQ` lines |
| `80329f8` drive reader errors through a plain connection | repair — test used `Socket` where product takes `Tr.Conn` |
| `362f70b` gate keystroke-to-composer latency | **new** test (`key_latency.py`) |
| `5763b6f` pin keychain ports to `transport_policy` | **new** test (66 lines, cross-language parity) |

The one genuine expectation change is `9b5bd55`. `ws2 framed rendered bytes exact`
compares `lines_text`, which concatenates every `OpLine`. Since the inline-`<nick>`
composer (`c19445d`) each frame also carries a `composer_ops` OpLine holding the
nine-space timestamp indent plus `<nick> `. The expectation predated that change and
stopped at `...a end`; it now includes the composer prefix. This matches documented
intent in `BACKLOG.md`'s `wf-composer split prefix` entry ("Bend **always** paints the
`<nick>` prefix in that same pane"), and is the same class of drift as the
already-accepted `test-feed body_ys` fix. It is test-only: no product change was made,
and none was needed.

Two expected-value corrections were made by hand during the review, both to fixtures
that predated a product change and were structurally impossible to satisfy:
`cards_view` overlay height `21→22` (`126dbcd`) and `media_history`'s 23-slot
`Session` (`d1f237f`). Each was verified green after the change, and in both cases the
*product* was correct and the fixture was stale.

**Net: 3 new tests, 4 repairs of structurally-broken tests, 1 justified oracle
correction, 1 strengthening. Nothing was weakened.**

---

## 8. What could not be done

### 8.1 `make check` is unpassable, and was at baseline too

`Makefile:1601` is `check: proof test lint-ffi test-paste-harness`. The `proof`
prerequisite does not complete in bounded time **on any host**:

| host condition | `PROOF_TIMEOUT` | result |
|---|---|---|
| idle 8-core lane | 10800 (3h) | `9374.16s user 21901.30s system 289% cpu 3:00:05.55 total` → `Error 124`, no verdict |
| idle 8-core lane | 2400 | `Error 124` after 40:13 |
| quiet lane | 180 (default) | `Error 124` after 3:11 |
| final tree, quiet lane | 600 | `Error 124` after 602s |

System time is **2.3× user time**, so the run is GC/allocation-bound inside Bun, not
doing proof math. Longer budgets do not converge.

It is also **unshardable**: a partial book holding 25 of the 535 laws fails with
`Error: 510 TODOs found`, because Bend checks the whole book at once. The corpus
cannot be split across lanes or cores.

`03cb8c2` (2026-10-08) took `LAWS.bend` from 425 to 535 laws; `make check` has been
unpassable since. This closes `TODO.md:60` ("locate the remaining full-book cost") and
bears on `TODO.md:44` and `:45`. A fix needs a Bend/Bun allocator or proof-engine
change, or a per-law check mode — **it is not reachable from this repository's
sources**. `BACKLOG.md` previously advised "rerun `make proof` on a calm host"; that
advice was wrong and has been corrected, because acting on it wastes hours.

The proof corpus is nonetheless kept structurally sound: `535 law` ↔ `535 def Laws.X`
is asserted at every merge, with zero orphans, and the pure/IO split holds (no `_io`,
`_worker`, `_live` or `_runtime` module appears in any proof file).

### 8.2 The 247-word C continuation cap

The pinned Bend C backend permits at most 247 flattened capture words per
continuation. As `Session` grew, test programs holding several live `Session` values
in one `main` breached it. The JS backend has no such cap.

Three test files were restructured around it using the established `SBox`/`ADBox`
singleton-list boxing idiom: `runtime_reconnect` (earlier), `media_anchor` (now
compiles natively), `session_cards_demo` (**still fails**).

For `session_cards_demo` the situation is now precisely characterised:

- native compile: `rc=1` in 31s, output is exactly one line — `Error: an arity over
  247`. **Bend does not name the offending def**, so the failure cannot be localised
  from the compiler.
- JS compile: `rc=0` in 7s, and the JS build **runs and passes**:
  `session_cards_demo=ok`.

So every oracle in that file is verified correct; it is only excluded from *native*
golden sets. That single binary is why `test-goldens-proto` and `test-goldens-view`
cannot complete — 111 of the 127 golden binaries are gated behind it. `t4.4` split
`main` into eight phase defs holding only boxed fixtures, which was the right
technique and fixed `media_anchor`, but was not sufficient here.

Remaining suspects, not yet tested: `ph_rows` holds one unboxed `C.State`
(`session_cards_demo.bend:357`), and any single unboxed `Session` temporary the C
flattener keeps live across a `ph_*` bind.

### 8.3 `media_anchor` stacked-clip geometry — needs a decision, not a fix

Fixing the compile exposed a failure that had been masked by it:

```
stacked distinct clips
  got =[1,2,40,6,2,3,11;1,8,40,6,2,2,22;]
  want=[1,2,40,6,2,3,11;1,7,40,6,1,3,22;]
```

Only the **second** stacked clip differs: `y` 8 vs 7, `clip_y` 2 vs 1, `clip_h` 2 vs 3.
Verified **byte-identical at `208f7c9` and at final** via the JS backend, so it is
pre-existing and was simply invisible before (the native build never compiled, and no
gate ran the JS build of this program).

Clip rectangles govern what part of an image is painted, so **`got` must not be copied
into `want`** without first establishing which geometry is correct. This needs the
media-slice owner's judgement.

### 8.4 Orphans

`test-orphans` is a quarantine of Bend programs "not reachable from `check`", kept out
of `test-review-pure` "until one has actually passed". It fails at the first target,
`build/notify_binding_gates.js`, with `expected: a pattern (a binder or a constructor)`
at `tests/bend/notify_binding_gates.bend:572`.

That test file is **unmodified** since baseline, and every internal API it calls has a
byte-identical signature at `208f7c9` and at final (`ws_notify.spawn_ticket`,
`ws_notify.lease`, `ws_notify.completed_hit`, `ws_notify.completed_lease`, `WsEvts`,
`known_helper`). So a wave-induced break is unlikely, but **a baseline recompile to
confirm it was blocked by an SSH agent outage**, so this classification rests on
API-identity evidence rather than a reproduced baseline failure. Per the standing
instruction, orphans are reported, not fixed.

---

## 9. Deferred and recommended next

Ordered by value per unit of risk.

1. **Split the hub modules.** `irc.bend` (fan-in 183/196), `links`, `emoji`,
   `diagnostic`, `buffer`, `dns_wire`, `endpoint`, `wire_style` (155–171) still cost
   nearly a full rebuild each. This is now the largest remaining build-speed lever,
   since the dependency *tracking* is fixed and only the dependency *shape* remains.
2. **`media_anchor` stacked-clip geometry** (§8.3) — needs a decision on which of
   `got`/`want` is correct before anything is edited.
3. **`session_cards_demo` native arity** (§8.2) — unblocks 111 golden binaries. Start
   with `ph_rows`' unboxed `C.State`.
4. **`test-state` `query_collision` and `test-state-review-identity`** — both are
   behavioural oracles in the target-normalization path, and there are **four separate
   implementations of target normalization** (`irc.bend:214-262`, `buffer.bend:57-82`,
   `isupport.bend:715-783`, `buffer.bend:1047-1073`). Consolidating them may fix or
   move both. Diagnose which of `query_collision`'s six simultaneous assertions fails
   first.
5. **`test-media-view`** `new live message schedules got=[0] want=[1]` — a folded live
   PRIVMSG schedules no media job.
6. **`test-pty-m20-media-cache`** — cache eviction re-uploads the oldest entry.
7. **Scrollback-length `List.length`** in scrolled-away frames (`view.bend:1236` and
   siblings) and `rev_tail` recursion depth — the remaining responsiveness items.
8. Smaller: remove `OpImage` CID from `timui_ffi.c` plus its Makefile alias (legacy
   adapters are characterization-only); wire `OpTabs` `mention_bg`/`mention_fg` (C
   already reads `f[8]`/`f[9]`); delete `keychain_birc.py`'s now-dead inline
   `trusted()` fallback; rename `workspace`→`servers` (`t2.4` produced a complete
   rename map).
9. **Not recommended:** a generic queue for `cards.bend`/`media.bend`. Deferred during
   the review because Bend has no generics over `Data`; the duplication is real but the
   abstraction is not expressible.

---

## 10. Reproducing any number in this report

| claim | command |
|---|---|
| structural before/after | `sh scripts/review-baseline-diff.sh [baseline-rev]` |
| per-file rebuild fan-in | `python3 scripts/review-fanin.py <tree>` |
| review metrics on a tree | `python3 scripts/review-metrics.py <tree>` |
| paint linearity | `python3 tests/perf/long_lines.py ./build/birc` |
| keystroke latency | `python3 tests/perf/key_latency.py ./build/birc` |
| the `/quit` fix | `server_multiserver` (not in `PTY_SUITE_TARGETS`; run it directly) |
| effect count | `grep -h 'io_eff(CID_' src/ffi/*.c \| sort -u \| wc -l` |
| law/proof invariant | `grep -c '^law ' LAWS.bend; grep -c '^def Laws\.' PROOF.bend` |

All three `review-*` scripts are read-only: they never write and never build, so
they are safe to run against a live checkout.

The raw gate logs were session artifacts under
`/tmp/birc-cursor-reports/wave5-final.log` and `wave5-tail.log` and are not
expected to survive; every number taken from them is transcribed into §5, and each
can be regenerated by re-running the named target on a lane.

Baseline metrics were taken on a lane pinned at `208f7c9`
(`/Users/angerman/birc-lane` on `aarch64-darwin-1`), not reconstructed.

Note on `tests/pty/*.py`: running one directly by path fails with
`ImportError: cannot import name 'Protocol' from 'typing'`, because
`tests/pty/typing.py` shadows the stdlib module via `sys.path[0]`. Use the make
targets.

---

## 11. Merge index

Baseline `208f7c9`. Waves merged in order; law/proof counts re-asserted at 535/535 at
every merge.

- **Wave 0** (build system): `18b099d` t0.2 · `571356b` t0.1 · `badce91` nix-preflight
  repair · `a16cb84`
- **Wave 1** (hot paths): `5ac7796` t1.1 · `afdbaf3` t1.4 · `aa7ef1d` t1.5 ·
  `c7f0742` t1.3 · `e4ceb5b` t1.2 · `12e90ac` t1.6
- **Wave 2** (DRY): `f18d477` t2.2 · `0db1064` t2.3 · `7a10365` t2.4 · `088034c` t2.1
- **Wave 3**: `8aa65ec` (FFI effects) · `e9ad489` · `69af0a5`
- **Wave 4**: `432083d` t4.1 · `0f506bd` t4.2a (the `/quit` fix) · `f36c417` t4.3 ·
  `ee52035` t4.4 · `4f75027` t4.2
- **Wave 5** (integration): `79ea0f9` FFI effect-count drift · `7f9af38` BACKLOG
  corrections

Fixes made directly during integration, after review found them:
`126dbcd` (`cards_view` height, `split` body height, goldens including non-programs) ·
`d1f237f` (`media_history` 24-slot Session) · `1aaa15a` + `0719095` (goldens-io
timeouts and `-j` oversubscription).
