# Column-walker retention

Date: 2026-10-14. Diagnosed on the current tree. The rewrite in this note is
not applied. `src/bend/columns.bend` is unchanged.

A long-running birc grows its physical footprint into hundreds of megabytes,
and in the observed client past 2 GB. An IRC client with these buffer caps
should stay in the tens of megabytes once the working set exists. The growth
that this investigation could name is Bend corpus pages allocated by the
column walks in `src/bend/columns.bend`. Those walks rebuild a heap task per
cluster on every paint, including an idle frame.

## What the bytes are

Bend 2 has no garbage collector. The runtime in the generated C
(`build/birc_bend.c` for this tree) is a bump allocator plus a per-class
freelist. A term is one 64-bit word:

```
term_make(tag, aux, loc) = (tag << 56) | (aux << 40) | loc
TAG_PAK 1, TAG_CTR 2, TAG_CLO 3, TAG_BUF 4, TAG_TSK 5, TAG_ARR 6
```

`PAGE_BITS` is 7, so a page is 128 words (1024 bytes). Allocation that misses
the freelist does `a32_add` on the bump and returns

```
HEAP_OFF + (old_bump << PAGE_BITS)
```

`heap_free` writes only the header word:

```c
e.mem[loc]     = ALC_AT(e, cls);
ALC_AT(e, cls) = loc;
```

The rest of a freed node, including child pointers, stays until that slot is
reused. Freed pages are not returned to the OS. `phys_footprint` from
`footprint -p PID` is the pages the bump has touched. It steps up and does
not come back down inside the process. A new process starts clean.

Worker threads reserve about 2 GiB stacks with `MAP_NORESERVE`. Virtual size
is not the resident corpus. RSS hides corpus pages the kernel has compressed
or swapped. On a fresh client the libc malloc zone was a few hundred
kilobytes dirty, so `leaks`, `heap`, Instruments, and heaptrack do not see
this allocator. Attaching them to the live raw-mode UI freezes TimUI. Profile
a copy.

`BIRC_FRAME_PROFILE=1` times pure View against the native frame phases. It
does not count words. The `bend` CLI and the binary's `--bend-help` flags
(`--threads`, `--gpu`, `--gpu-build`) have no heap profile. CPU samples work:
every Bend def is a `WL_FID_*` frame. A 10-second spindump of the long-running
client (`/tmp/birc.spindump.txt`, 893 samples) spent about 86% inside
`corpus_eval` / `work_loop` on wire-style, string, link, column, and card
code, with `term_drop` and `span_fade` hot, and about 14% in `__select`.
That is the same path as the retainer. It is a CPU profile, not a root.

These notes were taken on `bend-src` rev `4ff8545f19b09b7d2b8ca2303668100eac8efd66`
(v2.0.37). An earlier upstream survey pointed at jump-argument closure
retention (bendlang/bend #1243 and the surrounding memory issues) as the
compiler-side analogue. This note does not re-check those issues. The local
shape below avoids the closure. A pin bump is not the fix. On Bend 2.0.38,
runtime flags belong between `+RTS` and `-RTS`.

Constructor and function ids exist only as macros in the generated C of that
compilation. The store binary does not export them. CID numbers in an older
`build/birc.c` do not label `build/birc_bend.c` or a packaged binary.

## What the experiments ruled out

Caps in `src/bend/buffer.bend`: `MAX_BUFFERS` 16, `NORMAL_BUFFERS` 15,
`SCROLL_CAP` 1024, `MAX_NICKS` 256. Default `hist_cap` is 500. A few hundred
megabytes of stored chat text cannot account for a multi-gigabyte corpus.
One fat line measured about 17 KB of corpus. Sixteen full scrollbacks are a
few hundred megabytes at the cap, and that is the working set, not a climb.

All of the following used an owned loopback peer, synthetic lines, a private
pty, `--gpu off`, and no credentials. The metric is `phys_footprint` in KB.
"Plateau" means the quiet tail held. The driver's `VERDICT linear` fires when
the tail still moves by 1024 KB or more, so a single quiet step is labeled
linear even when the series then holds.

| Run | Result |
|---|---|
| Store binary, idle 240 s, 2 lines sent | 3553 → 5793. Still stepping at the end (5681 at t=214, 5793 at t=241). |
| One channel, 1024-line burst, then 2/s, then quiet | Plateau 18432. |
| Numerics alone, burst 1200, then sustain, then quiet | Plateau 16384. A CPU-contended twin reached 38912 and then mostly held. That high water is backlog. |
| 1440 join/part/query, then quiet | 45056 at sustain-end, one quiet step to 46080, then held. |
| Reconnect about 24 times at 8 s | Plateau 10240. A shorter first run ended at 7169 while still stepping. |
| 15 channels, shared host, short quiet | Still rising at 74752. A longer solo twin (`channels2`) was 4865 after the burst, 40960 at sustain-end, 47104 at quiet-end, still rising. Exit 1 there was the kill timeout, not the series. |
| Same 15-channel script on the census binary, alone, 150 s quiet | Flat at 13312 from t=22 through t=242. 2697 lines sent. The earlier climb was unprocessed backlog. |

A bounded production-view paint probe lives at `tests/perf/paint_footprint.bend`.
It is not the leak oracle. The leak shows up when the live frame loop keeps
calling the walkers.

The idle store run is the footprint leak: no chat arrived, and the bump kept
touching new pages. The census binary's idle run climbed 2688 → 4625 over
360 s (2 lines sent) and then held 4625 from t=282 through t=360. Its last
heap dump falls inside the climb, so that flat minute has no constructor sample.

## How the retainer was named

The census is a copy of generated C, not a product change. `/tmp/inject_heap_census.py`
inserts a scanner in front of `io_loop`. `SIGUSR1` only sets a flag.
`BIRC_HEAP_CENSUS=1` writes a TSV every 60 s on the IO thread, plus one dump
on the first loop tick. The first dump is empty (`bump_pages=33`,
`heap_words=4224`) because the session does not exist yet. The first useful
dump is about 60 s. Files are `{BIRC_HEAP_CENSUS_DIR}/birc-heap-{pid}-{seq}.tsv`.
`/tmp/census_diff.py` prints bump and per-name deltas. The binary used here is
`/tmp/birc-census`. Dumps:

- idle, pid 7206: `/tmp/birc-census-idle/birc-heap-7206-{0..5}.tsv`
- 15 channels, pid 7207: `/tmp/birc-census-channels/birc-heap-7207-{0..4}.tsv`

The scanner walks every word in `[HEAP_OFF, HEAP_OFF + (bump << 7))` and
counts pointer words whose aux is a known CID or FID. Because `heap_free`
clears only the header, child words of a freed node still look tagged. A
count that rises while `bump_pages` is frozen can be freelist residue, or
live objects filling slots the bump already touched. A rising bump is new
pages either way. The scanner does not know which root holds a word.

Idle, after the session existed (dump 1 at ~60 s through dump 5 at ~300 s):

| Name | Dump 1 | Dump 5 |
|---|---:|---:|
| `bump_pages` | 1065 | 1705 |
| `heap_words` | 136320 | 218240 |
| `CID_SCON` | 1494 | 3577 |
| `CID_CON` | 297 | 561 |
| `CID_BUFFER_LINE` | 13 | 61 |
| `tsk FID_COLUMNS_TAKE_GO_K6033` | 95 | 193 |
| `tsk FID_COLUMNS_TEXT_WIDTH_GO_K15654` | 90 | 155 |
| `tsk FID_COLUMNS_TAKE_GO_K6037` | 69 | 82 |

`heap_words` 218240 is about 1.7 MB of corpus. Footprint at the same time was
4625 KB. The rest is code, TimUI, and stacks. The bump moved on every dump
interval except dump 2 → 3, and the same three task names plus `CID_SCON`
rose on the intervals where it moved. `CID_BUFFER_LINE` went 13 → 61. That
is the small idle transcript, not an unbounded chat log.

15 channels, footprint already flat at 13312 KB:

| | Dump 1 (~60 s) | Dump 2 (~120 s) | Dump 4 (~240 s) |
|---|---:|---:|---:|
| `bump_pages` | 10345 | 10441 | 10441 |
| `heap_words` | 1324160 | 1336448 | 1336448 |
| `CID_SCON` | 377950 | 384631 | 385354 |
| `CID_CON` | 5025 | 5780 | 6067 |
| `CID_BUFFER_LINE` | 2667 | 2744 | 2768 |
| `tsk FID_COLUMNS_TAKE_GO_K6033` | 1311 | 1700 | 1892 |
| `tsk FID_COLUMNS_TAKE_GO_K6037` | 87 | 230 | 446 |
| `tsk FID_COLUMNS_TEXT_WIDTH_GO_K15654` | (in the working set) | | 144 total |

From dump 2 to dump 4 the bump did not move, and over those two quiet minutes
the scan still gained 723 `CID_SCON`, 192 `TAKE_GO_K6033`, and 216
`TAKE_GO_K6037`. Line count moved 2744 → 2768. Fifteen buffers near the scroll
cap are the working set. The quiet delta is the walkers.

Other tasks were present and much smaller. On the channel plateau:
`FID_VIEW_WRAPPED_MEDIA_K4980` about 344, `FID_VIEW_ANCHORED_LINES_MEDIA_CARDS_CM_K9093`
about 225, `FID_VIEW_VIEW_OPS_THEMED_K16822` about 118, `FID_IO_BIND_K21544`
about 239, `FID_NET_PAINT_GO_HINT_K18697` about 228. They did not dominate
the quiet delta. The `K` suffixes are lambda ids from this compilation.
A rebuild will number them differently. Match them by the `COLUMNS_TAKE_GO`
and `COLUMNS_TEXT_WIDTH_GO` stems.

## The allocating shape

`cluster_width_go` is already a direct recursive call. It did not appear in
the census. The three walks that did appear pass a capturing lambda as the
continuation:

```bend
def text_width_go(fuel: Nat, s: String) -> U32:
  match fuel:
    case 0n: 0
    case 1n+p:
      match s:
        case SNil{}: 0
        case SCon{h, t}:
          text_width_piece(cluster(SCon{h, t}), rest => text_width_go(p, rest))

def take_go(fuel: Nat, s: String, +cap: U32, +used: U32, head: String) -> Cut:
  match fuel:
    case 0n: Cut{String.reverse(head), s, used}
    case 1n+p:
      match s:
        case SNil{}: Cut{String.reverse(head), "", used}
        case SCon{+h, +t}:
          take_piece(cluster(SCon{h, t}), SCon{h, t}, cap, used, head,
            rest => w => acc => take_go(p, rest, cap, w, acc))

def cluster_go(fuel: Nat, s: String, +ri: Bool, head: String) -> Cut:
  match fuel:
    case 0n: cluster_cut(head, s)
    case 1n+p:
      match s:
        case SNil{}: cluster_cut(head, "")
        case SCon{+h, +t}:
          +c = Char.to_u32(h)
          cluster_char(extend(c) || (ri && regional(c)), U32.is_eq(c, 8205),
            SCon{h, t}, h, t, ri, head,
            rest => r => acc => cluster_go(p, rest, r, acc))
```

Bend compiles each `=>` as a `TAG_TSK`. The census names are those tasks.
`take_cluster` captures the accumulator with `String.reverse(text) ++ head`,
so every fitting step also allocates `CID_SCON` cells reachable from the task.

The frame loop calls these on every paint. `Cols.take` is reached from
`take_spans` (`src/bend/view.bend` around line 549). `Cols.text_width` is
called for the header, the composer prefix, word-break protection, and the
nick column (around lines 249, 611, 682, 1402, 1526, and 2488). An idle client
still paints, so the chains are rebuilt with no new IRC line.

`cluster_crlf` is a second, smaller allocation bug in the same file:

```bend
Bool.pick(Cut, U32.is_eq(Char.to_u32(next), 10),
  Cut{SCon{h, SCon{next, ""}}, rest, 0},
  Cut{SCon{h, ""}, SCon{next, rest}, 0})
```

`Bool.pick` evaluates both arms. Both cuts are allocated whenever a CR is
seen. Chat lines rarely reach this path. It is part of the same edit because
the eager pick is the same class of bug. It is not the idle task name.

View has the same lambda shape at `cluster_spans.go` (line 89), `take_spans`
(line 549), `word_break.go` (line 577), and `spans_drop_spaces.go` (line 594).
Those run once per span or once per cluster of a span. They were visible in
the census and were not the growing names. Leave them until a second census
says they are the remainder.

## The fix

Keep the helpers. Delete the continuation arguments. Have each helper call
`text_width_go`, `take_go`, or `cluster_go` directly, passing the
already-decremented fuel `p` as a normal argument.

Bend cannot `match` a computed value, a local binder, or a destructuring
`let`. `match cluster(...)` and `piece = cluster(...); match piece` are
illegal. The helpers exist so the `Cut` is matched as a parameter. Inlining
by matching the call result will not compile. Replacing the lambda with a
direct call inside the helper will.

`text_width_piece` takes the fuel instead of `k`:

```bend
def text_width_piece(piece: Cut, fuel: Nat) -> U32:
  match piece:
    case Cut{_, tail, w}: U32.add(w, text_width_go(fuel, tail))

def text_width_go(fuel: Nat, s: String) -> U32:
  match fuel:
    case 0n: 0
    case 1n+p:
      match s:
        case SNil{}: 0
        case SCon{h, t}: text_width_piece(cluster(SCon{h, t}), p)
```

`take_piece` / `take_cluster` take `cap` and `fuel` instead of `k`. The
no-fit arm still returns `Cut{String.reverse(head), s, used}` with the
original `s` of that step (`SCon{h, t}`), not the cluster tail. The fit arm
still recurses as `take_go(fuel, tail, cap, U32.add(used, width), String.reverse(text) ++ head)`.
Fuel-0 and empty-string arms stay as they are. Pass `p`, not a fuel reduced
by the cluster length. Today one input character decrements fuel by one even
when the cluster consumes several characters. The initial fuel is
`length(s) + 1`, so the tail's shorter length keeps the walk inside fuel.
Changing that changes the fuel-0 cut.

`cluster_char` and `cluster_join` take `fuel` instead of `k`. Preserve the
two continuations exactly:

- Attached (extension, or a second regional indicator): `cluster_go(p, t, ri && Bool.not(regional(Char.to_u32(h))), SCon{h, head})`. The regional flag is updated.
- ZWJ, not attached: `cluster_join` on `t` with head `SCon{h, head}`. An empty remainder is `cluster_cut(SCon{h, head}, "")`. A `SCon{h2, t2}` remainder is `cluster_go(p, t2, ri, SCon{h2, SCon{h, head}})`. The regional flag stays the outer `ri`.
- Otherwise: `cluster_cut(head, s)` where `s` is the whole remaining string, including the current character.

`cluster_crlf` matches a Bool parameter so only one arm allocates:

```bend
def cluster_crlf_cut(nl: Bool, +h: Char, +next: Char, +rest: String) -> Cut:
  match nl:
    case True{}: Cut{SCon{h, SCon{next, ""}}, rest, 0}
    case False{}: Cut{SCon{h, ""}, SCon{next, rest}, 0}
```

Call it with `cluster_crlf_cut(U32.is_eq(Char.to_u32(next), 10), h, next, rest)`.

Fuel stays the first parameter of `text_width_go`, `take_go`, and `cluster_go`.
The `1n+p` binder is linear and is used once, as the fuel argument of the
helper. Do not pass a recursive call as a `Bool.pick` value.

Returned `Cut` head, tail, and column width stay identical. `cluster_cut`
still reverses the head and measures it with `cluster_width_go`. The public
entries `cluster`, `text_width`, and `take` stay as they are.

This removes the `TAG_TSK` values the census counted. The fitting `take` step
still allocates the reversed piece and the appended accumulator. Those cells
are arguments of a plain call. When the call returns, the only live string
should be the returned `Cut`. A layout cache would cut the spindump CPU later.
It does not remove the task allocation, and it is not this fix.

## Applied fix — 2026-10-15

The helper-direct-call shape above does NOT compile on this pin: replacing
the continuations with direct calls makes `cluster_go`, `cluster_char`, and
`cluster_join` mutually recursive, and the checker rejects the cycle
("expected: a filled definition ... observed: cluster_go"). Checker rules
established by probe (`bend <file> --check-only`): matches cannot scrutinize
local binders (confirmed for Bool, ADT, and Nat); matches must follow
parameter order; self-calls terminate lexicographically (args unchanged until
one shrinks); bare constructors need an expected type (no unannotated
`SCon{...}` lets).

What landed in `src/bend/columns.bend` instead: single self-recursive walks
with a Decide/act phase parameter. Decide computes the branch values and
selects a phase VALUE with `Bool.pick`; act arms match parameters only.
`cluster_go` act arms pass fuel unchanged and shrink the string.
`text_width_go` and `take_go` decompose the computed `Cut` through
non-recursive `cut_text`/`cut_tail`/`cut_width` projections; `take_go` carries
the fit fields in its phase and doubles its entry fuel (two spends per
cluster). No lambdas, no mutual recursion, no match on a computed value.
Verified on `aarch64-darwin-4`: `columns_width=ok`,
`ui_review_columns=ok`, `ui_review_columns_parity=ok`.

## How to know it worked

Behavior, before any census rebuild:

- `make test-columns-width` rebuilds `build/columns_width` from
  `tests/bend/columns_width.bend`. Exhaustive scalar-width parity with TimUI.
- `make test-ui-review-columns` rebuilds `build/ui_review_columns` and checks
  native cluster boundaries and widths (ZWJ, VS16, regional indicators,
  control boundaries) plus wrapping. Golden: `ui_review_columns=ok`.
- Both binaries depend on `src/bend/*.bend`, so a `columns.bend` edit rebuilds
  the harness. It does not regenerate the 31 MB app C.
- Affected laws: `LAWS.bend` `Columns.text_width("👩‍💻❤️🇰") == 6` and
  `VL.header_columns_ok()`. Run those with the harnesses. Save `make proof`
  for the integrated batch.

Retention, after the harnesses pass:

1. Codegen the app from the changed `columns.bend`. Inject with
   `/tmp/inject_heap_census.py`. Compile a new `/tmp/birc-census`. Do not add
   the scanner to `make check` or to product C.
2. Repeat the idle run (about 6 minutes) and the solo 15-channel run with
   150 s of quiet. Use `/tmp/birc_exp.py --binary /tmp/birc-census --census-dir …`,
   `--gpu off`, synthetic lines, and the same env as the original runs
   (`BIRC_PREFERENCES=none`, `BIRC_IMAGE_CACHE=none`, `BIRC_HISTORY=none`,
   `BIRC_NO_TELEMETRY=1`, notify helper `birc-exp-none`).
3. Compare dumps with `/tmp/census_diff.py`.

Fixed means all three of these, on dumps taken after warmup, while the client
is idle:

- `bump_pages` stays on one value.
- `CID_SCON` stays on one value.
- No rising `FID_COLUMNS_TAKE_GO_K*` or `FID_COLUMNS_TEXT_WIDTH_GO_K*` row.
  Those lambda ids should be gone. A new rising task stem from the same
  walk means this pin is retaining the call itself. Record that and stop
  rewriting the same shape.

A flat `phys_footprint` is the user-visible result and is not sufficient by
itself. The channel run already held 13312 KB for three minutes while those
counts kept rising inside the touched pages. A flat `CID_BUFFER_LINE` near
the scroll cap, with a flat `CID_SCON` of similar magnitude to the capped
text, is the working set.

The historical multi-gigabyte client is explained only as far as this
mechanism. Confirm it by the idle bump stopping after the rewrite. Until that
census exists, the named retainer is the column-walker tasks and the string
cells they capture, and the fix is the direct-call rewrite above.

## Post-fix census — 2026-10-15

Binary: `a1aa3e6` (phase-machine `columns.bend`) plus the uncommitted
`Session.hist_live` boxing slice, codegenned and census-injected on
`aarch64-darwin-4` (load ~1.1; scripts md5-identical to `/tmp` on the
driver host). Driver `/tmp/birc_exp.py`, `--gpu off`, same env as the
original runs. Behavior harnesses re-verified on this exact tree first:
`columns_width=ok`, `ui_review_columns=ok`, `ui_review_columns_parity=ok`.

Idle, 360 s, 2 lines sent (pid 76214, dumps 0..5):

| Dump | `bump_pages` | `heap_words` | `CID_SCON` | `CID_BUFFER_LINE` |
|---|---:|---:|---:|---:|
| 0 (pre-session) | 33 | 4224 | 0 | 0 |
| 1 (~60 s) | 649 | 83072 | 1053 | 13 |
| 2 (~120 s) | 905 | 115840 | 1670 | 25 |
| 3 (~180 s) | 1033 | 132224 | 2156 | 37 |
| 4 (~240 s) | 1033 | 132224 | 2258 | 49 |
| 5 (~300 s) | 1033 | 132224 | 2619 | 61 |

Footprint 2353 → 3410 by t=92, then 3410 (two 3250 dips) from t=121
through t=343 (~220 s flat), one step to 3554 at t=353. Driver verdict
`unclear` (span 1169, tail_span 144). Pre-fix census idle for comparison:
bump 1065 → 1705 still moving, footprint 2688 → 4625.

15 channels, 60 s sustain + 150 s quiet, 2637 lines sent (pid 77756,
dumps 0..3):

| Dump | `bump_pages` | `heap_words` | `CID_SCON` | `CID_BUFFER_LINE` |
|---|---:|---:|---:|---:|
| 0 (pre-session) | 33 | 4224 | 0 | 0 |
| 1 (~60 s) | 9193 | 1176704 | 351410 | 2667 |
| 2 (~120 s) | 9193 | 1176704 | 351474 | 2685 |
| 3 (~180 s) | 9193 | 1176704 | 351438 | 2697 |

Footprint flat at 12288 across the whole quiet period (t=63..212,
tail_span 0). Pre-fix for comparison: flat at 13312 while the bump-frozen
window still gained 723 `CID_SCON`, 192 `TAKE_GO_K6033`, 216
`TAKE_GO_K6037`.

Against the three fixed criteria:

- `bump_pages` frozen: yes, both runs (idle 1033 x3 dumps, channels
  9193 x3 dumps).
- `CID_SCON` frozen: yes on channels (+64 then -36, net +28 over the
  frozen window vs +723 pre-fix). Idle still rises +102/+361 inside the
  frozen bump with no accompanying task stem; see below.
- No rising `FID_COLUMNS_TAKE_GO_K*` / `FID_COLUMNS_TEXT_WIDTH_GO_K*`:
  yes. Zero `COLUMNS` rows of any kind in all 10 dumps (the K-suffixed
  FIDs still exist in the binary's table as compiler-generated
  continuations for nested calls, but no live `TAG_TSK` ever points at
  them). No other walk stem rises either: the only idle creepers are
  `UTF8_DECODE_GO`/`IO_BIND` at +4..5 per interval, tracking the line
  trickle, two orders of magnitude below the pre-fix walker slope.

The `+12 CID_BUFFER_LINE` per 60 s idle interval is byte-identical
pre/post fix (13 → 61 at dump 5 both times): a pre-existing line
trickle (or paint-churn residue — the scanner cannot distinguish inside
frozen pages), not the walkers. Per this note's rule ("a new rising task
stem from the same walk means this pin is retaining the call itself"),
no such stem exists, so the named retainer is fixed. The idle
`CID_SCON` slope inside frozen pages is a watch item for a longer soak,
not a rejection.

`tests/perf/paint_footprint.*` (untracked at census time): `make
paint-footprint` builds and exits 0; checksum 2491 stable across all
32+32+64 paints; deltas +784/+800 at 32 passes and +1617 at 64 (staircase
with multi-second flats, verdict `unclear` all three runs). That is a
footprint-only signal with no corpus attribution — this probe is not the
leak oracle — and does not overturn the instrumented census above.
Commit-ready as a non-gate measurement probe, no code changes needed.

## Follow-up: idle SCON attribution (2026-10-15)

A 16-minute idle soak plus a live instrumented probe closed the watch
item above. Zero `COLUMNS` task rows in 30 dumps: the column fix is
exonerated. The live +336 SCON per interval is PONG keepalive trickle
logged through `feed_unk` (every server PONG logged an
unknown-command server row; PING was already skipped, PONG was
missed), with the raw-dump excess as freelist residue. Fix landed
with this note: `feed_pong` no-ops in both feed dispatchers while the
fold lag arm keeps measuring RTT off the raw line. Residual: the
>90-minute `SCROLL_CAP` bind (trickle must flatten once buffer 0 hits
1024 lines) was not observed; the negotiated-fold PONG-out arm still
emits and is a probable live-dupe vestige awaiting a live-server
probe (see BACKLOG).
