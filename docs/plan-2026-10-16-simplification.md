# birc simplification — parallel implementation plan (2026-10-16)

Handover document for `cursor-agent`. Derived from a nine-agent read-only design
review; every `file:line` citation below was verified by direct read.

**Scope:** all four priority tiers (P0 correctness, P1 iteration speed,
P2 UI responsiveness, P3 Bend-over-C, P4 structural DRY/SOLID).
**Verification policy:** focused per-task checks, then one integrated batch gate.
**Orphan tests:** wire them; if one fails, quarantine and report — never fix
product code and never weaken a test to make it pass.

---

## 0. Global rules (every task MUST obey)

1. **Stay inside your declared file set.** Another agent owns the rest and is
   editing concurrently. Touching a file outside your set will corrupt a merge.
   If you believe an out-of-set change is required, STOP and report it instead.
2. **Work mode is BUILD** (AGENTS.md 2026-10-12). Implement a vertical slice,
   run focused checks, commit. No per-commit freezes, no separate red commits.
3. **Never weaken a law to make a candidate pass.** `LAWS.bend` has 535 laws
   discharged 1:1 by 535 proofs in `PROOF.bend`. Re-prove on a new seam; do not
   delete an assertion.
4. **Fail closed.** Missing targets exit nonzero. Never suppress a failing check
   to manufacture a green result.
5. **Host contention budget.** 10 cores. Use `MAKEFLAGS=-j2` for every `make`
   invocation. Never `make -j` unbounded. Bound every build with the existing
   `timeout` values; do not raise them.
6. **No network, no credentials, no user files.** Tests use synthetic
   certificates, synthetic files, fake helpers, and owned loopback peers. Never
   contact `0x0.st`, never fetch a supplied private chat URL, never touch the
   real Keychain.
7. **Never `git push`.** Commit locally on your task branch only.
8. **Do not read or glob** `build/`, `.muse/`, `handover-recovery/`, `scratch/`,
   `result*`. `build/` holds 724 MB of generated C including single files over
   one million lines.
9. **Report honestly.** If a check did not run, say so. If a change is
   unverified, mark it. Never claim success without pasted output.

### Bend pitfalls (pinned backend — these will bite you)

- `Bool.pick` evaluates **both** alternatives eagerly. For recursive branches or
  row construction use a parameter match or a lazy continuation.
- Self-recursion needs a **decreasing fuel as the first argument**.
- No `match f(x)`. `match` cannot scrutinize a computed value, a local binder,
  or a destructuring let.
- `+T` is copyable; match binders go in parameter order; no dotted forward refs.
- The C backend caps flattened continuation capture at **247 words**. Boxed
  one-element `List` cells are the existing workaround — preserve them.
- Escapes: `Maybe.default`, `Maybe.bind`, `do Maybe`, decision `Bool` as a
  parameter.

### Command template

```sh
cd <worktree>
export MAKEFLAGS=-j2
export BIRC_UI_CACHE=1
export BIRC_UI_CACHE_DIR=/Users/angerman/Projects/zw3rk/birc-uicache   # shared across worktrees
make <focused targets>          # must pass
git add -A && git commit -m "<type>(<scope>): <summary>"
```

### Remote build lanes

The local 10-core host is often busy with unrelated work, and its wall-clock
numbers are worse than the calibrated bounds in `Makefile:18-20`. Four 8-core
`aarch64-darwin` hosts are available as build lanes:

| Host | Cores | Free disk | Typical load | Status |
|---|---|---|---|---|
| `aarch64-darwin-1.lan` | 8 | 198 GiB | ~1.0 | **provisioned, verified** |
| `aarch64-darwin-5.lan` | 8 | 112 GiB | ~1.5 | provisioning (store-lock retry) |
| `aarch64-darwin-3.lan` | 8 | 32 GiB | ~4.0 | busy — avoid |
| `aarch64-darwin-4.lan` | 8 | 29 GiB | ~1.0 | disk too tight for `build/` |

Each lane holds a copy of the tree at `/Users/angerman/birc-lane`. Provisioning is:

```sh
rsync -a --delete --exclude 'build/' --exclude '.muse/' --exclude 'handover-recovery/' \
      --exclude 'scratch/' --exclude 'result*' --exclude '.direnv/' \
      ./ aarch64-darwin-1.lan:/Users/angerman/birc-lane/
ssh aarch64-darwin-1.lan 'cd /Users/angerman/birc-lane && mkdir -p build \
  && nix --extra-experimental-features "nix-command flakes" develop \
       --no-update-lock-file . --command bend version'
```

Verified working: `make test-utc-time test-base64` from a cold `build/` returns
both `=ok` in 3.4 s at 192% CPU.

Two gotchas found the hard way:
- `build/` must exist. Raw `bend X -o build/X` does not create it (`ld: can't open
  output file … errno=2`); the Makefile's `@mkdir -p $(BLDDIR)` does. Always
  `mkdir -p build` after an rsync that excludes it.
- Do not pipe the ssh command through `tail` when you care about success —
  `ssh … | tail -4` returns tail's status, so a failed warm-up prints as if it
  succeeded. Check `${PIPESTATUS[0]}`, or capture and grep for `bend 2.`.

**Division of labour.** Agents run locally and do their own focused verification
(a handful of compiles each). The lanes are for the *expensive* work that the
reviewing agent drives between waves: the integration gate (`make -j10 check`,
154 Bend compiles), `make proof`, sanitizer builds, and perf sweeps. Nix remote
builders are *not* the mechanism — `builders =` is empty and would not help,
because the Makefile runs `nix develop --command bend`, which executes locally;
only `nix build` offloads to a remote builder.

Note that lane copies are rsynced snapshots. Re-sync before trusting a lane
result, and never treat a lane's `build/` as authoritative for the local tree.

### Report format (write to `/tmp/birc-cursor-reports/<task-id>.md`)

```
# <task-id> — <title>
## Changed files            (exact list)
## Findings implemented     (one line each, with file:line)
## Verification             (commands run + pasted tail of output; mark SKIPPED if not run)
## Deviations               (anything you did differently, and why)
## Out-of-set blockers      (changes you need in files you do not own)
## Unverified / risks
```

---

## Wave structure and merge order

| Wave | Tasks | Parallel | Gate to advance |
|---|---|---|---|
| 0 | T0.1, T0.2 | 2 | `make -n check` + `make lint-ffi` clean |
| 1 | T1.1–T1.5 | 5 | per-task focused checks |
| 2 | T2.1–T2.5 | 5 | per-task focused checks |
| 3 | T3.1 | 1 (critical path) | `make proof` + protocol suite |
| 4 | T4.1–T4.3 | 3 (API-frozen) | per-task focused checks |
| 5 | integration | — | `make -j10 check` + `make proof` + sanitizers |

Merge each wave into `master` in task order before starting the next.
Waves 3 and 4 change public APIs and must not overlap.

---

## Wave 0 outcome, and corrections to this plan

Wave 0 is merged (`571356b`, `e12fefc`). Both tasks were reviewed against their
commits, not their reports. Measured results:

| Metric | Before | After |
|---|---|---|
| FFI paths in `BEND_SRC_DEPS` | **0** | **11** |
| Deadline-checked compiler recipes | 154 | **777** |
| `lint-ffi` C file coverage | 5 of 7 | **7 of 7** |
| `test-*` targets defined | 347 | **361** (none lost) |
| Committed dead proof shards | 2,227 lines | **0** |
| `docs/FFI.md` effect coverage | ~13 of 44 | **44 of 44** |
| `make -n -B check` recipe lines | 841 | **1066** |

The last row is not a regression: the extra lines are per-test closure generation
and the cache conditional. **Raw `make -n` line count is no longer a useful
baseline** — use the `bend` invocation count and the 777 deadline count instead.

**Corrections — the plan was wrong about these. Later waves must use the corrected
facts:**

1. **33** unreachable Bend programs, not 32. `tests/bend/isupport.bend` is a
   *program* that sits beside `src/bend/isupport.bend`; the original count
   conflated them. After promoting the three that pass, `test-orphans` has **30**
   prerequisites.
2. **`test-mss-stale-socket` is not a target.** The real name is
   **`test-mss-stale-held`**. T2.4/T2.5 must use the corrected name.
3. **GNU make 3.81 has no `--eval`.** `tests/build_deadlines.py` reads `make -n`
   expansion instead. Any later task that wanted `$(MAKE) --eval` must not assume
   it exists.
4. **A command-line-only `make -j2` is still overwritten by `-j10`** on make 3.81,
   because `-j` is absent from `$(MAKEFLAGS)` during parsing and the environment
   copy is empty. An **exported** `MAKEFLAGS=-j2` *is* honoured. All wave
   launchers therefore export `MAKEFLAGS` rather than passing `-j` on the command
   line.
5. `make -n` will really rebuild a missing `build/<stem>.bend.d`, and the rebuilt
   `.d` then makes the binary look stale. **`make -q` against a stable closure
   file** is the check that distinguishes a real dependency from an artefact of
   dry-run regeneration. Use `make -q`, not `make -n`, when proving staleness.
6. The three orphans that pass and are now on `test-review-pure`:
   `test-outbound-txn`, `test-draft-nick-rename`, `test-ws-shutdown-pending`.
   `test-dns-live` was deliberately **not** executed (it needs a live resolver)
   and stays on `test-orphans`.
7. `tests/lint-ffi/ffi_stub.h` does **not** declare the park queue
   (`IoWork.next/item/time`, `io_park`, `io_runs`) that `tls_ffi.c` walks, which
   is why `lint_tls.c` carries its own prelude. Do not "fix" this by pointing
   `lint_tls.c` at `ffi_stub.h`.
8. The `dns` greps inside the `lint-ffi` recipe were stale — they matched a
   3-argument `io_eff` and a `4096u` clamp that no longer exist in
   `src/ffi/dns_ffi.c`. They now match the real 2-argument registrations and
   `if (max > 65536u)`. This is the same drift `docs/FFI.md` had; assume other
   grep-based assertions in the Makefile may be stale too, and check them against
   source rather than trusting them.

**Still open from Wave 0** (declared SKIPPED, being closed on the remote lane):
`make test-nix-preflight`, and an end-to-end exercise of the `BIRC_UI_CACHE`
restore-hit and store paths — only `build-ui-cache.sh key` was verified.

*Both subsequently closed.* `test-nix-preflight` **failed** on merged master: the
new `build/%.bend.d` recipes called `sh scripts/bend-deps.sh` directly, which execs
`python3`, and `tests/nix_preflight.py:22` shadows `python3` with a shim that
`exit 77`s so no recipe can reach for an ambient interpreter. Fixed in `badce91` by
routing the three closure recipes through `$(NIXRUN)` like every other recipe in
the file; `nix_preflight=ok`. The UI cache measured **3:22.68 cold → 1.919 s warm**
on the lane, identical 11,499,208-byte `birc` — a 105× win on the project's
slowest artifact.

---

## Proof cannot be sharded — measured, not assumed

`make proof` **fails at its default `PROOF_TIMEOUT=180` even on a quiet host.**
Measured on `aarch64-darwin-1.lan` at load 0.98, master `c33a3d2`:

```
proof_rc=2
make: *** [proof] Error 124
MAKEFLAGS=-j1 make proof  208.99s user 138.04s system 181% cpu 3:11.61 total
```

Error 124 is `timeout` expiring. This is pre-existing, not a regression — it is why
`74d344a` is titled *"docs: record proof-600 timeout, C8/G6 unqualified"* and why
`TODO.md:53` still reads *"Locate the remaining full-book cost; the bounded 535-law
run has no verdict."* **`make check` includes `proof`, so `make check` is red on
master today.**

**Sharding is impossible.** A probe discharged 25 of the 535 `def Laws.*` blocks
into a standalone file with `PROOF.bend`'s own 19-line import header, and Bend
rejected it:

```
shard_rc=1
SOME PROOFS FAIL
Error: 510 TODOs found.
The code is incomplete, and not a valid proof yet.
```

535 − 25 = 510: **every undischarged law in the imported `LAWS.bend` counts as a
TODO**, so the checker requires the whole book in one compilation unit. This
answers the question `724de4d` left open (*"Wiring into make proof pending
calm-host runs"*) — wiring was never possible, which is presumably why it never
happened. Wave 0's deletion of the eight shards was correct, and there is no
`scripts/split-proof.sh` worth writing.

**Consequences for every remaining wave:**

1. `make proof` is a **monolithic ~37,389-line closure compile** (`LAWS.bend`
   imports 49 modules). It cannot be scoped to a diff.
2. A task reporting a proof **timeout** has not necessarily broken anything.
   Re-run serially on the quiet lane before believing either outcome.
3. Use the documented override `make proof PROOF_TIMEOUT=<n>`; **never edit the
   Makefile default** without a measured calm-host number to justify it.
4. Gate waves on the **golden suites** (`test-goldens-proto` / `-view` / `-io`,
   which do scope to the diff) and treat `proof` as a separate, serial,
   lane-only check run once per wave rather than once per task.
5. The only durable ways to make proof cheaper are to shrink what `LAWS.bend`
   imports or to make the checker faster — neither is in scope here. Record this
   as the answer to `TODO.md:53`.



---

# WAVE 0 — Foundation

## T0.1 Build correctness and speed

**Owns:** `Makefile`, `mk/pty-shard.mk`, `mk/wf-cards.mk`, `mk/wf-filter.mk`,
`mk/wf-settings.mk`, `scripts/shard-pty.sh`, `scripts/bend-deps.sh` *(new)*,
`tests/lint-ffi/lint_tls.c` *(new)*, `tests/lint-ffi/lint_history_search.c` *(new)*,
`tests/build_deadlines.py`

**Why first:** every later task depends on builds being correct and fast.
Measured today (`make -n -B check`): **154 `bend` invocations, 35 `$CC` steps,
153 `check-golden.sh` runs, 80 PTY runs, 479 `nix develop` re-entries**.

### Changes

1. **P0 — FFI staleness (one line, highest severity in the whole review).**
   `Makefile:120` is `BEND_SRC_DEPS := $(wildcard src/bend/*.bend)`, but
   `.bend` files inline C directly — e.g. `src/bend/tls.bend:16`
   `import "../ffi/tls_ffi.c"`; 16 modules do this. The pattern rules at
   `Makefile:122` and `:134` therefore miss FFI edits, while the *link* rules do
   list `BEND_UI_SRCS` — so Make relinks confidently from a stale generated `.c`.
   **50 of 196** test binaries are affected. `src/ffi/timui_ffi.c` is the
   third-churniest file in the repo (73 commits).
   → `BEND_SRC_DEPS := $(BEND_UI_SRCS)` (already correctly defined at `:107`).

2. **P0 — fail-closed includes.** `Makefile:1473-1476` uses `-include` for all
   four `mk/*.mk`. Absence is silently ignored, so deleting `mk/wf-filter.mk`
   drops its targets from `test-review-pure` → `test` → `check` and
   `make check` still exits 0.
   → Guard with `ifneq ($(wildcard mk/x.mk),) include … else $(error …) endif`,
   with an escape hatch `BIRC_ALLOW_MISSING_MK=1` set only by the
   `test-nix-preflight` temp-dir invocation.

3. **P0 — lint coverage.** `make lint-ffi` covers 5 of 7 C files. Missing:
   **`src/ffi/tls_ffi.c`** (663 lines of OpenSSL cert/SNI/verification code) and
   `src/ffi/history_search_ffi.c` (386 lines). The real build compiles both with
   `-w` (`Makefile:104`), so this is their only warning pass.
   → Add `tests/lint-ffi/lint_tls.c` and `lint_history_search.c` mirroring the
   existing `lint_history.c`, and two recipe lines.

4. **P1 — default parallelism.** `MAKEFLAGS` occurs exactly once in the Makefile,
   inside the comment at `:119` that says `make -jN check` is safe.
   `README.md` tells newcomers `make check`.
   → `MAKEFLAGS += -j$(shell sysctl -n hw.ncpu 2>/dev/null || nproc)` guarded by
   `ifeq (,$(findstring j,$(MAKEFLAGS)))`, with
   `update: MAKEFLAGS := $(filter-out -j%,$(MAKEFLAGS))` so pin moves stay serial.

5. **P1 — exact import-closure deps.** Real graph = **5,615** (test,src) edges;
   the wildcard assumes **15,092** = **2.69x over-invalidation**. Editing
   `net.bend` needs 20 rebuilds, Make does 196. Editing `app.bend`, 6 vs 196.
   Every `import` in the tree is one of two statically scannable forms:
   `import Base` or `import <path>.bend`.
   → New `scripts/bend-deps.sh <entry.bend>` printing the transitive closure
   (must also follow `import "../ffi/*.c"` so change 1 stays satisfied).
   Emit `build/%.d` and `-include` them *after* the fail-closed guard from
   change 2. Keep `BEND_SRC_DEPS` as the fallback if a `.d` is missing.

6. **P1 — layer-scoped aggregates + `focus`.** None exist today. By import
   graph: **39** goldens touch `view.bend`, **72** touch `irc.bend`/`client.bend`,
   **16** touch `net.bend`/`actor.bend`.
   → `test-goldens-view`, `test-goldens-proto`, `test-goldens-io`, and
   `make focus T=<target>`. Generate the membership lists from the import graph
   (change 5) rather than hardcoding, so they cannot drift.

7. **P1 — wire the cache that already exists.** `scripts/build-ui-cache.sh`
   (196 lines) is a working content-hash cache for the slowest artifact — the
   33 MB / 1,032,610-line `build/birc_bend.c` TU whose link takes 143s calm and
   ~280s loaded (`Makefile:18-20`). Its own header at `:11` says
   *"this script is inert until wired in."* `BIRC_UI_CACHE` defaults off.
   → Wire restore/store around the `build/birc_bend.c` and `build/birc` recipes.

8. **P1 — `nix develop` re-entry warning.** 479 re-entries × ~1.2–1.6s warm
   ≈ 10–13 min of pure overhead for anyone not inside `make shell`
   (`BIRC_NIX_SHELL` is set only by the devShell, `flake.nix:69`).
   → Parse-time warning when `BIRC_NIX_SHELL != 1` and `command -v bend` is empty.

9. **P1 — PTY target list drift.** `scripts/shard-pty.sh` hardcodes 73 entries,
   `mk/pty-shard.mk:4` claims 73, the Makefile defines **79**.
   → Export `PTY_SUITE_TARGETS` from the Makefile and consume it in the script.

10. **P0 — wire the 32 orphan test programs.** 32 of 196 `tests/bend` programs
    are unreachable from `make check`; three have zero referencers anywhere
    (`isupport_adapters`, `preferences_history_characterization`,
    `preferences_runtime_typecheck`). The targets already exist
    (`test-wsnet-gates`, `test-cards-live`, `test-sessws-s1s5`, `test-workspace`,
    `test-session-drafts`, `test-draft-nick-rename`, `test-ws-carrier-native`,
    `test-ws-first-connect`, `test-ws-shutdown-pending`, `test-ws-upload-frame`,
    `test-ws-media-stage-native`, `test-workspace-005-source`,
    `test-workspace-isolation-step`, `test-mss-stale-socket`, …) — they are simply
    in no aggregate. Source files admit it: `tests/bend/wsnet_gates.bend:8`
    *"Authored-but-NOT-run"*, `Makefile:1719` *"SOURCE UNRUN"*.
    → Add a `test-orphans` target listing all 32. Run it. **For each failure:
    leave it in `test-orphans`, do NOT add it to `test-review-pure`, do NOT edit
    product code, do NOT weaken the test — record it in your report.** Add the
    passing ones to `test-review-pure`. Prefer the JS-backend recipes (13 of 16
    ws/cards orphans already have `.js` rules at 30s timeouts).

11. **P1 — Makefile DRY (do LAST in this task, and only with change 12).**
    ~500 removable near-duplicate lines: 12 blocks at `:138-172` differing only
    in one timeout integer; 12 identical `$CC` link blocks at `:178-213`;
    **217 `@mkdir -p $(BLDDIR)`** of which ~190 are redundant because the
    pattern rules at `:123,127,131,135` already create it; 137 copy-pasted
    target/recipe pairs; 99 `.PHONY` lines; 16 scattered `test-pty:`
    accumulations.
    ⚠️ **`tests/build_deadlines.py:19-20` scans Makefile *text* for
    `timeout\s+[1-9][0-9]*\s+bend`.** An `$(eval)` refactor makes those recipes
    invisible to the scan, silently narrowing coverage from 154 recipes to 4.

12. **P1 — update `tests/build_deadlines.py`** to introspect
    `$(MAKE) --eval` / `make -n` output instead of Makefile text, so change 11
    cannot narrow the deadline scan. Land 11 and 12 in the same commit.

**Verification**
```sh
make -n -B check | wc -l                 # compare against 841 baseline
make lint-ffi                            # now covers 7 C files
make test-build-deadlines
make test-golden-runner
make focus T=test-utc-time               # new target works
make test-goldens-view                   # 39 binaries, scoped
make test-orphans                        # RECORD FAILURES, do not fix
sh scripts/build-ui-cache.sh key         # prints a stable hash
```

**Done when:** FFI edits invalidate affected test binaries (prove it: touch
`src/ffi/clock_ffi.c`, `make -n test-utc-time` shows a rebuild); a missing
`mk/*.mk` exits nonzero; `lint-ffi` covers 7 files; `make focus` works; the
orphan report is written.

---

## T0.2 Repository hygiene and documentation truth

**Owns:** `.gitignore`, `PROOF.shard0.bend` … `PROOF.shard7.bend` *(delete)*,
`AGENTS.md`, `README.md`, `TODO.md`, `HANDOVER.md` *(move)*,
`docs/handover-2026-10-08.md` *(new)*, `docs/FFI.md`, `docs/build-speed.md`,
`BACKLOG.md`

### Changes

1. **`.gitignore` is 8 lines** and ignores none of `.muse/` (337 MB, 25
   registered worktrees), `scratch/`, or `handover-recovery/`. Suppression exists
   only in the *untracked* `.git/info/exclude`, so a fresh clone or another agent
   sees all of it. Measured: `grep -rl` across the tree = **25.66s**; with those
   excluded = **0.278s** (**92x**). `find . -name '*.bend'` returns **8,065**
   files vs **276** real.
   → Add `.muse/`, `scratch/`, `*.orig`, `*.rej`; move the `.git/info/exclude`
   entry into the tracked file.
   → **Do NOT delete `handover-recovery/` or prune worktrees** — destructive,
   needs the author. Report them instead.

2. **Delete `PROOF.shard0-7.bend`** (2,227 lines). Commit `724de4d` is literally
   titled *"proof: add eight timing shards (unwired)"*; nothing in `Makefile`,
   `mk/`, `scripts/`, `nix/`, or `docs/` references them, and `make proof`
   (`Makefile:1398`) runs only `PROOF.bend`. They are an exact partition of
   `PROOF.bend`'s 535 defs, so they are pure hand-synced duplication.
   → Before deleting, verify the union of shard `def Laws.*` equals
   `PROOF.bend`'s, and note in the commit that `docs/build-speed.md:22-24`
   promises *"Run affected law checks while iterating"* — a mechanism that has
   never existed. If selective law reruns are wanted later, generate shards into
   `build/` from `PROOF.bend`; do not commit them.

3. **Regenerate `docs/FFI.md`'s Effects table.** It documents **~13 of 44**
   `io_eff(CID_*)` registrations across **3 of 7** C files. Entirely
   undocumented: all six TLS effects, `APPEND_PRIVATE`, `HISTORY_SEARCH_OPEN`,
   `SEARCH_SCAN`, `SETUP`, `NOTIFY`, 15 of 21 `timui_ffi.c` effects,
   `TCP_CONNECT_FOR`, `TCP_SEND_FOR`, `UDP_BIND6`, `MILLIS`, `NET_TRACE`,
   `UTC_LOCAL_PARTS`.
   → Generate from `grep -h 'io_eff(CID_' src/ffi/*.c`. It is mechanically
   derivable and should never have been hand-maintained.

4. **Fix the three verified factual errors in `docs/FFI.md`:**
   - `:18` documents `io_eff(CID_<NAME>, run, flags)` — every one of the 44
     registrations is **2-arg**.
   - `:47` and `:280` say the recv clamp is 4096 — `dns_ffi.c:52-53` clamps to
     **65536**.
   - `:12` shows `Timui.frame(ui, ops, input, seed)` — `timui.bend:63-66` has
     **five** args (`compose_x` added).

5. **`AGENTS.md` Layout table:** 0 ghost paths, but it omits **48 of 77**
   `src/bend` modules (**81% of lines**). It never mentions `docs/` at all
   (`grep -n 'docs/' AGENTS.md` → 0 hits), so `docs/FFI.md`,
   `docs/build-speed.md`, and `docs/column-walker-retention.md` are invisible to
   anyone following the documented entry path.
   → Replace per-file rows with ~8 concern rows naming a **glob plus an
   invariant**, not a file list. The most valuable is the proof boundary:
   `src/bend/{actor,net,wsnet,timui,dns*,tls,transport,clock,app,*_io,*_live,*_worker,*_runtime}.bend`
   = *IO/effect layer — MUST NOT be imported by `LAWS.bend`*.
   → Keep per-file rows only for the ~15 modules with non-obvious contracts.
   → **Add the missing `cap_notify.bend` row.** It is 1,025 lines and its own
   header (`:2`) says it is the *IRCv3 capability registry and sole `CAP END`
   owner* — not notification policy. It currently gets zero mentions while the
   much smaller `notify.bend` gets one.
   → Add a `Docs` row. Add one work-mode rule: *"a commit that adds or renames a
   `src/` file updates the concern row it belongs to — never a file list."*
   → Fix the `TODO.md` row: it says *"M8 = TimUI example parity"*; `TODO.md`
   runs through **M27**.

6. **`TODO.md:14-18` is dangerously stale.** It says *"Its stock 425-law proof …
   passed"* and *"The separate 535-law final candidate is preserved on the local
   `checkpoint/birc-final-candidate-2026-10-08` branch … It is not merged."*
   `git show 03cb8c2:LAWS.bend | grep -c '^law '` returns **535** — it merged on
   2026-10-08. `TODO.md:11-12` already half-says this; the block below it was
   never updated.
   → Add a banner retiring the checkpoint block. Do not rewrite the milestone
   history.

7. **Archive `HANDOVER.md`** → `docs/handover-2026-10-08.md` with a
   `SUPERSEDED — see AGENTS.md` banner. Two live hazards:
   - `HANDOVER.md:184` *"A changed PTY test needs three consecutive passes"*
     directly contradicts `AGENTS.md:206` *"do not require three reruns before
     every commit"*. Following HANDOVER triples PTY cost per commit.
   - Its "Durable recovery" block tells you to `git log -1
     checkpoint/birc-final-candidate-2026-10-08`; that ref no longer resolves
     (moved under `refs/archive/2026-10-12/`, 223 refs live there).
   Archive rather than delete: it holds the only record of the `refs/archive`
   migration and the calm-host prebuild/load evidence at `:30-52`.

8. **`README.md`:** 0 ghost links and all 25 hand-named laws still exist — the
   healthiest doc. Two fixes: the ASCII diagram at `:63-69` lists 4 FFI files,
   omitting `auth_bridge_ffi.c`, `history_ffi.c`, `history_search_ffi.c`; and
   the quickstart at `:190` says `make check` where `:740-741` says
   `make shell` first — reorder to `bootstrap` → `shell` → `make -j check`.

9. **`docs/build-speed.md:11`** cites `NIXRUN (Makefile:20-24)`; NIXRUN is at
   `Makefile:25-28`.

10. **`BACKLOG.md` is current** (HEAD commit, explicit FIXED/UNIFIED/ATTRIBUTED
    statuses). Only add a "Resolved" tail section so the open set is scannable.
    Add entries for the deferred destructive cleanups from change 1.

**Verification**
```sh
git status --porcelain                    # only intended paths
git ls-files PROOF.shard*.bend            # empty
grep -c 'io_eff(CID_' src/ffi/*.c | …     # table row count == 44
for p in $(grep -oE '`[a-z_/.]+\.(bend|c|h|py|md)`' AGENTS.md | tr -d '`' | sort -u); do
  [ -e "$p" ] || echo "GHOST: $p"; done    # no output
```

**Done when:** no backticked path in `AGENTS.md`/`README.md` is a ghost; the FFI
Effects table has 44 rows; `git ls-files PROOF.shard*.bend` is empty.

---

# WAVE 1 — Independent fixes, public APIs frozen

Five tasks, provably disjoint file sets. **Every task in this wave must keep the
public API of every module it touches unchanged** — internal-only edits. That is
what makes the parallelism safe.

## T1.1 Paint-path responsiveness

**Owns:** `src/bend/columns.bend`, `src/bend/view.bend`, `tests/perf/key_latency.py` *(new)*

**API freeze:** `view.bend`'s public entry points and the `DrawOp` contract must
not change. `net.bend` (T1.5) and `session.bend` call them.

1. **P2 — the hottest paint primitive is quadratic.** `columns.bend:116`:
   ```
   cluster_go(Nat.add(1n, String.length(rest)), rest, regional(...), SCon{h, ""}, Decide{})
   ```
   `String.length` is a linear recursion over `SCon`. `cluster()` is called once
   **per cluster** from `columns.bend:143,144,167,168,169` and
   `view.bend:89,592,609,648,665`. For a string of L chars, each of L cluster
   steps pays O(L) ⇒ **O(L²)**. At IRC's 512-byte cap that is ~260k reductions
   per line, per frame, per pane.
   → Add `cluster_bounded(s, fuel)` and thread a caller-owned decreasing fuel.
   `take_go`/`text_width_go`/`cluster_spans.go` already carry such a fuel (`p`);
   initialise the outer fuel to `2n+2` instead of `n+1`.

2. **P2 — the same redex three times.** `columns.bend:167-169` builds
   `cluster(SCon{h, t})` **three separate times** for one cut; `:143-144` twice.
   → `+cut = cluster(SCon{h, t})` once, then `cut_text(cut)` / `cut_tail(cut)` /
   `cut_width(cut)`. The accessors already exist (`columns.bend:120-127`).

3. **P2 — per-frame O(scrollback) copy.** `view.bend:985-986`:
   ```
   def pending_display_lines(+name, +pends, +lines) -> List<&2, Cl.Line>:
     List.append(&2, Cl.Line, lines, pending_for_buf(pends, name))
   ```
   Called unconditionally from the production themed path at `view.bend:3200`.
   `List.append` recurses over its **left** argument, so this is O(scrollback)
   cons allocations per frame per pane, discarded when `pends` is empty — the
   normal case.
   → Guard on `List.is_empty(pends)` and return `lines` unchanged.

4. **P2 — full scrollback reversal per frame.** `view.bend:3194` reverses all
   lines at the bottom anchor, and there are **six** such sites:
   `1140, 1145, 1199, 1210, 2874, 3194`. `recent_lines_cards.more_cm_themed`
   (`view.bend:1180-1188`) stops as soon as its row fuel hits 0, so only
   ~`height` lines are consumed — but the O(scrollback) reverse already ran.
   `List.length(&2, Cl.Line, lines)` at `:3195` is another full walk.
   → Prefer a view-local reversed-tail cache invalidated on append.
   **Do not change `Cl.Buffer.raw_lines` order** — history save and replay read it.

5. **P2 — eager `Bool.pick` doing real work.** `view.bend:3236, 3270, 3062,
   3094, 2491, 2506, 2535, 2557, 3109, 3285` —
   `Bool.pick(String, legacy, preview_path_of(b), "")`. Every production entry
   passes `False{}` (`:3273, :3288, :3096`), yet `preview_path_of`
   (`view.bend:1811-1814`, a `String.eq` plus `Links.is_url_prefix` scan) is
   evaluated and discarded. Also `msg_prefix_w.parsed` (`view.bend:692-698`)
   eagerly builds `"<" ++ nick ++ "> "` and runs `Cols.text_width` even when the
   guard is false. This is exactly the pitfall AGENTS.md documents.
   → Replace with a parameter match on `legacy`.

6. **P2 — nothing measures keystroke→pixel latency.** The requirement
   "absolutely responsive at all times" is currently unfalsifiable.
   `BIRC_FRAME_PROFILE` reports only intra-frame phases;
   `tests/perf/cpu_pty.py` measures idle/flood CPU; `startup_profile.py`
   measures first paint.
   → New `tests/perf/key_latency.py`: a pty harness that writes a key and
   measures elapsed time to the byte sequence that changes the composer cell.
   Assert a budget (propose p95 < 16 ms). Use a deterministic progress
   condition, not a fixed sleep.

**Verification**
```sh
make test-columns-width test-wrap test-scroll test-scroll-edits test-ui
make test-ui-review-view test-ui-review-columns test-viewport-tail
make test-view-profile test-paint-slope test-perf-hardening test-theme-ws-render
make proof          # 535 laws; cluster-width parity at view_laws.bend:572-573
python3 tests/perf/key_latency.py ./build/birc   # record baseline AND after
```

**Constraints:** preserve TimUI common-cluster boundaries and widths (Bend
layout, native tabs, and FFI clipping must agree); never clamp live navigation by
logical line count or store width-dependent row offsets; `ScrollAt{after, tail}`
semantics unchanged; view wrapping still supplies both paint rows and navigation
bounds.

**Out of scope:** the ~50-def 4-axis clone collapse (`×media`/`×cards`/`×cm`/
`×themed`) — that is T4.3. Do not attempt it here.

---

## T1.2 Protocol leaf DRY

**Owns:** `src/bend/irc.bend`, `src/bend/isupport.bend`, `src/bend/base64.bend`,
`src/bend/endpoint.bend`

**API freeze:** `Isupport.feed_state`, `Irc.*`, `Base64.*` signatures unchanged.
`session.bend`, `client.bend`, and `submit.bend` all call these.

1. **P2 — a full client fold computed and thrown away per wire line.**
   `isupport.bend:687-693`: every branch of `feed.gated` and `feed_parsed`
   returns `(…, Feed.feed(cl, line))`. `feed_state` (`:705-706`) then calls
   `feed_state.pair`, which discards the client. The sole production caller is
   `session.bend:4180` `+iso2 = Isupport.feed_state(iso, cl, line)` — it takes
   only the `State`. `Feed.feed` (`client.bend:1315`) re-runs `Irc.parse`
   (already parsed at `isupport.bend:694`) plus `Cl.stamp_logs`, which folds all
   buffers × all lines (cap 16 × 1024, `buffer.bend:98,105`).
   → Make the internal helpers return `State` only. They read just
   `Cl.nick_of`/`Cl.server_of` (`isupport.bend:681,694`) — pass those two
   Strings. **Keep `feed_state`'s external signature**; `LAWS.bend:1303,1306,1324`
   depend on it.

2. **P4 — `decimal` defined four times.** `endpoint.bend:36`,
   `isupport.bend:217`, `utc_time.bend:39`, `preferences.bend:128`. You own the
   first two; hoist to `endpoint.bend` (a 110-line leaf) and import.
   *Report the other two as out-of-set blockers.*

3. **P4 — two casemap ladders.** `irc.bend:125-153` `rfc1459_code.{tilde,rb,bs,lb}`
   vs `:178-193` `strict_code.{rb,bs,lb}` — identical except the `^`/`~` pair.
   → Parameterise one ladder with a `tilde: Bool`.

4. **P4 — two identical CPS sanitize loops.** `irc.bend:~475` `sanitize_in_go`
   (`SanPh`) vs `:680` `sanitize_keep_style_go` (`KeepPh`) differ only in the
   keep predicate (`is_c0_drop` vs `is_c0_drop && !is_style_keep`). A third copy
   is `irc_commands.bend:~170` `strip_format.go` *(out of set — report it)*.
   → One loop plus a `Char -> Bool` argument; removes ~25 lines and one phase type.

5. **P4 — `base64.bend:101-104`** passes a *recursive call* as a `Bool.pick`
   alternative. It terminates (fuel decreases) but eagerly evaluates both arms,
   contrary to the documented pitfall. → Convert to a parameter match.

6. **P4 — `irc.bend:1339 format_authenticate` is dead** while
   `base64.bend:99,101,103,104,109` inlines `"AUTHENTICATE "` /
   `"AUTHENTICATE +"` five times. → Route `base64.authenticate_chunks` through
   it, or delete it.

7. **P4 — dead defs.** `isupport.bend:1208 modes_per_line` has zero references
   (its `dflt_mpl`/`MAXMODES` parse at `:134,:376` is retained but unread).
   → Verify with `grep -rn '\bNAME\b' src tests LAWS.bend PROOF.bend Makefile`
   before deleting.

8. **P4 — five ISUPPORT defaults duplicated.** `buffer.bend:14-27` and
   `isupport.bend:116-175` both define `dflt_types()="#&+!"`, `dflt_status()="=@"`,
   `dflt_sigils()="=@"`, `dflt_cm()`/`dflt_casemap()="rfc1459"`;
   `buffer.bend:23 dflt_strip()="@+~&%"` vs `isupport.bend:146-149`
   `dflt_sigils()++dflt_extra()`. You own `isupport.bend` — make it the single
   owner and keep the literals byte-identical so `buffer.bend` can import later.
   *Report `buffer.bend` as an out-of-set follow-up for T3.1.*

**Verification**
```sh
make test-proto test-irc-commands test-message-split test-base64
make test-utc-time test-server-time test-commands test-feed proto-parity
make proof
```

**Constraints:** `irc.bend:6 LINE_MAX()=510` and `frame.bend:11
LINE_OCTET_MAX()` are the single source for the 512-byte rule — **verified clean,
do not touch**. Preserve `+#room` unchanged in creation/membership/history.
SASL uses 400-character UTF-8 Base64 chunks. `Sub.slash_rows` order is the
completion catalog.

---

## T1.3 C deduplication and safety

**Owns:** `src/ffi/clock_ffi.c`, `src/ffi/birc_utf8_valid.h` *(new)*,
`src/ffi/auth_bridge_ffi.c`, `src/ffi/history_search_ffi.c`,
`src/bend/utc_time.bend`, `tests/clock_local.c`

**API freeze:** `utc_time.bend`'s public API unchanged. **Do not touch
`timui_ffi.c`, `birc_media.h`, `theme.bend`, or `view.bend`** — T2.3 owns the
DrawOp-contract work.

1. **P3 — calendar validation written twice.** `clock_ffi.c:29-35`
   `birc_month_days` plus the range block at `:44-52` are an exact restatement of
   `utc_time.bend:16-37` (`leap`, `month_days`, `valid`) — same leap rule
   (`year % 4 && (year % 100 != 0 || year % 400 == 0)`), same bounds
   (1..9999, 1..12, `<24`, `<60`, `<=60`), same leap-second-only-at-23:59-on-
   month-end rule. `utc_time.bend:3` already claims *"Calendar conversion belongs
   to libc … this module only validates"* — then C validates again. The
   production caller (`clock.bend:70 local_stamp`) only reaches the effect with a
   `Utc.Valid`, so the C block is redundant there.
   → Delete `birc_month_days` and `:44-52`; keep `timegm`/`localtime_r` and the
   `tm` round-trip check. `utc_time.bend:valid` becomes the single gate.
   **Verify no caller passes an unvalidated `Utc` before deleting.**

2. **P3 — two independent strict UTF-8 validators.**
   `auth_bridge_ffi.c:42` `birc_auth_utf8` and `history_search_ffi.c:113`
   `birc_history_search_utf8_ok` both check lead ranges, continuation bytes,
   overlongs and surrogates, with different code and different edge handling
   (the former also rejects NUL/CR/LF). `birc_utf8_fit.h` is a third, weaker
   variant that **is** correctly shared (`timui_ffi.c:144`,
   `tests/utf8_fit_cap.c:10`) — leave it alone.
   → New `src/ffi/birc_utf8_valid.h` beside `birc_utf8_fit.h`; both callers
   include it. CR/LF/NUL rejection stays in `auth_bridge_ffi.c` as a caller-side
   policy. **Must keep failing closed.**

3. **P3 — undocumented test seams in production C.**
   `timui_ffi.c:577-578` `if (getenv("BIRC_DIE_AFTER_OPEN")) exit(1);` and
   `:564-566` `BIRC_FORCE_IMAGE_PROTOCOL`; `dns_ffi.c:175,183`
   `BIRC_DIAL_TRACE`/`BIRC_DIAL_TRACE_FD`; `clock_ffi.c:189` `BIRC_NET_TRACE`.
   AGENTS.md documents only `BIRC_FRAME_PROFILE`. You own `clock_ffi.c` — add a
   header comment naming `BIRC_NET_TRACE` and its default-off status.
   *Report the `timui_ffi.c` and `dns_ffi.c` seams as out-of-set blockers.*

**Verification**
```sh
make lint-ffi                     # must now include clock/history_search
make test-clock-local test-clock-local-native test-clock-local-native-ubsan
make test-utc-time test-sanitizers
make test-history-search test-utf8-fit
make test-auth-bridge 2>/dev/null || make test-tls-native
```

**Constraints:** never hand-roll cryptography; never disable certificate
verification. Helper diagnostics carry only safe stage labels and numeric codes —
never log child output. Never list global process command lines.

---

## T1.4 Python helper DRY

**Owns:** `src/media/image.py`, `src/media/cards.py`, `src/media/_cache.py` *(new)*,
`src/launcher/preferences_birc.py`, `src/launcher/keychain_birc.py`,
`src/launcher/search_probe_birc.py`, `nix/media.nix`, `nix/preferences.nix`

**Context that changes the approach:** `cards.py` is *not* an independent copy —
`cards.py:31-34` already loads `image.py` via
`importlib.util.spec_from_file_location("birc_image", Path(__file__).with_name("image.py"))`
and delegates `url_parts`, `public_address`, `cache_owned`, `cache_identity`,
`cache_directory`, `PinnedHTTP`, `MAX_CACHE_*`. **A `__file__`-relative shared
module is an already-shipping, proven pattern here.**

1. **P4 — the security-critical cache writer is maintained twice.**
   `image.py:235-333` `cache_write` (99 lines) vs `cards.py:264-379` (116 lines).
   Differences are only `cache_owned`→`image.cache_owned`, `other_count`→
   `img_count`, `data`→`stored`, the message string, `.img`(`:68`)→`.card`(`:69`),
   and one extra `parent` fd in the close list. Identical inner blocks:
   flock acquisition (`image.py:246-250` ≡ `cards.py:298-303` ≡
   `preferences_birc.py:270-275` — **3×**); staging write loop
   (`image.py:303-308` ≡ `cards.py:349-354` ≡ `preferences_birc.py:293-298`);
   identity-recheck-then-`os.replace` (`image.py:311-319` ≡ `cards.py:357-365` ≡
   `preferences_birc.py:303-311`); staging-name predicate verbatim **4×**
   (`image.py:176`, `image.py:278`, `cards.py:247`, `cards.py:324`).
   Also duplicated: `cache_read` (`image.py:199-234` ≡ `cards.py:194-231`),
   `fetch` (`image.py:377-426` ≡ `cards.py:77-132`), `read_local`
   (`image.py:506-525` ≡ `cards.py:453-472`), `encode_remote`
   (`image.py:334-347` ≡ `cards.py:438-452`), `destination` (`image.py:87-94` ≡
   `cards.py:68-76`), `cache_name` (`image.py:144-149` ≡ `cards.py:172-176`),
   and mirror-image usage scans (`image.py:150 cards_usage` ↔
   `cards.py:232 image_usage` — each helper walks the *other's* cache directory).
   → Extract `src/media/_cache.py`: `staging_name()`, `payload_name(suffix,width)`,
   `usage_scan(dirfd, suffix, width)`, `acquire_lock(dirfd)`,
   `write_staged(dirfd, name, data)`, `read_bounded(dirfd, name, limit)`,
   `bounded_fetch(...)`. Keeps the two cache namespaces separate.
   **Target ~330-380 lines removed** (image.py + cards.py 1041 → ~680).
   **Critical invariant:** "never clean up a staging file whose exclusive
   creation failed" — that is `temporary = None` assigned only *after*
   `os.replace` (`image.py:320`, `cards.py:366`). It must appear exactly once in
   the shared implementation.

2. **P4 — bounded checked regular-file open, 6 copies.** `image.py:507`,
   `cards.py:454`, `upload.py:59` *(out of set — report)*,
   `preferences_birc.py:206`, `keychain_birc.py:123`, `search_probe_birc.py:52`.
   Same shape: `os.open(O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC)` → `fstat` →
   `S_ISREG` + size bound.
   → One `open_regular(path, limit, *, nofollow=True)`; removes ~60 lines.

3. **P0-adjacent — resolve the private-directory mask divergence before
   extracting.** This is a *decision*, not a mechanical merge:
   - `image.py:123` (image cache dir) → `0o077` — requires 0700
   - `image.py:166`, `cards.py:145` (cards subdir) → `0o077`
   - `keychain_birc.py:205` (profile dir) → `0o077`
   - **`preferences_birc.py:175` → `forbidden = 0o022 if directory else 0o077`**
     — the preferences *directory* may be group/other **readable and
     traversable**; only write is refused.
   - `keychain_birc.py:127` (profile *file*) → `0o022`, consistent with
     AGENTS.md calling these "nonsecret TOML profiles".
   A naive shared `owned()` would silently tighten or loosen one caller.
   → Decide and document the policy per path class, then encode it as an
   explicit parameter (`dir_mask=`), not a default. **If you cannot determine
   intent, keep both behaviours exactly and report the divergence.**

4. **P4 — helper epilogue, 3 copies, 2 styles.**
   `signal.signal(SIGALRM, SIG_DFL); signal.alarm(TIMEOUT)` verbatim at
   `image.py:529-530`, `cards.py:476-477`, `upload.py:182-183`. Two incompatible
   styles: try/except + `sys.exit(code)` (image/cards/upload) vs
   `raise SystemExit(main(sys.argv))` (`notify.py:71`, `search_probe_birc.py:171`).
   → Fold into the shared module opportunistically; pick one style.

5. **P3 — cross-language constant drift.** `keychain_birc.py:92` hardcodes
   `6697 if tls else 6667` and `:89-90` re-implements conflicting-port
   rejection. That is exactly `src/bend/transport_policy.bend:8-15`
   (`TLS_PORT()=6697`, `PLAIN_PORT()=6667`, `default_port`) plus `endpoint.bend`.
   Python cannot call Bend, so **do not move the code** — add a parity golden
   that emits the Bend constants and asserts `keychain_birc.profile_endpoint`
   agrees. Today the two are bound only by *independent* assertions
   (`tests/keychain_tls.py:81,83,98,153,168` pin the same literals with nothing
   tying them together).

6. **P4 — `search_probe_birc.py` is the model to hold up.** 171 lines; its
   docstring at `:6` says *"Bend owns admission; this helper only reports OS
   evidence"* — zero policy. Push the other six toward this shape.
   → **Do NOT move into Bend:** cache FIFO/flock/`fchmod`/`dir_fd` (fd-level, no
   Bend equivalent), Pillow decode/normalize (`image.py:434-504`, legitimately
   native), HTML parsing (`cards.py:380-437` — Bend has no regex, and returning
   up to `MAX_HTML = 256 KiB` through the `Process.run` UTF-8 channel to re-parse
   in Bend is strictly worse), URL hashing (`image.py:144`, inseparable from
   cache ownership).
   → **Correctly duplicated, leave alone:** `keychain_birc.py:180-186` NickServ
   prefix validation, whose own comment says it refuses *before* Keychain lookup
   or a password prompt.

**Verification**
```sh
make test-media-image test-media-image-cache test-media-image-bounds
make test-media-cards test-preferences-helper test-preferences-package
make test-keychain-wrapper test-keychain-channels test-keychain-tls
python3 tests/media_cards.py && python3 tests/media_image.py
```

**Constraints:** `0600` files; refuse symlinked paths, unsafe ownership,
nonregular files, nonprivate directories; never change the global umask; never
change unrelated directory permissions. `nix/birc.nix:16-24` `cleanSourceWith`
already includes all of `src/`, so a new `src/media/_cache.py` ships
automatically; `sys.path[0]` is the script dir, so plain `import _cache` works
for `src/media/`, while `src/launcher/` needs the `importlib` pattern.

---

## T1.5 IO layer deduplication

**Owns:** `src/bend/net.bend`, `src/bend/live_context.bend`,
`src/bend/startup_headless.bend`, `src/bend/helper_io.bend` *(new)*,
`src/bend/dns_query.bend`, `src/bend/notify_io.bend`,
`src/bend/preferences_io.bend`, `src/bend/upload_io.bend`,
`src/bend/history_search_io.bend`

**Do not touch:** `session.bend`, `actor.bend`, `outbound.bend`, `history.bend`,
`wsnet.bend` (T2.4), `media.bend`/`cards.bend`.

1. **P0 — the endpoint-scope key is defined three times.**
   `net.bend:62` `endpoint(host,port) = host ++ ":" ++ U32.show(port)`;
   `live_context.bend:40-41` `endpoint(st) = Cl.server_of(...) ++ ":" ++
   U32.show(S.session_port(st))`; `startup_headless.bend:18-19` byte-identical to
   the latter. This string scopes **history records and credentials**, where
   AGENTS.md requires exact host spelling and terminal DNS root dots.
   → One owner in the already-proof-facing `endpoint.bend` (110 lines); all three
   call it. *`endpoint.bend` is T1.2's file — coordinate: T1.2 must land the
   new `endpoint` def with an unchanged public API, or report it as a blocker and
   keep one local definition with a `# MUST MATCH endpoint.bend` comment.*
   Also duplicated verbatim between the same two files: `now(cl)`
   (`live_context.bend:36` / `startup_headless.bend:21`) and `explicit_history(st)`
   (`live_context.bend:53` / `startup_headless.bend:15`).

2. **P4 — five dead shims.** `net.bend:35-60` defines nine `net_notify_*`
   forwarders to `Sess.notify_live_*`. Verified exactly one occurrence repo-wide
   (their own `def`) for: `net_notify_cancel`, `net_notify_reset_endpoint`,
   `net_notify_off`, `net_notify_merge_claims`, `net_notify_seed_accepted`.
   The other four (`_init`, `_observe`, `_complete`, `_seed_postrestore`) are live.
   → Delete the five dead ones. Then repoint `tests/bend/notify_full.bend:19`
   (`import ../../src/bend/net.bend as Net`) at `Sess.notify_live_*` and drop the
   import — today it drags 1,987 IO lines plus 8 `@unsafe` into a pure
   notification-policy test binary. **The test's assertions must survive
   unchanged.**

3. **P4 — six copies of the helper-process contract.** Same shape repeated:
   `IO.get_env("BIRC_*_HELPER")` → default name →
   `Process.run(helper, args, stdin, out_cap, deadline_ms)` → exit-code-to-safe-
   numeric mapping. Sites: `preferences_io.bend:13,39,58`; `notify_io.bend:30,95`;
   `upload_io.bend:12,69`; `history_search_io.bend:23,120`; `net.bend:1026,1185`.
   The fail-closed spawn idiom `Bool.pick(U32, U32.is_zero(code), 1, code)`
   appears verbatim **3×**: `preferences_io.bend:33`, `:49`, `upload_io.bend:45`.
   → New IO-only `helper_io.bend` with
   `type Spec{env_var, default_name, out_cap, deadline_ms}` and
   `run(spec, args, stdin)`. **Because it is IO it is free to the proof set** —
   no proof module can import it, so extraction costs zero proof time.
   **Carry every tuned bound per-spec; change no number:** notify 512/2000,
   prefs 4096/5000, upload 2048/35000, search 30000, media 2800000/11000.
   **Keep `Bool.pick(U32, U32.is_zero(code), 1, code)` semantics** — it prevents
   a failed spawn reporting exit 0 from reading as helper success.

4. **P4 — `dns_query.bend` is 112 lines of boolean fan-out.** All eight
   functions are `match aaaa: True → V6.x, False → Wire.x` (`:14-27, :29-40,
   :42-52, :58-71, :73-88`). Pure, not proof-facing. Its header gives a real
   reason to exist — *"the JS backend pins this admission without sockets"* —
   but the A/AAAA fan-out belongs in `dns_wire.bend`, the single proven wire
   owner. **The layering is otherwise right**: `dns_wire` = proven codec,
   `dns.bend` = UDP/TCP + deadlines + 8 FFI, `dns_query` = thin dispatch. This is
   *not* three modules doing one job.
   → Move the fan-out; keep only `first_of`/`should_fallback`/`peer_ok_at`, or
   add laws for them.

5. **P4 — inconsistent completion stamping.** All one-shot workers share one
   4-step shape (check stamp → `IO.spawn` → bounded `Process.run`/file read →
   post one `UiMsg`), but the stamp discipline varies (`session.bend:410-427`):
   `MediaFetched{generation: Nat, ticket: Nat}`, `SearchDone{ticket: Nat,
   gen: Nat, wgen: U32}`, `HistoryLoaded{ticket: Nat, gen: U32}`,
   `NotifyDone{ticket: Nat, endpoint: String}` (no gen), and
   **`UploadFetched{request, result, error, http_status}` — no ticket, no gen at
   all.** `gen` is `U32` in three variants and `Nat` in two.
   → Those variants live in `session.bend`, which you do not own.
   **Report the exact required shape as an out-of-set blocker for T4.1**, and
   make your IO side tolerant of both. Note `NotifyDone`'s endpoint-only match is
   *deliberate* (`notify_io.bend:172`) — making it a gen match would misattribute
   late completions.

**Verification**
```sh
make test-net test-actor test-actor-queue test-dns test-dns-tcp test-dns-timeout
make test-socket-deadline test-reader-errors test-reader-pongs
make test-live-context test-live-context-io test-startup-headless test-startup-headless-io
make test-preferences-io test-notify-full-witness test-upload-io test-history-search
make test-shutdown-ack test-shutdown-flush test-deferred-actor
make proof
```

**Constraints — LOAD-BEARING, DO NOT SIMPLIFY:**
- `outbound.bend` (138 lines, 0 IO, proof-pinned) owns `SEND_CAP`, `Budget`,
  `Batch`, and pong txn/generation arithmetic. **Keep proof-facing queue rules
  there, never in the actor module.** Importing the actor into `LAWS.bend` brings
  foreign/unsafe deps and the checker rejects the proof set.
- `actor.bend`'s CPS writer (`writer_batch` 12 params, `writer_admit_decide` 16
  including two higher-order functions) is *how* the affine `Tr.Conn` stays owned
  without a `Chan(Conn)`. **Never refactor it into a channel.**
- `history_search_io.bend`'s dual backend and two caps (`SCAN_OUTPUT_CAP:30`,
  `SCAN_NATIVE_CAP:33`, dispatch at `net.bend:261-262`) are deliberate.
- `upload_io.bend:20-38` exact-envelope `http_status` admission
  (`HTTP_PREFIX()` + exactly 3 digits + full-stderr equality) is narrow on
  purpose; widening leaks child output into a numeric channel.
- `notify_io.bend`'s **5** spawn sites (`:146, :185, :210, :239, :243`) are
  distinct: `run_jobs_done` posts the `NotifyDone` ticket/endpoint ack, `run_jobs`
  does not. Collapsing them loses the completion and stalls the UI.
- `history_startup_io.bend` (27 lines) is the ideal seam — do not inline it.
- The 13 `.details` box-unwrap pairs in `live_context.bend` exist for the
  247-word capture cap (`live_context.bend:3`). Removing them breaks compilation.
- The pinned IO loop detaches parked work into a local `todo`; an owned buffered
  reader there must become due without a duplicate queue insertion.
- Only the **current generation's** `WriterDone` acknowledges shutdown.

---

# WAVE 2 — Feature-layer deduplication

## T2.1 Slash-command dispatch and submit dedup

**Owns:** `src/bend/submit.bend`, `src/bend/session.bend` *(slash-dispatch regions only)*

1. **P4 — 70 lines duplicated, exactly 4 differ.** `submit.bend:1963-2032`
   (`submit_cmd.do`) vs `:2034-2103` (`submit_cmd_with.do`): the diff is the
   signature plus three arms (`Msg`, `QueryCmd`, `NoticeCmd` → `_with(iso,…)`).
   66 lines are byte-identical. Every new command is added twice.
   → One `submit_cmd.do` taking `Maybe<Is.State>` (or `iso` defaulted to
   `Isupport.defaults()`), with the three iso-sensitive arms branching internally.

2. **P4 — adding a command is a 4–6 place change (OCP violated).** Catalog:
   `submit.bend:1471-1516`, **42–44 `SlashRow` entries**, order = completion
   order. Lookup `:1518-1525` uses
   `Bool.pick(Slash, Irc.ieq(name, verb), c, slash_lookup(t, verb))` — and
   because `Bool.pick` evaluates **both** arms, this never short-circuits: it
   rebuilds the ~42-node list and does ~42 case-insensitive compares on **every**
   parse. Session-owned verbs are not in the `Slash` type at all; they are
   catalog rows tagged `Unknown{}` (`:1488,1489,1493,1498-1502`) and re-identified
   by **string compare** in `session.bend` at 12 sites for 3 verbs
   (`Irc.ieq(verb,"connect")`, `"reconnect"`, `"history"` —
   `session.bend:668,692,700,717,729,737,3936`). Split verbs live in a *third*
   place: `split.bend:337-350`.
   → Single catalog as the one source of truth; make session verbs first-class
   `Slash` constructors; hoist the fold out of the scan.
   **Preserve `Sub.slash_rows` order exactly — it is the completion catalog,
   including Session-owned aliases in their established order.**

3. **P2/P4 — `Sub.parse_input` runs 7× on one Enter.**
   `session.bend:4089` (`upload_input`), `3941` (`history_typed`), `3689`
   (`media_intent`), `3707` (`theme_session`), `3787` (`preference_enter`),
   `3435` (`session_submit_target`), `759` (`submit_pair_with_echo`), plus `3745`
   offline. Each parse calls `slash_of` → rebuilds the catalog → ~42
   non-short-circuiting `Irc.ieq`. ≈290 allocations and ≈290 case-insensitive
   compares **per Enter keystroke**.
   → Parse once; thread `Sub.Input` through the `step_keys.normal` hook chain
   (`session.bend:3951`).

4. **P4 — the `echo`×`iso` variant explosion.** `session.bend` has 6 `_with_echo`
   + 19 `_with` + 13 `_echo` = **38**; `submit.bend` 5+5+13 = **23**. Most are
   one-line delegations (`session.bend:2885-2886`:
   `submit_or_split(…) = submit_or_split_echo(…, False{})`). `submit_or_split`
   alone is **12 defs / 121 lines** (`:2828-2949`) for one function of two
   booleans.
   → Introduce `SubmitCtx{iso: Isupport.State, echo_ok: Bool}`; collapse
   ~61 wrappers, starting with `submit_or_split` (12 defs → 3), then
   `apply_keys`/`submit_pair`/`submit_input`.

5. **P4 — three identical predicates.** `session.bend:3542-3544 media_job_net`,
   `session.bend:3614-3616 cards_job_net`, `session_cards.bend:102-105 job_net`
   are the same `match net: case Stopping{}: False{}; case _: True{}`.
   Also `session.bend:3509-3513 visible_media_net` ≡ `session_cards.bend:96-100
   schedule_net`, and `session.bend:3609-3612 session_accept_card_result` ≡
   `session_cards.bend:176-178 accept_result`.
   → You own the `session.bend` copies. Deduplicate within your file;
   *report the `session_cards.bend` side to T2.2.*
   ⚠️ **Suspected divergence, do not silently unify:**
   `session_cards_job_allowed` (`session.bend:3619-3625`) gates on
   `C.is_open(fullscreen)`; `job_allowed` (`session_cards.bend:154-156`) does
   **not**. Same name, different policy. May be intentional (text cards need no
   display gate, `session_cards.bend:20-22`). **Report it; do not guess.**

6. **P4 — 17 dead defs (85 lines)** in `session.bend`, verified zero references
   in `src/`, `tests/`, `LAWS.bend`, `PROOF.bend`, `Makefile`:
   `fold_lines_typing`(229), `push_pure_typing_join`(312), `push_pure_pair`(330),
   `push_pure`(349), `submit_pair_with`(761), `submit_pair_hist`(774),
   `apply_keys_hist`(777), `apply_keys_with`(783), `keys_hot`(1145),
   `session_mode_class`(1554), `session_takes_arg`(1558), `session_redact_line`(1562),
   `session_hist_batch`(1762), `session_nick`(2424), `online_media`(3555),
   `notify_seed`(4734), `notify_collect_claimed`(4829).
   Note `session.bend:771` labels `:761-785` *"Compat aliases over the live
   path"* — four of them are dead.
   ⚠️ **`apply_keys_with_echo` is LIVE** (used at `:2900`) — do not remove.
   ⚠️ Do not touch any `*_ok` predicate referenced from `LAWS.bend`.

**Verification**
```sh
make test-submit test-commands test-irc-commands test-message-split
make test-split test-split-rename test-action-budget test-diagnostic-submit
make test-state test-state-review test-echo-message test-mute-scope
make test-upload-session test-session-preferences-intent
make proof
```

**Constraints:** upload consent stays a later physical **F8**, never Enter or
pasted text; a new request must cross a completed warning frame before F8 can
authorize it. Never replace a draft with a warning. Target predicates stay
shared with submission. `+#room` preserved. Preserve the `NOTICE *` broadcast
exception. Space-scan wrapper remainder policies stay distinct (protocol keeps
separators, verb drops one, word drops all).

---

## T2.2 Cards / drafts adapter removal

**Owns:** `src/bend/cards.bend`, `src/bend/session_cards.bend`,
`src/bend/cards_net.bend`, `src/bend/cards_view.bend`,
`src/bend/session_drafts.bend`, `src/bend/drafts.bend`,
`tests/bend/session_cards_demo.bend`, `tests/bend/cards_live.bend`

**Do not touch `session.bend`** (T2.1 owns it this wave).

**Context:** these files carry merge-scar banners — `session_cards.bend:4`
*"ADAPTER BOUNDARY (branch c8/session-adapter, from parent HEAD 910f622)"*,
`session_drafts.bend:4` (branch `adapter/session-workspace-drafts-multiserver`),
`cards_view.bend:4`, `cards_net.bend:7`, `workspace.bend:4`. They were written by
parallel agents against a frozen parent, then merged. Much of the layering below
is that residue, not design.

1. **P4 — `session_cards.bend` (265 lines) is vestigial.** `session.bend` has
   native cards state and API: `session_full:3500`, `session_cards:3571`,
   `session_set_cards:3575`, `session_observe_visible_cards:3598`,
   `session_accept_card_result:3609`, `session_cards_job_allowed:3624`,
   `session_fullscreen_key:3651`. Production (`net.bend:1102,1174,1176`) uses the
   **Session-native** variants `CN.cards_stage_session` / `CN.on_card_session`.
   The `AD` wrapper path — `CN.cards_stage` (`cards_net.bend:97`) and `CN.on_card`
   (`:110`) — has **no production caller**; its only callers are
   `tests/bend/session_cards_demo.bend:290,292`. `cards_net.bend:20` admits it:
   *"The SC.AD variants stay as the law/test adapter surface."*
   Of ~40 `session_cards.bend` defs, production uses **5**, all inside the dead
   AD path. Its header also flags stranded work: *"Out of scope … the explicit
   fullscreen open/close key or click binding (`open_full` and `close_full` are
   pure and ready)"* (`:37-39`) — the integrator shipped `session_fullscreen_key`
   natively instead, so `open_full`/`close_full` are stranded.
   → Delete `session_cards.bend`, `CN.cards_stage`, `CN.on_card`, and
   `cards_view.bend` (30 lines, two one-line forwarders — inline into
   `net.bend:172` *via an out-of-set blocker report*).
   ⚠️ **`session_cards_demo` IS in `make check`, so those laws are live gates.**
   Deleting them removes coverage. **Re-express each removed law on the
   Session-native path first; never drop an assertion.** ~30 of the 52 `cards_*`
   laws in `LAWS.bend` are `cards_adapter_*`/`cards_live_*` covering the dead path
   (`LAWS.bend:1752-1782` vs `:1806-1835` prove the same four properties through
   two seams).

2. **P4 — `cards.bend` has three pane-walk cascades; production uses one.**
   plain `visible_*` (`:528-603`, used only by the dead AD path),
   `visible_*_cards_cm` (`:614-652`, **the production one** —
   `session.bend:3586`, `wsnet.bend:1165`), and `visible_*_cards` (`:657-672`,
   used only by orphan `cards_live.bend`). Plus `cards.bend:184 ready_url` has
   zero references.
   → Delete the two unused cascades and `ready_url`.

3. **P4 — a second card-row renderer.** `cards.bend:487-503
   rows_for_texts/rows_for/rows_for_target` survives only via
   `cards_view.card_rows` (dead) and `cards_empty_rows.bend`. The real painter is
   `view.bend:851-868 card_rows_for_*` (`view.bend:848` comments *"Cards.rows_for
   (System styling, no timestamp, per-card row cap)"*). Production feeds
   `C.paint_entries` into `V.view_draft.state_typing_media_cards_cm_themed`
   (`net.bend:198`).
   → Delete the `cards.bend` renderer; keep `view.bend`'s.

4. **P4 — `session_drafts.bend` (736 lines): production uses 6 symbols**
   (`active_key`×4, `typing_keys`×3, `with_drafts`, `ad_session`, `ad_drafts`);
   tests use ~20 more (`AD.do_enter` 39×, `AD.step_cmd` 34×, `AD.do_step` 27×).
   → Shrink to the 6 used symbols plus whatever `workspace.bend:536` needs
   (`AD.step_keys`, `AD.with_drafts`, `AD.ad_session`, `AD.ad_drafts`).
   *Report `workspace.bend` needs as an out-of-set blocker for T2.4.*

5. **P4 — dead defs.** `session_cards.bend:78 ad_enabled`, `:74 ad_media`,
   `:213 lift`; `session_drafts.bend ad_server`; `drafts.bend:468 rename_nicks`.
   `drafts.bend` maintains a full plain/`_cm` dual API; the plain halves of
   `find_entry`, `set_ok`, `rename`, `rename_nick`, `rename_nicks` have **zero**
   callers, and `focus_admits`, `after_submit`, `stash_modal` are `_cm`-only in
   production.

6. **Naming (report, do not rename unilaterally):** the alias `AD` and type `AD`
   are meaningless. Separately there is an **active collision**: `Ws` means
   `wire_style.bend` in six production modules (`cards.bend:7`, `client.bend:7`,
   `media.bend:5`, `submit.bend:7`, `view.bend:7`, `view_laws.bend:8`) while
   `WsNet`/`ws_*` means *workspace* in `wsnet.bend`.
   `tests/bend/theme_ws_render.bend` is about **wire style**, not workspace.
   → Record both in your report for the wave-5 integration pass.

**Verification**
```sh
make test-cards-policy test-cards-view test-cards-live test-session-cards
make test-media-cards test-drafts test-session-drafts test-draft-nick-rename
make test-cards-empty-rows test-media-history
make proof      # 81 of 535 laws are cards_*/draft_*/workspace_*
```

**Constraints:** production View uploads only accepted nonzero `OpMedia` tokens;
pending/failed intents draw placeholders, never a raw-file fallback. Legacy
`OpImage` adapters are for characterization/law tests only. Images use one
bounded helper worker, eight pending requests, eight cached results. The
fullscreen overlay must keep re-validating the stored token against live
Media/Client on **every** paint (`cards_view.bend:9-14`) — do not lose that when
collapsing paths. Cards deliberately have **no** terminal-support gate
(`session_cards.bend:21`) — do not add one.

---

## T2.3 C→Bend boundary, phase 2

**Owns:** `src/ffi/timui_ffi.c`, `src/ffi/birc_media.h`, `src/bend/timui.bend`,
`src/bend/theme.bend`, `src/bend/media.bend`

**Do not touch:** `view.bend`, `columns.bend` (T1.1, merged), `clock_ffi.c`,
`auth_bridge_ffi.c`, `history_search_ffi.c` (T1.3, merged), `net.bend` (T2.4).

1. **P3 — theme colours live in C.** `timui_ffi.c:717`:
   ```c
   style = timui_style_make(0x1E1E2Eu, 0xFFD700u, TIMUI_ATTR_BOLD);
   ```
   `FFD700` appears **nowhere** in `src/bend`, and `theme.bend` has **no** gold,
   mention, or alert colour at all. `theme.bend:5` declares *"RGB U32, 0xRRGGBB"*
   with Dark/Light/Mono. So **Light and Mono themes cannot affect tab alerts** —
   the theming hook does not exist.
   → Add the colours to `theme.bend` and carry them on `OpTabs`, which already
   carries Bend-owned alert levels plus `bell`/`bell_seq` (`view.bend:102`).
   C reads them instead of hardcoding.
   ⚠️ `OpTabs` is declared in `view.bend`, which you do not own. **Changing its
   constructor is an out-of-set change — report it and coordinate with the
   integration pass, or add the colours via a separate new field on an op you do
   own.** Do not edit `view.bend`.

2. **P3 — layout policy in C.** `timui_ffi.c:1330-1344` chooses the composer
   pane by geometry (`in_bottom > cur_bottom || (== && in.x < cur.x)`) and `:794`
   *infers* pane roles from `if (ly->bu->body_count == 0 && r.x == 0)` → chat
   body, else nick list. `view.bend:1638` keeps a mirror whose agreement is
   hand-reasoned: *"The ordering mirrors C's (in.y+in.h, in.x) up to constant +1
   offsets."* Bend already computes `split_composer_rect` and already passes
   `compose_x` (`timui.bend:64`).
   → Delete the chooser loop and the `x == 0` role inference; replace with an
   explicit role field carried on the frame/`OpSplit`. C keeps pane capture only
   for mouse hit-testing.
   ⚠️ **Risk: split-mode typing must stay live at every size** —
   `BACKLOG.md:61-64` records a prior regression here.

3. **P3 — base64 and envelope parsing in C.** `birc_media.h:96-140`
   `birc_media_add` is a complete base64 decoder with padding-bit checks;
   `:34-94` `birc_media_parse` validates the private `BIRCIMG1` envelope (magic,
   w/h ≤ 320, `pixels*count ≤ 1536000`, rgba/gif lengths, GIF87a/89a magic plus
   trailer `0x3b`, per-frame duration 20..10000). `base64.bend` already exists.
   Only the `image_png_header_` call (`:88`) is genuinely native.
   → Move header-field validation and envelope framing to `media.bend`, which
   already owns request identity and worker bounds; C keeps
   `Timui.media_add(ui, bytes, len)` that only re-checks the PNG header and stores.
   ⚠️ **Measure before landing** — a 2 MiB decode in Bend may be slower than the
   C loop. Report both numbers.

4. **P3 — per-paint no-op dispatch.** `net.bend:197` issues `Timui.view_begin`
   on every paint; `timui_ffi.c:309-310` returns `f[0]` untouched unless
   `BIRC_FRAME_PROFILE=1` (default off). **It is not redundant with `profile_t0`
   (`timui_ffi.c:1229`)** — it marks the start of Bend's pure-View phase and
   frame entry marks its end, so the seam is real.
   → Gate the *call site* on a session flag so the crossing is only paid when
   profiling. The call site is in `net.bend`, which you do not own —
   **report as an out-of-set blocker**; on the C side, keep the seam.

5. **P3 — external-helper selection policy in C.**
   `Sys.open_program` (`:1686`), `Sys.clipboard_program` (`:1725`),
   `Sys.notify_default` (`:1711`) are `#ifdef __APPLE__` constant strings —
   policy belonging to `notify_io.bend`/`net.bend`. `Sys.media_program` (`:1700`)
   is `getenv` only and correctly native.
   → Collapse the three constant ones into one `Sys.platform() -> U32` and let
   Bend own the program names. *Report the Bend-side call-site changes as
   out-of-set blockers.*

6. **P3 — constants defined on both sides with no single source of truth.**
   Document each in a header comment and report the pairs:
   recv clamp (`dns_ffi.c:52` `65536u`, `tls_ffi.c:47` `bytes[65536]` vs
   `actor.bend:264`); history scan 8 MiB (`history_search_ffi.c:30` vs
   `history_search_io.bend:34`); TLS setup 5s (`tls_ffi.c` reads `f[2]` vs an
   **unnamed literal** `5000` at `transport.bend:22`); buffer/tab slots 16
   (`timui_ffi.c:701,841,843` — `spans[16]`, `store[16][64]`, `alerts[16]`, with
   **silent truncation** in `birc_str_list` — vs `drafts.bend:48` `16n`);
   composer 512 (`timui_ffi.c:116` vs `drafts.bend:51`); media caps
   (`birc_media.h:8` CAP 8 / FRAME_CAP 24 / LIMIT 2 MiB vs `media.bend` 8 pending
   / 8 cached). OSC8 1024 is already single-sourced (`timui.h:843` →
   `timui_ffi.c:92 BIRC_URL_CAP`) — leave it.

7. **P3 — `docs/FFI.md:6` claims** *"A URL longer than 255 bytes is drawn as a
   plain span"*; `timui_ffi.c:625` declines at `ulen >= BIRC_URL_CAP` = 1025.
   T0.2 owns the doc — **report the correct number to it.**

**Verification**
```sh
make lint-ffi test-utf8-fit
make test-ui-review-native test-ui-review-widgets test-ui-review-output
make test-ui test-theme test-theme-selector-boundaries
make test-media-native test-media-policy test-media-view test-media-terminal
make test-m20-media test-pty-media test-pty-preview test-pty-split-composer
make proof
```

**Constraints:** C does not tokenize, classify, or wrap IRC. Bend owns frame
iteration (`Timui.frame` = one begin/draw/end); C has no outer frame while-loop
and no blocking input poll. Native cells store complete UTF-8 clusters in
buffer-owned arenas; bare cell copies must not transfer arena attachments. Bend
layout, native tabs, and FFI clipping must use the **same** TimUI common-cluster
boundaries and widths, not scalar sums. OSC8 targets are exact through 1024
bytes; decline larger. All terminal writes use the frame deadline. Clipboard
process work runs through Bend `Process.run` outside the frame, not synchronous
`popen` in C. Every paint applies the keys the frame read. Decode/ingestion does
not allocate terminal image IDs or write output.

---

## T2.4 Multiserver: signature bundling + first real coverage

**Owns:** `src/bend/wsnet.bend`, `src/bend/workspace.bend`,
`tests/pty/server_multiserver.py` *(new)*, `tests/bend/wsnet_gates.bend`

**Do not touch:** `net.bend` (T1.5, merged), `session.bend` (T2.1),
`cards*.bend`/`drafts*.bend` (T2.2).

**Context:** `workspace.bend` + `wsnet.bend` are **multi-server support** —
`Workspace` is a list of at most `Key.MAX_SERVERS()` (4)
`Part{id, gen, scope, st: Sess.Session}` records, i.e. up to four independent IRC
connections each owning a whole `Session`, plus a shared `Drafts` store and
`SlotEpoch` tombstones (`workspace.bend:74`, `:15`). `wsnet.bend` is a **second
complete IO frame loop** (`run_ws`), a sibling of `net.bend`'s `run_live`,
selected only when `--server HOST[:PORT]` is passed (`app.bend:69-76`,
`args.bend:93`). The names "workspace"/"ws"/"part" describe none of this.

1. **P0 — the `--server` production path has zero enforced coverage.**
   `app.bend:76` dispatches to `WsNet.run_ws`. `--server` appears in `tests/`
   **exactly once — inside a usage string** (`args_demo.bend:90`). No PTY test,
   no integration test, no golden. 2,742 lines are compiled into every shipped
   binary and never executed by any gate.
   → New `tests/pty/server_multiserver.py`: two owned loopback peers, launch with
   `--server`, assert both register, a message routes to the correct part, an F7
   slot switch preserves drafts, and shutdown acknowledges for **both**
   generations. Deterministic progress conditions only — no fixed sleeps.
   Add the target to `test-pty`.

2. **P4 — adopt `WsLoop` across all continuations (mechanical, do this first).**
   98 `wsnet` defs thread `ctx: PrefLive.Context` plus 17 other loop fields by
   hand; the longest signature is **626 characters** (`ws_net_painted`,
   `wsnet.bend:1968`). `type WsLoop` (`wsnet.bend:174`) was added as the fix —
   *"Loop accumulator bundle (struct match keeps nesting shallow)"* — but is
   constructed/destructured at only ~8 sites (`:1388, :1535, :2002, :2247, :2252`),
   never in the deep continuations.
   → Adopt it everywhere. **Semantics must not change.**
   ⚠️ Bend's affine/`&2` rules and the **247-word flattened capture cap** may
   reject naive bundling — the repo already has a commit
   (`d286f90`) splitting a function for exactly that cap. Box fields if needed.

3. **P4 — fold the duplicated cards/fullscreen sidecar.** `wsnet.bend` keeps
   cards in a loop sidecar (`type WsCards{s, gen, cards: C.State, full:
   C.Fullscreen}` `:121`; `WsCardsAll{parts, lease}` `:139`) rather than
   `Session.cf`. `net.bend` consequently has two paint entry points:
   `paint_session` (`:209`, reads `Sess.unbox_cards(cf)`) and
   `paint_session_cards` (`:222`, takes the sidecar and **ignores** `cf`). wsnet
   uses the sidecar at `:1558` and the Session-native one at `:2629`.
   Also `wsnet.bend:1206-1235 ws_fullscreen.{pick,toggle,f9,go,key}` is a 5-step
   clone of `session.bend:3631-3651 session_fullscreen_key.{pick,toggle,f9,go}`.
   → Drop `WsCards`, use `Session.cf` per part. *The `net.bend` and
   `session.bend` deletions are out-of-set — report them for the integration pass.*

4. **P4 — merge the shredded proof files.** Four files exist to prove **one**
   law, `case_b_isolation` (`workspace_isolation_proof.bend:136`, discharged at
   `PROOF.bend:1238`). `_route.bend:12-13` states the reason: *"Exact
   tripped/emit/routed expansion with ONLY its ceiling left open"* — `route.guarded`
   is a hand-copy of `WS.step_keys.routed.pick` (`workspace.bend:517`) whose only
   difference is that the overflow ceiling is a parameter.
   **Reassuring:** `law route_transport` (`_route.bend:30`) ties the copy to the
   original and its proof closes with `{==}` after one `%Equal.sym`, so
   **definitional equality is actually checked** — the mirror cannot silently
   diverge.
   `_arithmetic` (47 lines, 5 Nat lemmas) and `_selectors` (63 lines, fixtures,
   whose own header disclaims *"These partial laws do not prove Workspace guard
   admission or isolation"*) are not concepts.
   → Merge all three into `workspace_isolation_proof.bend` (314 → ~250 lines),
   keeping `route.guarded`/`route.normal`/`route_transport` as named defs inside.
   **Never weaken `case_b_isolation` or `route_transport`.** `_proof.bend:126`
   warns: *"Do not replace this endpoint with `{WS.isolation_ok()==True}`: that
   would restore the old nullary conversion seam."*
   Note all 9 `PROOF*.bend` files import `_proof.bend` at line 18, so this file
   is paid for 9× per `make check`.
   ⚠️ These four files are **not reachable from `app.bend`** and no test imports
   them — they are proof-only. That is legitimate; do not "wire them in".

5. **P4 — rename for comprehension (do LAST, and only if 1–4 are green).**
   `workspace.bend`/`Workspace`/`Part` → `servers.bend`/`Servers`/`ServerSlot`;
   `wsnet.bend`/`WsNet` → `servers_net.bend`. Resolve the `Ws` alias collision.
   ⚠️ This touches `LAWS.bend`, `PROOF.bend`, and many importers you do not own.
   **If the rename requires out-of-set edits, STOP and report the full rename map
   instead of performing a partial rename.** A half-applied rename is worse than
   none.

**Verification**
```sh
make test-wsnet-gates test-ws-first-connect test-ws-shutdown-pending
make test-workspace test-workspace-005-source test-workspace-isolation-step
make test-sessws-s1s5 test-ws-carrier-native test-ws-media-stage-native
make test-ws-upload-frame test-session-drafts
python3 tests/pty/server_multiserver.py ./build/birc
make proof
```

**Constraints:** do not import `wsnet`/`net`/`actor` into `LAWS.bend` — the
checker rejects foreign/unsafe deps. Keep proof-facing queue rules in
`outbound.bend`. A new connection clears channel roster/topic but keeps
same-endpoint chat history. Reconnect dividers are a `Reconnect` event, not a
substring test. Only the current generation's `WriterDone` acknowledges shutdown.
Tests use owned loopback peers only.

---

## T2.5 Orphan-test triage and quarantine

**REASSIGNED — no longer a cursor-agent task.** Two reasons: the work is execution
and classification rather than code editing, and T2.4 already runs the 16
ws-family orphans, so the scopes overlapped. Dropping it also removes the only
Makefile ownership conflict in Wave 2 (T2.4 needs the Makefile to register its new
PTY target).

The reviewing agent runs it on the remote lane instead, after Wave 2 merges:

```sh
rsync -a --delete --exclude 'build/' --exclude '.muse/' --exclude 'handover-recovery/' \
      --exclude 'scratch/' --exclude 'result*' --exclude '.direnv/' \
      ./ aarch64-darwin-1.lan:/Users/angerman/birc-lane/
ssh aarch64-darwin-1.lan 'cd /Users/angerman/birc-lane && mkdir -p build \
  && MAKEFLAGS=-j6 make test-orphans > /tmp/orphans.log 2>&1; echo rc=$?'
```

**Ownership for this task:** `BACKLOG.md` (append only) and the triage report. The
Makefile stays with T2.4 during Wave 2; promotions to `test-review-pure` are
applied at integration.

T0.1 already wired the orphans into a `test-orphans` target (30 prerequisites) and
promoted the three that passed a smoke run. This task triages the remainder.

1. Run `make test-orphans` and classify every failure:
   **(a)** test rotted against a migrated API (e.g. `session.bend`'s native
   cards/drafts migration) — record the exact assertion and the API it expects;
   **(b)** genuine product defect — **record, do not fix**;
   **(c)** needs a native/PTY lane that was never granted
   (`Makefile:1719` *"SOURCE UNRUN: standalone until compile/native/three PTY
   runs qualify"*).
2. Add passing tests to `test-review-pure`. Leave failing ones in
   `test-orphans` with a one-line comment naming the classification.
3. Append a `BACKLOG.md` entry per unresolved failure.
4. **Never edit a test's assertions and never edit product code.** This task is
   triage only.

**Verification:** `make test-orphans` output pasted in full into the report;
`make -n check | grep -c test-orphans` shows the wired subset.


---

# WAVE 3 — Wide API change (serial, critical path)

## T3.1 `_with`/`_cm` twin collapse and the `Iso` record

**Owns:** `src/bend/client.bend`, `src/bend/buffer.bend`,
`src/bend/client_laws.bend`, plus **call sites in** `src/bend/session.bend`,
`src/bend/view.bend`, `src/bend/isupport.bend`, `src/bend/submit.bend`,
`src/bend/history_search.bend`, `src/bend/typing.bend`, `src/bend/join_plan.bend`

**This task runs alone.** It changes public APIs across the protocol core; no
other task may edit Bend sources concurrently.

1. **P4 — 137 twin defs, ~825 lines of near-copy.** Measured: `client.bend` has
   260 defs of which **79 (30%)** are `_with`/`_cm` twins covering **502 of
   1546** def lines; `buffer.bend` has 400 defs, **58** twins, **323** lines.
   Twins are literal copies modulo five extra positional params.
   `client.bend:362-392` (`feed_join.*`) vs `:394-424` (`feed_join_with.*`)
   differ only in `join_upd`→`join_upd_with` and `wire_get`→`wire_get_with`.
   `client.bend:983 feed_num.by` vs `:1005 feed_num_with.by` are a 6-arm ladder
   where 5 arms are byte-identical. `client.bend:1341 feed_at.stamped` vs
   `:1329 feed_at_with.stamped` likewise.
   The five params are always extracted together (`session.bend:4303-4307`):
   `+cm = Isupport.casemapping(iso2) … +strip = Isupport.strip_set(iso2)`.
   → Introduce one record `Iso{cm, types, status, sigils, strip}` with
   `Iso.defaults()`, thread **one** parameter, delete every non-`_with` twin.
   `client_laws.bend` (which uses `Feed.feed` ~25×) calls
   `Feed.feed(cl, Iso.defaults(), line)`.
   **Sequence after T1.2**, which makes the default chain production-unreachable.

2. **P4 — `Settings` is a 14-field god record** (`buffer.bend:166`) holding
   display prefs *and* `sasl_user`/`sasl_pass` *and* UI state (`unreads`,
   `bell_seq`). Every `set_*` rebuilds all 14 fields, and every consumer receives
   the password even when it only reads `settings_ts` (Interface Segregation).
   There are **47** accessors (`buffer.bend:166-320`).
   → Extract `Credentials{user,pass}` and `Alerts{unreads,bell,bell_seq}`.
   Shrinks the credential surface and removes ~20 accessor defs.

3. **P4 — target normalization implemented four times.**
   (1) `irc.bend:214-262` `is_chan_type`/`starts_channel`/`chan_target` —
   hardcoded `#&+!`, `@+`; (2) `buffer.bend:57-82`
   `target_channel_with`/`target_key_with` — param types/status/sigils;
   (3) `isupport.bend:715-783` `head_in_types`/`is_channel`/`chan_target` —
   `State`-derived; (4) `buffer.bend:1047-1073 message_key`/`message_key_with` +
   `isupport.bend:780 chan_target_cl` — resident-first audience.
   `isupport.bend:756-762 chan_target.head` and `buffer.bend:71-73
   target_key_with.name` are the *same algorithm* (strip one leading sigil iff
   the tail is a chantype). Supporting helpers duplicated too: `buffer.bend:9
   has_ch` / `:32 head_in_types` vs `isupport.bend:222 has_char` / `:715
   head_in_types`.
   → Keep (1) as the fixed-charset leaf. Make (3) the single negotiated owner;
   (2) delegates to it at defaults. Preserve (4)'s resident-first rule as the
   only audience wrapper.

4. **P4 — dead defs, verified zero references** repo-wide:
   `buffer.bend:799 auth_for_credentials`, `:962 clear_unread`, `:1456 buf_log_at`,
   `:1549 is_sigil`, `:1683 nick_add_idx_cm`.
   Test-only (delete only if you also update the test):
   `client.bend:1369 demo_lines`, `:1529 search_buf`,
   `buffer.bend:1513 purge_nick_from_active_buf`, `:939 mark_unread_idx.on`,
   `:931 mark_unread.buf`, and the thin `dflt_cm()` wrappers
   `is_line_muted`/`mute_match`/`is_muted_list`/`is_line_muted_pat`/
   `add_unread_item`/`rename_unreads` used only by
   `tests/bend/mute_scope_demo.bend` and `state_demo.bend`.

5. **P4 — `AuthPhase` self-nests** via `AuthProfile{phase, config, success_seq}`
   (`buffer.bend:656`), forcing every reader through the recursive `auth_phase()`
   unwrapper (`:658`). The comment at `:654` admits it exists to *"keep the old
   phase seam and all container arities"*.
   → **Suspected** that arity preservation is unnecessary once change 1 lands.
   **Verify against `auth.bend` consumers before touching.** If unclear, leave it
   and report.

6. **Explicitly do NOT do:** split `buffer.bend`/`client.bend` into more files.
   Bend elaborates whole-program, so moving defs across files changes **zero**
   compile cost — a split is cosmetic. `buffer.bend` does hold seven
   responsibilities (ISUPPORT defaults + target normalization `:9-96`;
   `LineKind`/`Line`/`Scroll`/`Buffer` containers `:111-159`; `Settings` + 47
   accessors `:166-320`; mute/unread/mention policy `:323-577`; auth types
   `:636-681`; the `Client` container + buffer registry `:683-1000`;
   diagnostics/stamping/reconnect `:1115-1370`; nick-roster ops `:1539-1700+`) —
   record this in the report, but do not split.
   Also **do not** replace the numeric-reply or verb ladders with bigger tables:
   `client.bend:943-953 num_rows()` (6 rows) and `irc.bend:868 cls_rows()`
   (18 rows) are **already** data-driven and are the right shape.

7. **P2 — hoist the fold out of the table scan.** `irc.bend:887 classify` →
   `cls_verb` → `cls_lookup(cls_rows(), cmd)`; `cls_lookup` (`:871`) does
   `ieq(name, cmd)` per row and `ieq` (`:171`) folds **both** strings every
   iteration, so `cmd` is re-`rfc1459`-folded 18× per `classify`, allocating ~36
   Strings. `classify` runs ≥3× per inbound line (`client.bend:1263`,
   `typing.bend:270`, `join_plan.bend:251,285,325,348`).
   → Compare pre-folded names, or `U32` verb hashes.

**Verification**
```sh
make test-proto test-feed test-feed-bench test-state test-state-review
make test-commands test-irc-commands test-message-split test-submit test-split
make test-mute-scope test-action-budget test-server-time test-server-id
make test-auth test-auth-profile test-auth-profiles test-reconnect-registration
make test-reconnect-recovery test-reconnect-auth test-reconnect-echoes
make test-mode-privacy test-join-plan test-join-capacity
make test-ui test-ui-review-view test-columns-width test-wrap test-scroll
make proof          # 535 laws — must stay 535
make -j10 test      # full Bend suite; this is the one task allowed the wide gate
```

**Constraints:** the first valid connection-server `001` owns the assigned
nickname; normalize before Auth/JoinPlan/Client consume it; reject malformed,
peer-prefixed, and later conflicting welcomes without changing live state. Split
NICK handling shares Client's accepted-rename predicate. Canonicalize known
synthetic identities at creation, not generic stored-name lookup; a peer named
`server` is a query. Keep `+#room` unchanged in creation, membership events, and
stored history; prefer an exact resident channel before STATUSMSG fallback;
`@#room` remains an unambiguous alias. Normalize wire targets before
reserved-name validation and lookup. Preserve the `NOTICE *` broadcast exception.
Log lines carry author identity and stable global IDs — never infer new events by
comparing rendered text or timestamps. **Never weaken a law.**

---

# WAVE 4 — Three parallel structural refactors (API-frozen contracts)

Each task owns one large module and **must keep every other module's public API
usable unchanged**. If a task finds it must break a contract, it stops and
reports rather than editing another task's file. Merge order on conflict:
**T4.1 → T4.3 → T4.2**.

## T4.1 `session.bend` decomposition

**Owns:** `src/bend/session.bend`, `src/bend/net_msg.bend` *(new)*,
and the ~32 `tests/bend/*.bend` files that would import `net_msg.bend`

`session.bend` is **5,254 lines** — the largest Bend module — with 831 `def`s and
19 `type`s. **93 of 196** test files pull it in (47%), and it imports 24 modules,
so every one of those binaries elaborates the whole hub closure. Documented cost:
`HANDOVER.md:132` *"Isolation runtime fixture | Compile timeout, 180 s | Its ten
assertions did not run"*.

**Responsibility map (verified; ~1,030 lines / 20% have 0–1 `Session` references):**

| Concern | Range | Lines | `Session` refs |
|---|---|---|---|
| Registration/line fold | 32–378 | ~347 | mixed |
| **`NetEvt`/`NetCmd`/`UiMsg`/`NetState` + gen guards** | **380–449** | **70** | **0** |
| Submit `echo`×`iso` family | 640–800 | ~160 | 0 |
| `Hist` input-recall ring | 800–905 | 105 | **0** |
| `Keys`/`KeyPol`/KEY_*/wheel/scroll | 905–1166 | 261 | **0** |
| `Comp` completion | 1168–1410 | 242 | 1 |
| `Session` type + accessors | 1413–1770 | ~357 | core |
| History search/import/drain glue | 1773–1990 | 217 | high |
| JoinPlan flush / reconnect / auth reset | 1994–2060 | ~66 | high |
| `pend_*` optimistic-send ledger | 2062–2312 | 250 | **1** |
| Autoreconnect/error/theme/size | 2313–2495 | ~183 | high |
| `session_after` NetCmd apply | 2497–2578 | ~82 | high |
| Upload consent state | 2629–2810 | 182 | high |
| `split_apply`/`submit_or_split` | 2775–2950 | 176 | 0 |
| Typing expire/tick/merge | 2952–3220 | 268 | 52 |
| `finish_keys`/`finish_hist`/`finish_comp` | 3220–3410 | ~190 | high |
| **`step_keys` hook chain** | **3469–4113** | **644** | high |
| Live loop / `step_on_chunk*` | 4135–4620 | 486 | high |
| **Notify classification + live queue** | **4623–5042** | **420** | 74 pure |
| Law predicates/fixtures (`*_ok`) | 5050–5254 | ~205 | n/a |

1. **P1 — extract `net_msg.bend` (highest-value change in this task).**
   `session.bend:380-449` (`NetEvt`/`NetCmd`/`UiMsg`/`NetState`/`event_current`/
   `writer_done_current`) has **zero `Session` references** — it only needs
   `Up.Request`, `Prefs.Preferences`, `Hs.DiskResult`, `Cl.Client`.
   **32 of the 93** session-importing tests use no `Session` core at all — they
   touch only `Sess.NetCmd`/`NetState`/`UiMsg`/`Cont`/`Dial`/`Eof`/`keys_enter`/
   `endpoint_client`/`notify_dispatch` (`actor_queue.bend`, `ipv6_transport.bend`,
   `shutdown_ack.bend`, `server_id_demo.bend`, `startup_actor.bend`,
   `ws_first_connect.bend`, …). Re-pointing those 32 removes `session.bend` and
   its 24-module closure from **~16% of the suite**.
   → **Honest caveat: a cosmetic file split of `session.bend` alone would NOT
   measurably help build time** — the 59 core-coupled binaries compile the same
   closure either way. The payoff comes *only* from narrowing importers. If you do
   one thing in this task, do this.

2. **P4 — stop exploding `Session` into 25–29 positional parameters.**
   `Session` (`session.bend:1416-1467`) has **24 positional fields**; **79 of 83**
   `case Session{…}` patterns destructure **all 24** (only 4 use 10). Every setter
   is a full rewrite — `session_set_media` (`:3495`) destructures 24 slots to
   change one. Worse, the record is exploded into parameters:
   `finish_keys.comp` (`:3282-3311`) takes **29**; `finish_keys.nav` 27;
   `session_after` 25; `finish_hist` 25; `step_on_chunk_pair_ceiling` 25;
   `session_after.dial` 20; `finish_comp` 23; `session_expire_typing.got` 24.
   There are **36 full `Session{…}` constructor literals**.
   **Adding one `Session` field is a ~120-site change.**
   → Convert those functions to take `Session` plus a small `KeyCtx`; add named
   setters so a field change is one place.
   ⚠️ The 247-word capture cap is *why* 7 fields are boxed one-element `List`
   cells (`media`, `iso`, `hist_live`, `cf`, `reg`, `labels`, `pends`) with
   comments at `:1435-1438, :1443-1446, :1450-1456`. **Measure flattened words
   after each move.** Preserve the boxes.

3. **P4 — extract the genuinely Session-free clusters** (932 lines, 18%):
   `Keys` 261 + `Hist` 105 + `Comp` 242 + `pend_*` 250 + `notify_is_*`/
   `notify_collect*` 74. `notify.bend` already imports `Cl`/`Irc` and **not**
   session (`notify.bend:30-33`), so the 13 classification defs move verbatim and
   become provable in the notify law set.

4. **P4 — apply the `Stamp` shape T1.5 reported.** Completion variants are
   inconsistent (`session.bend:410-427`): `MediaFetched{generation: Nat,
   ticket: Nat}`, `SearchDone{ticket: Nat, gen: Nat, wgen: U32}`,
   `HistoryLoaded{ticket: Nat, gen: U32}`, `NotifyDone{ticket: Nat,
   endpoint: String}` (no gen), and `UploadFetched{request, result, error,
   http_status}` — **no ticket, no generation at all**. `gen` is `U32` in three
   variants and `Nat` in two.
   → One pure `type Stamp{ticket: Nat, gen: U32, wgen: U32, endpoint: String}`
   plus `stamp_current(stamp, live) -> Bool`.
   ⚠️ **Add the field and the predicate; do not replace existing checks.**
   `NotifyDone`'s endpoint-only match is deliberate (`notify_io.bend:172`) —
   turning it into a gen match would misattribute late completions.

5. **P4 — move the notify classification defs to `notify.bend`** (see 3).
   `session.bend:4623-5042` is 420 lines of which only ~74 are pure session state.

6. **P4 — the `step_keys` hook chain is 644 lines** (`:3469-4113`), composed at
   `:3951`:
   `step_keys.preferences(keys, step_keys.intent(keys, …, step_keys.history(keys,
   step_keys.plan(st, keys, step_keys.base(st, keys)))))`
   → Flatten into a list of handlers or at least document the order as a contract.

**Verification**
```sh
make test-session-preferences-intent test-state-review test-runtime-review
make test-actor-queue test-shutdown-ack test-startup-actor test-deferred-actor
make test-typing test-preview test-search test-scroll test-scroll-edits
make test-upload-session test-notify-runtime test-live-context
make test-reconnect-registration test-reconnect-preferences
make proof
```

**Constraints:** `*log*` is lazy read-only app-session state — one of 16 buffer
slots, at most 128 rows of 512 chars, preserved across endpoint changes. Error
mirrors keep their original event IDs and never steal focus. Log rows never enter
chat history. A history-save failure goes directly to the log and schedules a
coalesced repaint — not a persisted chat error and not another save. IRCv3
`+typing` is Bend-owned, capped at 32 entries, expires from a one-second
`TypingTick` (active 6s, paused 30s). Upload consent is a later physical F8.
Authentication profiles bind credentials to the initial host and port; **any**
endpoint change permanently clears them. Shutdown: the writer flushes its healthy
pending FIFO, closes, and posts `WriterDone`; only the **current generation's**
`WriterDone` acknowledges. **Do not use `IO.die` for successful UI shutdown** —
the pinned runtime writes an unbounded stderr newline even for an empty message.
Scroll uses one `ScrollAt{after, tail}` anchor.

---

## T4.2 `wsnet`/`net` loop unification

**Owns:** `src/bend/wsnet.bend`, `src/bend/net.bend`

**Prerequisite:** T2.4 landed (WsLoop adopted, `--server` PTY coverage exists).
**Do not start if `tests/pty/server_multiserver.py` is not green.**

`net.bend` and `wsnet.bend` share **zero** def base names (127 vs 87 families —
`comm -12` is empty) yet implement the same families side by side:
`media_stage`↔`ws_media_stage` (`net.bend:1048` / `wsnet.bend:1099`),
`upload_stage`↔`ws_upload_stage` (`:1086` / `:1119`),
`cards_live_stage`↔`ws_cards_stage`, `preferences_stage`↔`ws_prefs_stage`
(`:1369` / `:1254`), `shutdown*`↔`ws_shutdown*` (`net.bend:68-131` /
`wsnet.bend:2078-2210`), `on_search.*`↔`ws_search.*` (`net.bend:1188-1207` /
`wsnet.bend:1871-1886`, with identical `.landed/.done/.got/.gated`
decomposition), `net_notify_*`↔`ws_notify.*`.
wsnet *does* reuse 29 `Net.*` leaves (paint, watches, spawns) — the duplication
is in the **loop, staging, lease, and shutdown orchestration**, ~2,000 lines.

→ Fold `net.bend`'s single-server loop into `run_ws` with a 1-part workspace.
Also collapse `ws_fullscreen.*` into `session_fullscreen_key` and delete
`Net.paint_session_cards` (both flagged by T2.4).

**Risk: HIGH.** This is the live path for both single-server and `--server`.
Sequence it: signatures first (T2.4), then staging, then shutdown, then the loop
itself. Commit after each stage so any one is revertible.

**Verification**
```sh
python3 tests/pty/server_multiserver.py ./build/birc     # must stay green
make test-net test-actor test-actor-queue test-live test-dns test-dns-timeout
make test-shutdown-ack test-shutdown-flush test-deferred-actor test-deferred-frame
make test-wsnet-gates test-ws-first-connect test-ws-shutdown-pending
make test-ws-carrier-native test-ws-media-stage-native test-ws-upload-frame
make test-mss-stale-socket test-reader-errors test-reader-pongs test-socket-deadline
make test-pty test-pty-autoreconnect test-pty-disconnect-cleanup
make test-output-shutdown test-output-progress test-output-utf8
```

**Constraints:** the `IO.spawn` actor owns the affine `Tr.Conn`; UI ↔ actor via
`Chan(NetEvt)`/`Chan(NetCmd)`. The actor owns the fd/TLS handle — **never
`Chan(Conn)`**. `SEND_CAP` is 8 outbound lines per actor tick; leftover stays in
`pending`; cmd-close and fuel-0 flush `pending` so `/quit` is not dropped.
`--frames N` is N ticks; `frames=0` live loops are `@unsafe`. Demo/offline idle
actor waits for `Dial`; Demo/Connecting `Cont` carries no IRC outs. Reader/writer
handles share one TLS connection on the pinned serial IO loop; shutdown must wake
the shared reader. Preserve exact OpenSSL retry buffers. Every paint applies the
keys the frame read, including a chunk or Eof paint. `UiKeys.more` is input-only;
terminal recovery does not schedule synthetic input wakes. Ordinary frames have a
40-ms output budget; writable repairs 200 ms; still-full repairs do not wait.
Normal Esc has a 50-ms watcher deadline.

---

## T4.3 `view.bend` 4-axis clone collapse

**Owns:** `src/bend/view.bend`, `src/bend/view_hint.bend`,
`src/bend/view_laws.bend`, `tests/bend/theme_ws_render.bend`

`view.bend` (3,295 lines) carries a 4-axis combinatorial clone of the same
pipeline: `×media` / `×cards` / `×cm` / `×themed`. Examples:
`body_of.buf_media` (`:1148`), `_cm` (`:1154`), `_cards` (`:1202`), `_cards_cm`
(`:1213`), `_bottom_themed` (`:2872`), `_cards_cm_themed` (`:3197`);
`recent_lines.*` has six variants (`:1104-1195, :2847-2862, :3167-3182`);
`visible_media.*` has eight (`:1857-2062`). **~50 near-identical defs.**

→ Collapse the axes into one record of options (`theme`, `casemapping`, `media`,
`cards`, `legacy`) threaded as a single parameter.

**This is the enabling refactor for T1.1's fixes to stop needing six
applications each.** Responsiveness payoff is indirect but real.

Also: **`OpImage` (`view.bend:104`) is emitted only by `image_ops`
(`:1735-1742`), reachable only through `legacy=True{}` adapters.**
`view.bend:2294` states *"Production media-aware entry points never emit
OpImage"*; `:2511-2512` *"Legacy pure characterization/law adapters retain
OpImage spelling."* Three production entry points pass the legacy flag as
`False{}` (`:2262, :2479, :2514`), and `ViewModel` carries a `legacy` field
(`:2292`) whose only `True{}` producers are those adapters. `legacy` appears
**36×** in a 3,295-line module. It still costs a CID slot (`timui_ffi.c:878`)
and a Makefile alias.
→ Move the adapters to a clearly-named `view_legacy.bend` so the production type
stops carrying a field production never sets true, then migrate
`tests/bend/theme_ws_render.bend:145,165` to `OpMedia` and drop `OpImage`.
⚠️ **Risk: MEDIUM.** The `LAWS.bend`/`PROOF.bend` import graph must be
re-checked; AGENTS.md warns that importing the wrong module into `LAWS.bend`
breaks the proof set. Dropping `OpImage` also requires a `timui_ffi.c` CID
removal — **report that as an out-of-set blocker rather than editing C.**

**Verification**
```sh
make test-ui test-ui-review-view test-ui-review-columns test-ui-review-widgets
make test-view-profile test-wrap test-columns-width test-scroll test-scroll-edits
make test-viewport-tail test-theme test-theme-ws-render test-theme-selector-boundaries
make test-media-view test-media-anchor test-media-branches test-media-policy
make test-cards-view test-formatting test-richtext-model test-richtext-painter
make test-paint-slope test-perf-hardening test-perf-media-wrap
python3 tests/perf/key_latency.py ./build/birc      # must not regress vs T1.1
make proof
```

**Constraints:** Bend expands logical chat lines into resize-safe visible rows
with hanging indents. Live paint is `List<DrawOp>` (`OpBox`/`OpSplit`/`OpText`/
`OpTabs`/`OpLine`/`OpMedia`); C walks and paints and does not tokenize,
classify, or wrap IRC. Bend keeps clusters whole across source style runs with
the leading character's style; word wrapping prefers complete IRC spaces;
oversized words/URLs hard-wrap; hidden boundary spaces still contribute to
source-character anchors. Measure nickname-prefix columns on the complete painted
text, not nickname width plus punctuation. Use exact painted panes, mute filters,
row anchors, and stable event IDs. Preserve selected visible results at cache
capacity.

---

# WAVE 5 — Integration and qualification

Not a cursor-agent task. Performed by the reviewing agent.

1. Merge order T4.1 → T4.3 → T4.2 if conflicts arose.
2. Apply the out-of-set blocker reports collected in waves 1–4.
3. Resolve the collected naming decisions: `cap_notify.bend` → `caps.bend`
   (it is the IRCv3 capability registry and sole `CAP END` owner, not
   notification policy); the `Ws` = `wire_style` vs `ws_*` = workspace collision;
   the meaningless `AD` alias; `workspace`/`Part` → `servers`/`ServerSlot`.
4. Full gate:
   ```sh
   make -j10 check          # proof + test + lint-ffi + paste-harness
   make proof-kernel        # BendTT independent check
   make test-sanitizers test-asan test-ubsan
   make test-perf-gates
   ```
5. Confirm the law count is still **535** and proofs still **535** with zero
   orphans: `grep -c '^law ' LAWS.bend` and `grep -c '^def Laws\.' PROOF.bend`.
6. Re-measure the baseline and record the delta:
   `make -n -B check | wc -l` (was **841**), `bend` invocation count (was
   **154**), `nix develop` count (was **479**), total Bend lines recompiled
   (was **4,023,081**), and `python3 tests/perf/key_latency.py`.

---

## Explicitly deferred / rejected

**Rejected — would make things worse:**
- Growing `tests/bend/expect.bend` (12 lines, imported by **174 of 196**
  goldens). Bend compiles whole-program, so every line added to an imported
  fixture is recompiled into all 174 importers. **Freeze it at 12 lines.**
  Residual per-file boilerplate is ~5-7 lines × 196 ≈ 1,000-1,300 lines and is
  **irreducible**: Bend requires each program to define its own `main`, and the
  closing `IO.print("<name>=ok")` *is* the contract —
  `scripts/check-golden.sh:19` does `grep -F -x -q -- "$token"`.
- Splitting `buffer.bend`/`client.bend`/`session.bend` into more files *for
  compile-time reasons*. Whole-program elaboration means moving defs across files
  changes zero compile cost. Splits are justified only when they let **importers
  narrow** (T4.1 change 1) or improve comprehension.
- Replacing the numeric-reply or verb ladders with bigger tables — they are
  already table-driven (`client.bend:943-953`, `irc.bend:868`).
- Touching `scripts/check-golden.sh`. It is 22 lines, `set -eu`, correctly
  fail-closed (exit status checked *first* at `:12-17`, then the whole-line
  fixed-string token at `:19-23`), and self-tested by `tests/golden_runner.sh`.

**Load-bearing complexity — do not simplify:** `outbound.bend`; the `.details`
box-unwrap pairs; `actor.bend`'s CPS writer; `Bool.pick(U32, U32.is_zero(code),
1, code)`; `upload_io.bend:20-38`; `notify_io.bend`'s 5 spawn sites;
`history_startup_io.bend`; `history_search_io.bend`'s dual backend;
`theme_dark_*` RGB literals in `LAWS.bend:1147-1231` (intentional per AGENTS.md
*"Dark preserves historic values"*); the `BIRC_*` env switches (dual-use:
user-facing disables **and** test isolation, set by `Makefile:41-50`).

**Deferred, needs the author:**
- Deleting `handover-recovery/` (220 tracked files, 6.2 MB, including ~30 stale
  Makefile snapshots and 56 `.bend` copies that pollute every glob) — zero build
  references, but removal is the author's call. Move to a git tag or release
  artifact rather than `git rm`.
- Pruning the 25 registered worktrees / 337 MB `.muse/`.
- `LAWS.bend:1171 emoji_table_has_seventy`
  (`{List.length(&2, Emoji.Entry, Emoji.aliases()) == 70n : Nat}`) — **adding one
  view-only shortcode fails `make proof`.** This is a size snapshot, not a
  behavioral guarantee, and the real guarantees already exist separately and
  better (`emoji_birc2_load_keeps_source` `:1273`,
  `emoji_production_renders_glyph` `:1276`). Replace with a *stronger* property
  form (every alias `:`-delimited, every glyph non-empty, aliases unique) — that
  **adds** coverage and survives table growth. Deferred because changing a law
  needs author sign-off.
- 61 laws whose RHS is a bare numeric literal (e.g.
  `LAWS.bend:277-278 media_virtual_rows_six`) turn cosmetic edits into
  proof-layer edits. Same reasoning.
- Law fixture duplication: 77,230 chars of copy-pasted statement text in
  `LAWS.bend`, which has **zero `def` helpers**. Exact repeats:
  `Sess.session_online(Sess.session_with_client(` **×15**; the
  `Cl.buf_set_lines_at(Cl.init("me","s"), 0n, [Cl.Line{…}])` fixture **×13**; the
  `Cards.State{…}` fixture **×9**; the 8-entry `Notify.Mark{…}` table **×4** at
  `:1207,1210,1213,1216` (~730 chars each — the three longest statements in the
  file). Hoisting into named fixture `def`s is legal (statements already call
  `CL.*`, `VL.*`, `Hs.*`, `Notify.*`). **Suspected** safe w.r.t. the 247-word cap
  since that is a C-backend continuation limit, not a proof-term limit — confirm
  on the first migrated law.
- Proof coverage thin spots: `session.bend` (5,254 lines) gets 64 law-mention
  lines and `workspace.bend` (1,989) gets **7**, while `theme.bend` (small,
  cosmetic) gets 26 and `isupport.bend` gets 65. `buffer.bend` is best covered at
  143. Target new quantified laws at `workspace.bend`'s routing/fencing
  predicates next, following the `outbound.bend` precedent. Only **29 of 535 laws
  (5.4%)** are universally quantified; 506 are concrete examples that the 196
  golden fixtures already check in milliseconds.
- `preferences_runtime.bend` (618 pure lines) is not proof-required but 11 test
  binaries exercise its coalescing/rebase/16-job queue without IO — the best
  candidate in the IO subsystem for new laws.
- `media.bend` ≡ `cards.bend` generic queue extraction: **47 shared def base
  names**, and `take_job_allowed` is byte-identical (`cards.bend:307-310` /
  `media.bend:351-354`) *including the same verbatim comment* at
  `cards.bend:312` / `media.bend:356`. Both are law-covered, so the 8-pending/
  8-cached bounds are maintained twice. **Deferred because Bend has no generics
  over `Data`** — unifying forces one shared type and may breach the 247-word
  capture budget. If not extracted, add a characterization test pinning both to
  one observable table so drift fails loudly. Do **not** merge the display-gating
  arms: cards deliberately have no terminal-support gate
  (`session_cards.bend:21`).
- `dns_ffi.c:38-39` and `tls_ffi.c:544-546` build `List U32` with **one `io_node`
  heap cons per octet**; `actor.bend:264` requests 65536, so a full-size read
  allocates 65,536 cons cells. The octet representation is *justified*
  (`dns_ffi.c:1-4`: Base `UDP.recv_from` returns an `io_str` String, so A-record
  rdata 0x80–0xC1 is unrecoverable; AGENTS.md requires Latin-1 fallback). No
  flat-byte primitive is exposed to Bend. **Reported, not fixable without a Bend
  runtime change.**
- Batching outbound sends: `send_line` (`actor.bend:33`) issues one
  `Tr.send_for` **per line**, and `send_line.traced` (`:28`) adds a
  `Clock.net_trace` crossing each — with `SEND_CAP` 8 that is 16 crossings and 8
  syscalls per writer tick. Batching preserves the FIFO and the "last attempt may
  have written only part of its line" rule (`actor.bend:56-57`) **only if** the
  batch is all-or-nothing on failure, which needs `Sent{count}` accounting
  reworked. Needs measurement first.
- The 10 test-side wall-clock sleeps that violate "deterministic progress
  conditions": `output_progress.py:54` (1.1s), `:61` (0.2s),
  `output_recovery.py:76` (1.2s), `output_stall.py:144,145` (0.2s each),
  `stall.py:105` (0.3s), `chunk_flood.py:83` (0.2s), `history_pty.py:126` (0.1s),
  `:219` (0.2s), `ws_upload_frame.py:117` (0.1s). These wait for the documented
  40 ms / 200 ms output budgets with no observable signal. `output_recovery.py:76`
  is the clearest — it precedes `conn.sendall(PING)` and `:84 assert not
  select.select(...), "retry did not start"`, while `:81-83` already does the
  correct `select` five lines later. **Replace the wait, never shorten the
  budget.** (The other ~112 `sleep` occurrences are compliant poll ticks inside
  bounded wait loops, e.g. `live_minus.py:56-62`, `typing.py:45-60`; and the 3
  sleeps inside generated fake helpers — `media.py:119,334`,
  `preview_retry.py:21` — are the feature under test.)
- `tests/pty/` has **no shared harness**: across 79 files, **74** hand-roll the
  `TIOCSWINSZ` ioctl, **57** define their own `drain`/`read_until`/`pump`, **56**
  bind their own loopback server — while **11 files** do
  `from output_stall import drain, receive`, importing a *test* as a library
  (real definitions at `output_stall.py:25` and `:37`). Promoting
  `drain`/`receive`/`winsize()`/`loopback_peer()` into `tests/pty/_harness.py`
  would remove ~900-1,200 of 14,165 lines. **Must move the real deadlines and
  cleanup assertions, never relax them.** Do it file-by-file so each conversion is
  independently revertible.
- `mk/pty-shard.mk:6-8` implements exactly the right stamp cache (skips a shard
  when `build/birc`, the selector, and `tests/pty/*.py` are unchanged) but
  `Makefile:1394` routes `check → test → test-pty`, the **unsharded** path — so
  the cache is dead code in the default gate. Wiring it saves ~80 PTY launches per
  unchanged-binary loop. The stamp must also invalidate on `src/bend` change;
  `build-ui` is a prereq (`mk/pty-shard.mk:30`) so `build/birc` mtime covers it.
- `Makefile:38-39`: a `PTY_APP` override drops the build prerequisite entirely
  (verified with `make -n test-pty-local-time PTY_APP=/nonexistent/birc` — no
  `build-ui` prereq, fails only if the Python test errors). Add
  `test -x $(PTY_APP) || exit 2`.
- `make clean` (`Makefile:1588-1589`) is all-or-nothing over 724 MB / 1,569
  files, discarding ~3.4h of compiled state. Add `clean-logs`
  (`rm -rf build/test-logs build/pty-shards`) and consider a content-hash layout
  `build/<hash-of(bend-rev,src/bend)>/…` so branch switches reuse compiles. Keep
  `$(BLDDIR)/build-config` (`Makefile:674`, `FORCE` + `cmp -s` guard in
  `scripts/build-config.sh:26-28` — that pattern is correct) as the
  toolchain-change trigger.

**Not a problem (verified):** `nix/birc.nix:16-24` `cleanSourceWith` filters
correctly, so `nix build` does **not** copy the 724 MB `build/` or 337 MB
`.muse/`. Both `nix build` recipes (`Makefile:691`, `:1594`) are correctly
double-bounded (`timeout 900` + `--option timeout 900`), satisfying
`tests/build_deadlines.py:11-13`. `git status --porcelain` takes 0.089s — git
itself is not the bottleneck; untracked-directory *search* is. The pure/IO module
split is **principled, not accidental**: zero `_io`/`_worker`/`_live`/`_runtime`
modules appear in any proof file, and `LAWS.bend` imports zero IO modules.
`wsnet.bend`'s and `actor.bend`'s exclusion from proofs is the intended boundary,
not a coverage gap.
