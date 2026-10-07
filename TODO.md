# birc — Bend migration checklist

Goal: move as much of the IRC client as possible into Bend 2. End state:
**Bend owns `main`, protocol, client state, networking, and the frame loop**;
C is only thin TimUI FFI.
Verified TLS is the default; `--plain` explicitly selects plaintext. No ncurses.
The milestones below include historical behavior. Current contracts are in
`AGENTS.md`; a recorded earlier proof pass is not a verdict on the current tree.

## Pickup checkpoint — 2026-10-08

Read `HANDOVER.md` first. The current Root source is prebuilt at
`/nix/store/vznfyvnf6xkr74zhjmc9f4pi7hn306bd-birc-0.1.0`.
Its stock 425-law proof and six focused regression/package targets passed.
The complete Root `make check` was not run for this checkpoint.
The separate 535-law final candidate is preserved on the local
`checkpoint/birc-final-candidate-2026-10-08` branch, with raw receipts and
donor recovery packets. It is not merged, fully verified, or freshly prebuilt.
Use the handover's current queue instead of restoring the old conversation.

## Current final qualification

Work is being qualified in `/tmp/birc-final-candidate`. The final changes have
not been integrated into the Root worktree; the pickup snapshot is separate.

- [x] Admit reviewed production/Nix changes while preserving both Root layers.
- [x] Build the locked default Nix app and verify its default-app output path.
- [x] Pass the six selected installed-package suites on that exact output.
- [x] Qualify Cards test isolation red -> green without changing old oracles.
- [x] Qualify private settings success/refusal and three full upload-suite runs.
- [x] Pass three consecutive runs of all four changed terminal drivers.
- [x] Remove duplicate View theme selectors with baseline/post-change guards.
- [x] Qualify the new framed workspace theme-render witness before/after cleanup.
- [x] Pass and register the three notification gates (promotion approved).
- [ ] Apply the approved fixture corrections and qualify them.
- [ ] Compose all reviewed tests, Make targets and documentation coherently.
- [ ] Obtain a stock `bend PROOF.bend` pass; latest bounded run timed out.
- [ ] Pass the complete standard `make check` on the final candidate.
- [ ] Integrate safely, make meaningful local commits, and do not push.
- [ ] Reconfirm the final default Nix build and measure warmed `nix run` startup.

### Proof bottleneck review — current qualification

- [x] Independent Astra review of evidence, complete propositions and proof strategy.
- [x] Symbolic arithmetic and equality transport in the candidate's actual isolation law;
  preserve runtime Workspace, arbitrary Nat, `2^44` ranges and strict overflow guards.
- [x] Stock-check the complete isolation proposition on current dependencies: 12.832 s.
- [x] Stock-check the unchanged complete generation law alone: 1.627 s.
- [x] Fix the separately observed multiline defect: all 488 compile/golden assertions pass.
- [x] Preserve all ten isolation runtime checks; their compile gate is still unqualified.
- [x] Measure retained-C frontend/IR/optimizer and compile-to-object stages.
- [ ] Qualify native linking and the original current-source fixtures.
- [ ] Locate the remaining full-book cost; the bounded 535-law run has no verdict.
- [ ] Complete standard project checks and safe final integration.

The detailed receipts below distinguish check-only proofs, runtime assertions,
native diagnostics and censored timeouts. No numeric migration, new axiom,
weakened law, compiler limit change or independent kernel is selected.

### Approved corrections awaiting qualification

The user approved all eleven correction groups below and the single bounded
checker diagnostic on 2026-10-06T23:19Z. Checkboxes record qualification, not
approval. Preserve all assertions outside each exact approved correction.
Notification promotion remains conditional on all three gates passing.

- [x] Preserve IRC bold bytes in two stored MODE expectations; check plain
  visible text separately through View.
- [ ] Permit only the fixed startup title/mouse prefixes in the Carrier and
  Cards terminal fixtures; do not strip arbitrary control sequences.
- [x] Correct the notification producer-name pin and give its B fixture a
  real self-JOIN, with joined/unjoined controls.
- [ ] Give both notification-binding B setups a real self-JOIN; preserve
  all 92 existing assertions and add joined/unjoined controls.
- [ ] Correct four STATUSMSG expectations for negotiated prefix handling.
- [ ] Keep chat and desired rooms on a host-case-only reconnect, while still
  clearing credentials when the exact credential endpoint changes.
- [x] Include the implemented `--server` option in the CLI help expectation.
- [ ] Check the upload final marker against saved OPOST/ONLCR terminal flags.
- [x] Include `draft/chathistory` in both CAP handshake expectations.
- [x] Include account, away and history requests in the actor-redial wire
  expectation. The observed wire matches the single capability registry.
- [ ] Correct the new workspace G3 fixture's ISUPPORT source from `:irc`
  to its configured server `:a.example`, with source/recipient guards.
- [x] Run the reviewed copied checker timer once, default-off, names/durations
  only and a hard ten-minute bound; preserve stock tools, limits and laws.

The copied diagnostic ran once on 2026-10-06T23:22:00Z–23:31:52Z and timed
out (exit 124), with no proof verdict. Its receipt is
`/tmp/birc-checker-timers-run.c9AfuW6K/RECEIPT.txt` (SHA256 `77794ef5…`).
The 88 input files, five copied checker files, ten stock tools, and fixed
53-file proof closure stayed unchanged. The metadata is `metadata.jsonl`
in that directory (SHA256 `bcea9d35…`): 12,965 starts, 12,961 ends, four
unfinished spans, no name truncation. Durations are inclusive and nested.
This is not a stock proof run or a passing proof.

Notification binding controls currently stop before runtime: the unchanged
physical fixture contains two untyped `=` locals inside `do IO`. The raw
compiler failure is `/tmp/birc-bind-ctl-RED.raw.txt` (`eba5e1a8…`). A narrow
typed-`IO.pure` repair is reviewed and released; no runtime RED/GREEN is claimed.

Four further fixture corrections are now explicitly approved:

- [ ] Change only the two S1S5 Session PONG expectations to no Session output;
  keep buffer-limit checks and require exact-one-PONG socket witnesses.
- [ ] Keep the archive-only wire2 setup and add a mixed live/imported-row
  witness: the real JOIN stays unclaimed and is saved; archive rows are excluded.
- [x] Correct only Carrier `parked-prefs` ownership for the disabled worker
  and absent server; preserve other leases and add retired/retained controls.
- [x] Add the real visible-media observation stage to G3 media setup; preserve
  all 45 checks and add byte-feed-only and disabled-preview controls.

The current MODE framed target passes (`/tmp/birc-g3framed.raw.txt`,
`40decb83…`). The added media controls pass before the older image scheduling
assertion fails (`/tmp/birc-g3trav-char.raw.txt`, `a28e03b3…`). The approved
setup repair then passes `make test-g3-traversal` with all 45 existing checks
and three new controls (`/tmp/birc-g3trav-repair.raw.txt`, `51a2afb4…`).
Its final fixture is `1d8f3490…`. Byte feeding alone does not enqueue images;
live Net and WsNet separately call `Session.session_observe_visible_media`.

The single diagnostic localizes unfinished checking to
`LAWS.workspace_parts_isolate_state`; it does not identify a costly subexpression.
A minimal DRY proposal shares one `step_keys` result in `Workspace.isolation_ok`.
Its six characterization guards must pass before and after the change, followed
by the original workspace target and one bounded changed-source stock proof.
No performance benefit or proof verdict is claimed before those results.
The first characterization attempt fails at compilation, not runtime
(`/tmp/birc-isolstep-base.raw.txt`, `baac6395…`): the builtin product has `Type`,
so `+trip` is invalid although each field is `Data`. That invalid production
proposal (`eb693b05…`) is withdrawn. The corrected one-use parameter match
passes all six controls before and after its application (both raw logs
`4390db8b…`); fixture `3b778417…`, production `44cc1045…`. The original native
workspace target reaches its compiler-command timeout with no runtime verdict.
This remains an open gate, not a proven regression or performance finding.
The changed-source stock proof also reaches its bound without a verdict
(`/tmp/birc-stockproof.raw.txt`, `16355b51…`). Its fixed 53-file before/after
manifests are identical (`881339ba…`), and all ten stock-tool checks pass
(`11c24a7a…`). Native and full-check qualification remain required. Do not
repeat an unchanged proof or infer a timeout cause from host load.
The receipt is `/tmp/birc-stockproof.receipt.txt` (`4653388b…`):
2026-10-07T00:13:25Z–00:23:17Z, outer exit 124.

The approved help correction passes `make test-args`
(`/tmp/birc-args.raw.txt`, `1952b6a5…`). `make test-auth-profile` also passes
(`/tmp/birc-authprof.raw.txt`, `a9afd4f6…`), but `test-reconnect-endpoint` reaches
its native compiler-command timeout before any runtime verdict. Its cause is
unknown; the auth-profile pass does not qualify reconnect recovery.
The approved actor capability correction passes `make test-actor-queue`,
including all nine queue/drop cases and the redial FIFO case
(`/tmp/birc-actor.raw.txt`, `d81d1ed3…`).
The added source/recipient guard passes `make test-workspace-005-source`
(`/tmp/birc-ws005.raw.txt`, `280b03cc…`). The corrected original workspace
fixture (`56e35d91…`) still has only a compiler-command timeout receipt
(`/tmp/birc-workspace.raw.txt`, `06f8ebba…`); its correction group is not yet
qualified as a whole.

The binding fixture has four additional reused `+` product results in its
physical block. A separate syntax-only adapter repair is reviewed and released
after the two typed-local fixes (`911be90d…`, resulting fixture `23ae2d03…`).
Preserve the 92 old checks, eight added controls,
received completion identities and helper ordering; do not run the known-invalid
fixture again or claim a runtime RED from a compiler error.

Notification attribution now has genuine runtime RED at the joined-B premise
(`/tmp/birc-attr-RED.raw.txt`, `9609e838…`). The approved framed self-JOIN then
passes all 56 existing assertions and four controls
(`/tmp/birc-attr-GREEN.raw.txt`, `48dc8ab0…`; fixture `4fb4a773…`). The corrected
static pin also passes (`/tmp/birc-followstatic.raw.txt`, `5db3c93f…`). The pure
follow-up guard passes too (`/tmp/birc-followguards.raw.txt`, `14a07145…`). All
three gates are GREEN; their approved promotion is released. A fresh
post-promotion static pass also succeeds
(`/tmp/birc-followstatic-post.raw.txt`, `789d349f…`). The exact three
`test-review-pure` edges are registered; the final static oracle is `8898be6b…`.

Two independent source reviews find a concrete normalization risk: the stock
checker represents `Nat` with unary successors, and `Nat.cmp` consumes both
prefixes one successor at a time. Workspace slot 1 seeds its sequence at
`2^44`; `fx_rooms` already demands a large-prefix overflow comparison while
joining `#b`. The native backend instead has machine-number arithmetic.
This is a verified source distinction, not a final whole-proof timeout cause.
The narrow stock probes now complete: small accepted/rejected-input controls
pass in 760 ms; seed and ceiling WHNF controls pass in 335/396 ms. Both exact
large-prefix comparisons hit their independent ten-second bounds (TERM), with
no verdict. All 13 source/tool identities remain unchanged. The receipt is
`/tmp/birc-nat-results/receipt.json` (`3b62acdc…`) and invocation raw is
`/tmp/birc-nat.raw.txt` (`11857ea6…`). This confirms the isolated comparison
cost, not the whole law's attribution or a speedup. No probe retry is needed.
A semantics-preserving proof strategy remains open.
Do not lower ID ranges, truncate through U32 conversion,
bypass guards in fixtures, weaken laws, or add an independent proof kernel.
The independent source report is
`/tmp/birc-nat-guard-source.dKjg4rrt/REPORT.txt` (`f448ebd5…`). Neither subtraction
of the large prefix nor conversion to U32 is a safe small fix: subtraction
still walks unary values, and conversion also loses high ID bits.

The proposed native compile timer is rejected, not approved for execution.
Root and an independent source review found that its active owner starts after
setup, so it does not enforce the claimed end-to-end bound. Its final marker
also includes owner cleanup rather than ending at command exit. Its controls
do not cover setup or the actual two-layer cancellation path. The frozen
packet is `/tmp/birc-native-compile-timer-implementation.Gd6h2Nve`
(`observer.py` SHA256 `8ae1b8dd…`). No timer controls or diagnostic ran.
Any replacement must be smaller, retain stock deadlines and report truthful
coarse spans; it needs a separate source and ownership review before use.

An event-ID representation migration is not released as a small timeout fix.
The source-only feasibility report
`/tmp/birc-event-id-feasibility.mBzvsipB/REPORT.txt` (`914fc2a5…`) identifies
16 stored fields and at least 63 API boundaries. Two U32 limbs could preserve
native ID values, but not the current arbitrary-Nat source domain without an
explicit contract change. Exhaustion and public-constructor invariants also
need decisions. Constructive stock proof transport is the smaller next
alternative; its full Workspace derivation remains unqualified. No
representation, law, fixture or compiler change is admitted.

The 47-line arithmetic concept is now stock-qualified once:
`make -f /tmp/birc-stock-symbolic-qualification.D4pnFygo/Makefile check-symbolic`
runs in the locked Nix shell with a ten-second checker limit and returns
`ALL PROOFS CHECK`, exit zero. Its actual output is
`/tmp/birc-stock-symbolic-raw.txt` (`33426359…`); source `250a0da1…`, stock
tools and candidate Workspace/LAWS/PROOF remain unchanged. This qualifies
the constructive arithmetic helpers and two small accepted/rejected-input
goals only. The exact Workspace derivation and final proof remain open.
The next open guard theorem packet (`70fcfac2…`) hits its separate whole-Nix
ten-second limit with no theorem verdict
(`/tmp/birc-stock-routed-raw.txt`, `c158e1b7…`). Root released one new stock
180-second source-only book check with the same frozen goals and imports;
this changes no existing test, runtime, compiler or full-proof deadline.
The original ten-second recipe and source packet stay unchanged. Classify
the stock checker's global unsafe/foreign rejection separately from type
errors; it scans all imported non-Base definitions, not just these theorems.
The 180-second stock book check now stops with `SOME PROOFS FAIL` and
`the machine stack overflowed`, before a global unsafe/foreign verdict
(`/tmp/birc-stock-routed-book-raw.txt`, `fb109104…`). No theorem in that
packet is qualified. The ten-second timeout has no measured phase attribution.
On the user's new request, fresh independent proof, boundary-regression and
native-phase reviews run in parallel. A separate proof worker follows the
independent strategy review. Root coordinates integration; Main retains the
single heavyweight lane. Preserve complete laws, arbitrary-Nat behavior,
the `2^44` ranges, overflow guards and stock tools. No numeric migration is
released. Compare actual Workspace validation before claiming a speedup.
The fresh independent review (`/tmp/birc-proof-independent-review.txt`,
`118a4490…`) and distinct proof-worker report
(`/tmp/birc-proof-regressions.xIgszrnr/PROOF_WORKER_RESULT.txt`, `63312e48…`)
find no complete bridge to the unchanged nullary law. Rwt checks its outer
motive against that old endpoint before the rewritten body; a failed rigid
comparison can evaluate both original B JOIN guards first. Three additional
worker constructions (refutation, indexed trace and suspension) still require
the unproved original-to-result equation. Epoch reuse also needs a
`nat_max(base, base)` boundary proof and its actual transition transport.
This is a finite failed strategy, not an impossibility theorem or a measured
full-timeout cause. Do not integrate helper-only proofs or change numeric
representation without a new decision. No after-performance result exists.
The unrun range-regression proposal initially included `2^100` JS checks.
Root rejected them: pinned `comp.ts` caps compiled Nat at `2^48-1`; the worker
removed those assertions. The remaining runtime proposal covers actual
`2^44` slices and below/at/above guards. Arbitrary-Nat behavior remains a
separate, unqualified formal obligation; no existing oracle was changed.

The fresh Astra review (`/tmp/birc-astra-proof-review-20261007.txt`,
`87dbf797…`) corrects two constraints: preserving the complete proposition
need not preserve its exact nullary spelling, and stock recursive conversion
does not retry the initial rigid shortcut. The copied timing trace used
Workspace `4fdac5be…`, not current `44cc1045…`; their exact diff preserves the
seeds and guards but consolidates the isolation step tuple. That trace is
not a current-source profile or a Nat-subphase measurement.

The approved current-source experiment now uses two separate stock entrypoints
from `/tmp/birc-current-proof-probes.pF3tOnRt/Makefile`, with default-off timing
committed first in the owned scratch repository (`master`, `cfbbded`). In one
locked Nix shell, `make -f …/Makefile proof-alias-control` passes stock
`--check-only` with `ALL PROOFS CHECK`, exit zero, real 5.882 seconds. Only then,
`make -f …/Makefile proof-alias-unfold` runs once and reaches its fixed ten-second
limit: timeout 124, make exit 2, real 10.143 seconds, no verdict. Raw evidence is
`/tmp/birc-proof-probes-raw.txt` (`5fa4af38…`). The enclosing shell exit zero
records collection, not unfolding success. The first process is cold and the
second is warm; do not subtract these times or claim a speedup or phase cause.
The actual alias/body conversion is costly at this bound, not proven impossible.

The regression review (`/tmp/birc-proof-regression-acceptance-20261007.txt`)
preserves A's JOIN guard, both B JOIN guards, exact Session/drafts handoff,
all three observations, strict ceiling rejection and arbitrary Nat. Astra
accepts the complete branch-preserving source catalogue (`c66dde7b…`) and
ledger (`1bae9935…`) in `/tmp/birc-isolation-expansion.3Harf4dG` as a source
re-expression, not a completed proof. Its review is
`/tmp/birc-case-b-source-review-20261007.txt` (`5f30adbe…`).
No candidate law, runtime range, guard, tool or numeric representation changed.
Full stock proof and complete `make check` remain open. No unchanged retry is
released by the two-probe result.

The next actual-AD selector packet now passes a separate stock check:
`make -f /tmp/birc-ad-join-selectors.kpX9M9rm/Makefile check-actual-ad-selectors`
returns `ALL PROOFS CHECK`, exit zero, real/user/system 6.323/7.131/0.721
seconds, within its fixed ten-second checker limit. The source (`3cf69876…`)
proves A's actual post-sequence is zero and both consecutive B post-sequences
equal arbitrary source Nat `q`. B uses A's actual resulting drafts; B2 consumes
B1's complete Session and drafts, then reconstructs AD with the exact server
ID as Workspace does. Original initialization-before-seeding and all actual
Session/AD calls remain. Raw is `/tmp/birc-ad-selectors-raw.txt` (`f7c37b18…`);
the five direct dependencies and candidate Workspace/LAWS/PROOF stay unchanged.
Default-off timing was committed first in the owned scratch repository
(`master`, `0def385`, Makefile only).

These are qualified partial selector proofs, not complete Workspace admission
or isolation. The actual tuple/sequence guard context still needs dependent
elimination, followed by the original seed-floor/range inequalities, all three
admitted Workspace transitions and the three final observations. A's and B1's
AD outputs are only the prospective admitted paths until those guards are
proved false. Do not assume those paths, copy an affine tuple, rename a nullary
predicate as a fix, or claim a whole-proof speedup from the partial check.

The actual route-product transport candidate is not yet qualified. Its first
stock check stopped at a dotted scratch-directory import (`7f36171b…`;
`/tmp/birc-ad-route-raw.txt`, `0e64620c…`), before checking the derivation.
The import-only correction uses a regular local selector copy with the exact
qualified bytes (`3cf69876…`). A symlink would not fix this: the stock loader
validates the canonical realpath namespace too. The corrected source
(`13b9114b…`) then reaches a named type error in `route.guarded`: expected an
annotated term, observed `_ => Bool` in Base's `Pair` motive. It fails in
7.379 seconds, checker exit one / Make exit two, not a timeout. Raw is
`/tmp/birc-ad-route-corrected-raw.txt` (`9d192111…`); imports, laws and candidate
source stay unchanged. Astra and the worker traced the error to promotion of
the third dependent product field. The minimal source repair keeps `+ad` but
uses plain `cmd` and `halt`, which each have one live use. That repair and the
complete open-ceiling expression were source-only at that point; the complete
qualification below includes the repaired route.

The complete case-B packet now passes the pinned stock checker:
`make -f /tmp/birc-complete-caseb-Pk4bINOP/Makefile check-complete-case-b`
prints `ALL PROOFS CHECK` with exit zero in 24.341/25.481/1.418 seconds
real/user/system, within its fixed 180-second limit. Raw is
`/tmp/birc-complete-case-b-raw.txt` (`115776f3…`). Its four sources are
`full_case_b.bend` (`8a0b2aed…`), repaired `route_bridge.bend` (`414eb0b7…`),
the exact selectors (`3cf69876…`) and arithmetic (`250a0da1…`); its complete
equivalence ledger is `5d423a99…`. Astra and the independent reviewer read
all source and accepted the complete original-fixture mapping. All three
guards and rollback payloads remain in the proposition. The proof derives
original floor/range inequalities, actual Session/drafts and lookup handoffs,
and all three original observations, with no unproved final-law premise.
The actual literal endpoint avoids the old nullary conversion seam. Runtime
Workspace, ranges, ceilings and all candidate laws are still unchanged.
Default-off timing was committed first in the owned scratch repository
(`master`, `6f2db98`, Makefile only). This qualifies the complete isolated
packet, not the full project proof book, regressions, kernel or a speedup.
The earlier broad equality-transport obstruction is no longer supported for
this isolation case: complete checked integration works after an equivalent
expression change. The measured old alias seam does not justify event-ID
redesign. Other Workspace laws and native phases still need their own evidence.
There are 535 root law declarations; the earlier 53-entry manifest is a watched
subset, not the entire book. Import-mapped repository integration and the full
stock book still require separate verification.

The exact reviewed integration patch (`c75334b2…`) is now applied only in
`/tmp/birc-final-candidate`. It adds four regular proof-only modules, maps
the one existing isolation law to the qualified literal endpoint, and adds
four production JOIN boundary checks. Runtime Workspace remains `44cc1045…`;
all 535 root law names retain their identical hash (`dbf93905…`). No old
assertion or test oracle changed. The user worktree and index remain protected.
Default-off mapped-gate timing was committed first in the owned scratch
repository (`master`, `1a47e20`, Makefile `949cd312…`). The existing project
Makefile owns both the regression and the full proof commands. Mapped
regressions run first; the complete stock book still needs its own verdict.

The expanded isolation regression did not reach runtime. Its unchanged
180-second Bend-to-JS limit expired (`timeout` 124, Make 2); the measured
whole gate was 181.267/97.433/319.517 seconds real/user/system. Raw is
`/tmp/birc-mapped-isolation-raw.txt` (`31d6614d…`). All mapped sources,
535 law names and candidate status remained unchanged. This is no assertion
verdict and does not identify a compiler subphase or root cause. Do not rerun
it unchanged, increase its deadline, remove the boundary tests, or change an
oracle. The separately meaningful full mapped stock book is released once
at its existing approved 600-second proof bound, serialized without native
jobs. Regression validation remains open regardless of that proof result.

The full mapped stock book also reaches its fixed 600-second limit without
a checker verdict: `timeout` 124, Make 2, whole-gate real/user/system
601.498/338.792/788.824 seconds. Raw is
`/tmp/birc-mapped-stockproof-raw.txt` (`b5e848d1…`). Every mapped source,
all 535 law names and the candidate status remain unchanged. No failed
theorem or numeric subphase is identified. The complete isolated proof pass
does not resolve this full-book bottleneck, but its checked transport remains
valid for that case. No numeric representation change is selected. Complete
`make check` cannot be reported green while its proof prerequisite has no
verdict; an unchanged full-book retry would add no evidence.

The separate `sessws_s1s5_demo` RED has a verified dispatch cause:
production `Sess.step_keys` always used single-line submission, so
`Irc.strip_ctl` changed `aa\nbb` to `aabb`. Main and Astra source-accepted
the unapplied repair `bc7f7ad3…` in
`/tmp/birc-session-multiline-fix-OgIpWzmX`. It routes ordinary multiline
Enter through existing Session policy and removes AD's duplicate bypass.
One shared `keys_without_enter` also replaces the duplicate upload transform.
Rejected slash-led blocks cannot halt or trigger command hooks. All 473 old
assertions remain; 15 are additive. This patch is held until the frozen proof
job ends. Session/AD changes need fresh runtime and full-proof qualification;
neither source review nor an earlier dependency pass replaces those gates.
After the bounded full-book job and its children ended, Main applied the exact
reviewed multiline patch only in the candidate. Its new Session/AD/test hashes
are `476ca9bc…` / `6ff1ea4a…` / `6bcfb107…`; Workspace, LAWS and PROOF bytes
remain unchanged. The next bounded runtime gate runs all 488 assertions on
this new dependency snapshot. No root source or index change is promoted.
That runtime gate now passes: `test-sessws-s1s5` compiles with its unchanged
180-second bound and prints `sessws_s1s5_demo=ok`; all 488 assertions run.
Whole-gate real/user/system times are 5.264/9.138/0.867 seconds, Make zero.
Raw is `/tmp/birc-multiline-v2-raw.txt` (`6abc3a97…`), with stable source/status
receipts. Default-off timing was committed first (`668a562`, driver
`454fd58a…`). This fixes the observed multiline defect, not the remaining
proof or native bottlenecks. Isolation requalification on the changed
Session/AD is released separately at the same compile/runtime bounds.

The next stock-profiler seam has bounded source-reviewed controls only:
`/tmp/birc-stock-bun-profile.4vnM5wqd`, instrumentation commit `d989bc4`.
It keeps the pinned stock Bend/Bun wrapper and uses default-off host profiling.
A normal help control tests flag transport; a real synchronous finite busy
loop tests SIGTERM finalization at two seconds, without a signal handler.
Only safe owned, bounded JSON with busy-function samples can pass. Missing,
partial or unsafe output, unsupported data, or kill exit 137 blocks heavy
profiling. Bun documentation does not establish that SIGTERM behavior.
Controls are released only after the current regression job ends; no real
profile, changed signal/deadline, or new checker implementation is released.
These controls now establish a limit of that profiling seam. Help completes
normally and writes valid private JSON (228 bytes, one node, zero samples).
The real CPU-busy loop receives SIGTERM at two seconds and returns the
expected raw timeout 124, but writes no profile. The read-only validator
correctly fails; overall Make is two. Raw is
`/tmp/birc-bun-profile-controls-raw.txt` (`753ff5f5…`). No long profiling job
is released. Existing control sources, signals and bounds remain unchanged;
a different interrupt control would need its own explicit review and result.
The new-dependency isolation gate separately times out at its unchanged
180-second compile bound (180.732/95.629/302.991 seconds real/user/system,
Make two), with no runtime or named-error verdict. Raw is
`/tmp/birc-mapped-isolation-v2-raw.txt` (`f7235545…`). The 488-assertion runtime
pass stands, but it does not resolve this distinct compiler gate.

The separately reviewed SIGINT control also fails to produce a profile.
Its instrumentation-only scratch commit is `0c30326`; the unchanged finite
busy loop returns raw timeout 124 after 2.013/1.898/0.039 seconds
real/user/system, then the validator and Make return two because the private
profile is absent, including no symlink. Raw is
`/tmp/birc-bun-sigint-control-raw.txt` (`c20d5294…`). Both tested signal
controllers are therefore unqualified for heavy profiling. Stop this avenue;
do not add a handler, change the stock tools or silently reuse either signal
for a full proof. This finite result does not establish that profiling is
impossible or identify the proof bottleneck. The next source-only proposal
checks the complete mapped isolation proposition against the new dependencies,
with canonical imports and exact law/proof extraction, not a helper-only test.
That current-dependency slice now passes the stock checker once:
`make -f /tmp/birc-current-isolation-slice.MQZbMKei/Makefile
BIRC_CURRENT_ISOLATION_SLICE=1 BIRC_BUILD_PHASE_PROFILE=1 check-isolation-slice`
prints `ALL PROOFS CHECK`, Make zero, in 12.832/13.932/0.553 seconds
real/user/system, within its fixed 60-second limit. Instrumentation-only
scratch commit `5800140` precedes the run. The complete law and actual proof
call match current LAWS/PROOF byte-for-byte; canonical imports and the full
local Bend manifest are guarded. Raw is
`/tmp/birc-current-isolation-slice-raw.txt` (`76be29a6…`). All three reviewers
accepted the source; inputs and candidate status remained stable. This
qualifies the complete mapped isolation proposition and its loaded closure
on Session `476ca9bc…` and AD `6ff1ea4a…`, not all 535 laws, runtime boundary
checks, native builds or an independent kernel. No before/after speedup can
be inferred from the separately cold/warm 24.341-second old-dependency run.
After that pass, Astra source-accepts one canonical current-snapshot
`make -j1 check PROOF_TIMEOUT=600`. This is the first full-book validation
after the real Session/AD change, not an unchanged retry or a predicted
performance fix. Default-off timing is committed first in the owned scratch
repository (`d40bad2`, driver `9fad376a…`); the driver guards the current
snapshot/manifest and applies a separate 1800-second aggregate limit with
five-second cleanup. The controlled locked-shell launcher clears inherited
Make flags; all original per-target deadlines remain unchanged except the
previously approved 600-second proof budget. The proof prerequisite runs
first. A proof failure stops the check; standalone isolation, Session,
upload-frame and carrier gates retain their separate qualification status.
This current canonical check now fails at its proof prerequisite: `timeout`
124, Make two, with no checker verdict or named law. The whole timed check
is 601.480/257.580/894.366 seconds real/user/system. Raw is
`/tmp/birc-current-canonical-check-raw.txt`; Bend/test/FFI/UI/pin/law digests,
all 535 law names and candidate status stay unchanged. No project test, lint
or paste-harness pass is implied; Make stopped before them. The owned proof
children have exited. Do not retry this snapshot unchanged or infer a Nat
subphase, a speedup, or a failed theorem from the timeout. The next admissible
proof diagnosis preserves complete original law/proof pairs in one small,
separately reviewed domain group; no automatic sweep or numeric migration.

The first such group now reaches its fixed 60-second bound without a verdict:
`make -f /tmp/birc-generation-slice.X4qOvdRA/Makefile BIRC_CURRENT_GENERATION_SLICE=1 BIRC_BUILD_PHASE_PROFILE=1 check-generation-slice`.
Both original generation and epoch-reuse law/proof pairs remain complete;
only the proof definition headers drop `Laws.` for the standalone book.
Instrumentation commit `83b7ec6` precedes the one run. Raw timeout 124 propagates
to Make/Nix two; the phase is 60.576/56.238/88.982 seconds real/user/system.
Raw is `/tmp/birc-current-generation-slice-raw.txt` (`c0e50ce6…`, 29 lines).
All pinned inputs, the full Bend manifest, 535 law headers and candidate status
remain unchanged. There is no checker output, named failure or qualification
for either law. This does not show that Workspace caused the full-book timeout.
No unchanged retry follows. Astra recommends one complete generation law as
the next smaller discriminator, not a disjoint coverage group. It needs its
own source review and release. A pass would qualify that law alone, not prove
that the other law fails alone or explain the full-book timeout.

That smaller discriminator now passes: `make -f /tmp/birc-generation-single-slice.Dhz7GBWP/Makefile BIRC_CURRENT_GENERATION_SINGLE_SLICE=1 BIRC_BUILD_PHASE_PROFILE=1 check-generation-single-slice`.
The complete original `workspace_generations_drop_stale` pair, its nullary
endpoint and all predicate checks are unchanged. Instrumentation commit
`72c2313` precedes the run. Stock `--check-only` reports `ALL PROOFS CHECK`;
the phase is 1.627/2.503/0.324 seconds real/user/system, runner zero. Raw is
`/tmp/birc-current-generation-single-slice-raw.txt` (`c7113cf8…`, 30 lines).
All 15 pinned inputs remain intact and owned children have exited. This
qualifies only that complete law on the frozen current dependency closure.
The pair's timeout does not prove epoch fails alone; the next discriminator
requires a separately reviewed complete epoch law, with no timing subtraction.

The complete epoch-only discriminator now reaches its own unchanged 60-second
bound: `make -f /tmp/birc-epoch-single-slice.VXOdKuK3/Makefile BIRC_CURRENT_EPOCH_SINGLE_SLICE=1 BIRC_BUILD_PHASE_PROFILE=1 check-epoch-single-slice`.
Instrumentation commit `2b73e4e` precedes the run. Original LAWS/PROOF excerpts,
both remove/re-add scenarios and all observations remain intact. Timeout 124
propagates to Make/Nix two; the phase is 60.504/57.716/85.285 seconds
real/user/system. Raw is `/tmp/birc-current-epoch-single-slice-raw.txt`
(`f6abe8f2…`, 29 lines). All 15 pinned inputs remain intact and owned children
have exited. There is no checker output or named error. This directly records
an unqualified complete epoch slice and its closure; it does not distinguish
conversion from loading or name the full-book cause. No repeat or numeric
migration follows from this result.

Astra's final source-only recommendation is a complete proof-facing epoch
factorization with the initial B seed and selected ceiling open. Keep both
scenarios and all 12 conjuncts. Derive the first actual Online `/connect` AD
tuple and its strict-cap admission; keep that exact Workspace, drafts and retired
mark through removal/re-addition. The final `/connect` runs on the re-added
Connecting Session and returns the busy diagnostic plus `Cont`, not another
Dial. Its generation increase comes from retirement/re-addition. Endpoint
replacement also preserves the actual sequence; do not reconstruct it as zero.
The metadata observations may remain invariant across both original overflow
branches, which could avoid an unnecessary acceptance proof or concrete maximum
reduction. A Boolean-case lemma for `nat_max.pick(c, q, q) == q` is another
source-level avenue if maximum idempotence is needed. These are unqualified
proposals, not accepted connected proofs or measured Nat-cause findings. Exact
goal/motive alignment, stock checking of the full proposition and runtime
boundary qualification remain required before integration or a redesign.

The focused regression gate is
`/tmp/birc-proof-integration-regression-gate-20261007.txt`. Its unrun additive
draft (`/tmp/birc-workspace-join-boundary-regressions.bend`, `9c9bd97e…`) covers
actual nonallocating JOIN at base and ceiling minus one, and rollback at the
exact ceiling and above it with distinguishable original drafts. Preserve the
six existing isolation checks and all original range/retirement expectations.
The targeted Workspace checks are standalone; `make check` does not imply
that they ran. No test expectations changed in this investigation.

Separate native investigation now has a 30-line standard Bash-time driver
(`/tmp/birc-native-front-end.m9vRi4R8/Makefile`, `cd6fa2aa…`). It is independently
source-reviewed, default-off and opt-in; it preserves the original native
fixture and adds only `-fsyntax-only` in a separate 300-second diagnostic on
the exact retained upload C. Status controls with timing off pass
(`43d470c2…`); timing-on and missing-opt-in invocations reach their enclosing
Nix60 bounds without control output (`57fbc997…`, `733e7b9b…`). No compiler
diagnostic ran. One combined locked-shell control invocation is released
with a separate 180-second provisioning bound; all command and existing
proof/runtime deadlines stay fixed. No custom timer or native subphase
attribution is admitted.
The combined control invocation now passes all statuses and timing-marker
checks (`/tmp/birc-front-end-combined-raw.txt`, `6abd2562…`). It measures 70
seconds overall and 2 seconds between in-shell markers; do not attribute a
Nix subphase from those coarse spans. The instrumentation alone is committed
in the owned scratch repository (`master`, `4dd958234444bccb4e56dbb4b61471fae18af9e1`),
not in Root or the candidate. The bare shell `CC=clang` resolves to the pinned
wrapper but fails the driver's literal guard; the diagnostic explicitly sets
the same absolute wrapper path inside the locked shell.
The single syntax-only diagnostic then exits zero
(`/tmp/birc-upload-frontend-syntax-raw.txt`, `9d2cbfcf…`): measured invocation
real/user/system times are 25.807/23.255/0.911 seconds; whole invocation is
97 seconds. This qualifies preprocessing, parsing and semantic analysis of
the exact retained C and current headers in that diagnostic only. It does not
retroactively identify the full CC300 timeout, qualify optimization/linking,
create a binary or pass a native/terminal fixture. The generated C, driver,
candidate Make/Workspace/LAWS/PROOF and project headers remain unchanged.
Its before-provenance timeout/Bash/OpenSSL paths are outside-Nix resolutions,
not captured in-shell tool/header identities. The actual CC guard proves the
absolute pinned compiler path; do not claim stronger provenance than recorded.
No proof integration or after-proof performance result exists. The full
proof and `make check` remain open; heavy jobs are held after this receipt.

A separate, source-reviewed IR-generation diagnostic is now released once,
serialized after the route check. Its 18-line default-off driver is
`/tmp/birc-native-irgen.qjW53gjb/Makefile` (`2656452d…`), instrumentation-only
scratch commits `d32eb30` and `fb03565`. It preserves the exact retained C,
compiler, flags and ten aliases, with a fixed 300-second limit. It adds
`-S -emit-llvm -Xclang -disable-llvm-passes` and writes only an owned scratch
text-IR file; existing output and dangling links are refused. It measures the
combined front end, IR generation and serialization without LLVM passes.
Neither success nor timeout can establish the prior full-compile cause,
qualify a native fixture, or explain Nat proof costs.
The first runner's controls returned 0/2/2/0, but it printed those statuses
without assigning its gate variables. Nix also reset its inherited CC. It
did not run the compiler (`/tmp/birc-upload-irgen-raw.txt`, `8512c155…`).
The independently reviewed corrected harness (`9bc3974d…`) records statuses,
uses a pinned Make `CC` argument inside the shell, and returns the real status.
Its single real IR-generation diagnostic passes in 63.707/42.626/8.198 seconds
real/user/system, producing an 882,172,707-byte scratch text IR (`b0e9f232…`).
Raw is `/tmp/birc-upload-irgen-corrected-raw.txt` (`3d36162e…`); all pinned
inputs and candidate laws remain unchanged. This is only a combined front-end,
IR-generation and serialization result with LLVM passes suppressed. It does
not identify the earlier CC300 timeout, qualify optimization/linking or produce
a runnable binary. No cold/warm subtraction or proof-cause claim is justified.

The separate LLVM optimizer diagnostic also completes on that exact retained
C, with the original pinned compiler, O2 flags and ten aliases. Its default-off
instrumentation commit is `f1b94db`; source-reviewed `EmitLLVMOnly` enables LLVM
optimization but discards output before IR serialization, machine-code
generation and linking. `diagnose-upload-optnull` returns compiler/Make zero
in 49.878/46.324/3.070 seconds real/user/system, with the reserved output
absent, including no symlink. Raw is `/tmp/birc-upload-optnull-raw.txt`
(`1e83c28d…`). Clang's measured wall-clock split in this run is optimizer
37.9245 seconds, front end 7.0495 seconds and IR generation 4.5846 seconds;
the top pass is DeadArgumentElimination at 5.6865 seconds. Inputs, headers,
535 law names and candidate status remain stable. This measures only that
diagnostic path on the old generated fixture snapshot. It does not identify
the earlier normal CC300 timeout, qualify a current native fixture, explain
proof costs or justify subtraction of separately cold/warm measurements.

The separately reviewed compile-to-object diagnostic now passes on that retained
C. Instrumentation-only scratch commit `83f2640` precedes the one bounded run:
`make -f /tmp/birc-native-object.MADHUrIe/Makefile CC=/nix/store/2yfrcmkvspsrjhj283gdawqp37aghxva-clang-wrapper-21.1.8/bin/clang BUILD_TIMEOUT=300 BIRC_NATIVE_OBJECT_DIAGNOSTIC=1 BIRC_BUILD_PHASE_PROFILE=1 diagnose-upload-object`.
The original O2 flags, ten aliases, compiler and inputs remain unchanged;
`-c -ftime-report=per-pass` measures this separate path without linking.
Compiler and runner return zero in 127.988/116.918/10.560 seconds
real/user/system. Clang's wall split is machine-code generation 77.5568 seconds,
optimizer 38.6357, front end 7.1935 and IR generation 4.2832 (total 127.6693).
Nested pass reports are not additional phase costs. Raw is
`/tmp/birc-upload-object-raw.txt` (`2a030b34…`, 429 lines). The owned regular
0600, single-link object is retained at `/tmp/birc-native-object.MADHUrIe/upload.o`
(13,889,672 bytes, `43bfa49d…`); no automatic link, run or deletion follows.
Pinned inputs, candidate status and root source/index protection hashes remain
unchanged. This qualifies only object production from the old generated C.
It neither explains the earlier CC300 timeout nor qualifies a current fixture,
proof optimization or a before/after speedup.

The native source reviewer confirms that the original driver produced an
executable, while this diagnostic uses `-c`. The pinned Nix Clang wrapper adds
`NIX_CFLAGS_LINK` and linker flags only in linking mode. Thus identical C and
explicit O2 flags do not establish identical effective compilation actions.
Actual linking, library resolution, executable writing and the current-source
PTY fixture remain unmeasured. Any link-only follow-up must be separately
reviewed and bounded; it must not overwrite or run the project executable.

Native link-source packet `4d4976d` passes its separately released tiny controls
(exact 0/2/2/2/0 and all refusal diagnostics; raw `/tmp/birc-link-controls-raw.txt`,
`f15bb244…`, 168 lines). Its metadata-only stock `-###` pass records one planned
pinned linker job, no compiler/assembler job and no executed linker. Driver zero
and read-only validation pass in 0.163/0.022/0.036 seconds real/user/system.
Raw is `/tmp/birc-link-metadata-raw.txt` (`52d36fc2…`, 93 lines); private metadata
is `/tmp/birc-native-link.8B6aAhHE/link.metadata.txt` (`a0a5bd05…`, 8 lines).
No executable is created. This is Clang's plan, not final linker-wrapper argument
expansion or library resolution.

The runner's extra environment gate is not qualified: it contains an invalid
indirect expansion and masks the random-seed value rather than requiring strict
equality. Main's independent unmasked comparison confirms the recorded 15-channel
subset matches, but some extended BEFORE/AFTER names use the wrong suffix order
and omit actual linker channels. This is not complete environment provenance.
All evidence remains intact. Do not reuse the gate or release a real link until
a small strict, source-reviewed environment check captures the actual channels.

The strict PONG witness now has a reviewed additive guard requiring exactly one
`PONG :fresh-gen` CRLF line in the full socket capture through EOF. It preserves
all 29 original checks and deadlines and adds malformed/extra-reply controls.
Its final source is `96be9273…`; self-test and three current-build PTY runs are
released but unqualified. The original five-second substring wait is unchanged;
do not claim that the CRLF terminator itself is checked within that deadline.

### Remaining test composition

The reviewed theme-render witness passes its standalone target. The initial
source inventory identified twelve donor target definitions absent at that time:
`test-isupport`, `test-cards-live`, `test-sessws-s1s5`,
`test-history-ceiling-drain`, `test-history-runtime`, `test-history-wire2`,
`test-i2-h5-combined`, `test-mss-stale-held`, `test-nix-eval-selftest`,
`test-pty-ponggen`, `test-pty-net-trace`, `test-ws-media-stage-native`.
Their exact source/recipe/coverage inventory is saved at
`/tmp/birc-theme-ws-render-slice.BVU6KG19/INVENTORY.txt`. This is a literal
target inventory, not a complete evaluated dependency graph or overlay approval.
Each needs narrow source review, admission and qualification. Existing standalone
greens also still need coherent aggregate registration. No full-check pass is
claimed from the selected suites.
The media-import companion and standalone media-stage sources are now admitted.
`make test-ws-media-stage-native` exits zero, but its delivered output is partial
(`/tmp/birc-ws-media-stage-orig-partial-raw.txt`, `258d1c75…`). A bounded
runtime-only rerun on the exact newly built binary (`b33631c4…`) passes all
four headless cases: free, blocked, jobs-none and jobs-some. Its saved output is
`/tmp/birc-ws-media-stage-verify-raw.txt` (`26249999…`). The original compile
and runtime deadlines are unchanged; no compiler replay or PTY run is claimed.
The stale-socket sources and standalone recipe are also admitted, but the
original `make test-mss-stale-held` reaches its Bend-to-C 300-second limit
(`/tmp/birc-mss-stale-held-raw.txt`, `d8f8da5a…`; make exit 2, command 124).
No C file, CC phase or runtime verdict exists. Hold that lane and continue
independent gates; neither its timeout cause nor a passing stale-socket test
is established.
One separately bounded stock `--check-only` invocation on that unchanged
MSS fixture reaches the expected global unsafe/foreign rejection after book
loading and type validation (`/tmp/birc-mss-checkonly-raw.txt`, `fb769d15…`).
No C emission or runtime occurs. This establishes validation completion in
that diagnostic run only; it does not locate the original timeout or pass
the stale-socket runtime gate.
The S1S5 fixture reaches a stale, nonexhaustive `dial_show` match at line 192:
the current NetCmd type also has `Pong` and `Search` cases
(`/tmp/birc-sessws-s1s5-raw.txt`, `9b5f9f01…`). This is a compilation failure,
not runtime RED. A narrow fixture-inspector repair is being prepared; keep
all 469 checks and the two explicitly approved PONG expectations unchanged.
The reviewed inspector repair (`fe508602…`, fixture `40d848cb…`) preserves
those 469 checks and adds four controls, but the next compile stops at
`frame_trip_halt` with an unannotated product-type inference error
(`/tmp/birc-sessws-s1s5-repair-raw.txt`, `fa72d737…`). It still has no runtime
verdict. A separate syntax-only repair is being investigated.
The reviewed one-character follow-up (`168799f2…`, post `ca104db7…`) removes
only the unnecessary `+` from the one-use `halt` projection. All 473 checks,
inputs and golden text remain byte-identical. It is released for the original
JS180/Bun30 target; no further expectation change is authorized.
That follow-up compiles, then fails at `s2p production multiline outs fifo`:
the direct Session seam emits `PRIVMSG #b :aabb`, while the fixture expects
two multiline rows (`/tmp/birc-sessws-s1s5-followup-raw.txt`, `591c133f…`).
The independent source review finds a single-input/multiline-adapter setup
mismatch, not a demonstrated FIFO defect. Keep all 473 checks unchanged
until the actual production seam and a narrow setup correction are reviewed.
The separate upload fixture emits 35,061,000 bytes of C (`02ee3a59…`), then
reaches its downstream CC300 bound without a binary or terminal run
(`/tmp/birc-ws-upload-frame-raw.txt`, `35e9eb2f…`). Do not attribute its
compiler-driver timeout to proof normalization or a measured optimizer phase.
Carrier now passes all three consecutive terminal runs after one build,
including its approved owner and fixed-prefix corrections
(`/tmp/birc-ws-carrier-native-raw.txt`, `eff36333…`; binary `1272fbfd…`).
Its final Bend fixture is `72a31c15…` (277 lines) and driver `89b6f126…`.
The earlier checkpoint token `27772a31` combined that line count and hash;
it was a note typo, not a changed source packet. Cards prefix qualification
and the other terminal suites remain open.
The admitted CAP target now passes all 25 existing assertions plus three phase
controls (`/tmp/birc-cap.raw.txt`, `d8e849a2…`; fixture `1a3e0c53…`). The
Cards live target also passes its 201 checks (`/tmp/birc-cardslive.raw.txt`,
`d8b9c9b7…`; exact fixture `411b789a…`). Its aggregate edge remains held with
the other uncomposed groups.

An evaluated dependency review extends that literal inventory. Its conditional
composition preserves all Root and candidate edges and reaches 43 scoped targets
from `check`. Additional Cards, Carrier, upload and notification definitions need
separate admission; the literal twelve are not the full closure. Two proposed
Cards tests share native build outputs, so they need one common build prerequisite
before concurrent registration. A donor-only `nix/cards.nix` build-input edge is
not a verified invalidation defect: the helper is selected at runtime and Nix
already includes its derivation. Do not add that edge merely to match the donor.

The narrowly admitted `make test-nix-eval-selftest` passes all six controls
(`/tmp/birc-nixself.raw.txt`, `4cb11421…`). It is not a live Nix timing result.
The remaining scoped source/recipe packets are reviewed and queued; their
aggregate registrations remain held until their exact standalone tests pass.

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
  helpers) are UNQUALIFIED until a green proof-600; cause unverified.
  Diagnosis: paired LAWS/PROOF C8-only partition (14 laws, checker
  requires completeness — subset PROOF alone reports 375 TODOs);
  partition runs are diagnostic only, never qualification.
  Partition RESULT: C8-only 14 laws ALL CHECK in 29.5s real (user
  7.1s/sys 2.6s — starved, load ~44) — no C8 hang; full-set 600s
  timeout cause still unverified (no quiet-window evidence yet).
- C8-live2/39 SENT concrete correction: delete the 111-line duplicate
  links lexer, reuse accepted G3 `Ws.url_runs` + deps, adapt Cards +
  `Media.media_run_hit` to that API; no placeholder merge point.
- G3-traversal `c8c4035` ACCEPTED (30 guards: Fr->Session traversal
  for MODE/mention/KICK incl. SOH/color/reset pairs + live media
  pending/visible/job/open agreement). G3 line (9 commits
  `1cf9028..c8c4035`) queued for parent integration with proof-600
  after; freed slot held for follow-ups.
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
- Proof green on retry: `ALL PROOFS CHECK`, real 149s / user 83s (raw
  timings retained as facts). RETRACTED 2026-10-03: the claim that the
  earlier 180s timeout was pool-load-induced (load 44, real >> user) is
  NOT verified — load correlation is not established cause, and earlier
  trace/coalescing benefit claims are unmeasured until new per-ID
  evidence lands. Deadline unchanged; final proof runs on merged source
  via `make check PROOF_TIMEOUT=600`.
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

## Handoff qualification record (2026-10-03; do not restore withdrawn quals)

Current checklist (02:22 KST 2026-10-04; branch + HEAD provenance, no secrets;
parent HEAD `4b4cbef`; no push anywhere; lane work on branches only):

- G6 ACCEPTED source+focused-green, full proof pending: `g6-live` 5b6b2aa +
  `c378ed0`, `g6-repair` 4c73236 + `492fd17` (shared phase gate, Cont-only
  tick, `g6_live_demo=ok` parent-verified, single CAP-END owner, laws
  unweakened). Parent adds `test-g6-live` at integration. Session `reg`
  field — arity-merge with H5/I2.
- H5 `8a2c8da` REJECTED-complete; `h5-wire3/58` RUNNING (wire3 gates +
  cutoff/ticket/endpoint + endpoint-scoped case-sensitive seen retention
  across same-endpoint generations; stale-gen quiet). Kept positives:
  split-prepass removed/admitted rename only, nonzero unused exact search
  ticket/gen/endpoint, String.eq in-page dedup, peer server query, actual
  history-save claimed-ID exclusion (that exclusion does NOT qualify N9).
  UPDATE 03:07: `h5-wire3/58` GHOST (transcript terminally failed
  02:58:41 `log_error`, same signature as 51; last tools 02:57-02:58
  red-vs-now return prep; roster `running` stale). HEAD `c623c3f`
  behavioral red + 14 dirty files preserved in the retained worktree;
  all 8 queued gates (live-path, claimed drain, LAWS syntax, test
  flips, affine seam x3, cutoff, ticket, endpoint, seen) orphaned into
  a staged successor INITIAL prompt (original GATES 1-6 + all queues
  verbatim). UPDATE: successor `h5-successor/72` ACTIVE (complete
  INITIAL accepted: read-only port of `c623c3f`+14 dirty + G1-6 + all
  8 queues + preserved positives).
  UPDATE: `h5-third/78` RETURNED `h5-wire3c` `625f7df` (G1-G3).
  FINAL CRITICAL: Gate2 is TESTS ONLY — C/Python/HSIO/Session/Net
  byte-identical to `524b2af`. Actual C cap+1-EOF and Python
  SCAN_MAX+1-EOF success are STILL BUGS; HSIO :149/:169 real
  workers are still NOT the affine entry. The new tests call
  `Hs.search_loop` on `File` with supplied old `remaining` (the
  unused bounded Bend driver), not the actual production mutation.
  Do NOT accept cutoff as green-on-arrival. POSITIVE: exact-target
  source `5e763a9` with actual StepEnter stands; H/I lifecycle
  final soon. IMPLEMENTED main normal-turn (branch `h5-cutoff`,
  Muse owns, no second H5 owner): red `5820d4b` + green `8f493f4`
  (fstat snapshot + exact-size snapshot core in C
  `scan_snapshot` + Python `scan_fd`, killing the `cap+1` /
  `SCAN_MAX+1` over-reads; shrink -> TRUNCATED bit / exit 5 ->
  exact shared `scan_changed_text()` parity with the affine path;
  cursor/cap behavior preserved). SOURCE ACCEPT `8f493f4`
  (independent final verdict forthcoming). Verified light:
  `history_search_fd=ok` (s7 incl), `search_helper_cutoff=ok` +
  `search_helper_scan=ok`, `history_search_io=ok` (4 new pins),
  `history_search=ok`, `history_wire2=ok` via bun JS (never native
  compiled; zero heavy-lane use). IN FLIGHT: wrapper
  capture/mutation qual (interposed fstat/read/close around the
  real wrapper, per advice; no /proc, no threads, no prod hooks)
  + INDEPENDENT foreign-result restore (live-post pins through
  `search_run.post`, replacing the pre-port `Net.history_disk_search`
  assertion lost in `4d689a7`; mapping pins alone do NOT restore
  it; EISDIR prefix-pin weakener noted). Residual honest limits:
  scan-level shrink close-once is single-site structural (no
  deterministic trigger), foreign-OWNED bit unfabricable without
  privilege (parity pinned via other refusal bits + exact strings).
- N9 `5836ebb` helper-only ACCEPTED (HOLD: stage/order/laws, 3 suites
  parent-green). `n9-bind/52` returned `b8e6d52` REJECTED: R1 ticket
  across cancel (`Session:2652/2657/2668` clear active while detached
  `run_jobs_done` continues; `Net:1194->1199/1161` second worker); R2
  call-local claims `:434/435` not durable, `Net:1184` still Nil
  (archive may notify later); R3 refused/stale HistoryLoaded seeds floor
  `Net:1226/1253` after unchanged `PrefLive.history` (suppresses pending
  live rows); R4 `notify.py:36` bare notify-send unprovisioned, fake
  clean-PATH test proves forwarding only. Kept: actual retained Net
  loop, exact callback signatures (proof/old-focused green does not
  disprove the source cases). Fresh `n9-bind2/69` RUNNING with complete
  initial gates (G1-6 + R1-R4 + Q4 HOLD + real mixed claim producer +
  overflow->completion->no-new-IRC rescan guard; rescan qualification
  only, no permanent-loss defect claimed). CHECKPOINT 03:07: R1 commit
  `1032aa9` source-POSITIVE (scoped, not full qual): actual
  Net/NotifyIO retains original ticket+endpoint across reset/off/
  cancel, rejects wrong completion, rebinds queued work only on exact
  completion. Still required: owned held-helper physical concurrency
  test; Q4 six expectations stay held. R2 PRECISION (d20 grep):
  notify_claims_installed test-only (:395,410), no producer exists,
  no production install path; unconditional Net:1231 global seed via
  StartupIO:22-23 -> HistoryLoaded:1258-1261 -> install_startup:203
  masks runtime overflow. RETRACTED: 65-ID overflow demonstrated in
  production. CONFIRMED: overflow in the new claimed-policy seam on
  real imported clients (hist cap100 / SCROLL_CAP1024), leaks when
  bound unless fixed. Fix the NEW :995-998 drops-newest guard (not
  legacy Q4); need actual per-ID producer + safe bound/dedup + R3
  accepted-vs-refused floor jointly. CHECKPOINT 9e73971: stale/
  refused seeding FIXED (:81-82 + :1274-1277), producer genuinely
  called :1251; ACCEPTED mixed-backlog floor jump OPEN (:1240 +
  :2709->2697 whole-log_seq floor/mark + prune => live id9 skipped;
  needs per-ID quieting + rescan-delivery proof). CLAIM_CAP64/fresh-
  dup ledger still open (:442-456/:2582). CHECKPOINT 46771eb: R4
  default provenance FAILS (libnotify appended after PATH :10, bare
  notify-send :32-33, :105-110 asserts shadowing); needs absolute
  default backend + BIRC_NOTIFY_SEND injection + impostor/override
  pair (+ argv-boundary seam if convenient; $* logging unproven).
  Retained: birc:64 absolute helper, keychain launcher :66-69,
  redacted :80/160, direct argv, --, suppressed output, timeouts,
  Darwin osascript policy. All routed to 69; Q4 held.
  UPDATE: `n9-bind2/69` RETURNED `46771eb` PARTIAL; fresh
  `n9-bind3/77` ACTIVE. ROOT verdict on `e7635e7` (R2c) PARTIAL,
  gap survives `cb44639` R3d: Session:2587-2588 drops first
  qualifying IDs; Notify:461-462 evicts stored claims without
  at/below-floor proof; 65-row red test builds only 5 qualifying
  mentions (misses >64 capable rows) — after R3 preserves pending
  live9/floor8, 65 real imported mentions above old9 lose exclusion
  and a rescan can notify archive (global seed masks; no immediate-
  leak claim). Repair routed to 77: lossless floor-tied claims
  owner with proven exclusions, NOT keeps-newest truncation; bar is
  65 real qualifying mentions + pending lower-live all quiet,
  retained-live each notifies once; fresh-dup dedup positive kept;
  verify 1081-1088 false->true origin (preexisting user fixture =>
  HOLD for approval; candidate-side bad guard => fix correct
  policy); never claim unchanged. R3d live9-delivers kept.
  DELIVERY: first send (path target + interrupt) REJECTED
  `invalid_input`, never delivered; second send (documented UUID
  `01a1033d-…-2985cad`, queue) ACCEPTED receipt #1338
  (`01a1035a-9e43-…-84d`). Consumption UNVERIFIED: tip still
  `cb44639`, worker active with dirty held-helper files
  (`Makefile`, `tests/bend/notify_held.bend`). Bar restated:
  joint 65 qualifying mentions + pending live9 with no eviction,
  R4 absolute default, Q4 hold. If 77 returns before consuming,
  fire a fresh successor INITIAL (needs a freed slot).
  UPDATE: joint-R2 ACTUAL trace queued (#3, accepted
  `01a1035e-18fc-…-e52`): accepted LC.history preseq9 + 65
  peerHighlight archives IDs10..74 (+divider75), producer last64
  drops 10, Net:1240/1251 no floor jump, full8/busy completion
  rescan dispatches live9 AND unclaimed archive10 (HL author
  retained, no timestamp/visibility exclusion). Cap-test
  provenance VERIFIED and queued (#4, accepted
  `01a1035f-3cd7-…-696`): drops-newest added `d2b1d5c` in-lane,
  changed `ceebe5b`, root 4b4cbef has no notify_full file — NOT a
  preexisting user fixture, no approval hold; replace with genuine
  all-needed-claims safe joint guard. Fresh-dup union FIXED (no
  regress); R3 no-global-floor positive, R1 lease unchanged; Q4
  six held, R4 absolute-default bar unchanged. Consumption still
  enforced before DONE.
  UPDATE: `n9-bind3/77` RETURNED `7870db5` (R4 red `389ef4c` +
  fix committed; G1 qual claimed, G2/G3 as before). Queues #1/#3
  (joint-R2 lossless + 65-qualifying), #4 (cap provenance),
  #5 (R1 latch) ALL UNCONSUMED (verified at HEAD: keeps-newest
  stands, no latch). R4 `7870db5` SOURCE ACCEPT (absolute
  installed libnotify, direct argv; Linux closure qual pending).
  Fresh `n9-final/82` ACTIVE from `7870db5` with all gates
  (joint-R2 lossless + 65 real LC, R1 held latch + received
  completion + wrong-origin, R4 verify, in-lane cap-policy
  correction, Q4 six held). Never queue to dead 77.
- MSS multiline commit `653da6fe` source-POSITIVE (scoped, not full
  qual): actual Session.step_keys, atomic no-wire + no Hist/recall for
  sensitive pasted command blocks, 15 new assertions, old expectations
  unchanged. Classifier still fixed, not negotiated; merged I2
  classifier + custom-target privacy guards remain required.
  CHECKPOINT f6a1cea: WsNet global bell-seq threading positive;
  per-part opt-out defect open (mismatched flags; event-origin opt-in
  required). CHECKPOINT 37e3e9d: retained live_client :538 + actor
  SASL from retained Part :492 positive; endpoint-change clears
  creds :1422-1426, same-endpoint retains profile/resets exchange
  :1298-1318, actor scope independent :334-338/:488-495; no weakened
  assertions. AuthBridge missing from WsNet path (sole observed at
  Net.live_step.next:1102-1103 bypassed) — shared private success
  owner + synthetic paired tests required; NickServ qual must reach
  trusted primary completion (exactly-one frame; stale/foreign/dup
  none) + SAME-endpoint redial actual routed exchange. Global
  chat-ID/runtime leases still open. All routed to 68.
  CHECKPOINT 5b70e57: PRIMARY P2 remove/re-add scalar ID reuse
  (Workspace:300 fixed-base reseed; SlotEpoch gen-only; :805 encodes
  bug) + SEAM1 constructor/restore seed_seq reset :196-210 (not a
  live-launch bug — launcher supplies empty client) + SEAM2 2^44
  bound :186-195 with unguarded Buffer:1025/1239 increment (needs
  fail-closed boundary guard + ordinary unique-ID pair) + SEAM3 N9
  integration lower-ID guard at bind time (not a regression).
  Policy: one authoritative owner, admit-before-allocate, preserve
  existing IDs, exhaustion fail-closed. All routed to 68.
  CHECKPOINT 7fea21c bridge+typing POSITIVE (scoped): WsNet:334
  bridge-after-fold, Workspace:863-879 Key.first delta + exact
  host+port, native one-shot :131-144; typing watcher :548,
  dispatch :355-356, per-Part expiry :818-849, paint-only-changed
  :337-340. Missing-bridge gap lifted. Still required: same-endpoint
  redial actual exchange + exactly-one pipe frame (stale/foreign/dup
  none); full runtime worker integration (le :824-828 pure fixtures
  hold no leases). No blanket MSS acceptance. Routed to 68.
  UPDATE: `mss-resid/75` RETURNED `sessws-full3` `5c2560d` PARTIAL
  (under review); fresh `mss-full/80` ACTIVE with full-baseline
  INITIAL (shared allocation owner, runtime wiring, owned auth
  pipe, negotiated multiline merge).
  UPDATE: `mss-full/80` RETURNED PARTIAL `sessws-full4`
  (`4425847`/`a4dad42` G1 owner + `1dace53`/`52a7e0a` G3 auth
  pipe; G4/G2 residual). G1 SOURCE BLOCKER on `a4dad42`
  (workspace:705-714 clamp retains outs/metadata; near-ceil
  two-DM drops dave row yet creates query/unread/BELL; test:1147
  prefix-only) + G3 narrow guard (NickServ/stale pure-only;
  renewed exchange needs post-auth JOIN #t + one-shot bridge)
  BOTH queued (#1 accepted `01a1037d-…-0ccd`, #2 accepted
  `01a1037e-…-9a8e`) but UNCONSUMED (HEAD predates receipts).
  Fresh `mss-full5/86` ACTIVE from `52a7e0a` with all gates
  (G1 effects/rollback + two-DM negative + one-DM positive,
  G3 actual fixtures + renewed JOIN, G2/G4 residual + full
  baseline incl IO worker leases). Never classify queued inputs
  as implemented or pure fixtures as runtime.
- I2 `709c766` PARTIAL: `#t`/implicit styled flags fixed (5/5 suites
  parent-green); signed `+#room` styled flags still leak.
  `i2-dynamic/61` returned `d4d3c8c` (G1-G4 negotiated ISUPPORT live,
  24/24 claimed; red `e6038af`+`7c0b71a`). FINAL review: scoped AUTH
  FIX stands (Session:2643 -> fold_step.got_at_with:176 ->
  Auth.step_for:167/consume+credential:164, one shared owner) +
  lookup/roster/completion/audience/MODE-precision positives; residual
  open (F1 KICK victim :1068->:508/:497; F2 self :1091/feed_self :951
  Irc.ieq; F3 NICK absent-dynamic Session:2618-2627; F4 typing/View
  custom $/^ + ASCII identity/mute; F5 signed styled flags
  Submit:1417/1453/IrcCommands:156). `i2-dynamic2/71` RETURNED
  `805e34e` (red `c8deb9d` + F1/F2 `5566fed` + F3 `42f7ba8` + F4
  `b4ca34e` + F5 `805e34e`). FINAL verdict: scoped positives ACCEPT
  (F1/F2 victim/self/DM, F3 Client rename, F4 typing/mute via actual
  Net paint — body_of.lines_cm, not full paint qual — F5 bold-wrapped
  +k, d4 Auth chain; old assertions/LAWS/PROOF/Make unchanged), NOT
  full acceptance. Five residuals open (colored MODE key recall,
  unrelated ASCII split rename, fixed mention highlight/BEL, fixed
  tab unread lookup, duplicated NICK traversal). `i2-third` staged
  with ALL residuals + shared-owner/hist-admission criteria in
  INITIAL. UPDATE: `i2-third/73` ACTIVE. CHECKPOINT 54c5aa2: R1
  scoped source-FIX ACCEPTED (shared fixed+negotiated
  Commands.mode_key_tail admission Submit:1419/1456; actual
  StepEnter->step_keys Hist gate :2320 suppresses colored +#room
  +k; strict outbound rejection unchanged; paired isupport_live
  :723-727 noWire/noHist/noRecall + nonkey +o exact HistPrev;
  no new parser; old assertions/laws unchanged).
  FINAL: `i2-third/73` RETURNED `46e77d9` PARTIAL — ACCEPT R1,
  R3 shared write owner, R4 cm fullView lookup, R5 DRY sole
  owner (-82 lines, wrapper :778-779 shares :697-775);
  assertions/LAWS/PROOF unchanged. REQUIRED pending: R2 raw
  chunk prepass (Session:2733 same-chunk 005+NICK); R4 unread
  mutation fixed (Buffer:873 sibling alert/severity); exact-once
  BEL NEW guard absent (:819 still >0; bell-1 wording is NOT an
  ==1 assertion — ADD, never replace). Fresh `i2-fourth` staged
  INITIAL (both state defects + same-chunk/admitted-history
  criteria + severity/coalescing pairs + ==1 guard + positives
  + final qual). No queue to returned 73. No blanket full accept.
  `i2-fourth/76` RETURNED `2e768ef` (red 74173d0 G1C/G2C fail G3C
  green + 65c768b G1 + 2e768ef G2): G1 prepass removed
  (live_split_step evolving iso2, admitted-only), G2 unread cm
  owner (severity separate, coalesce self-only), G3 ==1 BEL added
  (:819 >0 unchanged); 8 suites green, registrations untouched.
  FINAL SOURCE ACCEPT 2e768ef: G1 actual-fold mapped + G2
  mutation/full-OpTabs + G3 exact1, old >0 unchanged. OPEN:
  native bell + H5 archive merged qual. DRY opportunity (no bug/
  perf claim): repeated prepare+admission OR-expression cleanup —
  prepare once, pass rename effect, share split effect; preserve
  H5 archive-reject combined guard. Plan staged below.
  FIRED: `i2-dry-owner/81` ACTIVE on the freed slot (branch
  `i2-dry` from `2e768ef`, full INITIAL per the plan below + H5/I2
  combined guard; positives preserved).
  PLAN (I2-DRY owner, fires on freed slot): single live_prepare
  returning (iso2, line2, reg, consumed) — one live_step.prep, one
  registration_client_iso, one consume/echo OR — consumed by BOTH
  live_step (Client feed) and live_split_step (rename); zero
  behavior delta (existing G1/G2/G3 pairs byte-identical); ADD H5/I2
  combined guard (rejected history line + same-chunk NICK => no
  rename, no import; admitted-only preserved); old assertions/LAWS
  unchanged; native bell + H5 archive merged qual stay open.
  UPDATE: `i2-dry-owner/81` RETURNED `b814e8e` (Buffer sole
  mute/unread/mark wrappers): SOURCE ACCEPT scoped (order/
  severity/default-cmp preserved) but WRONG SCOPE for the
  original Session task. `i2-sessiondry/83` RETURNED `cb66489`
  (OR helper harmless-positive; still TWO prep paths + split
  registrations, no sole owner; `i2_h5_combined` fixture is
  plain MODE/NICK/PRIVMSG without BATCH/tag/negotiation/ticket
  and imports History not history_search — NOT the combined
  guard). Fresh `i2-final/88` ACTIVE from `cb66489`: sole
  preparation/admission owner (one reusable prepared/admitted
  result consumed by BOTH feed and split once) + ACTUAL
  H5-interceptor combined guard (rejected archived NICK vs
  admitted live rename). Never let the renamed fixture replace
  the original task.
  Full privacy line beneath stays accepted.
- C8 `c8-live2/39` LIVE (no stop; OWNER PLAN: Ws imports Links so
  NEVER import Ws into Links — remove C8 Links duplicated OUTER
  parser, preserve inner Markdown lexer; port per-run media verdict
  to main Media over Ws.SRun; Submit.extract_urls->Ws.extract,
  View.render_spans->Ws.render, Cards.targets_go on Ws.SRun +
  Ws.url_runs; one boundaries owner; fullscreen+visibility via
  existing visible_media_candidates + maintain_full + !is_open
  scheduling; live bypass maintenance-only via
  session_observe_media->M.observe; media_history cutoff negative
  kept; no second observer. BASE: G3-base coherent C8-overlay
  snapshot after L1, never copy the unsafe lexer whole. RECORDED 39
  SNAPSHOT: HEAD 88e695b2e8024c371474ec623c6be969a7eceb6f,
  dirty-diff sha256 99a5eefead929f2f45e64c8c2e74dd70ce99db4
  bfd55de137de48274b5509970; NO wire_style.bend in 39 tree
  (Ws overlay required). Endpoint helper + exact-lease pair
  review next. Fresh `c8-gates/79` ACTIVE (full FINAL plan
  INITIAL: overlay/schedule/allowed, maintain-only observe,
  outer-lexer removal + Ws binding, endpoint split, lease pair,
  standing gates, Q1 hold; 39 untouched). UPDATE: gate3
  `b0b0c597` SOURCE POSITIVE (actual View/Submit/Media/Cards Ws
  owners, 168-line outer scanner removed, no import cycle,
  View_laws adapter preserves control-free mapping). SOURCE
  BLOCKER routed to 79 (queued, accepted): LAWS:1000 stale
  `Links.extract` (styled infix URL `== []`, no inner-only
  extract) must call `Ws.extract` retaining SAME `[]`; LAWS:1006
  stale `Links.Run` arg to `Media.media_run_hit` (now
  `List<Ws.SRun>`) needs `Ws.SRun{0,0,False{},")",None{}}`
  fixture + `Ws` import in LAWS. Owner/type migration only,
  assertions + PROOF witnesses preserved, never weakened; enforced
  with full standard proof merged. Gates 1/2/4/5 open, no full
  claim. UPDATE: `c8-live2/39` RETURNED (clean tree `7782c75`,
  3 commits; heavy lane RELEASED). `c8-gates/79` RETURNED
  `07c6b9c`: gates1/2/4 SOURCE ACCEPT, gate5 policy correct
  tests-incomplete; LAWS queue unconsumed at tip.
  `c8-lawsmig/84` RETURNED `4f2a538` (LAWS-only Ws migration):
  SOURCE ACCEPT (same inputs/results, PROOF unchanged).
  `c8-gate5/85` RETURNED `b7d2b3c` (+81 tests-only, all three
  near-misses threaded pure+CN, old tests untouched): SOURCE
  ACCEPT. Fresh `c8-gate1close/87` ACTIVE from `b7d2b3c` for
  gate1 physical-close -> visible unmuted admission once
  (remains separate qualification).
  Make-k batch DONE 02:46
  `args_demo=ok`
  last target, NOT all-green: 8x exit-124 reconnect-registration,
  reconnect-preferences, deferred-frame, session-preferences-intent,
  media-view, m20-state, split, typing; 7x exit-1 tls-native,
  media-anchor, diagnostic-session, reader-errors, runtime-reconnect,
  shutdown-flush, feed; SOME PROOFS FAIL x2). F1-F8 + D1-D3 + lexer
  queues accepted, consumption unproven, all enforce at return.
  diagnostic_session is an INHERITED master4b+fork88 defect (not
  drift): fixture:126 a.example->A.EXAMPLE equal ports,
  Session.endpoint_same String.eq (root:1403/fork:1427) resets chats;
  fix = case-only chat retention + EXACT credential endpoint policy,
  never normalize stored raw endpoint, never relax auth scope.
  TLS 8MiB CA child exit cause UNKNOWN (tls_native:273/294; rc70 env /
  rc71 check / signal incl alarm-2; outer exit 1, not 30s timeout;
  ca_contents unreached; master/fork identical); next = safe decoded
  exit/signal+elapsed diagnostics, conditional default-off per-phase
  CA instrumentation only if SIGALRM confirmed, before perf measure.
  Shared URL lexer faults pinned (Links SHA256:4e989d24: :379-381
  backward-soft suffix admit, :455-461 forward truncated keep/fetch,
  SOH/ESC-infixed prefix keep; View:249/Media:73/Cards:73 callers);
  fix = uniform Ws.url_runs:196-199/223-228, no byte exceptions.
  Four original gates (occlusion, mute/visibility, duplicate parser,
  completion pairs) enforce at return. No deadline/assertion
  weakening, no load-cause claims. HEALTH 03:34: transcript active
  within the minute (base probes, arity suites, tls-native + keep-
  going retries, live bash_input; 662 tools, zero terminal/fatal);
  gates3.log 02:46 batch complete, retries under separate logs;
  frozen UI counters are display artifacts. Bounded retries
  preserved; checkpoint 88e695b+dirty PARTIAL (R1-R5 + pinned blobs
  routed); 11 gates enforce at return.
- SessWS `sessws-full/51` GHOST (transcript terminally failed 01:23:09
  `log_error`; last tools 01:23:07 Makefile pty edits; ~46 min stale at
  02:09 read-only probe; roster `running` stale). Four queued followups
  (repro/paste/lease/wsnet) accepted but never consumed. Retained
  source and registry untouched. `sessws-successor/68` RETURNED
  `sessws-full2` @ `bd3656b` (port + 5 red/green pairs + PTY fix).
  FINAL verdict PARTIAL: positives stand (multiline privacy, bell-seq
  threading, primary auth scope, typing expiry, success bridge).
  Defects UNCHANGED (required correctness): bell opt-out follows
  focused server not event origin; global scalar IDs reused on
  remove/add (+ constructor/exhaustion seams). G2/runtime REJECTED
  (baseline workers + physical leases UNWIRED) despite JS/native/PTY
  greens. Still required: same-endpoint routed auth exchange/bridge
  pipe + held-helper ownership guards. GATE0 load-62 causal wording
  RETRACTED (raw timings/compiles kept as data; no perf fix without
  instrument/measure). PTY3x qualifies exact returned binary only.
  Fresh `mss-resid` staged INITIAL (all residuals + 6 queues
  verbatim); fires per staged order. No queue to returned 68.
- L1: `recover-l1/37` DONE. `53/56/60/62` scoped-partials. `l1-src5`
  `a5fe2d9` positives kept (native NODATA/NXDOMAIN/bothfail
  `dial_dual_at`, Python UDP/TCP host probe; bothfail noTCP needs an
  observer or a narrowed claim; sleep0.3 is not a drain fix).
  `l1-src6/65` RETURNED branch `l1-src6` (red `15ff1b9` + green
  `91b7057` from `a5fe2d9`): single-file Python self-tests only +
  one `cc` refusal test, 3x consecutive green claimed, Bend edits
  uncompiled in that lane, no native/Nix/proof. FINAL source verdict:
  PARTIAL — scoped positives stand (pressured attach, recursive winner
  admission :827, honorDrop :805, pre-Dial prefix cleared :658 /
  post-Dial FIFO preserved, sequential native/TLS/affine ownership);
  P2 zero-exhaustion still accepted end-to-end; native actual
  Drop/third/FIFO + candidate-inflight queued-Dial proof + timed
  release :1073 + REF-A drain + REF-B observer all still open (shapes /
  selftest-3x alone do not qualify). Successor `l1-src7/70` RUNNING.
  CHECKPOINT 5cfe133: GateN scoped source-POSITIVE (done+join then
  nonblocking-drain into SAME seen list :759-772/:864-877; 17th
  datagram raises :40-58 with exact suffix; guards :1584-1627) +
  zero stage6/4 suppression positive; no new >=P2 defect. Still
  required: paired verdict guard (expected-query passes vs extra-A
  post-exit drain rejects); GateT native actuals (held fixture still
  original SHA071243a...); REF-B observer; Q5 held.
  FINAL: `l1-src7/70` RETURNED `c145ef4` (8 commits; Z fail-closed +
  held flags honored; N native incl first-ever admit compile, held
  token, loopback drain, t0 pre-probe, honeypot+ narrowed claim).
  PARTIAL: P2 honeypot stop-race open (:871-879/:898 no post-stop
  accept drain => :920 false-pass; needs bounded accept-to-EAGAIN +
  paired paused-hit-rejects vs empty-passes); native Drop-after-
  winner/third-Dial/FIFO modes absent (model/shape/compile
  insufficient); Q5 held. Residual owner `l1-resid` staged INITIAL
  (P2 + UDP verdict pair + native event/race/Drop/3rd/FIFO + Q5),
  fires on next freed slot.
  FINAL 6c7e742: structure ACCEPT (P2 drain, UDP verdicts, Drop/FIFO
  writer_loop+EOF, third staging, FIFO reading matches actor).
  Normal-turn EOF top-up (branch l1-eof): red ec3e948 + green
  312b858 (shared collect_to_eof owner in both winner peers,
  check_no_late_duplicate verdict, hermetic socketpair pair,
  default-off BIRC_DIAL_TRACE setup-start seam in
  writer_admit_begin, inflight marker gating; self-tests green).
  Native build + inflight/third mode proof PENDING one-heavy-lane
  (39 final-gates job active 04:34-04:44+; no second heavy job).
  Harness fault at 312b858 (gen2 breaks exact check) FIXED: red
  c194094 + green 42b4f31 (LineTap single-owner byte collector,
  order-free expected multisets, unexpected fail; FFI
  native-setup-started seam at connect() issue replaces the Bend
  intent marker; phase correlation documented; self-tests green).
  Native proof still pending lane (39 job active 04:54).
  FINAL REVIEW `42b4f31`: SOURCE POSITIVES stand (genuine connect()
  marker, no EINTR/endpoint/credential leak; Bend intent marker
  removed; single-byte LineTap multisets/EOF handles coalesced
  buffer + unexpected + missing; EOF accepted). CONCRETE MUST-FIX:
  `dns_ffi:156` `write(STDOUT_FILENO)` has no nonblocking/budget
  check — a full inherited blocking pipe parks serial IO
  indefinitely BEFORE the deadline `:160` is assigned (atomic short
  write != bounded). Require an owned nonblocking marker sink with
  refusal of unbounded sinks: never mutate inherited FD flags, no
  hidden thread blocking; trace stays default-off and connect
  runtime deadlines unchanged; pair owned-full-blocking-pipe +
  `BIRC_DIAL_TRACE` (no setup/cleanup stall) vs drained owned-
  nonblock pipe (exactly one marker) vs unset (none); the harness
  owns a configured nonblocking write pipe; failing trace
  observability must not widen runtime. DO NOT run native on the
  known blocking trace without the fix. QUALIFICATION TOP-UP:
  selftests `:2848-2859` feed one 4-event expectation, not the
  actual TWO-PHASE release — add direct phase1 (queued +
  native-marker in both orders/coalesced => release only then) and
  phase2 (recursive native + final => EOF); missing/wrong/
  unexpected phase1 must never release. Preserve EOF accepted,
  native deadlines, Q5. IMPLEMENTED normal-turn (branch
  `l1-tracefix`, Muse writes, no new subagent): red `3a82e1d` +
  green `66ea738` (owned nonblocking sink `dial_trace_emit`:
  `BIRC_DIAL_TRACE` arms, `BIRC_DIAL_TRACE_FD` names the harness
  pre-fork nonblocking FIFO; stdio/unparsable/non-FIFO/blocking
  refused, inherited flags never mutated, all errors drop the
  marker; mode rewired to two taps via `wait_for_two` + `pass_fds`;
  two-phase hermetic top-up; async-signal-safe stall-phase
  postmortem, alarm budget unchanged). Verified light: full python
  selftests green incl `line-tap-phases`, `dial_trace=ok` via nix
  cc strict flags. EXACT-GATE follow-up (same branch): red
  `49086ce` (buffered duplicates release) + green `58f9351`
  (`wait_for_two` rejects already-buffered extras; sequential
  writer-thread positives, prequeue shape removed) + `9c1d15a`
  (selftest intent fix). Full selftest exit 0. FINAL SOURCE
  ACCEPT `9c1d15a`: phase1 buffered-extra rejects before release,
  positives emit phase2 only after gate, native harness uses the
  same predicate; marker/actor/deadlines/Q5 unchanged. SIGPIPE
  provenance pinned (Bend comp.ts IGN, C adds no global change).
  HEAD `9c1d15a`, tree clean. Native inflight/third proof
  SCHEDULED (heavy lane FREE 05:46; re-verify no worker heavy job
  at start; never trust roster alone).
  Never transplant branch DNS (main `aba2f98` `dial_dual_at` only).
- Theme: `be51b7a` bindings stand; `r9-guards/64` returned `b753f97`
  tests-only (25/25, red-by-mutation, held hunks untouched) — loaded-path
  SCOPED ACCEPT (`L.loaded` then actual Session paint; wrong-ticket +
  untouched-storedLight positives; existing negative is the inverse
  polarity; formatting half is old-branch characterization, not
  merged-G3 qualification). `theme-guards2/67` RETURNED `47d885f`
  tests-only (+11 lines): Gate1 exactDark DONE (scoped positive,
  28/28, red-by-mutation with uniqueness proof); Gate2 merged
  Ws.render fixture BLOCKED (path absent on branch — wire_style.bend
  missing; present on lane3-wire-style/g3-traversal/repair-g3),
  correctly stopped per discipline. Shared-G3 integration still open.
- G3 traversal honest-reconnect fix green (`g3_traversal=ok`); shared
  integration HELD.
- WHOLE-TREE FINDING W1 (native OSC8 identity; header blob
  77a47c08da64490124230c418549fb98b84ce674): timui_hyperlink_set
  (timui.h:17658) validates length only; emit_osc_string_sanitized
  (:17931) drops C1. Live `https://e.test/a<U+009F>b` survives
  Fr/Irc/Ws/Links (take_raw only stops <=32), native stored/click
  target stays original, but the emitted terminal hyperlink becomes
  `https://e.test/ab` (silent rewrite). REQUIRE: decline unsafe/
  malformed URIs at ONE shared native admission owner; NEVER rewrite
  an admitted target. Pair: actual-C1 URI rejected/no-OSC8 vs
  percent-encoded equivalent + ordinary max-size exact-URL positive.
  IMPLEMENTED (main-turn scoped edit, branch w1-osc8): red 4c13477
  (C1 admitted, exit 1) + green 1ad68de (timui_uri_admitted owner in
  timui.h; ui_review_native=ok exit 0, single-file cc, -Wall -Wextra
  -Werror). FOLLOWUP malformed-UTF8: red cb1ebf0 (raw 0xFF admitted)
  + green 0ed316f (reject U+FFFD-with-adv!=3 per documented decoder
  distinction; literal EF BF BD + percent positives exact; C1/length
  guards + old assertions preserved; ui_review_native=ok exit 0).
  FINAL source gate ACCEPT (no concrete failure). Coverage 59f7fd8:
  ED A0 80 / F4 90 80 80 / terminal E2 82 / 3-4-byte overlong /
  C0/DEL negatives + link_count==0 no-allocation pin, all green,
  old assertions preserved. No full qual claimed.
  Root staged G3 + live worker sources untouched; no push.
- WHOLE-TREE FINDING W2 (G3 visible search; Client blob
  5842e49aa83c2b9d018fcf11f0d77acc07ad6384): staged
  Client.search_text_matches:905 fuzzy-matches rawLine.text while
  mIRC color digits now survive in source — framed PRIVMSG with
  `<color>04hello` then `/search 04` matches a visually digit-free
  row. HistSearch.match_text delegates the same owner. REQUIRE:
  normalize ONLY the shared haystack via the existing Ws owner; keep
  stored rows and results raw-styled. Pair: style-only-04 no-hit vs
  literal-04 hit + hello styled-traversal hit. IMPLEMENTED inline
  (branch w2w3-g3, snapshot base 9f2b55d): red afd12a3
  (style04_only_literal got styled hit, exit 1) + green 3503bde
  (search_text_matches haystack via Ws.rendered_text(Ws.render);
  Hs.match_text delegates same owner; stored/results raw;
  search_demo=ok exit 0, all old assertions pass). No push.
  W1 PATH CONFIRMED: Ws.wire_drop:140 only <32/127, catchall retains
  U+009F, Links.take_raw:50 only <=32, View.render_run.url:235 exact
  to FFI; ui_review_native:80 exact_links is the ready native OSC8
  seam (fold into W1 owner INITIAL).
- WHOLE-TREE FINDING W3 (G3 contract/path mismatch — verified, not an
  RFC acceptance requirement): staged Irc:369-375 says framed style
  bytes normalize at EVERY identity/policy comparison via proto_atom;
  new wire_style test:189 requires Feed `:s 001 <STX>bob :welcome`
  to assign bob. Actual Session.registration_client:40-44 instead
  tests raw msg_param and REJECTS the same framed first welcome
  before Feed/Auth/JoinPlan. REQUIRE: framed actual-Session
  traversal negative (wrong/forged source) + positive normalized
  styled valid first welcome + ordinary valid; reuse EXISTING
  shared Irc.proto_atom normalization; no new parser, no relaxed
  trust. Preserve raw-style source/result lines. Styled CAP
  comparisons have no direct positive-policy guard — retain as
  AUDIT EVIDENCE ONLY, not a fourth finding. IMPLEMENTED inline
  (branch w2w3-g3): red 1c3a1a6 (styled welcome rejected, exit 1)
  + green 854a1d3 (nick via Irc.proto_atom at Session:40;
  wire_style=ok exit 0, old assertions pass) + combined coverage
  578ab72 (Fr->Session->Submit: hidden-04 no-hit / literal-04 hit
  + raw result; styled+ordinary welcome adopt + JOIN release;
  forged/malformed/conflicting quiet; g3_traversal=ok exit 0).
  FOLLOWUP SOH overwrite: red 614c681 (N001 stored raw b\x01ob,
  exit 1) + green 643b4d0 (N001 identity via proto_atom at
  client.bend:666, welcome body stays raw; SOH canonical +
  color adopt/JOIN positives; g3_traversal=ok exit 0).
  Q1 hunks untouched (base only, not promoted). No push.
- WHOLE-TREE REVIEW COMPLETE (fresh cleared context; read-only, no
  tests/jobs/writes/network): W1 pre-existing native OSC8 exact-URI
  rewrite P2, W2 hidden color search P3, W3 explicit G3
  normalization-contract Session registration mismatch — all
  VERIFIED, all staged INITIALs assigned. No fourth CAP finding; no
  new concrete duplication/performance claim. FINAL SOURCE PINS:
  root 4b4cbef; header 77a47c08da64490124230c418549fb98b84ce674;
  ui_review_native 8b88056be0bd82808d15b7a017dae6529c65467d;
  staged Client 5842e49aa83c2b9d018fcf11f0d77acc07ad6384; Session
  54012a4b711105f44d79ebe5feacce182e5f077d; staged wire_style_test
  5ea03cf8e69971040531b6cc7e2271b352e0bf6b; Fr
  67659036b93f748704545b6555c760ef2c0234d0. COVERAGE: root G3 /
  protocol / auth / submit / search / history / startup / DNS-TLS /
  UI / media-upload-keychain-prefs / package representative seams.
  GAPS (explicit): NOT every vendored header line; NOT a complete
  six-candidate runtime trace. Full implementation + final gates
  continue.
- HOLDS [SUPERSEDED 2026-10-04 ~09:15 — Q1-Q5 user-approved to exact questions, not blanket; see appended entry]: Q1 four G3 legacy fixtures; Q2 H5 fifth timestamp + `/history`
  catalog; Q3 theme `m20_state` K02 + `session_preferences_intent`; Q4 N9
  six `notify_full` expectations (`busy` false->true reset:618/off:634/
  cancel:665; `comp_rel` false->true reset:630/off:646/cancel:673; :632
  after-exact-release busy-false stays; pending/marks/disabled/
  unrelated-wrong-completion preserved; no silent alteration, no compat
  shim; coherent hunks held at integration); Q5 L1 net_trace valid-
  ordering fixture migration to explicit carried nonzero IDs
  (reader/raced/parked/late :674-723, synth :635, etc.;
  ordering/timing/QUIT expectations unchanged; pong_gen process-
  exit/stale-count zeros unchanged; separate zero/exhausted negative
  proceeds). HELD FROM INTEGRATION (Q3/Q4 coherent hunks exist in
  worker commits; held means unmerged/unpromoted, not source-erased).
  Raw timings kept; pool-load and trace/coalescing causal claims stay
  RETRACTED (see above). N9 build 1200-timeout factual cause UNKNOWN
  (manual-3600 unauthorized, retracted). L1 6c7e742 tests-only return
  under independent review.
- Crypto scope: NO BLAKE/BLAKE2 source anywhere (grep-verified); standard
  TLS only, no new crypto.
- FINAL (all open, proof budget 600 approved): exact command
  `make check PROOF_TIMEOUT=600` (single invocation, never split);
  then merged native, exact-final PTY 3x, default `nix build
  --no-update-lock-file`, installed checks, hot-cache. Fixed gate
  semantics required (never trust wrapper exit/GREEN alone).
- Qualification limits: worker-reported greens are claims until parent
  or independent review; pure-fixture suites do not qualify runtime or
  native paths where native qualification is stated. Slot pool 5/8 at 06:15 (active 82 N9-final, 86 MSS-full5, 88
  I2-final DONE, 92 v6probe-impl, 93 theme-gate2, 94 integration,
  95 h5combo-interceptor; 91 DIED on redirect, no usable work;
  ghosts 51/58 REAPED 05:46; V6 external returned-stale).
  RETURNED with receipts: 39 c8-live2 `7782c75`, 77 n9-bind3
  `7870db5`, 79 c8-gates `07c6b9c`, 80 sessws-full4 `52a7e0a`,
  81 i2-dry `b814e8e`, 83 i2-sessiondry `cb66489`, 84 c8-lawsmig
  `4f2a538`, 85 c8-gate5 `b7d2b3c`, 87 C8-gate1close `31b49c6`
  (pure Session key-close only), 88 I2-final `0fc812f`
  (prep+registration ACCEPT; H5-combined NOT DONE), 89
  L1-nativequal (inflight/third markers only; full suite FAIL),
  90 H5-wrapqual `c4794f5`.
  Durable current: ACCEPTED SOURCES L1 `9c1d15a` Final exact gate
  (ONLY inflight+third PASS by markers; full-main FAIL at :3320
  (False,True) docketed; tail-pipe exit-0 RETRACTED), H5 `8f493f4`
  FINAL cutoff + `c4794f5` wrapper + `9c152b2` (live-post guards
  ONLY, NOT history_runtime restore — corrected per review),
  R4 `7870db5` (abs backend; Linux closure pending), C8 `07c6b9c` +
  `4f2a538` + `b7d2b3c` + `31b49c6` + `ca0d92b` docs rename (native
  key qual stays PTY), I2 `b814e8e` scoped + `0fc812f` prep ACCEPT,
  MSS `9899bb1` DM-rollback ACCEPT (G1 rename-before-ceiling
  residual sent to 86; G3 physical JOIN gates remain), theme
  `47d885f` Gate1 exact-dark ONLY (Gate2 shared Ws.render NOT in
  47d885f; modal pin NOT authority — corrected per review).
  G1 RESTORE `88346d0` FINAL SOURCE ACCEPT (preserved pin):
  synthetic ownership -> production Hs.disk_file_admitted ->
  real Hs.search_opened -> exact DiskFailed; real owned-private
  positive + all old asserts intact; no native foreign-UID claim. V6 `322eae1` SOURCE ACCEPT (thin bind/FD ABI);
  native full-run FIRST-HAND: `timeout 120 python3
  tests/ipv6_transport.py ./build/ipv6_transport_native openssl`
  on 322eae1 binary (897608B 06:25) → 32 =ok incl bind6neg/v6udp/
  bind6inuse/inflight/third/tls6 family, `bind6=supported`, final
  `ipv6_transport_native=ok` last line, no traceback, log
  /tmp/l1_fullmain_322.log (3 FAIL-substring lines are benign
  dualdnsbothfail names); exact exit rerun scheduled after lane
  transfer 06:41:25 (prior echo typo, no rerun under contention).
  MSS `9642b20` scoped NEW PHYSICAL FIXTURES ACCEPT
  (multiserver SASL/NickServ); residual/runtime open (96
  NICK+stale light, 97 baseline-IO heavy). Gate2 `9a952a3`
  REVIEWED (not accepted): theme_ws_render=ok via nix make
  first-hand; wire_style port byte-verbatim (blob 82c9a066);
  diagnostic_session fails IDENTICALLY base-vs-HEAD (exit 1,
  same-endpoint-keeps-chats got/want); ascii no-main identical
  by file identity; caveat: 93's 30-suite list ran ambient
  bend/bun, nix-driver confirmation pending (theme HELD Q3).
  HELD (excluded): Q1-Q5 holdings (incl Q2 hunks + Q3 selectable
  lifecycle), e7635e7 keeps-newest drop policy (R4 backend-only
  acceptance). 625-blanket REMOVED (QA/QB guards accepted).
  Integration `398f4bc` + `e26a7d9` UNPROMOTED (shim, not
  exclusion); 94 rebuilding NON-THEME-ONLY branch (theme held
  Q3 branch, never merged). 82 AUDIT 06:44: proof terminal
  (bound expired); package retry exec-7831 TERMINAL 06:41:26:
  `make: *** [build-package] Error 124` (timeout-900 kill;
  nix interrupted, no out-link). No 'healthy' claim — exact
  terminal evidence decides it. Pending status: bounded
  sleep-280 (06:40:43 to ~06:45:23); one unprocessed terminal;
  three steers undispatched (user_steer 0); roster
  running-fresh. NOT stalled; no cancellation, no worktree
  mutation; dirty source + untracked file preserved for 82's
  own checkpoint. LANE TOKEN: 82 -> 97 transferred 06:44 on
  terminal receipt, BUT 82 started UNCLAIMED package build
  06:45:57 with inflated --option timeout 3600 (Makefile bound
  900; forbidden). 97 HOLDING native until all-clear; 82
  STOP+checkpoint+short-waits ordered (4th steer; prior 3
  undispatched). No force yet; 82 yield expires ~06:51.
  21bb150 spot: i2_h5_combined=ok + history_runtime=ok exit 0
  first-hand (wire reviewer assigned; Q2 excluded). 322 exit:
  rerun TERMINATED per no-concurrent-rerun order; exact exit
  still open, scheduled for a quiet window. Integration:
  94 CANCELLED 06:53 (merged C8 atop rejected Theme 06:46 +
  a7b5d28 'theme+cf' after 3 queued STOPs; tree clean at
  cancel). 398/e26/8dd/476/a7b5d28 PINNED EVIDENCE ONLY.
  Fresh 99 non-theme from 4b4cbef with complete exclusions +
  held/theme-q3 ref. 82 REMNANT: stuck sh3538/nix3556 (13min,
  0 CPU, childless, no build dirs/locks) reaped via exact-PID
  SIGTERM 07:00, both gone; lane verified clear (fields-only
  evidence, no command lines). Combo `7b427ee` Final scoped
  SOURCE ACCEPT (preserved pin): ACK->Enter->shared guards;
  IDs/checkpoint/quiet/driver intact; no new defect; laws
  unchanged; first-hand greens + neg are execution evidence.
  Q2 HELD (explicit, test hunks — original values preserved
  unless user approves): (1) tests/bend/history_search.bend
  cmd_around_stamp_prefixed — root 4b4cbef:291-292 uses
  timestamp=2026-10-03T10:00:00Z in/out; combo 7b427ee:305-306
  uses .000Z fifth millis form in/out; (2)
  tests/bend/m20_state.bend:162 K02 — root lacks /history
  (.../search|/preview/...); combo inserts /history after
  /search. Round 2 must carry root's values, not combo's.
  Feed: 99 NOT disturbed mid-run — combo queued for round 2.
  Lane reap receipt SUFFICIENT. 97 wsnet (+627/-165)
  confirmed actual implementation; no split.
  MSS de0edc7 scoped ACCEPT
  (rollback verified s1s5=ok first-hand); stale-auth NOT
  qualified, minimal repair to fresh 101 (PTY gated on lane).
  97 CHECKPOINT 07:03: HEALTHY implementation, no split
  (wsnet +627/-165 actual source). 07:2x: still editing
  (wsnet.bend only dirty file, no commit yet); built nothing
  07:11-15, so 100's native runs overlapped nothing heavy.
  Provisional review gap RELAYED (queued) but 97 CANCELLED
  on 60m bound (spawn 06:32:23, applied ~07:37) with steers
  undelivered. 97 had self-reverted +627 WIP to +122 lean
  fallback at 07:27 (saving full to /tmp/wsnet_full_io.bend):
  RESCUED verbatim as ca725d1 on wip97-rescue (unreviewed,
  not accepted, consult-only). 106 checkpointed current as
  381db93 and owns all four gates + cards/notifications +
  heavy lane from retained progress. Lean fallback NOT
  promoted as completed IO.
  N9 Final: R2 WIP ACCEPT (7870db5 +
  dirty; LC65/cap16k/import/dedup/live9/JOIN-shift ok; Net
  dispatch unqualified); R1 NOT qualified (sleep6 vs 2s,
  completion discarded, manual FIFO) with ACK+latch repair
  spec SENT to 82 (5th steer); checkpoint before promotion;
  Q4 held. OPEN: N9 R1 repair (100, from 82 checkpoint; 82
  cancelled), theme Gate2 `9788b05` REVIEW-ASSIGNED (framed
  paint/raw equality/held revert/wiring; verific. DONE:
  theme_ws_render=ok + feed_demo=ok incl held hostile, nix
  driver, exit 0; Ws reuse accepted, bg inherited, Q3 held,
  branch kept candidate), integration non-theme (99), MSS baseline-IO
  (97, token), MSS stale repair (101, PTY gated on lane).
  DONE this round: 95 combo (7b427ee ACCEPT), 96 NICK
  (de0edc7 scoped ACCEPT), 98 resid (9788b05 PARTIAL: framed
  paint/raw-equality/held-revert/wiring fixed; render_spans
  Ws->Links switch is the residual; 102 correcting), 99
  integration (5d297da: C8x4+L1x2 green first-hand
  cards_live/ipv6_transport =ok; zero-theme verified vs
  clean root; held/theme-q3 created).
  99 STOPs SUBSTANTIATED (content, not ancestry) BUT per
  scope clarification: NO branch veto — accepted tips stand;
  holds are specific bits for extraction: (a) e7635e7
  27/27 lines live at 7870db5 — ADJUDICATED: unsafe 64-cap
  keeps-newest drop REMAINS REJECTED; R4 acceptance =
  absolute backend/launcher/package ONLY. R4 path: extract
  scoped backend hunks OR integrate 100's R1 result (R2 WIP
  replacement); no wholesale revert. (b) 625f7df 76/76
  wire2 H/I lines live at 8f — ADJUDICATED: QA/QB guards
  ACCEPTED within H5 (no old expectation changed); stale
  HELD625 label REMOVED (Q2 hunks stay held). (c) `5d297da`
  Final scoped SOURCE ACCEPT (C8/L1 subset: no merge defect,
  Pong keeps boxed media/cards/fullscreen, no selectable
  theme, Q5 zero-ID intact, PONG corrections, laws
  additions-only). Omissions: iso/HistLive, undrained Net
  step, R4 helper/closure. Union owner 103 real-merging
  7b427ee in (no adapter bypass; R4 separable; Q1-Q5
  precise holds; K02 conflict = STOP+report).
  Theme: 'zero Theme' RETRACTED — 5d297da has shared
  palette helper (theme.bend UNCHANGED root->5d, values
  intact, no duplicates) + unused adapters; verified NO
  selectable lifecycle (command/completion/settings/intent/
  persistence lines identical to root). Hold = selectable
  lifecycle only.
  Final sequence: `make check PROOF_TIMEOUT=600`, then merged
  native, exact-final PTY 3x, default `nix build
  --no-update-lock-file`, installed helpers, hot-cache. No
  independent proof kernel. No full source or qualification claims
  beyond the scoped verdicts above.
  NATIVE EVIDENCE (L1 `9c1d15a`, worktree `l1-nativequal`, binary
  `build/ipv6_transport_native` 896408B 2026-10-04 05:56+0900 via
  `make test-ipv6-transport` = `timeout 300 bend
  tests/bend/ipv6_transport_native.bend -o ...` unmodified):
  FULL-MAIN FAIL: `nix develop --no-update-lock-file --command sh
  -c 'timeout 120 python3 tests/ipv6_transport.py
  ./build/ipv6_transport_native openssl'` printed `literal=ok`,
  `bind6=unsupported`, then `AssertionError` at
  `tests/ipv6_transport.py:3320 assert cand_v6 == host_v6` with
  `(False, True)`; suite exit nonzero. SCOPED PASS: `nix develop
  ... --command sh -c 'set -o pipefail; timeout 120 python3
  /tmp/l1_modes_verify.py'` (scratch driver calling the suite's
  own `mode_dialsupersedeinflight` + `mode_dialsupersedethird`)
  printed `dialsupersedeinflight=ok`, `dialsupersedethird=ok`,
  driver exit 0. REVIEW FINDING: fixture `mode_bind6probe:489-492`
  and v6udp `:555` call IPv4-only `Base UDP.bind` (pinned Bend
  `effs/udp_bind.c:5-13` AF_INET, `comp.ts:5488-5499`
  inet_pton(AF_INET)); host AF_INET6 True is valid; existing birc
  IPv6 DNS send/recv FFI does not replace Base bind. FIX (92):
  smallest owned IPv6 bind seam for both probes; negatives
  invalid-address/no-leaked-FD, positive ::1 byte exchange with
  exact peer addr/port+close, numeric diagnostics; assertion
  intact; no pin/runtime change.
  398 AUDIT (final): `398f4bc` includes HELD Q3 entire theme
  implementation/plumbing + K02 /theme + settings-intent 9->10
  (must exclude coherently); Q2/Q4/Q5 held legacy changes ABSENT
  (clean); no other old assertions changed (clean); LAWS/PROOF
  identical to root `4b4cbef` (clean). Promotion requires ONLY a
  corrected candidate excluding Q3. Integration worktree HEAD now
  `4b` (`398f4bc` retained as pinned evidence); old source commits
  retained; corrected branch/commits must be safe explicit new
  writes, no broad destructive commands. I2 `0fc812f` PARTIAL:
  prep+registration ACCEPT (once per line); complete
  auth/credential consumed decision still repeated (no observed
  divergence); H5-combined interceptor MISSING (owner 95).
  OWNERS: 93 theme-Gate2 shared Ws.render, 94 integration
  corrected-branch, 95 H5-combined interceptor. MSS GAP:
  rejected-NICK must preserve pane/query/IDs (Session:2482
  rename-before-ceiling; fitting NICK renames both once via
  ADMITTED owner) sent to live 86, consumption required before
  return; G3 physical JOIN gates remain.
  ad9c1d2 VERDICTS (g1 restore, review-pending): POSITIVE `nix
  develop --no-update-lock-file --command sh -c 'set -o pipefail;
  timeout 180 bend tests/bend/history_runtime.bend -o
  build/history_runtime.js && sh scripts/check-golden.sh
  history_runtime=ok timeout 30 bun build/history_runtime.js'` →
  `history_runtime=ok`, exit 0. NEGATIVE (flipped
  g1_fd_foreign_refused expectation, 1 line) →
  `g1_fd_foreign_refused got=[fail:history search refused: file
  not admitted] want=[WRONG:...]`, exit 1, no marker. File
  restored byte-identical before commit. CHECKPOINT `ad9c1d2` on
  `h5-fdrestore` over `9c152b2`, tests-only +22/-5 one file, tree
  clean, never pushed.
  N9 36499fd NEW-NEGATIVE flaw (preliminary independent review,
  newly introduced task test correction, NOT Q4): run_unreleased
  reused h after run_released created h.release; fake never
  consumes latch (Makefile poll `[ ! -e $rel ]`, 18x0.05s) so
  worker3 sees stale release -> done, not expired. No File.remove
  effect exists -> fix = fresh exact owned helper h2=h++"-unrel"
  (recipe cp sibling, same mktemp/trap) + bare held_unrel_expired
  (h2.log worker3-only); states/deadline preserved, no JS-typecheck
  green claim. Fix applied in n9-r1-guards (uncommitted);
  `make test-notify-held-blocked` native verification RUNNING;
  reviewer finishes pinned verdict.
  103 union b1822bf RETURNED clean (merge 5d297da+7b427ee);
  merged-owner source review underway. Precise integration
  correction 3bd8368 on integration-union: K02 expectation literal
  restored to root/5d value (drop /history between /search and
  /preview; combo side had inserted it). Production
  slash_command_list untouched (cmd_around_stamp_prefixed keeps
  bare-seconds per root Q2 check). Known held-test conflict
  reported in commit; old K02 assertion remains held, no
  completion shim, merge continues.
  HEAVY-LANE HONESTY (recorded, not non-overlap): root read-only
  lsof at 07:41:54 showed TWO concurrent clangs: pid 2329 cwd
  n9-r1-guards (outer timeout pid 1607 = my N9 held-blocked
  rerun) and pid 95296 cwd retained baseline106 (outer timeout
  pid 95177 = 106 heavy work). I created this overlap by
  launching the N9 native rerun while 106 held the heavy lane.
  Rule from now on: ONE heavyweight compiler/Nix/native lane
  (106 owns it); source/JS/small-FFI stay parallel. The bounded
  N9 rerun (needed for the final N9 hash) concludes as-is; no
  further heavy commands from me until 106 releases; no broad
  kill. N9 fix preliminary SOURCE-CORRECT per reviewer (h
  worker2, h2 worker3, start+expired/no-done, diagnostic-first);
  SOURCE ACCEPT FINAL pins Makefile cb32522 + fixture 44c6a627
  (dirty on 36499fd): VERIFIED exact match to worktree blobs
  (cb32522ea1.../44c6a62783...); tree stays dirty as pinned,
  no commit. EXACT NATIVE EXIT (bounded `make
  test-notify-held-blocked`, timeouts 300/300/90, full log
  /tmp/n9_held_rerun.log): make exit 2; golden inner exit 1;
  `held unreleased logs expired, no done got=[] want=[start --
  bob.../expired -- bob...]`. Diagnostic-first x2 PASSED but
  SPURIOUSLY via "unknown helper" UiError path. ROOT CAUSE
  (production gate, not test): notify_io.bend args_for.send
  (L78-79) requires basename exactly notify-send/birc-notify/
  osascript; h2 basename `notify-send-unrel` -> args Nil ->
  send.run Nil arm (L87-89) never spawns -> h2.log empty.
  Runtime verdict RED with diagnosed cause; narrow namespace
  source accept WITHDRAWN as qualification (never exercises
  helper). CORRECTED without new authority: 6a795ed on
  n9-r1-guards (Makefile e716abe, fixture 4c9da06, tree clean):
  recipe mkdir+cp \$d/unreleased/notify-send (same
  basename/trap), test reads exact path via IO.get_env
  BIRC_NOTIFY_HELPER_UNREL, h2 threaded deliver->run_held->
  run_spawned->run_released->run_unreleased. Production
  known_helper untouched, Q4 untouched, guards preserved.
  Static consistency verified (no builds: 106 holds heavy
  lane); native proof PENDING, commit notes truthful red.
  Union 3bd8368 NEW C8/I2 defect (precise, not veto): Session
  ~2789 visible_candidates_cards omits negotiated cm; Cards
  ~610 default-RFC anchored_lines_media_cards vs Net ~166
  *_cards_cm with Session cm (ascii + muted a{b repro).
  Fresh orthogonal repair agent SPAWNED (isolated tree,
  base integration-union@3bd8368): narrow no-hidden-enqueue
  + widened exact-enqueue tests, cm-aware painted owner
  reuse, Media-path audit, assertions preserved, no
  secondary owner, NO heavy commands (106 owns lane).
  Hold-heavy steers QUEUED to 104/105 (103 returned); 105
  steer REJECTED-terminal: 105 RETURNED 73440cc (theme-ws-only,
  Gate2 Ws-only single render owner, +39/-46, view.bend only,
  held hostile conflict) — pending review, root untouched.
  106 reviewer source guidance RELAYED (queued): ca725
  planning-only; worker envelope on spawn; physical lease first
  then PRESENT same-epoch Part, never ws_part fallback focused;
  removed origin retires lease only; boxed global lease bundle
  in WsLoop one-helper/type; routed-Main sole pref receiver;
  firstpaint->settings->archive->oneBegin via
  Act.deferred_start_tls+LC; session_upload_key/present;
  bind actual card+notify IO (painted visibility, per-ID
  exclusions, event order); no 2nd protocol/runtime; 5
  named tests. Union final 3bd: only cards-cm residual
  (107 owns); C8cf/media+I2soleprep+H5beforeprep+Netdrained
  + exact Q2 values preserved.
  Theme 73440cc FINAL scoped SOURCE ACCEPT (independent):
  all compat Links helpers/calls gone; live/unthemed/themed
  paint render_spans -> accepted Ws blob 82c9a066; framed
  bold/red Dark/Light/Mono + raw stored/history equality
  intact, no raw-row injection; only View/new theme guard
  changed, no held-assertion rewrite. Q1/Q3 old
  expectation/lifecycle holds REMAIN; no runtime/integration
  verdict. Source correction proceeds normally.
  N9 6a795ed (d/unreleased explicit-env fresh namespace)
  seen by root; narrow re-review underway, source-only until
  106 releases lane. Same owner preserved; helper basename
  allowlist NOT expanded.
  104 RETURNED 36158a2 on mss-stale-correct (parent de0edc7;
  blocked 52dccb9 untouched): 2 test files, zero src changes,
  NORMAL shutdown-on-Dial preserved (actor Dial still
  shutdown+close; old reader_run retires via EOF, no retained
  FD/TLS); heavy proof awaiting lane-free, root untouched.
  FULL FINAL candidate still needs: all accepted source
  integration + make check PROOF_TIMEOUT=600 + native + PTY3
  + default Nix + installed + hot cache.
  107 RETURNED 8c4e866 on repair-union-cards-cm (parent
  3bd8368 verified; +83/-4, 3 files; root untouched).
  First-hand: session_observe_visible_cards.gated gains +cm
  (binds +iso, Isupport.casemapping(iso)) -> new
  C.visible_candidates_cards_cm family over
  V.anchored_lines_media_cards_cm (same anchored owner Net
  paint uses; cards.bend pure addition, default-RFC defs
  untouched, no secondary owner); cards_live +32 with ascii
  muted a{b fixtures: narrow rows=6 candidates empty +
  schedules 0 + pins default-RFC leak "1", wide rows=24
  exact painted URL + schedules 1. K02/m20 untouched.
  Media audit: split ABSENT (live media already _cm), no
  fix. Tests authored-but-NOT-run, no heavy commands
  (both holds complied). Queued for review + lane-release
  verification. ACTIVE: 106 only.
  GATE 1 (MSS 36158a2 FINAL): shutdown-on-Dial preserved +
  NICK unchanged GOOD; stale physical qualification STILL
  ABSENT (PTY PING ACK before /connect+903send, no captured
  admission ACK; EOF closure-only; pipe-zero uncoupled;
  Bend manual stamp, no Actor capture). Successor 108
  SPAWNED (base mss-stale-correct@36158a2): actor-stamped
  callback held testqueue, admission ACK then physical zero
  before current success, one-frame EOF JOIN positive
  preserved; no new production lifetime/native framework;
  source-only, tests authored-not-run.
  GATE 2 (106 WIP 07:50 header): 'Cards single-server...
  no cards modules... UiError notifications' REJECTED as
  lean fallback (old 964/681 base absence authorizes no
  omission). Dependency steer QUEUED to 106: integrate
  accepted union 3bd/8c4 + N9 owners, reuse ACTUAL
  Cards/Notify IO (visible admission, per-ID excludes),
  no error-as-notification classification; full scope
  required. Fallback if unconsumed: source-only
  successor/dependency integration (no new authority).
  Union cards 8c4e866 FINAL functional SOURCE ACCEPT
  (independent): actual Session passes negotiated cm into
  same shared paint-row owner; new actual-Session guards
  narrow queue0 / wide queue1 / exact 1:1
  https://x.test/read; Media analogous path already
  cm-correct; old assertions unchanged. User-requested DRY
  cleanup ASSIGNED (not filed away): Cards ~651-690
  duplicates five-function default traversal ~604-643.
  Tiny orthogonal agent 109 SPAWNED (base
  repair-union-cards-cm@8c4e866): fixed-default APIs
  delegate to cm-aware forms via existing default mapping;
  public API/behavior/guards preserved; source-only, no
  test changes; native lane stays serialized (106).
  109 RETURNED c616668 on cards-cm-dry (parent 8c4e866;
  one file +20/-41; root untouched). First-hand: all six
  default-API signatures byte-identical (public API kept);
  bodies now one-line delegates to *_cm forms via
  pre-existing Cl.dflt_cm() (buffer.bend:26 = "rfc1459",
  not invented); no test changes; no heavy commands.
  Queued for review + lane-release verification alongside
  8c4e866. ACTIVE: 106 (heavy) + 108 (source-only).
  108 exact API guidance RELAYED (queued; planning, not
  acceptance): fixture actor_boot(_tls)+net_fwd; recv holds
  actual RoutedMsg{Sid,FromNet{oldgen,Chunk}} pre-ws_on_net
  (post65-68 generation, net_fwd Sid); 903-during-SASL
  capture+ACK then live_step_keys+ws_emit, await Up/EOF;
  release via production ws_on_net230; extract
  ws_net_painted333-336 auth_edge/auth_noticed seam helper
  shared by production+fixture; ACK after helper, pipe0
  before fresh CAP/903; no lifetime/runtime change; native
  waits 106 lane.
  Cards c616668 FINAL scoped source/style ACCEPT
  (independent): six default signatures + argument order
  preserved; one-line delegates via existing Cl.dflt_cm()
  rfc1459 to same cm-aware traversal; no recursion cycle
  or behavior change; only cards.bend changed,
  tests/laws/Session untouched; copied traversal removed.
  Source/style verdict ONLY — native merged qualification
  still pending; branch-local greens are not final.
  Integrates normally into final source candidate with all
  other accepted fixes. 108 real-callback harness + 106
  full IO incl dependencies continue; bounded final gates
  after.
  106 G4 counterexample RELAYED (queued; early source, not
  final grading): loaded1408->one_got1327->prepare loads
  BEFORE first paint/frame (UI open != input-bearing frame);
  begun/Begin before ws_act applies keys (first-frame
  quit/history-off late). Required: real first frame+input,
  then settings/archive, checkpoint before completion keys,
  exactly one deferred Begin; no synthetic guard, no
  comment-only claim. Prefs shutdown reads sole-receiver
  (hashes pending).
  110 final-candidate-integ SPAWNED (base c616668, isolated):
  integrate NOW in parallel — N9 6a, R4 scoped (e7635e7
  rejected; hold out if ambiguous), W1 (1ad68de+0ed316f+
  59f7fd8), W2/W3 (3503bde+854a1d3+578ab72+643b4d0, Q1 out),
  G6 (5b6b2aa+c378ed0+4c73236+492fd17, arity kept), G3
  (baef5f4+c8c4035), MSS de0edc7 only. Held expectations
  preserved, no ThemeQ3, no shims, source-only, no heavy.
  108 RETURNED e7c6636 on mss-stalequal-successor (parent
  36158a2; 3 files +213/-10; root untouched; declared
  authored-but-NOT-run, no heavy). First-hand: new
  mss_stale_held.bend (184) posts old/new-gen 903 via
  A.post + Chan.recv held queue (:163-164 fresh, :180-181
  stale) with W.auth_edge matching (:107/112/135); Makefile
  +6 native driver (unrun). GAPS vs relayed API guidance:
  PTY auth_profile.py hunks are DOCSTRING-ONLY (no
  executable reorder of the criticized 493-519 flow); no
  release via production WsNet.ws_on_net230; no
  ws_net_painted333-336 shared seam helper (zero src/
  changes — earlier no-src brief never reconciled with
  later seam guidance); no live_step_keys+ws_emit redial
  flow in harness. PARTIAL delivery queued for independent
  review; no accept, no self-directed re-repair. ACTIVE:
  106 (heavy) + 110 (integ).
  e7c6636 INDEPENDENT REVIEW: NOT real-callback/physical
  qualification — VERIFIED first-hand (imports lack
  WsNet/AuthBridge/socket/boot; :180 direct A.post with
  manufactured literal 903; :131-133/:103-105 wildcard
  received bytes and rebuild literals; live_on_msg/
  pipe_after pure; PTY PING ACKs current, not old-903
  dispatch). e7c6636 stays UNMERGED as qualification; no
  pure-stamp-substitute label/merge/spawn. Qualification
  REMAINS OPEN; teardown unchanged accepted; no demand for
  unnecessary extraction (shared-seam helper NOT required).
  MAIN OWNS narrow implementation: new branch from
  36158a2 (not e7c6636), small native fixture via actual
  Actor.socket reader/boot + net_fwd/ws_on_net + physical
  AuthBridge pipe following startup_actor.bend:38-43,
  preserving socket bytes/generation, never reconstruct;
  source-only until lane release, truthful not-run note.
  CHECKPOINT (~08:12): ACK-status steers QUEUED to 106
  (current job + log tail + per-steer CONSUMED/PLANNED/
  BLOCKED with evidence for guidance/dependency/G4) and
  110 (base + per-item + R4 lean + conflicts + zero-heavy
  confirm). 106 last commit read-only: 68112df on
  mss-baseline-io (parent 9642b20, +360/-12: wsnet +132 +
  multiserver_history_pty.py 238) = the LEAN history-first
  shape; all three steers postdate it. LABELS: union/N9
  dependencies + G4 fixes stay REQUESTED/QUEUED until
  worker/source receipt — queue-accepted is NOT
  implemented. 110 chain verified: 5dc1433 (parent c616668
  clean) W1 cherry-picked + e646cb1 R4 extracted. R4
  honesty rule RELAYED to 110: current-host + Linux
  binding/unit/eval evidence as-is; Darwin Linux-closure
  exec may be EXPLICITLY SKIPPED with smallest next
  check; never falsely claimed/cached; never whole-task
  blocker. FINAL proof = approved make check
  PROOF_TIMEOUT=600 only; no independent deadline raise.
  No interrupts/kills. Fixture implementation continues.
  106 G2 counterexample RELAYED (queued #4; WIP finding, no
  runtime claim): ws_post.prefs->ws_lease.kept absent-Part/
  gen-mismatch branches discard GLOBAL physical image
  lease (remove/reconnect/reset A frees; focused B double-
  spawns). Required: keep lease across removed/stale/
  reused origin until EXACT spawned completion retires;
  admission gate != free permission; no comment-only
  claim. Reviewer checks exact-request + token retention.
  ALL FOUR 106 inputs REQUESTED until ACK+evidence.
  106 media counterexamples RELAYED (queued #5; wsnet blob
  d37f4948; WIP, no type/grading): (1) prune on absent/
  gen-changed Part frees blocked helper; (2) WsLease only
  Sid/gen + MediaFetched lacks spawn-captured epoch/
  endpoint/request -> admits old payload after prune+reuse
  +fresh sameURL/gen1/ticket1; wrong-ticket tokened path
  clears global lease despite M.reject retaining worker;
  exact completion must retire captured envelope only,
  live effects need present same-epoch origin, never
  current-substitute; (3) media_add gets only completing-
  Part tokens -> native frees owned A tokens during B
  completion; need all-Part UNION + native8 gate. Listed
  positives don't close holes. ALL FIVE REQUESTED; no
  106 source/runtime accept yet.
  R4 e646cb1 scoped SOURCE ACCEPT (independent, extract
  only, no builds): exactly six backend/package/test
  files; no ledger/e763/theme; absolute libnotify,
  explicit-override-first, Darwin osascript, direct
  argv/--, 1s bound/redacted errors. Runtime binding
  PENDING: notify_io64 rejects packaged birc-notify; 110
  STEERED (queued): integrate accepted N9 admission/
  selection/observer before claiming feature; package
  tests != Session delivery. No branch veto from
  unrelated dirty source. Fixture/integration continue.
  110 RETURNED 4a3b5fc (final-candidate-integ, 5 on c616668;
  +1746/-192, 31 files; root untouched; zero heavy
  confirmed). First-hand: W1 5dc1433 cherry-picked clean;
  R4 e646cb1 extracted (already source-accepted); G3
  0b61af6 + G6 4a3b5fc PORTED (union context); W2/W3
  070ad99 cherry-picked. N9 HELD OUT (R1-latch production/
  run_jobs_done unaccepted, can't stand alone — reviewable;
  tension with N9-admission-for-R4 note recorded). MSS
  de0edc7 NO-OP subsumed (union line_cm covers —
  reviewable). RETRACTED: donor NOT subsumed — 4a/d120557 lack
  workspace.bend, sessws_s1s5_demo.bend, ceiling rollback API
  (Session 19228d16, Workspace 46bd523b, fixture 5d341278);
  preserved through 112 + final merged review (see appended
  entry). Holds verified: K02 root literal 1/1 (0
  /history); Q2 file (history_search.bend test helper)
  untouched; LAWS/PROOF +97/-0 (additions only, incl
  g6_live/proto_atom/styled/media_soh laws); Session +1
  field ONLY (boxed reg List, media/cf idiom + unbox_reg,
  documented 247-word rationale). session.bend 508-line
  G6 churn queued for independent review. ACTIVE: 106
  only (5 steers REQUESTED).
  106 BOUNDARY ENFORCED ~08:40 (bound ~08:38, running at
  08:39:39): cancel accepted with reason; tree quiesced at
  68112df + dirty live_context/preferences_live/wsnet;
  checkpoint COMMITTED a5be434 (unreviewed, not accepted;
  tree clean). Lane reaped BY VERIFICATION: one transient
  PID 26152 (sh, 106-tree cmdline) observed aging 21s->37s
  then GONE on its own; zero children under supervisor;
  NO kills, NO inference from frozen logs. Successor NEXT
  (after fixture commit): INITIAL original-scope ALL
  gates/deps + 5 counterexamples (guidance/dependency/G4/
  G2/media), concrete checkpoint a5be434, no history-only
  or fixture-only fallback. Heavy lane UNOCCUPIED (no
  grant taken; staying source-only until explicit).
  FIXTURE v3 (fragment-prefix hole, reviewed blob dae6ebc0
  @214 lines): shadow detector ABANDONED (prefix released
  pre-Dial + framer reset = false green even with broken
  fence). REWRITE: ARM hold-all-old at old AuthResult
  (phase-gated, split-immune); peer-close-first (teardown
  already accepted elsewhere); Eof-bounded hold incl Eof;
  live_step_keys redial; fresh Awaiting gate; byte-exact
  held-flight assert (prefix genuinely held); split+whole
  driver cases. rel trio VERIFIED positive (kept).
  G3:183 QUEUED (new-task fixture): g3_traversal.bend:183
  styled-nonkey-mode-renders (path absent from 4b4cbef);
  needs raw-preservation/provenance correction like N9;
  old Q1 holds remain; no weakening. After fixture.
  UPDATE ~09:15 (supersedes HOLDS/lean/no-op lines above; verified
  provenance kept; production deadlines UNCHANGED; final proof =
  `make check PROOF_TIMEOUT=600` standard checker only):
  Q1-Q5 ALL user-APPROVED to exact questions (not blanket
  weakening): Q1 four legacy fixtures (valid IRC style bytes,
  visible text kept, hostile-control checks kept); Q2
  sub_fetch_before_stamp .000Z + exact /history catalog, all
  else frozen; Q3 /theme completion + intent nine->ten,
  lifecycle/paint/persistence integrable; Q4 six notify
  reset/off/cancel busy+completion corrections, guards
  frozen; Q5 PONG-trace nonzero request IDs, order/timing/
  QUIT frozen + reject-zero/reject-exhausted guards. 114
  (from d120557, source-only) integrates Q1-Q5.
  113 N9 native qual BLOCKED FLAKY on 6a795ed13f66b (gate
  test-notify-held-blocked, fresh rebuilds, pipefail):
  run1 exit 2 (missing `expired`: fixed 2000ms Process.run
  killed fake helper first), run2 exit 0
  (`notify_held_blocked=ok`); fake measured 1.14-1.38s
  standalone. Logs /private/tmp/n9_qual_6a795ed_{fresh,
  rerun}.log. Lane verified reaped (result_ready, worktree
  cleaned, no work item) and handed to 115: narrow
  unreleased-helper retime 18x50ms -> 2x50ms ONLY (2000ms
  prod, latch timing, 300ms checks, all expectations
  frozen), 3x fresh requal min, no timeout-as-green.
  112 full-IO runs at /private/tmp/birc-106-successor
  (branch 106-successor-fullio @3228297, parent a5be434;
  assigned isolated tree is pristine 4b4cbef spawn
  checkout, NOT the work path). WIP-accepted: first
  frame/input/halt before load/boot/Begin; media lease
  persists; wrong-ticket retained; endpoint gen bump
  discharges endpoint field; one prefs forwarder. THREE
  residuals relayed: (1) ws_load.one_got:1374 must keep
  edit-wins media (not M.initial(on)); (2) reconnect-
  clears-lease must M.reject surviving Part (retained
  M.active blocks take_job); (3) union_tokens:837 needs
  all-Part capacity gate, not List.take8 truncation.
  Cards/Notify WIP; no whole-source/runtime accept.
  MSS take-3 abb4be8 Final scoped SOURCE ACCEPT (causal
  path genuine); take-4 02185a8 adds latched ':s '+'903'
  split + exact JOIN #t (Bend 30138be4, Py c77c79b4),
  pending reviewer pin. G3:183 fix active (Main,
  source-only; independent of Q1 four-file approval).
  UPDATE ~10:10 (explicit statuses, not checkmarks; lane
  now free; final merged check600/PTY3/Nix-hot-cache OPEN):
  MSS a004f3e FINAL scoped SOURCE ACCEPT (capture/prefix
  latch 432-461, EOF-before-redial 426-430, fresh AuthResult
  phase 304-323 pre-FIFO, bridge IO 139-153 pre-ACK255,
  edge/code/byte guards 173-180; App arm mode=app ONLY
  621-629; Actor/WsNet/Workspace/AuthBridge/native bridge
  unchanged; driver 61852d85 unchanged; 60s driver deadline
  kept). take5h native Error124 (CC 180s killed on 19.5MB
  app-closure .c) -> take5i 73cb4cd timeout300 BOTH build
  steps (shutdown_flush:632-633 precedent). take5i NATIVE
  GATE PASS: bend ok, CC ok, driver whole=ok split=ok, no
  make Error; binary 6891088B 10:06; log
  /private/tmp/mss_fixture_native_take5i.log. FIRST
  real-socket MSS native pass.
  114 4068edf (branch q1q5-approved-integ): Q3 scoped SOURCE
  ACCEPT (actualSession select 3020-3039, Net paint 164-177
  keeps_cm/boxed-media/cards/fullscreen/theme, prefsLive
  33-36/83-88, runtime 119-126; guards mostly
  session_paint_vm NOT actual Net runtime;
  cmd_around_stamp_prefixed stays distinct, pending). Q5
  NOT CLOSED in 114 (defaults False 186/394, live
  1213/1223/1232, allzero accept 1104-1110). Q4 ABSENT from
  114 (117 accepted-N9 import must bring six approved
  completion corrections).
  Q5 Main followup ad65566 (same branch, source-only, no
  Nix lane): strict_zero flag REMOVED (default rejects
  zero/exhausted; no opt-in remains); paired DEFAULT guards
  zero-chain-default-refuses + nonzero-chain-default-pairs
  (identical seqs); ambiguous-receive migrated nonzero
  Cont-space txn7 (two-candidate ambiguity preserved);
  double-reply-ambiguous migrated PONG_TXN x10 (two-branch
  selection refusal preserved); ALL order/timing/QUIT
  assertions kept; live 1213/1223/1232 now default-strict
  unchanged; oracle self-test 54 =ok exit0, log
  /private/tmp/q5_selftest_114followup.log. STATUS: awaiting
  pinned review, NOT accepted.
  115 8080621 retime: 3x actual exit0 logs on record.
  116 74763b3 C8 Final PARTIAL: first-key /images-off
  seed/merge + stale M.reject release + untruncated union<8
  admission PASS source review; residual capacity retry loop
  (rejected:1031 -> ws_media_stage clears active with NO
  failed/ready identity -> same-helper refetch EVERY
  completion) -> 119 followup.
  119 dc44e98 (branch 116-followup-norefetch, parent 747):
  shared M.reject_full media.bend:461 + ws_media.rejected_full
  + gated-False arm wsnet:1036/1067; 15 full8-* + 7 seven-*
  guards in wsnet_gates (registered test-wsnet-gates,
  Makefile:307); 116 seed/stale fixes preserved; Manual
  st_active_b correctly NOT used (no *preview* buffer).
  STATUS: SOURCE scoped (retry loop corrected per root
  read); NO native IO pass; verdict pending.
  117 5ab0e71 (branch notify-upload-repair, parent e51, 15
  files +1841/-170): BLOCKED, NOT accepted, DO NOT
  integrate. Pinned blockers: C8 ws_upload_complete
  1243/1245 STILL OMITS required notify,cards args (defs
  1222/1232 require both); new upload guard standalone, NOT
  test/check registered. Wire: five-field WsNotify REPLACES
  accepted Sess.NotifyLive; origin always empty 494/551; no
  accepted claims/reset/off/cancel owner calls; >8 mentions:
  N.stage ninth+ unadmitted, completion drains queuedReq
  then returns 535-544/1121-1129, NEVER rescans retained
  live rows -> ninth+ permanently lost absent later alert.
  Verified OK: per-ID mention classification + detached
  Process. Awaiting scoped finals -> fresh narrow full-owner
  successor with ALL initial gates, accepted N9 ownership
  reuse, no mini policy. 118 Cards still source-only
  running. G3:183 still QUEUED (lane now free; awaiting
  order).
  UPDATE ~10:20 (inner-exit receipts saved; 2 successors
  spawned; task checkmarks NEVER equal whole accept):
  MSS take5h inner MSS_NATIVE_EXIT=2 (Error124 CC timeout);
  take5i inner MSS_NATIVE_EXIT=0 (bend ok, CC ok, whole=ok
  split=ok, no make Error); binary 6891088B Oct4 10:06.
  Source a004 ACCEPTED; native PASS recorded.
  119 dc44e98 independently C8 SOURCE ACCEPT (retry loop
  corrected; inherited Make check registration via
  test-wsnet-gates). Q5 ad65566 independently scoped SOURCE
  ACCEPT (strict flag removed, default zero/exhaustion
  reject, paired nonzero guards; old order/time/QUIT/
  ambiguity/selection assertions intact; NO assertions
  removed; no jobs/runtime claim).
  117 5ab0e71 Wire Final NOT ACCEPTED (blockers stand).
  Spawned 120-notify-successor (gates 1-4: endpoint-only
  2^44/Sid0-silence; ninth+ all-9 drain; histload installed
  archive-DM quiet; origin/claims/reset + blocked-oldworker
  release; actual IDs/framed bursts; R4 package/attribution
  addendum with N9 fixtures + six Q4 expectations; register
  test-notify-binding-gates) and 121-upload-worker (ONLY
  notify,cards completion args 1243/1245 + completed-frame/
  Enter+F8 launch/cancel guards + register
  test-ws-upload-consent-gates), both from 5ab0e71,
  isolated, source-only. 118 Cards still running. Cap R4
  final pending. Main SOLE heavy lane: G3:183 active;
  normal integration of accepted owners starting in
  parallel; final merged 600/native/PTY3/Nix-hot-cache open;
  no push/pin update; platform skip is NOT green.
  UPDATE 2026-10-04 01:20 UTC (actual clock; checkmarks
  NEVER equal whole accept):
  Cap R4 Final scoped SOURCE ACCEPT on 5ab helper/package
  impl (direct argv, absolute backends, optout, redacted,
  bounded, async child; captured channel + global monotone
  ticket => blank origin alone NOT proven double worker;
  hardening speculation RETRACTED). REMAIN cross-Sid failure
  attribution + absent 3 fixtures/Make guards (in 120
  INITIAL addendum). No jobs/runtime pass.
  115 EXACT (branch n9-neg-timing-repair, base 6a795ed13f66,
  tip 80806217b0968e0917b8b758c17223bcf0caf4f8, Makefile:603
  1-line): each run = rm -f build/notify_held_blocked{,.c} +
  make test-notify-held-blocked via sh /tmp/n9_gate_once.sh N
  (pipefail, fresh PHONY rebuild); run1 exit0 224s, run2
  exit0 90s, run3 exit0 83s; all notify_held_blocked=ok.
  Timing: /tmp/n9_before_timing.sh 1.833/2.682/3.517s vs
  /tmp/n9_after_timing_predict.sh 0.541/0.804/0.840s.
  Script /private/tmp/n9_gate_once.sh; full report
  /private/tmp/ret115_full.txt (session 01a1043c-f73e seq
  981). Lane released by 115.
  G3:183 fix 731cbd9 (w2w3-g3, 3 files, 3 lines): donor
  070ad99:1047 drops Irc.sanitize_in at client.bend:708
  feed_mode.got (raw-preserving MODE render); donor
  070ad99:183 migrates traversal:181 expectation to raw form;
  framed:94 same-pair migrated (framed absent from donor
  line; kept green here). Pre-fix baseline g3_traversal=ok
  exit0 (WRONG-GREEN stripped). Post-fix: traversal=ok
  G3_TRAV_EXIT=0 + framed=ok G3_FRAMED_EXIT=0. Logs
  /private/tmp/g3_183_qual_{base,fixed}.log,
  /private/tmp/g3_framed_qual_fixed.log. Root pin-review
  pending after results.
  121 30d4ee4 returned CLEAN (branch upload-residual-repair,
  5095ec2/f37f82e/30d4ee4): C8 PARTIAL confirmed (notify,
  cards args fixed 1243/1245; test-ws-upload-consent-gates
  registered test-review-pure:749 + test-upload:435).
  Native/boundary OPEN: f37 guards inject
  ws_upload.presented + call key wrapper 22,0 separately
  (NOT enter=True/typed /upload via actual frame handler;
  launch-once is pure-state seam, NOT helper receipt). DO
  NOT call actual-boundary pass. Main to own bounded
  native/PTY frame + physical fake-helper +/- qual (warning
  completed pre-F8; coalesced Enter+F8 no-launch; next F8
  once; cancel never helper; 3 runs if new PTY).
  Spawned 122-upload-qual-prep from 30d4ee4 (source-only
  prep: actual-entry fixture + driver + fake helper +
  standalone Make target; Main runs). NOTE: 120/121 briefs
  carried base typo 5ab0e715 (actual 5ab0e713); 121 caught +
  verified parent e51; VERIFY 120 base on return.
  Integration STARTED: candidate .muse/worktrees/
  final-candidate @ e51fe89 detached. Lines: 4b4cbef-line
  (ad65566/73440cc/d120557/731cbd9), e51-line (dc44e98/
  30d4ee4), neither-line (8080621/73cb4cd); merge-base
  ca30774c (9k vs 13k insertions). ad65566-into-e51 probe:
  9 conflict files (LAWS/Makefile/PROOF/buffer/cards+cards_net
  AA/net/session/view; list /private/tmp/
  final_conflicts_ad65566.txt). Merge execution next. 118
  Cards + 120 Notify still source-only running.
  UPDATE 2026-10-04 01:37 UTC (merge done, qual owned):
  MERGE ad1822a (dc44e98=119 + ad65566=114Q1/Q2/Q3/Q5)
  committed in final-candidate. Per fixed-index guides:
  LAWS/PROOF union (stage2 17 AD/WS/Sess + stage3 269;
  both imports); Makefile union; cards/cards_net stage3
  wholesale (superset); net stage3 CardFetched arm (drained
  entry verified); buffer stage3 _cm + stage2 bell/log/ceiling
  kept, no default-only is_mention.on; session MSS ceiling
  rewritten around ONE stage3 pair (whole extended revert;
  prepass deleted; single chain deleted as callerless);
  ceiling entries + supplied_normal + 8 more sites extended
  to 22-field Session (iso/hl/theme preserved; dial resets
  reg by design); step_keys.normal = stage3 wrapper chain
  (history/intent/plan over iso base); orphaned routed/typed/
  is_multi_route removed; view cm cascade + cards variants;
  media_run_hit twin-dup removed. KNOWN 114-carryover (needs
  scoped repair, NOT merge scope): ipv6_transport_native.bend
  duplicates dualdnslazy_* defs (pre-exists ad65566).
  Cherry-pick c0aa912 (73440cc theme Gate2): reduced to
  ONE-path comment (code already via Q1; Links path absent,
  Ws render_spans present). QUEUED: G3 731cbd9 pick (client
  1-line + traversal line; framed file add), N9 range pick
  (fixture+target+8080621 retime), MSS range pick
  (bc3d9c0..73cb4cd fixture+driver+target).
  G3 731cbd9 scoped SOURCE ACCEPT independent (raw keepstyle
  Client/framer, shared Ws controls, redaction BEFORE log, 2
  positives only). Root read traversal/framed=ok, inner 0.
  118 79f459b (cards-fullowner-repair, 7 commits, +880/-64)
  NOT whole-accepted. Review partials: C8 physical lease
  BLOCKER stands (per-Part only, no global lease); Cap
  positives (inline paint, scheduler share_cm, bounded
  spawn/direct argv/captured ticket+URL/own channel, Make
  reg); NEW-task fixture INPUT typo 'a{b}'->'a{b' (keep
  asserts); negotiated-005/Theme/Ws-renderer + Session feed
  guard OPEN (no mini-ISupport copy). Spawned 124-cards-phys-
  owner from 79f459 (INITIAL A/B/C: global single worker,
  removed-origin release, fullscreen hidden-underlay + typo
  + cm/theme gates; source-only). 120 Notify + 124 Cards
  running; 121 slot freed then 122 spawned+returned.
  122 9b637c1 (upload-actual-boundary-prep, +450, 3 files)
  NOT actual-qualified: constructs UiKeys, direct painted/
  keys calls (no frame/ws_paint/T.frame), DEVNULL driver, no
  START barrier, no UploadFetched routing (target standalone
  752). Cap positives kept: App anchor, FFI aliases, bounds/
  temp/argv. Oracle gap: must reject unknown/malformed
  ledger + exact TOTAL. MAIN OWNS genuine correction NOW:
  actual ws_first.frame/ws_paint/Timui.frame on owned PTY,
  receipted warning completion, latched START/release helper,
  routed UploadFetched, next-F8-once/coalesced/cancel cases;
  3 PTY runs; register after true qual. No 4th wrapper.
  UPDATE 2026-10-04 01:39 UTC (120 consumed; reviewer on):
  120 20ccf1c (notify-successor-repair, 5 commits) RETURNED
  CLEAN (base verified 5ab0e713; brief typo caught): mini-
  owner REMOVED (per-part NotifyLive + global lease, floors/
  marks only in NotifyLive); gates 1-4 (seed_all floors,
  rescan/drain-merge/steal, install claims via
  history_accepted, fence/reset/release-once); attribution
  via captured owner+ticket+endpoint (wrong-sid drops are
  hardening-only); N9 fixtures verbatim incl six Q4
  expectations; binding + N9 targets registered (:586,740);
  ~75 framed-burst asserts, no Feed counts. FLAG: touched
  net/live_context/view/theme outside ownership (isolated,
  minimum for verbatim import + gate3). STATUS: needs
  Wire/Cap pinned review; NOT accepted; no jobs. Full report
  /private/tmp/ret120_full.txt. 124 Cards running; slot free.
  c0aa912 (merge + theme pick) first-hand verified CLEAN by
  root; whole/merge reviewer started pinned (read-only, no
  jobs; 120/124/UploadQual/pending-timestamp excluded as new
  findings). Critical regressions relay, NOT acceptance
  block for in-scope progress. Integration continues (G3/N9/
  MSS picks queued). Cap122FINAL: direct argv/local temp/
  alarm/fresh recipe App anchor + aliases confirmed; actual
  frame qual still missing. LEDGER ORACLE FIX (driver
  63-85): reject malformed rows/unknown kinds + EXACT TOTAL
  two starts (once, busy); paired forged-extra/malformed
  negative + exact positive. In Main's qual scope.
  Upload qual survey (upload-actualqual @ 9b637c1): entries
  mapped (ws_first.frame paints+reads real keys;
  paint_session -> T.Timui.frame; upload_spawn ->
  BIRC_UPLOAD_HELPER -> UploadFetched on evt chan ->
  ws_upload_complete fixed args). F8 = TIMUI_KEY_F8 (ffi
  14278). Design: PTY-driven real frames (composer pattern),
  receipted warning bytes, START/release helper, routed
  completion, exact-TOTAL oracle. No network/auth/uploads.
  UPDATE 2026-10-04 01:39 UTC+ (picks executed):
  Candidate 178b779 (= ad1822a merge + c0aa912 theme +
  MSS). G3 731cbd9 pick = NO-OP: production raw fmt_mode
  already at client.bend:1047 + traversal:183 raw
  expectation already present (both via ad65566 donor
  content). g3_framed NOT resurrected: absent from BOTH
  accepted parents and deleted on donor line; resurrecting
  200 unaccepted lines for the 1-line same-pair is scope
  expansion. Recorded for root confirmation.
  N9 6a795ed/8080621 pick DEFERRED (explicit, not skipped):
  qual fixture needs N9 production APIs (Sess.notify_live_*,
  NotifyIO.notify_live_spawn, UNREL env) absent from
  candidate (old 248-line notify.bend, zero UNREL refs).
  Integrating qual-against-mismatched-owners = broken.
  Correct vehicle: 120's branch 20ccf1c (matched verbatim
  owners + fixtures + targets) AFTER 120's pinned verdict.
  MSS pick DONE (178b779): fixture 635 + driver 209 (new
  files @ 73cb4cd) + target/phony/review-pure registration
  (timeout300/aliases/60s driver preserved; vars verified:
  BEND_CORE_CFLAGS ?= :79, ALIASES :711). Re-qual on merged
  tree OUTSTANDING (lane; queued behind upload qual).
  Next: Main's genuine upload fixture correction + 3x PTY;
  then MSS re-qual; then final check600/native/PTY3/Nix.
  UPDATE 2026-10-04 01:39 UTC++ (6 findings checklist):
  Reviewer FINAL on c0aa912 (production unchanged thru
  178b779): (a) DIRECT BOOT: BIRC_PREFERENCES=none first
  frame /connect B switches Session + Dial B/gen1, but
  ws_boot.each1580/ws_start1798 boots CLI A on post-key
  gen1; Actor911/969 drops equal-gen B Dial; A traffic
  admitted into B scope/history. Fix: boot from POST-KEY
  Part endpoint/client/auth (or honor routed Dial before
  direct Begin); reuse startup owner; actual +/- loopback
  endpoints (only-B/no-A, direct-A unchanged); preserve
  deferred + auth fences. (b) MULTILINE PRIVACY:
  multiline_sensitive.line3159 uses fixed input_sensitive
  (vs iso2834); CHANTYPES=$ rejected '/mode +k s3cret\nhello'
  sends no wire but HistPrev keeps raw secret3172. Fix:
  thread iso into hist_after_typed + shared
  input_sensitive_iso; AD/W key - keeps composer, EMPTY Hist,
  no wire; + recallable/no wire; asserts preserved.
  (c) SearchDone dropped ws_routed.msg1295: needs exact
  helper completion/removed-origin guards WITH Search
  dispatcher. (d) DRY: media45/52 same type/body; one shared
  body + compat delegator; fix stale different-type comment.
  Disposition: 125/126 started BEFORE these gates arrived,
  so gates NOT consumed (verified: briefs fixed at spawn;
  no steers per standing rule). Main owns (a)+(b)+(d) as
  isolated candidate commits NOW (source-only; boot runtime
  qual queued on lane). (c) QUEUED for 125 follow-up round:
  guards must target 125's in-flight Search dispatcher;
  pre-building against nonexistent code = collision.
  UPDATE 2026-10-04 01:39 UTC++ (124 in; Main owns 3):
  124 0d1885e (cards-physical-owner-successor, 3 commits:
  1e5e513 A/B/C, 2a2c45f typo, 0d1885e gates+Make) RETURNED
  (base 79f459b verified; C8 pins matched): (A) WsCardsLease/
  WsCardsAll bundle mirroring ws_mlease (free/exact/live,
  spawn_ok single gate, retired_if exact); (B) released/
  gone/retired exact removed-origin release; (C) cands_open
  via maintained overlay; typo 7 inputs fixed, asserts
  byte-identical; 49-guard physical gates + Make:744.
  STATUS: needs C8/Cap pinned finals; NOT accepted; no jobs.
  Report /private/tmp/ret124_full.txt.
  Main-owned corrections committed isolated on candidate:
  565f8c3 DRY delegator, d3a31fd boot-from-post-key-parts
  (mirrors ws_begin_all; runtime loopback +/- qual queued on
  lane), 7295ed2 iso-threaded hist_after_typed (AD passes
  session_iso). Candidate now 7295ed2. SearchDone1295 stays
  queued for 125 follow-up. Next: genuine upload qual
  (lane); 125/126 running; 120 verdict + 124 finals pending.
  UPDATE 2026-10-04 01:39 UTC++ (120 review -> restore+127):
  120 20ccf1c review CLEAN, NOT whole-accepted. Positives
  real (per-Part lease, rescan, captured channel, R2/R4, six
  Q4). THREE regressions: (1) reconnect loss (Dial gen bump
  vs fresh_nl at post-inbound seq; burst self-seeds
  scanned); (2) R1 guard deletions vs 808 (chained
  wrong-ticket->wrong-origin RETURNED asserts, UNRELEASED
  negative, comp_received nl_c reset, weakened always-done
  recipe); (3) binding direct-spawn attribution bypass (d0
  ignored, g1_c1 precomputed; Make:744 not a blocked qual).
  Main restored EXACT 808 NOW: 6e25c58 (fixture blob
  4c9da06 identical; recipe UNREL + main18 + negative2 +
  expiry; all other N9 blobs verified SAME). Spawned
  127-notify-followup from 6e25c58 (INITIAL: pre-accept
  reconcile + deliver-once/lease-held/same-gen guards;
  comp_received threading for restored asserts; START/
  release attribution + A/B-only + all9 + replay-quiet;
  targets stay standalone for Main's lane qual). Native
  notify qual pending; check600/cache still open.
  UPDATE 2026-10-04 01:39 UTC++ (5 merge faults -> workers):
  Pinned c0aa912 review: FOUR NEW verified omissions (new
  merge faults): (1) ws_emit.to lacks Pong/Search arms;
  (2) on_routed_chunk.gated calls ceiling-only, never
  drained (H5 batches never imported --server); (3) keys_done/
  tick never invoke typing tick owner; (4) Chunk{xs,req} ABI:
  Workspace/WsNet still one-field. FIFTH: Drafts/AD Irc.ieq
  aliases #a[/ #a{ under ascii (moved=False, drafts clobber;
  F7 current_key_draft too). Spawned 125-workspace-parity
  (gates 1-4, H5/Net/G6 owner reuse, Q5 preserved) + 126-
  drafts-casemapping (session_cm threading, default
  delegates, ascii-distinct/RFC1459-alias/origin-retain
  guards), both from c0aa912, isolated source-only, no
  jobs, overlaps via isolated commits only. Main: upload
  qual (lane) + controls sole lane. Final checks/cache open.
  CURRENT STATUS 2026-10-04 02:45 UTC (Main lane; root/master
  4b + candidate 7295ed2 unmerged; whole-app NOT done).
  SOURCE ACCEPTED: 126 e7f255 narrow (Wire); 125 58bd760
  positives; 128 0624f99 H5-ceiling+wgen (Wire+fresh, no
  exec); 05373ba h5c oracle refused-vs-live-only (clean
  read); 127 8d1e4dd floor; f8888d4 3 physical gaps
  behavior; 12a17ca sp_nnot+ linear; 744 Scope-A single-Dial
  owner; 72080b8 implicit MODE counterexample + 347e37b -k
  visibility pair (source counterexample until red
  experiment/check); Cards 44ef93f production +
  bac3fe6/d6137a1/2fd6b9e/a5a55af/0f26c2e compile-shape.
  UNREVIEWED: Cards 71ea414 tip (ab98563 kf 2-pattern,
  4f3c7af job lets, ae09498/3df182c lease_found, 71ea414
  cm_lines region).
  EXACT INNER: owner run13 cards_owner_gates=ok GREEN,
  OWNER_EXIT=0, /private/tmp/cards_owner_run13.log; native
  run9 SOME_PROOFS_FAIL consumed +tuple/Data,
  HANDOFF_EXIT=2, /private/tmp/cards_handoff_native_run9.log.
  STILL OPEN: true Upload actual-PTY/frame START-release/
  exact-total 3 runs; boot native -/+; exact-merged
  MSS/native + check PROOF_TIMEOUT=600 + PTY3 + Nix
  prebuild hotcache + installed helper quals;
  sessws-s1s5/history-wire2/workspace on merged lane;
  legacy cmd_around timestamp approval unchanged. Main sole
  heavy lane; all source workers returned.
  UPDATE 2026-10-04 02:50 UTC: C8 Final source ACCEPT
  71ea414 (5 test-only repairs, asserts intact). Native
  run12 inner: run_mode forward ref at run_case:163,
  HANDOFF_EXIT=2, /private/tmp/cards_handoff_native_run12.log.
  Fixture dispatch reordered (runners before run_mode/
  run_case). Run13 native next. Not green until actual.
  UPDATE 2026-10-04 02:55 UTC: native run13 inner ctx
  mismatch (fixture preferences_live vs production
  live_context), HANDOFF_EXIT=2,
  /private/tmp/cards_handoff_native_run13.log. Fixture now
  imports live_context as PrefLive + 4-arg initial (same
  alias/shape as production; production untouched).
  UPDATE 2026-10-04 03:00 UTC: native run14 inner args
  region-1 +list/Data, HANDOFF_EXIT=2 (fixed linear).
  Native run15 inner C-backend 'Error: an arity over
  247', HANDOFF_EXIT=2,
  /private/tmp/cards_handoff_native_run15.log; elaboration
  green (--check-only exit 0). Owner-gates C-codegen probe
  WITHOUT fixture passed (exit 0): bomb is in fixture got_on
  reach. got_on-stub bisection running; C8 read-only Box
  review assigned. No Bend/pin/deadline changes.
  UPDATE 2026-10-04 03:10 UTC: per-stub codegen verdicts
  (clean dc971aa unless noted): run15 arity FAIL exit 2;
  owner-gates C probe PASS (5.0MB .c); stub1 1/3 got_on
  arity FAIL; stub2 3/3 got_on PASS (409KB .c); stubA
  tokened-body PASS (2.6MB .c); stubB paint INVALID (stub
  dropped linears, no .c); stubC act-subtree arity FAIL
  (valid); stubD keys INVALID (same); stubE killed for
  lane serialization (no verdict). App.main on CLEAN tree
  serialized: arity FAIL inner exit 1 (production defect,
  not fixture-only). Bomb in tokened-body reach outside
  act-subtree. stubE rerun next, serialized.
  UPDATE 2026-10-04 03:29 UTC: stubE2 begun_after arity
  FAIL inner 1 (excluded); stubF3 ws_post->pure PASS inner
  0 (9.1MB .c): bomb in post stages. C8 scalar-hoist fix
  3cc7e2d in ws_media.job (clear/repaint above binds;
  SOURCE ACCEPT, +8/-4). Run16: Bend codegen PASSED
  (11.9MB .c, arity cleared) but CC FAILED make Error 1
  (7 undeclared TimUI CID + 3 follow-on; HANDOFF_EXIT echo
  missing from persisted log, implied 2),
  /private/tmp/cards_handoff_native_run16.log. App-main
  clean-tree control: arity FAIL inner exit 1 (in-band
  output, no raw log file; no .c emitted). Fixture
  af99f399 adds App.main dynamic anchor only (MSS
  precedent; 3 modes/asserts unchanged). Run17 (bend->CC)
  in flight on af99; CC/runtime pending. Not green.
  UPDATE 2026-10-04 03:42 UTC: run17 CC PASSED, binary
  ran; handoff mode rc=0 but golden rejects (ESC[?1002h +
  token same line; strict grep -F -x kept). Raw 3-mode rc
  on run17 binary: handoff/wrong/quiet ALL 0 (semantics
  good, framing only). Framing fix committed (newline
  before token x3). Run18: inner timeout 300 killed bend,
  make Error 124, HANDOFF_EXIT=2,
  /private/tmp/cards_handoff_native_run18.log (231 bytes,
  bend emitted nothing). Borderline App-closure codegen:
  run17 + stubF3 passed same closure; CC alone ~5min on
  23MB .c. Inner 300 deadline preserved; rerun with outer
  1500 wrapper + time phases next. Upload frame worker
  returned 7641034 (3 new files, prep retained, NOT-run);
  boot-guards worker active. Not green.
  UPDATE 2026-10-04 04:00 UTC: CC measured on run19 23MB
  TU: 237.96s real / 203.72 user / 11.34 sys / 2.65GB max
  RSS, binary emitted (8.2MB) to /tmp (build/ pristine);
  log /private/tmp/handoff_cc_measure.log. Fits 300 with
  62s margin; run19 timeout unexplained by typical case
  (load-sensitive tail). Justified: one bounded gate
  rerun (run20) with in-tee echo. Upload flow rework
  91163e8 (same-request held, reap owned PIDs, no jobs);
  boot-gaps worker spawned for CAP/ledger/scope/Make.
  Not green.
  UPDATE 2026-10-04 03:50 UTC: run19 bend PASSED but CC
  step timed out (make Error 124, HANDOFF_EXIT echo lost
  to truncation, implied 2),
  /private/tmp/cards_handoff_native_run19.log. 23MB
  app-closure TU needs ~300s CC (run17 fit, run19 did
  not). Flake-vs-code NOT established from timeout alone;
  no blind identical retry. Next: measure CC elapsed +
  owned CPU/RSS (default-off), then justified bounded
  step. Inner deadlines preserved. Boot worker
  returned 19fdeee (verified clean); C8 reviewing. Upload
  764 + cfd binder fix under review; blocker repairs
  (coal continuity done, drain/safety/negative pending).
  Not green.
  UPDATE 2026-10-04 04:51 UTC: Cards seam native GREEN
  (scoped, not App/Nix): source
  608c7f6b870c5fa11f7ddcb1bb21e0fbefef3f0a, fixture blob
  b56b2c52ca4c5cee82a4dc967bb05eb0d47fbd0b, codegen300 +
  CC300 + 3x60 runtime all strict, 3 ok tokens,
  HANDOFF_EXIT=0, /private/tmp/cards_gate_608c7f6.log,
  binary 4292472B SHA256
  bf52e9f0d367bade7aa5a6d6a6a4bbdaa3c1e906957e064fde5c1ffb1b691a39.
  Run20 strict codegen124 HANDOFF_EXIT=2 stands (cause
  unknown, no flake label). VERIFIED PINS: Boot
  32a02caa141edc357f5ec81c6f9189731d83b544 (sentinel-ack
  seal, counted deliveries; reviewer rechecks, no jobs);
  Upload 810afc1 + UNCOMMITTED 41-line close-order delta
  (post-release check, verified flag) in
  .muse/worktrees/w-upload-frame; scratch merge
  .muse/worktrees/w-upload-cardsbase has unresolved
  Makefile/wsnet conflicts (held). REMAINING: Upload
  close-fix verdict + Cards-base merge + clean pin, then
  normal/linger/late PTY; Boot seal verdict + native
  -/+; whole actual-first-frame/boot qualification
  still open (Timui.frame/ws_start.boot not covered);
  FINAL check600/native/PTY3/Nix per C8 order. Main sole
  heavy lane; no all-green claims.
  UPDATE 2026-10-04 05:05 UTC: Wire scoped SOURCE ACCEPT
  Upload close-order (snapshot blob
  b64220282ac0e16e52408b7df71de1f1e78030a4 verified
  unchanged) committed narrow as
  85dd9ecf32137865797376e910c563bd6ee0bb26 in
  w-upload-frame (clean). Port to scratch after merge
  repair review. Runtime HELD until coherent Cards
  off/global-owner binding (normal+late exit0 exact;
  linger and forced post-held-START failure nonzero,
  group empty after release). Boot prefix 080fc7b
  blocked on modes/matrix worker; actual-boot gate
  worker active; scratch post44/Escape worker active.
  No runtime inference from source verdicts.
  UPDATE 2026-10-04 05:17 UTC: Boot workers returned,
  both verified clean. Modes/matrix
  92295786a7026b5d2bdbc8056e2cef2eee13a51f
  (unknown-mode nonzero reject, WriterDone->extraUp
  reject, post-WriterDone benign-Eof accept; fixture
  8f1ebdf852fe726cea9d0c6b76bf536d778b593a,
  driver
  057725e5d480b38c9245a36ddac47ef1da0aa100).
  Actual-boot gate
  4d4284845cb9f4fb1b17a24fbbc400dc1646cd8c
  (causal post-open READY gate, no pre-open writes;
  fixture 1d34b1dd21e719471fc5fb9ea8c32d9d9dc0489d,
  driver 05628ebd2f019ffcd99b3de77830287e8d18a48b).
  Both await recheck; gates held. Scratch post44/
  Escape worker nudged for progress lines only.
  UPDATE 2026-10-04 05:20 UTC: Scratch repair
  returned; staged merge untouched, repair is
  UNSTAGED delta in 2 files (verified by direct
  read): wsnet.bend +239/-~110 incl donor-exact 3cc
  +clear/+repaint hoist above IO in BOTH media-job
  branches, single ws_fullscreen.applied with
  handled->key zeroing BEFORE upload-key admission,
  post-44 adaptations; cards_owner_gates.bend +92
  fullscreen-before-upload paired fixtures. Blobs:
  wsnet dfce61f5379340ad73e6fb185948916c2ec7cb8f,
  owner-gates
  14136b6d1473586c4d2372005eb6ba24609c72a1.
  Complete tree ready for pinned source review;
  ABI check-only/native only after accept. All
  source workers returned; Main sole lane, no jobs.
  UPDATE 2026-10-04 05:25 UTC: Boot prefix-native
  qualifier RED at codegen (deterministic, not
  timeout): source
  92295786a7026b5d2bdbc8056e2cef2eee13a51f,
  fixture 8f1ebdf8..., driver 057725e5..., Make
  b08f7479... all match release; inner bend exit 1
  SOME PROOFS FAIL (fixture:737 case
  Sess.Chunk{+xs} binds 1 field, production
  session.bend:376 is Chunk{xs, req} 2 fields),
  BOOT_EXIT=2,
  /private/tmp/boot_prefix_9229578.log. No CC/
  runtime phases reached. CORRECTION: failure was
  imported PRODUCTION src/bend/workspace.bend:737
  (not fixture:737); clean922 fixture already
  two-field at 551/619. Narrow ABI repair committed
  075206f5c19c5b620a75a0c965fc74b3dcc774af
  (SOURCE ACCEPT; +req bind, Chunk{xs,req}
  reconstruct at workspace 737/1114, ignored +req
  at wsnet 839; 9 pure-fixture explicit-0 ctors
  deferred to broader proof). Fixture +lets-in-do
  (270-272/308-310) hoisted above do (probe B
  isolated illegality; probes removed). Check-only
  round 2: `+x : T <-` also illegal in do (probe D:
  no + on do-binders; probe C: no = in do at all).
  Rule: plain do-binders only, multi-use via
  +param .got helpers (production net_fwd idiom).
  34-site systematic rewrite dispatched source-only
  (boot-do-shape worker, no commit); Main re-runs
  check-only after. No green inference.
  Scratch c34ec7e: production behavioral/
  source-PARTIAL accept only (lease/off/admission,
  donor-3cc, fullscreen-first; NOT compile-shape
  complete). Narrow hold: wsnet:1369 +staged affine
  Sigma cannot copy; ported exact 608:1223 marker
  removal (one char, body/calls/WsNotify untouched;
  no other +typed tuples in c34 wsnet), blob
  e34334656e9f2c238c654efaedda0575be6d84dc.
  Second hold: quiet:172 CardInline{2n}->1n (chatBQ
  IDs 1,9; :176 unchanged; wrong-mode :162 2 kept).
  Two-line followup PINNED
  ab6b16a1084b87d8ac896780b9f45a7c6a1317fb
  (clean tree) for narrow review. Driver port
  e08369de5adf0cfb7727bd055327699f9f15351f
  (blob b6422028 verified). ABI r1 ALL4 EXIT1
  (/private/tmp/scratch_abi_e08369d.log):
  app/handoff/owner lack NotifyDone case in
  Net.on_msg_go:1040; upload fixture do-block
  pure +ctx:360. Narrow repairs applied
  (NotifyDone orphan case identical to
  CardFetched; run.go helper outside do).
  ABI r2: NotifyDone GONE; app/handoff/owner now
  report unsafe/foreign-reliance lists (check-
  only semantics suspect for IO entry points);
  upload fixture next: gate.fail +e tuple
  must drop + (not Data). No native.
  CONTROL: known-green cards_owner_gates (native
  run13 GREEN) ALSO fails --check-only with the
  same unsafe/foreign-reliance error
  (/private/tmp/control_check_owner.log). Thus
  --check-only can never pass IO-touching entry
  points: wrong gate. gate.fail +e->e applied
  (single-use, narrow, uncommitted). ABI needs
  reviewer direction (codegen-emit is the true
  elaboration gate); holding, no unilateral
  substitution.
  RESTART CHECKPOINT 2026-10-04 06:14 UTC (READY
  FOR RESTART; user approved, root owns restart).
  NO workers running; NO terminal jobs remain (up6
  finished naturally, not killed).
  PINS: scratch 469c58f + DIRTY 12/12 fixture-only
  delta (10x halt-plain, gate.tty Fail{e},
  run.go+ctx-annotation); boot 075206f + DIRTY
  do-shape fixture rewrite (uncommitted, unpinned);
  actual 9458c6a clean (HOLD2 bounds final);
  upload 85dd9ec clean; cards 608c7f6 clean.
  EMIT RECEIPTS (bounded 300, pinned Bend 2.0.34):
  app.c EMIT=0 22721994B
  f801e065a80f16e7966fbb6b0623aea3c1b12ad7917fd8985297652d72feb132;
  handoff.c EMIT=0 12219607B
  dcf93f8177057bad1131d76a6be397a82dbd6716ae147b7fab42fd33e01b1ff4;
  owner.js EMIT=0 604315B
  202a0d99c3d6b0239b7cdb5261d5a49350fc2d9260b54ac118bd31b400a8ba1d;
  upload.c RED up6 (ctx consumed-twice; next:
  `+ctx : Ctx = ...`, annotated-plus; probes
  proved `c : T = Ctor` fixes inference).
  Logs: /private/tmp/scratch_emit_469c58f.log,
  _up2, _up6.log; control_check_owner.log.
  PROBES: worktree *.bend probes already removed
  per prior orders; /tmp/probe_* + /tmp/
  handoff_cc_measure RETAINED, not deleted.
  HOLDS: upload RED/no native; boot do-shape
  needs bounded native C emit + clean pin/source-
  review (foreign/unsafe-IO check-only0 disproved
  by known-green control); actual9458
  HOLD2 bounds; 608 scoped-native only; final
  candidate UNINTEGRATED (C8 order pending).
  Root staged+unstaged preserved; no push/pin/
  checker changes. RESUME: `muse resume
  01a100f0-f389-7bd3-83d9-9774cbe4ec2b`
  (session soft-pavo, log under
  ~/.local/share/muse/sessions/2026/10/03/).
  RESTART RECEIPT 2026-10-04 06:28 UTC: old PID
  58383 exited naturally (absent from table), no
  workers/jobs killed (all had returned; up6 had
  finished RED). New PID 47279 same pinned Muse
  binary, same resume UUID 01a100f0-f389-7bd3-
  83d9-9774cbe4ec2b, elapsed 10:57 at verify.
  Restore delay (~8m46) is NOT evidence of a
  memory fix. All worktree pins/dirt retained
  exactly (scratch469+12, boot075+do-shape,
  actual9458, upload85dd9ec, cards608c7f6);
  root staged+unstaged G3 preserved. Park
  restriction lifted; Main sole heavy lane. Fixture reviewer
  confirms affine projections, Maybe recv, Result
  ownership, five-field WsNotify, got_on chain;
  final fixture report imminent; paired Escape
  guards pure-primitive scope (true Upload PTY
  still required).
  Actual-boot 4286578 HOLD3 (no native): quiet/
  OSError drain w/o EOF, uncapped retention,
  synthetic-only negative. Forwarded bounded-EOF/
  cap + delayed-physical-negative to active
  worker; probes confirmed removed from lane.
  Scratch pinned
  c34ec7eb6f187e38c0ed5746ef837f7b0f09430a
  (merge 44ef93f + post44/Escape + 608 guards-shape;
  clean tree; driver port + qualifiers held for
  review). Actual-boot 4d42848 SOURCE ACCEPT
  (initial window); lifetime worker unreachable by
  message (result pending; re-dispatch if plan
  missing). No upload native gate yet.
  EMIT 2026-10-04 06:40 UTC: scratch 1124049
  ws_upload_frame.c EMIT_UP7=0, 24180357B,
  SHA256 4859c1653c68e0deabcd85330f2c9f714659271fdd45c44b7320705048e689f0,
  /private/tmp/scratch_emit_1124049_up.log.
  All 4 scratch entries now emit-clean (app,
  handoff, owner.js, upload). No CC/run yet.
  BOOT 2026-10-04 06:50 UTC: d370 emit RED
  (unfilled-law proto_atom, irc:401 fwd-ref;
  /private/tmp/boot_emit_d370eab.log). Reorder
  pin 7296b46 SOURCE ACCEPT (124-line block
  byte-identical, proto_atom:515 before :526;
  irc blob 71de89b5; fixture c1e35344).
  7296 emit RED new cause: step_keys.intent
  session.bend:3067 enter consumed-twice
  (/private/tmp/boot_emit_7296b46.log). Smallest
  typed repair committed f1e0f83 (+typed/+enter,
  Keys is Data); re-emit running. No runtime
  qual on known-broken. Integration worker
  parallel, root G3 + 22-field ABI untouched;
  old-17 scratch wsnet NOT final donor.
  BOUNDS 2026-10-04 06:45 UTC: actual final-2
  pin e0965300d5089c672b11b7cdeb18334371ccc47a
  verified clean (driver-only 309+/5-, blob
  d475ee4ab675121270f46138a85f54ad8c7b5466):
  oracle read WIRE_CAP+1 overflow-reject, drain
  remaining<=0 explicit fail w/o widening 0.5s,
  paired cap-fit/overflow + timelyEOF/quiet/
  readerror/expiredreadyEOF guards. For review;
  no native yet.
  CHECKPOINT 2026-10-04 07:10 UTC (post-compaction, no restart):
  ROOT 4b4cbef dirty G3 intact (LAWS/Makefile/PROOF/TODO/auth/buffer/
  client/frame/...); no lane writes to ROOT.
  cards-handoff 608c7f6 clean GREEN seam (HANDOFF_EXIT=0); NOT App/Nix.
  w-boot-gaps 4e512ff + UNCOMMITTED wsnet moves: ws_post block above
  first use (770<773), prefs stage cluster above ws_post (734<748).
  No commit; compile-shape only, NOT runtime qualified.
  BOOT EMIT RED /private/tmp/boot_emit_wspost.log EMIT_EXIT=1:
  unfilled-law ws_prefs_stage used ws_post.carded:737, defined :804
  (def-order manifestation; filled body, use precedes def).
  Repair applied (cluster move); re-emit pending as sole heavy lane.
  Search9dd HOLD: must NOT forward to Actor (writer_command drops);
  reuse Net.emit_cmd Search-only owner, preserve captured fields/
  owning evt, add +/- dispatch guard. Donor picks/reorders do NOT
  authorize test weakening.
  w-upload-frame 85dd9ec clean; w-upload-cardsbase 1124049 clean,
  scratch C EMIT_UP7=0 24180357B SHA
  4859c1653c68e0deabcd85330f2c9f714659271fdd45c44b7320705048e689f0
  (inner emit only; NO CC/run yet).
  /private/tmp/scratch_emit_1124049_up.log EMPTY (0B); receipt is the
  byte/sha line above, not log tail.
  RED history: scratch_emit_469c58f_up4/5/6 Ctx affine-ctor errors
  (run.go:359-361), fixed by later pins.
  w-actual-boot e096530 clean, Final-2 source ACCEPTED; --bounds
  runtime + Make/check registration still pending.
  w-final7295 7295ed2 DIRTY (DISCREPANCY vs believed-clean):
  30 staged files +5752/-124 (LAWS/PROOF/actor/history_search*/
  live_context/net/notify*/timui/session_drafts/timui_ffi/
  workspace/wsnet + 9 new notify*/consent tests + check script)
  + 7 files with unstaged mods (drafts/session/session_drafts/
  workspace/wsnet/session_drafts_demo/workspace_demo). UNTOUCHED
  by Main this session; review as patch, do NOT whole-accept.
  final-candidate tree 7295ed2 clean (reference).
  INTEG WORKER RETURN: path .muse/worktrees/subagent-v2-01a100f0-
  f389-7bd3-83d9-9774cbe4ec2b-01a103ff-76f7-7dd1-b284-87303523a243
  branch final-candidate-integ pin
  4a3b5fc "integ: G6 live CAP/typing binding", tree CLEAN.
  No new owner/performance claim. Heavy lane: boot emit only.
  OWNER CLARIFICATION 2026-10-04 07:2x UTC (recorded, G6 scope cut):
  Pong exact-forward was field-mechanics ONLY; broader single-owner
  implication WITHDRAWN. Net.emit_cmd Pong branch stays quiet; actor
  reader is sole live-wire PONG owner. Actor.writer_pong does NOT
  dedup UI-forwarded Pong (matching gen queues it): no second sender.
  FINAL-source policy PRESERVED (verified in w-final7295 unstaged
  wsnet diff): quiet Sess.Pong{_,_,_} no-op + shared Net.search_spawn
  with wgen captured, SearchDone routed back via ws_search.got/done.
  Do NOT port boot-9dd Pong/Search forwarding into final.
  Boot Search shared-owner repair + paired guards still HELD; no
  whole-G6 accept until actual trace gate.
  PARTIAL SCOPE PIN (w-final7295 base 7295ed2, unstaged only,
  NOT full integration): 7 files 367+/81-:
  drafts 125, session 97, session_drafts 33, workspace 18, wsnet 70,
  session_drafts_demo 58, workspace_demo 47. Staged 30-file delta
  (+5752/-124) is separate unreviewed worker output; review as patch.
  BOOT CASCADE: prefsmove EMIT_EXIT=1 unfilled-law ws_post.painted
  (use tokened:790, def :1023; painted->paint->frame->keys->ws_act
  downstream, so move CALLER cluster down, not paint up).
  Cluster tokened/admitted/live/got self-contained (sole external
  caller :1298); moving below painted as next bounded step.
  PROVENANCE CORRECTION 2026-10-04 07:0x UTC (supersedes 07:10
  INTEG WORKER RETURN line): 4a3b5fcc788fcd736ac7f627803cd2a
  5264c0dde (parent 070ad99267bcbdef3f1f7c332aec9f426fe6854e,
  2026-10-04 08:27:17+0900) is OLD accepted integration donor
  (21st-reg-field era message), NOT fresh worker evidence. Do NOT
  whole-accept old-4a3b; do NOT replay 21-field Session over 22.
  CURRENT worker 01a105aa-3b39-7650-ab8e-d7c0d7ec4136
  (main/final7295-union/150, task ...3b38-7713-a725-80cd03c97b1d#5)
  terminal: FAILED ~07:01 UTC ("event log failed: Origin read
  requires valid checkpoint-suffix or origin-preserved full-replay
  authority"). NO fresh commit return exists. Last input it saw
  carried SUPERSEDED "PONG exact-forward stands correct" guidance.
  w-final7295 patch provenance: FAILED worker's uncommitted output
  (file mtimes 15:55-15:56 JST = 06:55-06:56 UTC, pre-failure).
  Base 7295ed2. Unstaged 7-file 367+/81- pinned; full HEAD-diff
  sha256 343018ef914d74114878dfcebe77733fd5ab309c10116844ba1be0
  2e78295d58. Worktree blobs: drafts bea22441, session e3d66f92,
  session_drafts e12155ff, workspace 673c8cbb, wsnet 8cd7fb24,
  session_drafts_demo d5d84e76, workspace_demo 4c0040f4.
  Owner VERIFIED in HEAD diff (wsnet+net): quiet Sess.Pong{_,_,_}
  no-op + shared Net.search_spawn wgen capture/route-back ONLY;
  no emit_cmd Pong arm, no writer_pong addition, no Pong forward.
  Session 22-field ctor lines are CONTEXT (regbox, theme intact);
  no 21-field replay in session.bend.
  FINAL7295 PARTIAL SOURCE FINDINGS 2026-10-04 07:3x UTC (stable
  7295 HEAD + staged/dirty patch; NOT a worker return; review-agent
  hashes pending):
  POSITIVE: 22 Session fields + boxed media/cf/reg/theme retained;
  shared CM draft stash/load and Search wgen/on_search_done
  returned-state routing source-positive.
  H5: full LiveAcc/split rollback + new ceiling drain atomically
  install fit imports; refusal claims none. GAP: no direct named
  ceiling-drain +/- test found.
  CM rename: live NICK->draft rename explicitly deferred, no callers
  (rename/retain default-map) -> NOT full CM rename qualification.
  UNION OMISSIONS (inherited 7295 integration gaps, NOT Search/tick
  regressions): staged NotifyIO:172/233-275 refs Sess.NotifyDone/
  NotifyLive APIs ABSENT from Session e3d66f92; WsLoop still N.State;
  ws_notify.fired NIO.send; no routed NotifyDone receiver. Accepted
  NotifyLive physical/global lease must be BOUND, not just helper
  modules copied. Cards ws_cards.found/fenced uses C.initial(True);
  schedule never CNet.cards_enabled -> accepted off-guard/global
  owner foundation still must port.
  POLICY: preserve Search shared Net.search_spawn + captured wgen
  and QUIET Pong in actual partial; do NOT replay boot9dd fwd.
  DIRECTION: continue repair/clean union pin, NOT broad acceptance.
  e096 --bounds still optional/omitted default Make: explicit bounded
  guard receipt + final registration REQUIRED (not yet run).
  NOTIFY SESSION PORT MAP 2026-10-04 07:38 UTC (source-only, VERIFIED):
  Donor 20ccf1c04a998d6f19238f6b28611c7c46fa44c8 session blob
  d019c197556bde592769affae96d9d9be773081b; span 2658-3086 (EOF).
  Import: `import ./notify.bend as Notify` (donor :20, after drafts).
  UiMsg: NotifyDone{ticket: Nat, endpoint: String} (donor :337,
  after HistoryLoaded). Four 17-patterns only: notify_scope_of 2669,
  notify_observe_session 2785, staged 2861, staged_claimed 2900.
  Span self-contained: helpers scope 2666/collect 2728/observe 2767/
  busy 2842/live.go 3076 + types NotifyFold 2735/NotifyLive 2801 all
  inside; external refs Notify/Cl/Irc/builtins only.
  Adaptation: bodies use cl+port ONLY (plan/edits unused) -> full22
  `Session{+cl,_+x12,+port,_+x8}` (cl=1,port=14 of 22; sess_drop
  precedent). Accessors NOT used (both take +st, single-use).
  Append after current step_on_chunk_ms body (:3864-3865), before
  step_on_chunk. No new Session fields/ctor/MediaBox/cf/reg/theme.
  Staged exactness: notify.bend=20cc dd7998cd, notify_io=12a 5cf935d9,
  9 fixtures + check script EXACT 12a17ca. Make: reuse 12a 740-796
  binding/full/history/held/held-blocked/followup/attr-blocked;
  followup standalone until actual green. LAWS/PROOF already Notify13;
  donor adds no laws; DO NOT overwrite or import NotifyIO/Actor.
  Wiring (WsNotify/global-physical/net loop) still required after port.
  BOOT RECEIPT upevt 2026-10-04 ~07:38 UTC: EMIT_EXIT=124 (timeout(1)
  killed inner bend at 300s bound), log 1 line (dirty warning only),
  build/direct_boot_guards.c ABSENT. Elapsed: NOT instrumented;
  exit 124 proves >=300s inner runtime. NOT green, NOT C-emit, NOT
  behavior qual. Type-error-free quiet interval proves nothing.
  HOLD: no limit widening, no repeated unchanged job, no CC/runtime.
  Source patch preserved; reassess before next bounded attempt.
  NOTIFY PORT LANDED 2026-10-04 07:4x UTC (w-final7295 worktree,
  UNSTAGED only; staged 30-file +5752/-124 INTACT): session.bend
  +import Notify:22 +NotifyDone:421 +429-line span (4x 22-adapted
  patterns) after step_on_chunk_ms; file now +519/-11 vs HEAD.
  Refs verified present: Cl.client_sasl_user/pass, Cl.server_of,
  Irc.ieq, Notify module (exact-20cc staged). No Session field/ctor
  change. Source-only; WsNotify/global-physical/net wiring + Make
  recipes + gates still pending. Partial scope grew; still NOT
  broad acceptance.
  ============ FRESH-SESSION HANDOFF 2026-10-04 07:42 UTC ============
  SUPERSEDES all older "current status" lines. Jobs/workers: ZERO
  (work_list empty; pgrep bend/cc/nix all 0). No cleanup/reset/push
  done or wanted. All trees below preserved as-is.
  ROOT 4b4cbef dirty G3 INTACT (LAWS/PROOF/Makefile/TODO staged+mods;
  src auth/buffer/client/frame/history/irc/irc_commands/join_plan...;
  unstaged 3 files +2091/-5). Lane edits NEVER in root.
  cards-handoff 608c7f6 CLEAN. GREEN seam only (HANDOFF_EXIT=0);
  NOT App/Nix. Bin receipt bf52e9f0 per earlier checkpoint.
  w-boot-gaps 4e512ff DIRTY (wsnet.bend + direct_boot_guards.bend,
  uncommitted): ws_post/ws_prefs/boot-cluster def-order moves,
  apply_keys+negotiated, erred/completed +notify/cards, fail/up_evt
  :Sid.RoutedMsg annotations. BOOT RECEIPT: EMIT_EXIT=124, inner bend
  killed at 300s bound, log 1 line (/private/tmp/boot_emit_upevt.log),
  build/direct_boot_guards.c ABSENT. NOT green. HOLD: no widening,
  no unchanged re-run, no CC/runtime until reassessed.
  Search9dd HELD: must reuse Net.emit_cmd Search-only owner, keep
  captured fields/owning evt, add +/- dispatch guard. Pong stays
  QUIET (actor reader sole live-wire owner; writer_pong no-dedup).
  Do NOT port boot9dd Pong/Search forwarding into final.
  w-upload-frame 85dd9ec CLEAN. w-upload-cardsbase 1124049 CLEAN.
  RECEIPT: scratch C EMIT_UP7=0, 24180357B,
  SHA 4859c1653c68e0deabcd85330f2c9f714659271fdd45c44b7320705048e689f0.
  EMIT-ONLY; NO CC/run. Scratch log /private/tmp/scratch_emit_1124049_up.log
  is EMPTY (0B); receipt is the byte/sha line, not a log tail.
  w-actual-boot e096530 CLEAN. Final-2 driver bounds SOURCE-ACCEPTED
  (oracle read cap, drain expiry, paired guards). --bounds RUNTIME +
  Make/check registration PENDING (bounds optional/omitted in Make).
  w-final7295 7295ed2 PARTIAL, failed-worker provenance (worker
  01a105aa FAILED ~07:01 UTC, no commit return; files written 06:55
  UTC; 4a3b5fc is OLD 21-field donor, NOT worker evidence):
  staged 30 files +5752/-124 INTACT + unstaged 7 files +800/-81
  (session.bend now blob c3b4c2c3 incl Main's landed Notify port:
  +import:22 +NotifyDone:421 +429-line 20ccf1c span, 4x 22-adapted;
  refs verified, no Session field/ctor change). HEAD-diff sha16
  6ab0e859e412847e. KNOWN GAPS (not regressions): NotifyLive
  physical/global lease unbound (no routed NotifyDone receiver,
  WsLoop still N.State); Cards off-guard/global owner unported
  (C.initial(True), schedule never CNet.cards_enabled); no named
  ceiling-drain +/- test; NICK->draft rename deferred. Wiring + Make
  recipes + gates pending. Review as patch; NO broad acceptance.
  final-candidate 7295ed2 CLEAN (reference).
  Next fresh session: reassess boot emit strategy within 300s bound;
  e096 bounds receipt+registration; upload CC/run; union wiring.
  ROOT VERIFIED ADDENDUM (07:42 UTC; authoritative handoff):
  Old Muse 47279 exited after /exit; no worker/build was killed.
  Start a NEW session, NOT resume 01a100f0 or load its 185 MB log.
  This is a verified handoff checkpoint, NOT a clean/green merged
  worktree. Dirty source/index states below must remain intact.
  Full HEADs:
    root: 4b4cbef5ffbf9ca5fc6dff913985a1318a4a6342
    w-boot-gaps: 4e512ff0a62e2c6c1e818e5cce712fad2c9e62de
    w-upload-cardsbase: 11240490594b6e3096dda0e95957ef23edaebd7b
    w-actual-boot: e0965300d5089c672b11b7cdeb18334371ccc47a
    w-final7295 / final-candidate:
      7295ed27f97d91f26f6f0d37d97db8dc8d6f8f52
    cards-handoff: 608c7f6b870c5fa11f7ddcb1bb21e0fbefef3f0a
    w-upload-frame: 85dd9ecf32137865797376e910c563bd6ee0bb26
  SHA256 of `git diff --binary HEAD` before host exit:
    w-boot-gaps:
      6780b3df0a89730b15361be21f261981baf1029c16a2668798cf2302ccd62d41
    w-final7295 (includes the newly landed Notify Session port):
      6ab0e859e412847e841ae4b0d692f94f65f65a0012b2a31074ddf638c47c804d
  SHA256 of `git diff --cached --binary`:
    root G3 index:
      a5f4cf9226f4c0b28ed8a98a255bc6a879ea932ab1173623d738f02035a47404
    w-final7295 index:
      9611dfeba75e3a25a1ae3f0f517e0eeb1be44184a28d3e4a622f715843730420
  All other named trees above are clean. Do not overwrite dirty
  root/partial trees with whole donor files. Keep final's 22-field
  Session, boxed media, cf/reg/theme, Search wgen, H5 atomic ceiling
  refusal, negotiated CASEMAPPING and quiet PONG single ownership.
  Scratch uses an older 17-field ABI: it is NOT a whole-file donor.
  Continue the whole-codebase defect/style/DRY cleanup and feature
  docket; use concurrent source-only implementation/review workers.
  Main alone owns ONE heavy build/proof/native/PTY/Nix lane. Keep
  receipts, distinguish wrapper success from inner exit, and make
  no false-green claims. IO `--check-only` is a proof-verdict path,
  not an elaboration gate; bounded backend emit is the right seam.
  Physical Notify foundation is 20ccf1c plus 6e25c584/8d1e4ddd/
  f8888d4 through 12a17ca47a360265496050675923a3559a2d3265; port
  global physical ownership and exact completion, not just APIs.
  Cards accepted complete owner/opt-out/compile-shape chain ends at
  608c7f6; preserve both exact pre-IO scalar hoists from 3cc7e2d.
  Preserve Upload's completed-warning/later physical F8 barrier and
  fullscreen-consumed Escape; retain all returned loop owners.
  Before closing: exact merged standard proof/check (PROOF_TIMEOUT
  =600), native gates, changed PTY tests THREE consecutive passes
  on ONE exact binary, then `nix build . --no-update-lock-file`
  and cached-launch/installed-helper verification. Final build is
  NOT qualified or hot-cached yet. Native emit and CC bounds remain
  300 s each, runtime 60 s; do not widen or repeat unchanged stalls.
  No push, pin/compiler/checker changes, destructive cleanup, real
  Keychain/credentials, public uploads or private chat-URL fetching.
  Prior fixture approvals are recorded above; do not ask again.
  New existing-test expectation changes still need user approval.
  Distinct pending expectation: cmd_around_stamp_prefixed needs
  .000Z; earlier sub_fetch_before_stamp approval is not its approval.
  ============ FRESH-MAIN CHECKPOINT 2026-10-04 ~17:05 UTC (sess 01a105df) ============
  Bounds receipt ONLY; no whole-green. Boot124 unchanged retry still forbidden.
  CMD (cwd=.muse/worktrees/w-actual-boot):
    nix --extra-experimental-features 'nix-command flakes' develop --no-update-lock-file . --command timeout 60 python3 tests/net/actual_boot_guards.py --bounds
  GUARDS: cap-fit=ok cap-overflow=ok timely-eof=ok quiet-no-eof=ok read-error=ok expired-ready-eof=ok bounds=ok
  INNER_EXIT=0 (SystemExit(0); timeout60 not triggered) WRAPPER_EXIT=0
  E096: HEAD e0965300d5089c672b11b7cdeb18334371ccc47a status-clean workdir-sha e3b0c442(empty)
  DRIVER_BLOB: d475ee4ab675121270f46138a85f54ad8c7b5466 tests/net/actual_boot_guards.py
  RECEIPT: /tmp/birc-fresh-main/bounds-actual-boot-receipt.log; sess log .../01a105df.../session.jsonl exec-199-1
  SCRATCH112404: build/ws_upload_frame.c 24180357B sha4859c165..f0 present; 0B emit log present; CC/run held for post-source-review sole lane.
  V PRE-APPLY BASELINE (w-final7295 workdir hash-object; hunk baseline re-hashed at apply time):
    2f97469f LAWS.bend 0fd5cd00 PROOF.bend 74ace39b scripts/check-notify-followup.sh
    f43894f3 actor.bend bea22441 drafts.bend c718e263 history_search.bend 431cbb0b history_search_io.bend
    baecd9fe live_context.bend aa01ce7a net.bend dd7998cd notify.bend 5cf935d9 notify_io.bend
    c3b4c2c3 session.bend e12155ff session_drafts.bend d766ba64 timui.bend 673c8cbba workspace.bend 8cd7fb24 wsnet.bend
    733f548c src/ffi/timui_ffi.c; tests/bend: 5680a7fa history_wire2 92ace07d notify_attr_blocked 82d3f6df notify_binding_gates
    2ac030b8 notify_followup_guards 2f655748 notify_full 34350068 notify_held 4c9da06e notify_held_blocked
    0a88114f notify_history d6dfbc1d notify_order df58648a notify_runtime d5d84e76 session_drafts_demo
    1474e317 sessws_s1s5_demo 6f2405a3 submit_demo 4c0040f4 workspace_demo 537f65f1 ws_upload_consent_gates 44cd97d2 wsnet_gates
    (Makefile untouched in V; full 40-hex list in sess log exec-223-1)
  OWNER/ORDER shared files serialize, no racing (Session shared by 1/2/3, wsnet by 1/2/4):
    session.bend: 1 notify-owner, 2 cards-lease, 3 cm-nick-h5, 6 cleanup-dry last
    wsnet.bend: 1 notify-owner, 2 cards-lease, 4 search-pong guard (serialize after 2 if same hunks)
    net/actor.bend: 4 search-pong; client/drafts/session_drafts/workspace.bend: 3 cm-nick-h5
    CLI/Makefile: 5 bounds-reg; notify*.bend + tests/bend/notify_*: 1; new tests: 3,4
    Order: 1,2 then 4 then 3 then 5 then 6; 6 skips scopes1-5 hunks; conflict = winner+rebase note + reviewer re-check.
  ============ INTEGRATED PIN 2026-10-04 (sess 01a105df) ============
  CLOCK CORRECTION: controller-observed 2026-10-04 08:29:53 UTC (host clock verified 08:35:54 UTC same day); earlier "~19:30 UTC" struck, author never checked clock.
  Base: w-final7295 workdir (7295ed2+diff 6ab0e859) isolated to /tmp/birc-fresh-main/snap22 (464 files, manifest f51c6dbd); applied serially 1,2,4,3,5,6 + BATCH guard.
  Canonicals (each git-apply round-trips byte-identical; -p2):
    scope1-notify dd127a35 (463+/142- net+wsnet; WsNotify owner, 63-thread, BATCH-archive claims fix, N-norm)
    scope2-cards 2f61db70 (433+/173- net/wsnet/wsnet_gates; WsCardsAll, 115-thread+10-revert, ws_act replace, gates port)
    scope4-search a14fec40 (w4: emit_spawns_search + law/proof, pure add)
    scope3-cmnick 8502402f (689+/19-: NICK renames + 2 suites 179/338L + Make test-review-pure reg)
    scope5-bounds 776c3acd (463+/1-: actual_boot_bounds.py slice + Make target standalone)
    scope6-cleanup 10606e4a (52+/41-: 17/18 w6 incl rebased ws_keys_halted; wsnet@914 kept, 0 dropped)
    scope7-batchguard 1f670e7f (169L notify_batch_archive.bend: BATCH->quiet->live +/- guard)
  PIN-full fe985637 (17 files +2233/-311); manifest 8643ccb3 (sorted); full round-trip identical.
  Dropped/superseded: w2 @469/@491 line_pick renames (defs deleted by w1, no dangling refs); nothing else.
  Preserved: 22-field Session (0 ctor removals; 3 match-arm DRY uses of notify_scope_of), H5 history_search byte-identical, PONG 0 diff lines, caps/union untouched, LAWS/PROOF +only, CLAIM 16*1024, R2/j65/floor8/live9 pins (no fixture edits except wsnet_gates owner port + sidecar True API repair).
  Remaining: agent review of pin; land to V after review; notify-test Make wiring (9 files incl new guard unregistered, consistent w/ siblings); full-driver-vs-slice decision (scope5); then proof600/check/native/PTY3/Nix. Runtime checks still held. Root index a5f4cf92 unchanged; V 6ab0e859/c3b4c2c3 untouched (all work in /tmp).
  Fresh launch verified 2026-10-04 07:45 UTC:
  session 01a105df-1ae3-7181-835b-90f49172fee5 (new, NOT resume),
  pinned Muse 1.4.0-R4161.1; initial prompt directed to this short
  checkpoint. New Main read it, checked worktrees and ran bend guide.
  ============ PIN2 CHECKPOINT 2026-10-04 09:01:23 UTC (sess 01a105df) ============
  TODO-ONLY update authorized this turn; root production files and root index
  remain frozen and untouched. No runtime pass is claimed; source-only freeze.
  fe985637 HELD/superseded by af3e9b15 (defects fixed post-pin: Sess.Session
  self-refs at session.bend:3922/3926/3933, .go Pair/Quad vs triple/quint
  mismatch at :3929; plus staged Cards/Notify ports absent from fe9856).
  PIN2: patch af3e9b15b5ac652b744a3639ff822e94036ce81e27fa94bef1480290e328ed2c
    manifest 4db1d2232ce3a165ddf87ba0c2512724e7049847d07249e2e1a9f0f7103040ba
    (472 files; 24 patch files snap22->stage8; git-apply -p2 round-trips
    byte-identical into chk-pin2, verified by diff -r; patch 351080B).
  Paths: base /tmp/birc-fresh-main/snap22 (frozen); work /tmp/birc-fresh-main/integ;
    frozen PIN2 tree /tmp/birc-fresh-main/stage8; patch /tmp/birc-fresh-main/
    PIN2-full.canonical.patch; manifest /tmp/birc-fresh-main/PIN2.manifest.
  Cards port (worker done, result_ready): 3 NEW files, staged byte-identical:
    tests/bend/cards_owner_gates.bend (449L, 83 E.must), cards_physical_gates
    (323L, 49 E.must), cards_handoff_native.bend (275L, 3-mode + ffi-retain
    seam); donor-assertions preserved; got_on 25-arg arity verified vs integ.
  Notify port (worker done, result_ready; donor w127-testfollowup 12a17ca +
    f8888d4 chain, read-only): 4 modified + 1 new (326L notify_batch_busy,
    50 asserts: busy/batch-quiet/erin-stage/stale-thread/exact-handoff/frank
    + RED control). Merge: 3 files worker-version superset (identical Chunk
    2-field fix + req-0 comment); batch_archive = Main floor-pin version +
    worker comment; busy staged with Main projector fix (5th conjunct
    List<String> -> List<D.NickRename> + drafts import; worker flagged it).
  CLOCK CORRECTIONS (verified evidence, host ls zone is KST=UTC+9):
    fresh-launch "07:45 UTC" was correct to the minute; exact session start
    2026-10-04T07:44:29.961465Z (session.jsonl recorded_at 1791099869961465).
    "~17:05 UTC" struck (KST wall clock mislabeled UTC): bounds receipt file
    mtime 2026-10-04 07:59:35Z; fe9856 patch 08:29:28Z, manifest 08:29:59Z.
    PIN2 patch+manifest mtime 2026-10-04 09:01:08Z; this stamp 09:01:23Z.
  EXACT REMAINING GAPS (pre-qualification, Main-owned, source-only):
    G1 same-chunk NICK +/- guards (NICK with BATCH +/- in one chunk).
    G2 H5 full-state/nonempty-outs guards (LiveAcc iso/typing/plan/reg/split
       unchanged on refusal; PING->PONG nonempty outs during refusal).
    G3 BATCH fixture ABI/claim-floor repair + Make registration (archive f0 +
       retained-claim test; busy/archive Make wiring).
    G4 actual-driver bounds reuse (replace actual_boot_bounds.py duplicated
       slice with reuse of tests/net/actual_boot_guards.py driver).
    G5 two read-only reviewer verdicts on PIN2 (requested this turn).
    G6 heavy qualification only after G1-G5: proof600/check/native/PTY3/Nix;
       runtime acceptance stays separate. Boot124 unchanged retry forbidden.
  ============ PIN3 CHECKPOINT 2026-10-04 09:21:14 UTC (sess 01a105df) ============
  TODO-ONLY update; root production/index untouched. PIN2 superseded by PIN3
  (WsShut fix + G1-G4 + Make seam + driver repoint absent from PIN2).
  PIN3: patch ea8957f2ce0bfe26d784fcf2d7da480a937f3cbe7bf8b2eb5ca579c8c00b60e3
    manifest 630635cbd6fd89b6c248a3eff97ccaeae3d31f50c11c63a478d802e39a85725f
    (472 files; 24 patch files snap22->stage9; git-apply -p2 round-trips
    byte-identical into chk-pin3; patch mtime 09:20:59Z, manifest 09:21:00Z).
  Paths: frozen tree /tmp/birc-fresh-main/stage9; patch+manifest PIN3-*;
    work /tmp/birc-fresh-main/integ (== stage9 at freeze).
  Contains vs PIN2: WsShut decl restored (wsnet.bend:178); G1 18 asserts
    (same-chunk NICK +/-); G2 21 asserts (seeded typing/reg, 5-state
    refusal equality, exact PONG outs); G3 archive claim-export (2) + 6 Make
    targets; handoff target donor-verbatim vs cards-handoff 608:751-756
    (explicit .c emit+CC, timeout60 &&-chain; NIXRON typo caught pre-freeze);
    ffi-retain split to its own separately-attributed target; G4 driver
    vendored (tests/net/actual_boot_guards.py, file-sha256 8c9aa15d...3d8e26)
    and bounds shim DROPPED (retired copy outside source; target runs the
    actual driver direct; no assertion/bound changes).
  PROVENANCE CORRECTION (verified read-only): d475ee4a is the git blob SHA1
    and 8c9aa15d the file SHA256 of the SAME e096 driver bytes; no missing
    blob. Main's open-item claim withdrawn; it lived only in the deleted
    shim docstring and one report line, never in TODO.
  Reviews: PIN2 NICK semantic SOURCE ACCEPT (per-line H5/reg/consume+CM,
    ordered effects, 7-field LiveAcc/split rollback; no compile/runtime
    claim); background pair 7 PASS (partial on plumbing only); Codex pair
    pending user relay. G2/newMake/bounds-reuse need fresh frozen review:
    this pin is the review target.
  Next: Main sole-lane bounded targeted gates (nick, ceiling, batch-archive,
    batch-busy, cards-owner, cards-physical, handoff-native, handoff-retain)
    with inner receipts; merge-prep workers in owned snapshot (no jobs);
    Main arbitrates. Full PROOF_TIMEOUT=600/check/native/PTY3/Nix only after
    exact rootG3+22+allowners final source merges. Boot124 barred; no pin/
    checker/deadline changes. NO PUSH AUTHORIZED (restated).
  ============ PIN3 GATES RECEIPT 2026-10-04 ~09:23 UTC (sess 01a105df) ============
  /tmp/birc-fresh-main/PIN3-gates.log: ALL EIGHT GATE-EXIT=2, not green.
  Wrapper completed (~58 s driver success) is not a pass. Inner receipts in
  gate-*.log. Inner2: (1) seven targets stop at irc.bend:401
  parse_after_prefix.empty using proto_atom defined 250+ lines later (def
  was :658); Bend 2 elaborates the forward ref as an unfilled law
  ("expected: a filled definition ... observed: proto_atom"). Pre-existing:
  frozen snap22 proto_demo fails identically; root G3 IRC already orders
  helpers before caller. (2) cards_physical_gates.bend:202 bare `1n + n`
  needs `(a + b : Nat)` (post-2.0.16 operator annotation).
  Repairs (source-only, Main lane): (1) accepted reorder-only donor
  7296b4669f2355a19cdb054bffff27c193d11cd4 (w-boot-gaps) applied byte-exact
  to integ irc.bend (donor base == integ bytes 68c2fc43; post efa103e8;
  pure 124-line move + 1 ws line; order is_c0_drop394/proto_atom515/
  empty518). (2) physical:202 annotated, count-preserving; owner:207
  already had it; scan found no other bare arithmetic ops in staged/new
  tests. Rerun protocol: ONE characterization target
  (test-draft-nick-rename) first to expose the next shared shape, all8
  only after green; no unchanged repeat. PIN3 source delta review still
  pending; no whole/runtime acceptance claimed.
  ============ PIN3 NOTIFY/BATCH SOURCE ACCEPT (narrow, no runtime) ============
  Frozen stage9 both BATCH fixtures accepted at source: exact 5-field
  List<D.NickRename> ABI; real framed archive IDs + exact claimed export /
  f0 retention / later prune; busy wrong-ticket -> wrong-origin -> exact
  completion threads returned states correctly and excludes the archived
  title. Two JS Make targets (bounded/standalone) and bounds-direct full
  byte-exact e096 owner reuse accepted. Prior 12a strict physical-chain /
  START / all9 assertions preserved (source-only). This is NOT global IO
  runtime qualification. Recorded SEPARATELY from: remaining NEW H5/NICK
  guard holds (H5 fullstate vacuity/plan-reg renders, NICK same-batch
  collect rule, PING-skip vs producer outs) and current compile-shape
  repairs (def-order/affinity/tuple-inference loop). Merge-prep workers
  both completed; final G3+22 union arbitration follows the guard fix.
  Full actualboot/frame/native/PTY3/Nix still pending. NO PUSH AUTHORIZED.
  ============ UNION ARBITRATION 2026-10-04 ~09:45 UTC (sess 01a105df) ============
  Both merge-prep workers done (source-only, no jobs); reports at
  merge-prep/_union/ABI_LAW_REPORT.md (572L) + MAKE_TESTS_REPORT.md (935L).
  Main arbitration: src/bend keeps PIN3 for all 73 files (root uniformly
  behind: staged G3 content is wire laws + wire_style.bend, both already in
  PIN3; all other root diffs are stale deletions/regressions incl. 17-field
  Session, _cm removal, theme/Edits narrowing, N9/sorting removal, 25k
  client/feature deletions). LAWS/PROOF take the additive +17 wire laws/
  proofs (pure addition, deps verified). Tests/Makefile: g3 block (2
  targets + gate deps) transplanted; g3_traversal = PIN3 + root closing
  guards (pure addition); g3_framed added (+C3 PIN3-raw alignment); C1
  wire_style whole-file split (PIN3 26-line registration stub kept at
  path; root 203-line view test transplanted as wire_style_view.bend +
  standalone target + token rename, assertions verbatim); C2b/C3
  sanitize-vs-raw decided PIN3-raw coherent (feed keeps bytes, proto_atom
  seam normalizes at registration); C4/C5 informational keep PIN3.
  Union assembled at /tmp/birc-fresh-main/union (= integ + exactly LAWS,
  PROOF, Makefile, g3_framed, g3_traversal, wire_style_view); integ frozen
  as the PIN3+ record. Post-PIN3 Main fixes carried by rebase (irc donor
  hoist, drafts reorder, notify sort-restore, session affinity + observed
  pieces, physical annotation, G1/G2 rewrites, handoff verbatim, bounds
  direct). Root G3 ground truth adopted for compile shapes: zero flat
  3+ tuple patterns anywhere in root src (nested pairs only); the 7295
  lineage flat patterns never compiled under the pinned checker. Next:
  migrate union gate closure to nested pairs, then one-target gates.
  NO PUSH AUTHORIZED (restated).
  ============ UNION CEILING TRACE 2026-10-04 ~10:40 UTC (sess 01a105df) ============
  TODO-ONLY update; root production/index untouched. PIN3 HELD (frozen
  stage9 + PIN3-full.canonical.patch ea8957f2 + PIN3.manifest unchanged;
  PIN3 gates receipt ALL-EIGHT-EXIT-2 stands). One-target union probes
  only (Main remains sole heavy lane); NO ALL-GREEN / NO PUSH claim.
  Union tree (excl build): db9af9354693cb908b894bcb64316cefee2522c9
  d164f6e3e6d93c8bbb644c74. Changed files: history_search.bend
  ae857516b942cbcd2934da84d4420aa92c87bf9d73c3843252848c52cafec810;
  history_ceiling_drain.bend c7c36aa4a90f37e64080095aef57aebc2d29a
  1369f1696990d13ee8fa33b4e42. Union vs stage9: 6 src/bend files
  differ; tests differ: cards_physical_gates, draft_nick_rename,
  g3_traversal, history_ceiling_drain (+g3_framed, +wire_style_view).
  Inner outcomes (make test-history-ceiling-drain in union):
  ugate1-2 exit2 (+rest affinity/Data notes, session ~3893);
  ugate3-4 exit2 (caret line 131); ugate5-6 exit2 (carets 247/250);
  ugate7 exit2 (caret 396); ugate8 exit2 (C-guard line 591 shape);
  ugate9 exit2 (paren at 592-593); ugate10 exit2 (undefined
  archived_now at 593); ugate11 exit2 RUNTIME s replay quiet seq
  got=[3] want=[2]; ugate12 exit2 RUNTIME seed split on;
  ugate13 exit0 history_ceiling_drain=ok. Logs: /tmp/birc-fresh-main/
  ugate{N}-ceiling.log N=1..13.
  H5 guard correction (production, retained contract): duplicate/
  stray server BATCH closes fell through hist batch interception to
  live Feed and logged "BATCH -abc" trace rows to server buffer
  (+1 log_seq each), failing OLD PIN3 asserts s replay quiet seq /
  s stray minus seq kept (stage9 ceiling lines 374-375,384-385).
  Fix in union history_search.bend only: batch_suppressed now also
  swallows BATCH-protocol command lines (new batch_protocol.parsed
  helper); tagged-archive claim path untouched; no law constrains
  the suppress predicate (zero LAWS.bend hits); no old test expects
  BATCH lines as visible feed. Paired probes showed roomy seq=2 vs
  replay seq=3 with identical #a texts pre-fix; post-fix replay
  server empty, stray seq=1=armed=base+0.
  H5 seed correction (fixture, NOT production): integ split_keys
  "/vsplit #a" can never seed split-on: active buffer is #a and
  Sp.activate refuses same-as-active in ALL of stage9/integ/union
  (split.bend byte-identical everywhere), so the integ assert was
  self-inconsistent. Fixture corrected to "/vsplit server" + paired
  control assert "seed split refuses active" (self-target stays
  off); retained refusal policy and error string preserved.
  C-guard (new H5/NICK) corrections this session: removed stray
  Nat.show around seq_is (String-typed), fixed paren balance at
  590/592/598, archived_now -> retained archived helper. zzprobe
  diagnostic RETIRED from union/tests/bend (never in maintained
  source); marker /tmp/birc-fresh-main/zzprobe-retired.txt. Next:
  remaining union one-target gates, then bounded gate set; freeze
  next pin only after green. NO PUSH AUTHORIZED (restated).
  ============ UCHK1 REVIEW CHECKPOINT 2026-10-04 ~10:55 UTC (sess 01a105df) ====
  TODO-ONLY update; root production/index untouched. NOT A PIN (no pin/
  push/deadline changes): stable read-only snapshot for parallel source
  review while union gates continue in the Main sole lane.
  PROVENANCE CORRECTION: the ceiling guards (replay/stray quiet seq,
  seed split/typing/caps/iso/plan, join/ping C-guards) are NEW worker-
  authored tests (PIN3-stage9 + integ), NOT old root/baseline contracts.
  The prior trace entry's "OLD PIN3 asserts" phrasing is withdrawn. The
  batch_suppressed extension (batch_protocol.parsed swallowing unmatched
  BATCH-protocol lines) is therefore a PRODUCTION BEHAVIOR DELTA, not a
  retained-contract implementation. It needs explicit source review plus
  meaningful +/- coverage before acceptance: matched open/collect/close,
  duplicate close, stray close, malformed BATCH (bad arity, non-server
  prefix, chat-body "BATCH"), and unrelated live-control preservation
  (PING/PONG flow, unknown numerics still traced, no unread/bell drift);
  no legacy assert weakening. That +/- work is pending in the sole lane.
  Contents: green-ceiling union source + G3 merge transplants + nested-
  pair/affinity compile-shape fixes + H5 batch_suppressed policy delta
  + split_keys fixture correction with paired refusal assert.
  Snapshot: /tmp/birc-fresh-main/chk-union1 (504 files, read-only).
  Manifest UCHK1.manifest sha256 c0dbdd615c5369333fe0d3b434b63c947
  3ae6626e7ef7ea0b7ef1158489e1753 (round-trip sha256sum -c: all OK).
  Canonical patch UCHK1-full.canonical.patch (stage9 -> chk-union1,
  git-diff format, 15 files: LAWS, PROOF, Makefile, drafts,
  history_search, irc, notify, session, workspace,
  cards_physical_gates, draft_nick_rename, +g3_framed,
  g3_traversal, history_ceiling_drain, +wire_style_view) sha256
  3f91770fc9f4e1cb2ac70417eb951e46558209be983e39ff4cb5c82e9f392ac8.
  Union tree hash at freeze: db9af9354693cb908b894bcb64316cefee2522
  c9d164f6e3e6d93c8bbb644c74 (excl build).
  Ceiling runtime record (ONE target only): token
  history_ceiling_drain=ok, inner bun exit 0 (ugate13). Full Bend
  suite, native/FFI gates, PTY3, proof600, and Nix qualification all
  still PENDING; no suite-wide claim. Next: draft-nick-rename one-
  target gate, then remaining characterization gates + BATCH +/-.
  NO PUSH AUTHORIZED (restated).
  ============ UCHK2 POST-REVIEW REPAIR 2026-10-04 10:35 UTC (sess 01a105df) ==
  TODO-ONLY update; root production/index untouched. NOT A PIN. Actual UTC
  clock used throughout this entry (10:35 freeze, 10:38 write); prior two
  entries' "~10:40/~10:55" labels were ahead of the real clock and are
  corrected here (events occurred ~10:20-10:35 UTC).
  UCHK1 FINITE REVIEWS COMPLETE: source shape/G3/laws additions ACCEPT
  narrow (22 fields/boxes/per-line effects/outputs intact; no proof or
  runtime claim). H5 batch_suppressed HOLD (blanket cmd==BATCH hid peer
  opens, bad arity, nonsense; seq falsely quiet) forwarded and repaired
  below. New-guard coverage PARTIAL at UCHK1 (live-overflow pair +
  exact batch-state projections missing; now supplied by workers).
  UCHK1 -> UCHK2 repair (sole lane): batch_suppressed constrained to
  trusted server source + validated +/- ref/arity (batch_quiet.close_
  shaped mirrors batch_open.bare word+64; valid opens reuse existing
  batch_open.msg owner; +server threaded through hist_collect_step.
  claimed/.done and hist_idle_step.opened; tagged-archive suppression
  retained). 12 new Session/Workspace +/- asserts (peer/bad-arity/
  nonsense traced seq+1 with #a unchanged; 001/CAP/JOIN/NICK live
  controls flow). split_keys fixture correction + paired refusal
  retained from UCHK1.
  SOURCE-ONLY WORKERS (disjoint, chk-union1 base, no jobs, both DONE):
  worker-A live-overflow pair (merge-prep/_union/uhk-live-overflow.md,
  7999 B): allocating untagged 005 on seeded ASCII fullstate, seq=
  ceiling-1 refuses with whole LiveAcc+split/iso/reg/plan/typing/split
  rollback incl cm+cm_known (Iso.show omits it), seq=ceiling-2 admits
  rfc1459 + one ID; 27 asserts. worker-B exact batch-state projections
  (merge-prep/_union/uhk-batch-state.md, 6511 B): batch_tag_now/
  ws_batch_tagIdle/Collect(ref,target)/Done; 14 !batch_done projections
  replaced with strictly stronger exact-state pins; 5 new NICK/valid-
  close asserts (wrong-ref stays collecting, live/arch NICK preserve,
  nick-then-close carries ref). Integration: worker-A srv_texts fixed
  to index-0 server buffer (Cl.buf_find.skip0 deliberately skips index
  0, so named_buf("server") is always empty); all else verbatim.
  UCHK2: /tmp/birc-fresh-main/chk-union2 (read-only), manifest d7b8d1e3
  9e7098f2d9a65cd04eb6f3aaec6c874886ee87cf6b2e4bfb9d32f662, full
  canonical patch (stage9->chk-union2) 228bcef9fd90312354e2a620cd58
  1074873880212e913f09ea35270a4af049, incremental patch (chk-union1->
  chk-union2, 4 files: history_search, net, wsnet, ceiling test)
  3dc873d1f3e5b8141b4a33d0d6368912ba10baad82d38741fe890c5b5d2a5b3a.
  Hashes independently verified by reviewer. UCHK2 early scoped SOURCE-
  positive: narrowed owner rejects peer/bad-arity/nonsense, trusted
  duplicate/stray quiet, server args threaded, Session/Workspace pairs
  present, 005 +/- rollback-vs-fit present; final source hash/assert
  review finishing. No physical/native/proof acceptance.
  GATE OUTCOMES (sole lane, one target each): ceiling ugate14 exit2
  (w_stray_minus forward ref, fixed by relocation); ugate15 exit0 token
  history_ceiling_drain=ok inner bun exit 0 (constrained suppression +
  12 +/- asserts); ugate16 exit0 same token inner 0 (+27 worker-A, 14
  worker-B replacements, 5 N1-N5). draft-nick-rename ugate1 exit0 token
  draft_nick_rename=ok inner 0 (first run). notify-batch-archive COMPILE
  failures only, no runtime pass: ugate1 exit2 (net.bend on_msg_go
  missing Sess.NotifyDone arm, fixed with drop arm matching sibling
  completion events); ugate2 exit2 (wsnet ws_npart.find/drop mutual
  recursion, fixed with rec-param pattern matching existing ws_cards.
  find_pick); ugate3 exit2 (ws_notify.steal_* 5-def mutual cycle);
  ugate4 same steal site; ugate5 exit2 (nested match order in new
  steal_go walker, fixed left-to-right xs-then-d); ugate6 exit2
  (owner_idle->owner_claimed forward chain, fixed by leaf-first
  reorder, zero semantics); ugate7 exit2 (ws_keys_ticked.go triple
  pattern inference, in progress). Logs: /tmp/birc-fresh-main/ugate*
  Notify walker/owner repairs POSTDATE UCHK2 freeze and need their own
  next-snapshot review. test-wire-style-view standalone must qualify/
  register before any final check claim. Full suite/native/PTY3/proof
  still pending. NO PUSH AUTHORIZED (restated).
  ============ UCHK3 COMPILER+DM REPAIRS 2026-10-04 10:51 UTC (sess 01a105df) =
  TODO-ONLY update; root production/index untouched. NOT A PIN. Post-
  UCHK2 sole-lane compiler/shape repairs + archive/busy DM fixture
  corrections + native recipe boundary fix, frozen for source review.
  Contents (UCHK2->UCHK3, 4 files): (1) wsnet.bend: StealDecision two-
  arm Continue/Handed decision type + nonrecursive steal_pick.* per-
  Part helpers + single list-decreasing steal_go walker (xs first, d
  second; left-to-right param matching) + steal_round wrapper, replacing
  the 5-def steal mutual cycle with identical winner-lease/next/lazy-
  tail semantics (reviewer proposal, Continue carries parts+next
  directly so no binder match is needed); owner_claimed/owner_all leaf-
  first reorder (zero semantics); ws_keys_ticked.go +halt->halt (pinned
  checker rejects all-+ flat triple patterns; mixed/plain-last is the
  accepted shape per ws_done:1350 precedent); ws_upload.url apply_keys
  6th arg Sess.session_negotiated(st) mirroring net.bend:1123; ws_upload
  erred/completed calls restored missing notify+cards args; ws_start.
  boot block (2424-2463) moved before ws_start.keyed (pure reorder).
  (2) notify_batch_archive.bend + notify_batch_busy.bend: RED/archive
  fixtures rewritten from vacuous channel-mention (import always stamps
  Cl.Msg, notify_is_mention needs Highlight/Action, channel is not DM)
  to genuine archived DM (fetch alice, BATCH chathistory alice, alice
  PRIVMSG me, title "alice (private);"); live bob/erin/frank #chan
  mentions unchanged; zero production change; N9 rules and all strict
  asserts preserved. (3) Makefile:882 handoff recipe explicitly sets
  BIRC_CARDS=on for the three owned-fake-helper native positive modes
  (handoff/wrong/quiet); global test% BIRC_CARDS?=off and production
  opt-out/off guards untouched; ffi-retain recipe unchanged; no C or
  backend edits (integration recipe boundary only). Prior 608 native
  3-mode receipt stays scoped, not default-target proof.
  UCHK3: /tmp/birc-fresh-main/chk-union3 (504 files, read-only), tree
  02b481c0e2f678384df5b4376830d447724b775c92845ad14fa68778c6cb4cd,
  manifest 0a17df4ce7e2418f5217f735ad90f92370a6b60a7f99cc6659fbba06
  f27ec96a (round-trip all OK), full patch (stage9->chk-union3)
  c4007d35ad7c07c872cb1f26d7f76b57568e08e48fd13bb9a9f847676fe83fe8,
  incremental patch (chk-union2->chk-union3) 73ecc7c9b4ac1adeed823c5
  e8b8444b1efbd5aed902abcdb8065afab9b64ff12.
  EXACT INNER RECEIPTS: archive ugate8 exit2 (ws_upload.url apply_keys
  arity, fixed); ugate9 exit2 (ws_upload erred/completed missing
  notify+cards args, fixed); ugate10 exit2 (ws_start.boot forward ref,
  fixed by block move); ugate11 exit2 RUNTIME red nil-claims admits
  archive got=[] want=[alice in #chan;] (fixture vacuity, DM rewrite);
  ugate12 exit0 token notify_batch_archive=ok inner bun exit 0.
  busy ugate1 exit2 (comp_rel +released flat-pattern, fixed plain);
  ugate2 exit2 RUNTIME same red vacuity; ugate3 exit0 token
  notify_batch_busy=ok inner 0. Ceiling ugate16 + rename ugate1 greens
  stand (unchanged since UCHK2). zzprobe2 retired from union/tests/bend
  (never in maintained source). Workers C (uhk-laws-syntax.md,
  mode_explicit_plus_contrast single-law restatement proposal) and D
  (uhk-actualboot-port.md, 13796 B actual-boot fixture/Make/ABI prep)
  DELIVERED; review/integration pending (actual-boot Bend fixture + ws_
  start ABI + native target still absent; Boot-prefix emit stays pending
  separate from first frame). Next: cards characterization gates, then
  bounded suite. Full suite/native/PTY3/proof still pending; no suite-
  wide claim. NO PUSH AUTHORIZED (restated).
  ============ UCHK4 CARDS+LAW + REVIEW CATCH-UP 2026-10-04 11:15 UTC (01a105df)
  TODO-ONLY update; root production/index untouched. NOT A PIN.
  REVIEW CATCH-UP (all received, now recorded): UCHK2 finite SOURCE
  ACCEPT for constrained BATCH + real 005/fullstate/cm_known/exact
  history-batch guards, with limits: draft_nick_rename still
  !batch_done states, one ceiling live 'idle' still !done, Workspace
  control matrix narrower than Session (not new production fault).
  UCHK3 finite SOURCE ACCEPT: lazy first-eligible StealDecision/next/
  exact lease+jobs, genuine-DM nil-claim controls + wrong->exact/live/
  floor assertions, upload notify/cards + negotiated arg, boot body
  pure move, narrow 3-native-on recipe; no native/full-app proof.
  Boot port proposal 6db9cbe8 SOURCE HOLD (3 faults: '<>' vs ++,
  IO.die drops held Ui vs gate_timeout close, strict argv/mode/arity +
  both preferences-none assertions removed); direction is smallest-
  preserve original e096 fixture (abstract factories, 17-arg
  ws_start.prepared already UCHK2-matching), adapt only demonstrated
  ABI needs; driver bounds/lifetime sensors stay byte-exact e096.
  Workers E (upload port prep) + F (strict-12a native Notify
  compatibility map) spawned source-only on chk-union3; F DELIVERED
  (uhk-notify12a-map.md 9806 B, pending review); E running. Worker C
  laws proposal (mode_explicit_plus_contrast A&&!B==True restatement,
  source-equivalence valid, not proof pass) APPLIED syntax-only to
  union LAWS.bend:1473; actual proof pin review pending (proof600
  still unrun).
  CARDS GATES (sole lane): owner ugate1 exit0 token
  cards_owner_gates=ok inner 0 (first run). physical: ugate1 exit2
  (cand_ids mutual cycle), ugate2 exit2 (argv_text cycle), ugate3/4
  exit2 (+takeA Sigma-pair not Data; diagnosed per accepted donor
  precedent: bare-& pairs are linear Type — single-use lets drop +,
  multi-use becomes consume-once inline recomputation / nullary defs;
  NO policy/type/argument rewrite, spawn_ok calls+inputs preserved,
  no hardcoded True), ugate5 exit2 (open_kept pair), ugate6 exit2
  (<>Nil{} gen inference), ugate7 exit2 (WsCardsAll field inference;
  parts0/cands2/allA/allB/lease57some nullary defs), ugate8 exit2
  (+open_kept), ugate9 exit2 (argv List &1 vs &2), ugate10 exit2
  (&1 linear list), ugate11 exit2 (argv_text.go arg order), ugate12
  exit0 token cards_physical_gates=ok inner bun 0 (JS emit + bounded
  golden; exact inner receipt confirmed in raw log). All prior
  assertions preserved; only fixture shape/binding repairs, zero src
  behavior change. handoff-native ugate1 exit2 C-backend "arity over
  247" at emit (capture-words cap; sole heavy lane; emit/CC 300 +
  runtime 60 UNCHANGED).
  UCHK4: /tmp/birc-fresh-main/chk-union4 (504 files, read-only), tree
  eea401ae097530226f641e1303358d82affb2ea8aa54b3bce4a41f1596ab6447,
  manifest 6f808456b8333d20abe6a4ac0d7a07131ef2949f0af9e8892d722f8
  cd68d3e98 (round-trip all OK), full patch d0efc9b5a3ad4ad053dd0be
  5b4ea9e4e95ec14d5e0ba4a13ced86c9b0aa97d5f, incremental (UCHK3->
  UCHK4, 2 files: LAWS.bend one-law syntax, cards_physical_gates
  fixture shapes) 22939010460921eb8c0adffcfd3c8d9f7967725c4947d20
  c26948940d334e067. Narrow source review only; does not replace
  native receipts.
  REGISTRATION LEDGER (union Makefile): check -> test(:1512) ->
  test-review-pure -> members. IN test-review-pure (hence check):
  draft-nick-rename, history-ceiling-drain, upload-{helper,policy,
  session,io,dispatch,...}, g3-framed, g3-traversal (+ unrelated
  members). STANDALONE targets (own rule + .PHONY, NOT in check):
  cards-owner-gates, cards-physical-gates, cards-handoff-native,
  cards-handoff-ffi-retain, notify-batch-archive, notify-batch-busy,
  wire-style-view (qualify/register still pending per earlier note).
  UNREGISTERED (no target, no caller): tests notify_followup_guards.
  bend, notify_attr_blocked.bend; script check-notify-followup.sh.
  Next: handoff 247-arity repair (sole heavy lane), ffi-retain,
  consent, followup direct runs, G3 gates, then proof600 + integrated
  checks/native/PTY3/Nix. No suite-green/push/deadline/pin/checker
  changes. NO PUSH AUTHORIZED (restated).
  UPDATE 2026-10-04 (Main lane, UCHK4 == union verified, app.bend
  37d9afc3722d4e05): App C-emit is a PRODUCTION defect, not
  fixture-only: `bend src/bend/app.bend -o build/birc_bend.c` inner
  exit 1, stderr exactly `Error: an arity over 247`, no artifact
  (ugate4-app-emit.log). Backtrace adds no def name; check-only
  shows only the expected foreign-proof verdict; JS emit stops at
  expected auth_bridge no-.js-import. Fixture-boxing hypothesis
  RETRACTED (ugate3 exit 2 unchanged); fixture restored
  byte-identical to UCHK4. Bisect1 emit-only all inner 0:
  ui_input_queue 642675B a5a702e50aab6188, deferred_actor 1653796B
  f4c34a3f90b02761, demo_identity 9052113B 5a04ce0bc254e5a8.
  Isolated-copy stub2 (got_on full stub, signature/owners kept,
  probe-gotonstub.diff) STILL FAILS inner 1: bomb is OUTSIDE
  got_on on current tree (differs from dc971 lineage where stub2
  passed). Bisect2 (shutdown_flush/live_context_io/mss_stale_socket
  emits) in flight, serialized. 3cc hoists confirmed present both
  ws_media.job branches; no compiler/checker/pin/limit changes.
  SOURCE ACCEPTS (prep/integration only, NOT App/native/physical
  green): Boot uhk-actualboot-port.diff
  ed7f2680acea95a91740cdef037443b8125478774a4fe5a70cd79edd63910ca5
  (count-only repair +1366,13/+1502; fixture byte-exact e096;
  17-arg ABI + exact 300/300/60 recipe); Notify
  uhk-notify12a-makerecipe.diff
  4d9002f9c940a469486c6ee6156a0182e1f8ebd78fe925d6fcb775407c3e2340
  (context-space repair, 6/6+64/64; exact12a+separator bodies,
  8 targets/9 fixtures, 5 pure prereqs + 3 standalone followups;
  donor runtime bounds incl. 90, main18/no-release2 latches, fresh
  d/unreleased/notify-send, SHUTDOWN_FFI_ALIASES kept; no new
  numeric IDs/assertion edits). Both zero-fuzz dry-run clean on
  scratch chk-union4 spans. Upload-binding diff delivered 80343B
  952a5d06c468 (11 hunks OK, dry-run clean, driver
  b64220282ac0e16e52408b7df71de1f1e78030a4/27833 exact); review
  pending. Minimal Boot+Notify source integration released; apply
  on freed lane BEFORE normal qualification. NO PUSH AUTHORIZED
  (restated).
  UPDATE 2026-10-04 (bisect2 exact): live_context_io emit inner 0
  (12407398B 84382f304ca9091e); shutdown_flush inner 124 (300s
  timeout, NO branch verdict); mss_stale_socket inner 1 on CHECK
  (Sess.Chunk 2-field pattern vs 1-field case at :210), NO arity
  verdict. Isolated stub2 (got_on full stub) inner 1: bomb OUTSIDE
  got_on. Isolated MSS-only ABI repair/probe (Chunk +req x4,
  cmd_show Pong/Search, local evts for ws_on_net/ws_emit) is
  CHARACTERIZATION ONLY, never qualification/final migration;
  probe4 in flight. Boot+Notify APPLIED source-only (patch -p1
  --fuzz=0 clean): fixture 5159a9964495c86a matches extraction;
  Makefile +test-actual-boot-guards/+test-notify-binding-gates;
  union vs UCHK4 differs ONLY Makefile/TODO/new fixture (no
  src/bend); in-tree driver 8c9aa15d78711663 == e096 exact.
  Upload 952a5d06c468 HELD for two source-only verdicts (not
  applied). UCHK5 after accepted Upload/application. App arity
  repair still OPEN. Bounds unchanged (native 30/60/90, emit 300).
  Union source preserved during active emits. NO PUSH AUTHORIZED
  (restated).
  UPDATE 2026-10-04 (UPLOAD SOURCE-RELEASE, both reviews accept):
  stable complete diff SHA
  952a5d06c468a20d3464cb194df73f4635e2d0afcec18c70351ca5badda39e22
  verified firsthand. 11 hunks/5 files, 9 old anchors valid; new
  394-line fixture fd98d6d... exactly D2, 667-line driver
  b6422028... exactly D1; strict ledgers/START-release/raw-exit/
  guardian-cleanup/assertions unchanged. Frame key/presentation
  owner preserved: ONE fullscreen first, consumed-key skip, OLD
  painted part post-completed-frame only, staged Confirm stays
  unpresented, typed restoration, live Net.paint_session_cards
  untouched, Notify/Cards lease args retained. APIs/changed-arity
  callers fit incl. wsnet_gates restoreFalse, old expectations
  untouched. Make exact D2 standalone/PHONY/preflight/
  300-BUILD_TIMEOUT-120 bounds kept (Upload120 NOT forced to 60).
  RELEASE: apply smallest diff AFTER probe4 receipt, then freeze
  UCHK5 + verify exact integrated blobs. NOT native/App/PTY
  qualification. Root edits this session: TODO.md appends ONLY;
  all other worktree/index state pre-existing and untouched.
  UPDATE 2026-10-04 (probe4 + UCHK5): mssprobe4 inner 124 (300s
  timeout, empty log, NO verdict; characterization only, bounds
  unchanged). Upload
  952a5d06c468a20d3464cb194df73f4635e2d0afcec18c70351ca5badda39e22
  APPLIED (patch -p1 --fuzz=0, 5 files clean) + UCHK5 FROZEN:
  chk-union5 read-only 507 files; blobs fd98d6d8 (394-line D2
  fixture), b6422028 (667-line/27833B D1 driver), 5159a9964495c86a
  (boot fixture) verified in frozen tree; incr-uchk4 exactly 7
  paths (4 modified + 3 new); full 24 files vs stage9; painter/
  owner terms as released. Source only; NO native/App/PTY
  qualification. App arity repair OPEN. NO PUSH AUTHORIZED
  (restated).
  UPDATE 2026-10-04 (UCHK5 pins, verified firsthand): manifest
  83f46217f34ad2c24d1a6a90e3ec4db1e21e52183ac2aac902b38f3ca47eed2f;
  incr-uchk4
  fdd77b43fae67e6ea509cd9f4ddd99c01529abe1c0f143d8bf1c0d344874b92b;
  full d6f4f421fc5d8f93c1da475b3d743c37335b294d5a820c05080420da97eafe81.
  chk-union5 read-only 507 files (union now differs ONLY in TODO.md
  trace lines appended post-freeze). Narrow applied-delta review
  running read-only. Next: isolated ws_post stub probe (shape under
  review; source prep only until verdict) + disjoint source-only
  capture/ABI investigation. NO PUSH AUTHORIZED (restated).
  UPDATE 2026-10-04 (stubF3 exact, UCHK4 same-pin): isolated copy
  probe-wspost4 (baseline verified identical), ONE-body diff:
  `ws_post.skipped(...)` body -> `IO.pure(<existing 8-tuple
  type>, (ui, new_ws, ctx, media, owner, ups, cards, False{}))`
  (reviewer-confirmed prefs pattern; signature untouched; Ui once;
  diff probe-wspost4.diff read back firsthand). Entrypoint
  app.bend: inner **1** `Error: an arity over 247`, NO .c
  (ugate4-stubf3.log) vs UCHK4 control inner 1. Valid same-pin
  result: still fails with ws_post BODY replaced by pure return;
  signature/caller continuations/other paths remain. Widths
  ~108/~113 are tasked-heuristic ESTIMATES (List/Maybe opaque,
  one-unfold AuthPhase), not compiler instrumentation; no
  exclusion proof, no box rewrite. mss probe4 124: prior CHECK
  faults source-adapted, timeout gives no phase/verdict. UCHK5
  App control in flight (no inference until receipt). UCHK5
  applied-source closure positive; finite final imminent.
  NO PUSH AUTHORIZED (restated).
  UPDATE 2026-10-04 (UCHK5 App control MEASURED): entrypoint
  app.bend on UCHK5 tree (app.bend 37d9afc3722d4e05, union ==
  chk-union5 except TODO traces): inner **1** `Error: an arity
  over 247`, NO .c (ugate5-app-emit.log). UCHK5 App failure is
  now measured, not inferred. Next same-pin probe (router-body
  stub) in source prep; emit held for shape review. NO PUSH
  AUTHORIZED (restated).
  UPDATE 2026-10-04 (UCHK5 SOURCE ACCEPT + router receipt):
  finite accept: 6 implementation/Make files byte-exact union of
  Boot/Notify/Upload artifacts + 53-line TODO trace only; 7 paths,
  507 manifest entries match; full d6f4f421…, incr fdd77b43…,
  manifest 83f46217… (all match Main records). NO native/App
  qualification. Router probe (released shape 7d955e27…, one
  ws_routed.msg body -> ws_drop tail, ONLY wsnet differs):
  entrypoint app.bend inner **1** arity over 247, NO .c
  (ugate4-routed.log; wrapper exit is not green). Precise: still
  fails with router BODY replaced; signature/callers/other paths
  remain. Locked-compiler read-only note (ns9 narHash-verified as
  locked rev 7d8a3eb): trigger is a 248+-param SEGMENT or
  encoded arity>255 (comp.ts:2927-2928); lay_of/fun_of auto-box
  wide layouts (:1032,:1270); no dump flag (main.ts:240-263).
  No compiler/checker/debug patch. NO PUSH AUTHORIZED (restated).
  UPDATE 2026-10-04 (MSS genuine migration, Main): inventory
  fc6a60e3… verified; threaded real-evt WsEvts x4 through 72
  signatures + 93 sites into rel/ws_emit x3; Chunk wildcard x4
  (rm/FIFO kept); redacted Pong3/Search9 arms (6 strings kept);
  recipe unchanged; NO probe stand-ins in union. check-only exit
  1 expected-foreign-verdict only, zero type errors. Gate run
  held (source-only). Binder worker got seg_open/emit_clo/
  emit_fork precision (estimates only). NO PUSH AUTHORIZED
  (restated).
  UPDATE 2026-10-04 (view excluded, framekeys prepped): binder
  inventory 371145B demoted to DEFINITION/CALLSITE INDEX ONLY
  (unit mismatch: 38 source binders vs 247 flattened segment
  words; 'no scope near cap' REJECTED, not exclusion evidence;
  no report-driven boxing). P-VIEW MEASURED: entrypoint
  tests/bend/cards_view.bend on union @ UCHK5 + MSS migration +
  TODO traces, inner **0**, 4806099B 0b6a5b37578732f9 (subset
  ONLY: fixture has no _themed/paint_session_cards; excludes
  neither all View nor proves frame loop sole region). Next
  same-pin probe source-prepared on verified UCHK4 copy
  (probe-framekeys, diff c085fd27a872e7b0 read back;
  ws_frame.keys body -> ws_drop tail, signature untouched): EMIT
  HELD for shape review (new: drops plain-Data keys).
  NO PUSH AUTHORIZED (restated).
  UPDATE 2026-10-04 (framekeys CHECK + MSS accept): released
  framekeys probe inner **1** on CHECK (use-before-def, ws_drop
  at 1495 after use at 1473), NO arity verdict; tails must use
  earlier defs or inline. Follow-up framekeys2 prepared
  (ws_drop body inlined via ws_mkloop:1338, diff 4a7928cc8fcb1558
  read back, ONLY wsnet differs): EMIT HELD for release. MSS
  finite SOURCE ACCEPT: blob 867488629e9a5c24ed0e9ae3cb3d8e3d8ff56f5b
  + 24 E.must + 6 strings + driver 61852d85 + Make a3f01e71 all
  verified firsthand; source only, no native pass. NO PUSH
  AUTHORIZED (restated).
  UPDATE 2026-10-04 (v1 WITHDRAWN, v2 released+running): v1
  release withdrawn (reviewer missed the dotted forward ref
  ws_drop 1472->1495); Main's CHECK inner 1 stands as the exact
  invalid-probe receipt, no arity verdict. V2 SOURCE-RELEASED
  for one bounded UCHK4 same-pin characterization: diff
  4a7928cc8fcb155887ddf08a226993544550e46f6b66f241e19a1e35e3161522
  verified firsthand, ONLY wsnet differs, ws_mkloop:1338 before
  use:1472, exact ws_drop body inlined. Emit in flight
  (ugate4-framekeys2.log); receipt to follow. No production/
  native/arity-fix claim until actual result. NO PUSH AUTHORIZED
  (restated).
  UPDATE 2026-10-04 (v2 RECEIPT): entrypoint app.bend on UCHK4
  + framekeys2 body: inner **124** (300s timeout, 0-byte log,
  NO artifact). NO phase/verdict: neither arity error nor check
  error observed; timeout alone decides nothing. Same non-verdict
  class as mss probe4/shutdown_flush emits. No bound change, no
  retry, no claim. Next same-pin step awaits direction. NO PUSH
  AUTHORIZED (restated).
  UPDATE 2026-10-04 (inspector run 1 ABORT): timeout -k 10 290
  run.sh (9c6524d4+3ffea00d), 13:46:30Z-13:47:19Z, exit 1, no
  URL in 45s. Cause: BSD sed lacks \(a\|b\), PORT stayed empty
  although ws://127.0.0.1:54591 was present (:0 works). Raw
  receipt kept; port verified free post-trap. Fix (two -e,
  extracts 54591 from raw log): run.sh
  940c9609987a78e7f193d9ebddca340faeccf066f3657b425474da7a7d08cc56.
  NO relaunch until re-released. NO PUSH AUTHORIZED (restated).
  UPDATE 2026-10-04 (inspector run 2 ABORT): f8dda046+3ffea00d,
  13:50:27Z-13:51:01Z, exit 1. Listener verified (target 64435
  on 127.0.0.1:55837); client 64557 failed rc=1 at fetch(/json)
  non-OK, no CDP traffic. Raw receipt kept. Post-cleanup:
  both PIDs gone, port free (verified). Cause wording: exact
  port-expression failure (delimiter collision), not a general
  BSD claim. Proposed: drop /json, validate advertised host/port
  against verified values. Awaiting release, no claim. NO PUSH
  AUTHORIZED (restated).
  UPDATE 2026-10-04 (inspector HOLD): Bun embeds
  InspectorCDPAdapter but /json+adapter need #nodeInspector mode
  (run 2 lacked it); no launch until verified mode selector /
  protocol mapping. No-discovery scripts f9495d70+1bd98abd stand
  by unrun. No backend change, no claim. NO PUSH AUTHORIZED
  (restated).
  UPDATE 2026-10-04 (inspector run 3 ABORT): f9495d70+c5c6793d,
  bun 5f4369ed6f53, 14:10:13Z-14:12:45Z, exit 1. Listener verified
  (77676/127.0.0.1:59474); client attached, breakpoint set, zero
  pauses in 150s while target printed known arity error. Durable
  verdict: ZERO OBSERVED pauses / NO segment result (binding
  unrecorded, not proved). Raw receipt kept; both PIDs gone,
  port free. No fallback, no retry, no claim. NO PUSH AUTHORIZED
  (restated).
  UPDATE 2026-10-04 (binding run PARTIAL): 1e14efcd+cc2c2f20,
  14:26:46Z-14:28:50Z, exit 0. Verified listener (17055/
  127.0.0.1:61391). Receipt: exact locked comp.ts scriptId 35;
  setBP id ok pending; ONE resolved at line 3115 (asked 2926);
  source getter failed (no die line); 0 pauses; status PARTIAL,
  noSegmentResult true. Banner-only target log = terminated at
  window end, NO phase verdict (not 'mid-compile'). Cleanup
  verified (PIDs gone, port free). Metadata-ready only; no
  inference. HOLD: owner deciding paused-source vs
  pause-on-exceptions route; no new jobs/implementation until
  finite decision. NO PUSH AUTHORIZED (restated).
  UPDATE 2026-10-04 (exception run ABORT): f434401e+b1a0e77d
  (hashes verified), 14:46:28Z-14:49:32Z, exit 1. Listener
  verified (5837/127.0.0.1:64210); ordered acks ok; ZERO pauses
  in 150s, empty JSON; banner-only target log, NO phase verdict.
  NO exception/frame/metadata. Raw receipt kept; PIDs gone,
  port free. Stopped; next check awaits direction. Prep landed:
  gates-registration 7588B, handoff-creadiness 20370B (nothing
  applied). NO PUSH AUTHORIZED (restated).
  UPDATE 2026-10-04 (wire-style guard): exact recipe, make exit
  2. Emit inner 0, no arity error (binary 1127984B
  d819c6d8d145629a); runtime inner 1 on `typing strips style
  nick got=[a lice] want=[alice]` (STX retained). RED on
  behavior; stays standalone with the other 7 promotions held.
  NO PUSH AUTHORIZED (restated).
  UPDATE 2026-10-04 (typing seam scoped greens): production
  delta fd60cdbf0b0303bb (243 lines, 3 files, vs chk-union5)
  accepted NARROWLY by both source reviewers; no
  negotiated-CM or Workspace coverage claimed. test-typing:
  make exit 0, token typing_demo=ok
  (build/test-logs/golden.ofrJ1t); sources irc.bend
  ccc220d2e9cddf08, typing.bend 7a0d3e4fa533352b,
  typing_demo.bend 567eb4580d285754; binary build/typing_demo
  0061c46036106bd5. Original red gate test-wire-style-view:
  make exit 0, token wire_style_view=ok
  (build/test-logs/golden.uXlwcG); fixture 47c7f8734dcaf699
  unchanged; binary d4f0aa2a01c3f11b. Scoped greens only; the
  extra U5 control below is NOT part of either verdict.
  UPDATE 2026-10-04 (180s control NON-QUALIFYING): isolated
  chk-union5 copy + repaired Irc/Typing, U5 typing_demo.bend
  byte-identical (cmp clean); make test-typing inner timeout
  180 bend -> Error 124, wall 3m3.506s. No artifact, no
  behavior verdict, no phase cause stated. Compile-bound
  timeout only; not a recipe qualification.
  UPDATE 2026-10-04 (timeout600 attempt CANCELLED,
  NON-QUALIFYING): inner bend recompile with lifted timeout
  600 launched WITHOUT authorization; owner STOP executed via
  tool-reported session cancellation (work outcome cancelled,
  zero output bytes, no exit code, no artifact). No
  wider-bound result exists or is claimed. No PID lineage was
  recorded, so independent descendant-absence is UNQUALIFIED.
  NO PUSH AUTHORIZED (restated).
  UPDATE 2026-10-04 (psrc run NO-FINDING): cmd `timeout -k 10
  290 run.sh psrc.ts` (hashes verified pre-run: run.sh
  a1d077ae..., psrc.ts 8703b48d...), START
  2026-10-04T15:51:16Z, END 15:55:04Z, WRAPPER-EXIT 1.
  Listener VERIFIED (target 30069 on 127.0.0.1:57960); client
  30175 attached, setup acks ok, then NO locked-script
  scriptParsed within shared 220s:
  `PSRC-NO-FINDING: no-locked-script: budget exhausted`
  (client.json empty, 52B err). Target log banner ONLY (no
  arity line either way): terminated at window end, NO phase
  verdict. NO metadata/source/eval. Raw receipt kept
  (/tmp/birc-inspect/run-UWYvtNCL/). Post-cleanup absence
  VERIFIED (both PIDs gone, port free); no cleanup
  limitation. Stopped per release: no cause inference, no
  unchanged rerun. DEBUG receipt only. NO PUSH AUTHORIZED
  (restated).
  UPDATE 2026-10-04 (psrc reordered run ABORT): cmd `timeout
  -k 10 290 run.sh psrc.ts` (hashes verified pre-run: run.sh
  a1d077ae..., psrc.ts 0bcf0273...), START
  2026-10-04T16:07:36Z, END 16:07:49Z, WRAPPER-EXIT 1.
  Listener VERIFIED (target 3919 on 127.0.0.1:59894); client
  4037 attached, setup acks + exact script capture passed,
  then `PSRC-ABORT: pause not acknowledged` (35B err,
  client.json empty). Measured sequence differs from run6's
  pre-init gate (past script wait here); no cause claimed.
  Target log banner ONLY (no arity line either way). NO
  pause/source/metadata/eval. Raw receipt kept
  (/tmp/birc-inspect/run-PuFPrZfz/). Post-cleanup absence
  VERIFIED (both PIDs gone, port free); no cleanup
  limitation. Stopped per release: no inference, no
  unchanged rerun. DEBUG receipt only. NO PUSH AUTHORIZED
  (restated).
  UPDATE 2026-10-04 (guardH typing TIMEOUT, no verdict):
  `make test-typing` on released guardH bytes (delta
  e27143e7... re-verified pre-run), START
  2026-10-04T16:13:07Z, END 16:16:11Z, make exit 2. Inner
  `timeout 180 bend tests/bend/typing_demo.bend -o
  build/typing_demo` -> Error 124 (killed at bound, no
  diagnostics; a type error would exit 1). No binary, no
  golden, no behavior verdict. Load delta vs last green:
  ~150 new staged session-builder lines; bound already
  marginal (smaller U5 control timed out once at 180).
  Sequence HALTED per release (workspace not run): no
  timeout lift, no unchanged retry. Awaits direction. NO
  PUSH AUTHORIZED (restated).
  UPDATE 2026-10-04 (guardH typing diagnosis RETRACTION):
  the prior entry's cause language is RETRACTED as
  unmeasured: 'compile work scales with def count',
  'variance plus added load crossed the bound', 'a type
  error would exit 1' used as exclusion, and 'bound
  marginal'. Line/def counts and pre-kill silence do not
  identify phase/cause and do not rule out a later
  type/linearity error. RETAINED measured facts only: inner
  `timeout 180 bend ...` -> Error 124, no new artifact
  emitted, no assertion executed. The old pre-guard binary
  must NOT be run as new evidence. No wider bound, no
  unchanged retry. Awaits direction. NO PUSH AUTHORIZED
  (restated).
  UPDATE 2026-10-04 (psrc instrumented run ABORT): cmd
  `timeout -k 10 290 run.sh psrc.ts` (hashes verified
  pre-run: run.sh a1d077ae..., psrc.ts 5f2e28e5...), START
  2026-10-04T16:38:36Z, END 16:38:52Z, WRAPPER-EXIT 1.
  Listener VERIFIED (target 58373 on 127.0.0.1:63547);
  client 58637 attached, setup + script capture passed.
  Fixed pause-ack JSON: category timeout, protocolCode
  null, closed/error false, pausedDelta/resumedDelta 0,
  currentPaused false, elapsedMs 12515 (TOTAL client time),
  remainingMs 207485; then `PSRC-ABORT: pause not
  acknowledged`, client.json empty. Target banner ONLY, no
  app.c. ZERO metadata: stop, no relaxation/retry. Raw
  receipt kept (/tmp/birc-inspect/run-7DourUvF/).
  Post-cleanup absence VERIFIED (both PIDs gone, port
  free); no cleanup limitation. CHECKPOINT: union typing
  repair fd60 accepted narrow; guardH e27143e7 applied,
  typing gate 180-timeout unqualified, workspace unrun;
  C-emit plan 7c97e915 pending source-only. App arity
  STILL UNFIXED. Full proof600 / make check / native /
  PTY3 same-binary / Nix qualification ALL STILL PENDING.
  NO PUSH AUTHORIZED (restated).
  UPDATE 2026-10-04 (C-emit measurement FINDING, emitted-C
  only): plan 64b11418 (wording-corrected release) executed
  verbatim via file driver (direct `&` refused by harness;
  all children waited in-command). FIXTURE guardH 165ace89
  matched; flake.lock d205145c; nix 2.35.2; BEND_BIN
  vp83vc93.../bin/bend; DRIVER pid 77062 pgid 77059; JOB
  77910 reaped by wait, EMIT_EXIT=0, 16:55:11-16:56:08Z.
  Fresh C: 15277710B, sha256 6810e004... in
  /tmp/birc-typing-emit.LKO0kYVs/ (full raw recipe.log
  kept). SCOPE: C codegen completed <170s on guardH bytes
  ONLY. Native 180 timeout still unexplained; no
  phase/cause claim; no native/assertion/App
  qualification. Descendants NOT OBSERVED/unqualified per
  plan. NEXT (chosen, needs release): bounded CC-only
  compile of the emitted fresh C to bisect the remaining
  post-codegen unknown; no prep/run until released. Full
  proof600 / make check / native / PTY3 same-binary / Nix
  STILL PENDING. NO PUSH AUTHORIZED (restated).
  UPDATE 2026-10-04 (C-emit driver-language RETRACTION):
  'all children waited in-command' is RETRACTED as
  overclaim. Measured facts only: JOB root reaped by
  `wait`; lineage samples observed PIDs while running.
  Descendant absence was NOT OBSERVED and is unqualified;
  no full-census proof exists or is claimed. No other
  receipt field changes. NO PUSH AUTHORIZED (restated).
  UPDATE 2026-10-04 (proof600 launch HELD on pins): Fresh2
  readiness pins LAWS0367e98e/PROOF21035ce8/Makea3f01e71
  match NEITHER union NOR chk-union5 NOR root blobs.
  Measured: union == chk-union5 byte-identical on all three
  (LAWS34464c85/PROOF609d6e2d/Make26ee1872); root differs
  from both. Same-ness half holds; hash values
  unreconciled. Proof gate NOT launched; awaits pin
  reconciliation. NO PUSH AUTHORIZED (restated).
  UPDATE 2026-10-04 (pin HOLD correction -- algorithm
  mix-up, no source mismatch): Fresh2's pins were Git blob
  IDs (40 hex), compared against my SHA256 (64 hex).
  Independently re-verified: `git hash-object` on union
  LAWS.bend/PROOF.bend/Makefile = 0367e98e.../21035ce8.../
  a3f01e71... EXACT match to Fresh2; sha256 =
  34464c85.../609d6e2d.../26ee1872... as measured. Pin
  hold WITHDRAWN on this ground; all pins labeled by
  algorithm from here. Proof600 release revalidates on
  these verified bytes. NO PUSH AUTHORIZED (restated).
  UPDATE 2026-10-04 (proof600 FAILS, stopped): `make -C
  union proof PROOF_TIMEOUT=600`, START
  2026-10-04T17:04:51Z, END 17:04:57Z, make exit 2. Inner
  `timeout 600 bend PROOF.bend` -> "SOME PROOFS FAIL /
  expected: a term (the keyword 'def' cannot head one) /
  observed: 'def' / Location: 1717
  `def Laws.typing_out_observed_sentinel():`". Measured:
  PROOF.bend:1716
  `def Laws.mode_ordinary_explicit_recallable():` carries
  NO body term (all siblings carry `{==}`); the following
  def fails to parse. Name present, body absent -- a
  name-list match cannot catch this class. File is
  byte-identical to chk-union5 (pre-existing; untouched by
  typing/guard work). Diagnostics preserved in
  /tmp/birc-fresh-main/proof600-run.log (11 lines).
  Stopped per release: no edits, no weakening, no retry.
  NO PUSH AUTHORIZED (restated).
  UPDATE 2026-10-04 (proof600 rerun: semantic failure,
  stopped): restored ONLY the missing `{==}` body under
  PROOF.bend:1716 (diff vs U5 exactly +2 lines; LAWS.bend
  untouched, all other bodies preserved; adjacency scan
  found no other bodyless def). Rerun `make -C union proof
  PROOF_TIMEOUT=600`, START 2026-10-04T17:07:42Z, END
  17:07:53Z, make exit 2. Parse error gone; semantic
  failure at law `rejected_welcome_preserves_live_state`
  (LAWS.bend:63, sole call site): calls 4-arg
  `live_step.registered`, but source (union == U5,
  session.bend:3542) takes 5th `welcomed: Bool` ->
  observed `@welcomed:Bool -> LiveAcc` vs expected
  `LiveAcc`. Pre-existing U5 drift, not typing/guard
  work. Diagnostics preserved in
  /tmp/birc-fresh-main/proof600-run2.log (15 lines). CC
  plan 555a0ef3 (anchored awk) saved, unrun. Stopped per
  release: no law edits, no weakening, no retry. Awaits
  direction. NO PUSH AUTHORIZED (restated).
  UPDATE 2026-10-04 (proof600 run3: 600s timeout, no
  verdict): changed-source rerun after welcomed migration
  + restored body (NOT an unchanged retry). START
  2026-10-04T17:11:00Z, END 17:21:13Z, make exit 2. Inner
  `timeout 600 bend PROOF.bend` -> Error 124, killed at
  bound with ZERO checker output (2-line log: command echo
  + make error). No law verdict in either direction; no
  phase/cause claim. Empty log preserved at
  /tmp/birc-fresh-main/proof600-run3.log. Stopped per
  release: no retry, no edits, no weakening. NO PUSH
  AUTHORIZED (restated).
  UPDATE 2026-10-04 (CC-link measurement: 170s timeout,
  no artifact): plan 555a0ef3 executed verbatim via file
  driver. Preflight passed: IN 6810e004 matched, BANGS0 +
  zero-imports re-verified, CC = nix-store clang 21.1.8
  (major gate passed), DRIVER pid 49876 pgid 49874. JOB
  50997, START 17:22:19Z, END 17:25:09Z, CC_EXIT=124
  (outer TERM at 170s), NO-CC-ARTIFACT. Resample showed
  nix only (sample timing, not a finding). Full 25-line
  raw log kept (/tmp/birc-typing-cc.gkK8KDci/). SCOPE: CC
  step did not complete within 170s; sub-phase unknown,
  no cause; binary never executed; no native/assertion/
  App qualification. Descendants NOT OBSERVED per plan.
  No retry (one run per release). NO PUSH AUTHORIZED
  (restated).
  UPDATE 2026-10-04 (CC scope wording correction): the 'CC
  step did not complete' phrasing is CORRECTED. Measured
  scope only: the Nix+CC envelope did not complete within
  170s; the sample observed Nix only and actual CC admission
  was NOT acknowledged. Do not assert the CC phase was
  entered or slow. No other receipt field changes. NO PUSH
  AUTHORIZED (restated).
- App route-split control result (verbatim-pattern driver
  /tmp/birc-app-control.recipe.sh, closed terminal receipt
  2026-10-04): in-run preflight BASE-507-OK; entry raw-byte
  SHA256:37d9afc3722d4e05a22d0ee1762aa9319793afa4847d
  1075e6c3d5f7cbe5420b; flake.lock raw-byte SHA256:d2051
  45c50d04c45865a3018dd1051d796a081b9e7ffb9b0e9037b9
  67bb50d34; nix 2.35.2; BEND_BIN vp83vc93fd31ykls5x39
  mjac3xjh08mw-bend/bin/bend; DRIVER pid 25027 pgid 250
  24; JOB pid 28355; 17:44:26-17:47:01Z (~155s). Inner
  EMIT_EXIT=1 (child's own failure; not 124/137 outer
  kill). Bend emitted EXACTLY 'Error: an arity over 247'
  (once) and NO C artifact. Resample observed nix only
  (sample timing, no admission/causation claim). Descendants
  NOT OBSERVED per plan. Plan sha256:6fb76ed592c6385e2e
  816b776a695fa76bbf2b756ef00f021637520181bcff0f with
  variant rule; control meets the gate text exactly (known
  failure, no C) but SplitA is NOT released by this receipt
  alone -- a separate review still gates it. One run per
  release; no retry. NO PUSH AUTHORIZED (restated).
- Control verification addendum (controller direct read
  2026-10-04): recipe.log confirmed EMIT_EXIT=1, exact
  'Error: an arity over 247', NO-EMIT-ARTIFACT, 17:44:26-
  17:47:01Z. Correct owned IDs are driver25027/PGID25024,
  JOB28355; worker prose mixed older CC IDs (corrected
  here; both TODOs already held the correct IDs). Inner
  chain sample at 17:46: timeout28359 -> Bun33044. The four
  captured PIDs are now absent; that is a PID-absence
  observation, not a full descendant census. NO PUSH
  AUTHORIZED (restated).
- SplitA variant result (released run, verbatim-envelope
  driver /tmp/birc-app-splitA.recipe.sh raw-byte SHA256:87
  1cd0aa6f2bd27e1c34f4e1f20211b9b1fb6453f1d05bf32d20
  928ad2385e20, closed terminal receipt 2026-10-04):
  preflight re-verified manifest raw-byte SHA256:56e2ddf5
  17019951cf3e3533a6124fb7e5d3a7c95fbe26ab7b0e1470f43
  8ed71 (507 OK, 0 FAILED); splitA entry raw-byte SHA256:
  95b91bfef90fbaf0ea40d01f7ecf6b36e3d5fc99aa38ad500df
  2758dd25e52f3; frozen diff raw-byte SHA256:18f0786a614
  dd578ae3c4171f0d8e0e8d10c89a3db99ca4895b9622669c02b
  bb; live diff -rq shows ONLY app.bend differs; union
  entry still 37d9afc3 (preserved); in-run gates SPLITA-
  506-OK + SPLITA-DIFF-MINIMAL-OK. Pins: flake.lock raw-
  byte SHA256:d205145c50d04c45865a3018dd1051d796a081b9
  e7ffb9b0e9037b967bb50d34, nix 2.35.2, BEND_BIN vp83vc93
  fd31ykls5x39mjac3xjh08mw-bend/bin/bend. DRIVER pid 69725
  pgid 69714; JOB pid 71051; 17:49:34-17:51:17Z (~103s).
  Lineage: launch timeout->nix; resample inner timeout->
  bun (sample timing only). Inner EMIT_EXIT=1 (child's own
  failure; not 124/137). Bend emitted EXACTLY 'Error: an
  arity over 247' (once) and NO C artifact. Descendants NOT
  OBSERVED per plan. Receipt /tmp/birc-app-splitA.d1FRpQgU
  (19-line raw log). Emit-only: no CC, no runtime; the
  altered App never ran. Interpretation per release: the
  variant FAILED, so neither route is exonerated (multiple
  offenders remain possible); nothing about cause, width,
  or any other route. One variant only; no retry, no
  further branch jobs. NO PUSH AUTHORIZED (restated).
- SplitA receipt acknowledgment (controller direct read
  2026-10-04): /tmp/birc-app-splitA.d1FRpQgU/recipe.log
  confirmed 17:49:34-17:51:17Z, EMIT_EXIT=1, exact 'Error:
  an arity over 247', no C. Captured PIDs 69725/71051/
  71054/71397 are now absent; that is a PID-absence
  observation, not a full census. No unique-subsystem
  inference; removed routes are NOT exonerated. Standing
  prose correction: worker chat text mixed older CC-lane
  IDs into control/SplitA summaries; owned receipts and
  both TODOs hold the correct per-run IDs (control
  driver25027/PGID25024/JOB28355, SplitA driver69725/
  pgid69714/JOB71051). NO PUSH AUTHORIZED (restated).
- SplitB complementary preparation (SOURCE-ONLY 2026-10-
  04; NOT launched, no job): built from frozen BASE (not
  from SplitA) at /tmp/birc-app-split/splitB. ONLY change
  is app.bend line 77, the main_dispatch.servers False
  branch body: 'WsNet.run_ws(...)' replaced by
  'IO.pure(Unit, Unit{})' (one '-' plus one '+' line).
  Retained byte-identical: signature/match/True75,
  main_live43-44, run_demo14-15, all demo/replay branches,
  all imports (WsNet import retained). Wire verified
  affine-safe with only Data/primitive args (release
  statement; recorded, not re-derived). SplitB entry raw-
  byte SHA256:d3339fbb052a9286e515baab866d319dcb3c7f350
  b37f04b22e13e8a01f02d7f; exact diff file splitB-
  base.diff raw-byte SHA256:02c1af591ac8aefde327785a0ca
  20c70ed5c472305afd17b4a4105b7a2a1e228; live diff -rq
  shows ONLY app.bend differs; all other 506 files match
  the frozen base manifest. Driver /tmp/birc-app-
  splitB.recipe.sh raw-byte SHA256:a74649f041c7498833aa
  7f4684e3995678e96c2f7192715040ba38d0c865c477 carries
  a DO NOT LAUNCH header, is syntax-checked, and was NOT
  run: same C-only hard300 envelope, fresh /tmp/birc-app-
  splitB.XXXXXXXX receipt/app.c, no CC/runtime. Base
  (37d9afc3), base manifest (56e2ddf5), union (37d9afc3)
  re-verified unchanged; root untouched. No debugger/CC/
  runtime jobs. The exact artifact awaits review before
  any release. NO PUSH AUTHORIZED (restated).
- SplitB variant result (released run of the literal
  reviewed driver /tmp/birc-app-splitB.recipe.sh raw-byte
  SHA256:a74649f041c7498833aa7f4684e3995678e96c2f71927
  15040ba38d0c865c477, closed terminal receipt 2026-10-
  04): pre-launch recheck matched driver/entry/diff pins;
  in-run gates SPLITB-506-OK + SPLITB-DIFF-MINIMAL-OK;
  entry raw-byte SHA256:d3339fbb052a9286e515baab866d31
  9dcb3c7f350b37f04b22e13e8a01f02d7f. Pins: flake.lock
  raw-byte SHA256:d205145c50d04c45865a3018dd1051d796a0
  81b9e7ffb9b0e9037b967bb50d34, nix 2.35.2, BEND_BIN
  vp83vc93fd31ykls5x39mjac3xjh08mw-bend/bin/bend. DRIVER
  pid 54778 pgid 54771; JOB pid 63212; 17:56:26-17:58:36Z
  (~130s). Lineage: launch timeout->nix; resample nix
  only (sample timing, no admission/causation claim).
  Inner EMIT_EXIT=1 (child's own failure; not 124/137).
  Bend emitted EXACTLY 'Error: an arity over 247' (once)
  and NO C artifact. Descendants NOT OBSERVED per plan.
  Receipt /tmp/birc-app-splitB.mb1DETOp (18-line raw log).
  Emit-only: no CC, no runtime; the altered App never ran.
  The run wrote only the fresh receipt dir; union/root/
  base untouched. Interpretation per release: the variant
  FAILED, so remaining errors cannot be attributed
  uniquely and the removed workspace route is NOT
  exonerated; nothing about cause, width, or any other
  route. One run per release; no retry. Stopped for a
  source-supported next step; no other job released. NO
  PUSH AUTHORIZED (restated).
- Tool-display correction (recorded 2026-10-04, not
  silently passed): the 'Recheck SplitB driver and pins'
  tool call displayed failure because its FINAL command,
  'diff -rq base splitB', exits 1 whenever differences
  exist -- and the single EXPECTED app.bend difference
  exists. All actual pin outputs in that call matched
  (driver a74649f0, entry d3339fbb, diff file 02c1af59,
  rq listing only app.bend). The failure display was
  diff's difference-signaling exit code as the pipeline's
  status, not a pin mismatch; the guarded run proceeded
  on matched pins plus its own in-run gates. NO PUSH
  AUTHORIZED (restated).
- SplitB direct receipt acknowledgment (controller read
  2026-10-04): /tmp/birc-app-splitB.mb1DETOp/recipe.log
  confirmed EMIT_EXIT=1, same 'Error: an arity over 247',
  NO-EMIT-ARTIFACT, 17:56:26-17:58:36Z. This does not
  isolate Net or WsNet; no unique-subsystem inference, no
  exoneration. NO PUSH AUTHORIZED (restated).
- splitC/search-noop preparation (SOURCE-ONLY 2026-10-04;
  NOT launched, no job): built from frozen BASE at
  /tmp/birc-app-split/splitC. ONLY change is net.bend
  search_spawn body (lines 258-261): the 3-line match body
  replaced by 'IO.pure(Unit, Unit{})'; the signature line
  is byte-identical and all callers are preserved
  (net.bend:288 inside emit_cmd, wsnet.bend:328 via
  Net.search_spawn; both files otherwise byte-identical).
  Unlike the Ws-branch-only noop, both Search worker calls
  stop here. Wire verified DiskQuery is Data and no
  Ui/File/Conn enters this boundary (release statement;
  recorded, not re-derived). splitC net.bend raw-byte
  SHA256:eb5bda29f7d935fa85dd43db63d035ab8f42bab47fe39
  3024d3bd34e55ad7030; exact diff file splitC-base.diff
  raw-byte SHA256:38aa079c41da12d4d9b7b6e1854227219ec59
  5004f50012d9d537a47138ec03a; live diff -rq shows ONLY
  net.bend differs; all other 506 files match the frozen
  base manifest. Driver /tmp/birc-app-splitC.recipe.sh
  raw-byte SHA256:8efae8de5b858faa2517b1e6ac91515d61f60
  1d564aae893b8e4ac75b53e507d (entry gate = base app pin
  37d9afc3 plus NET_SHA gate, manifest-minus-net check,
  minimal-diff check) carries a DO NOT LAUNCH header, is
  syntax-checked, and was NOT run: borrowed C-only
  hard300 envelope, fresh /tmp/birc-app-splitC.XXXXXXXX
  receipt/app.c, no CC/runtime. This altered app must
  never run because requests then receive no completion.
  Base app/net (37d9afc3/8d221db2), union app (37d9afc3)
  re-verified unchanged; root untouched. No retries,
  debugger, CC, runtime, or width/cause claims. Job held
  until artifact review. NO PUSH AUTHORIZED (restated).
- splitC/search-noop result (released run of the corrected
  literal driver /tmp/birc-app-splitC.recipe.sh raw-byte
  SHA256:8b1f8095b98dfe7de6f48b2542ee71714eacc65f49082
  fb6a9afd0c28684c87e, closed terminal receipt 2026-10-
  04): the ONLY driver change from reviewed 8efae8de was
  the cosmetic label line 15 ('app.bend excluded' ->
  'net.bend excluded'); the actual filter already excluded
  Net; syntax re-checked. Pre-launch recheck matched app
  37d9afc3, net eb5bda29, diff 38aa079c, rq only net.bend;
  in-run gates SPLITC-506-OK + SPLITC-DIFF-MINIMAL-OK.
  Pins: flake.lock raw-byte SHA256:d205145c50d04c45865a
  3018dd1051d796a081b9e7ffb9b0e9037b967bb50d34, nix
  2.35.2, BEND_BIN vp83vc93fd31ykls5x39mjac3xjh08mw-
  bend/bin/bend. DRIVER pid 7787 pgid 7785; JOB pid 8767;
  18:03:12-18:05:02Z (~110s). Lineage: launch timeout->
  nix; resample inner timeout->bun (sample timing, no
  admission/causation claim). Inner EMIT_EXIT=1 (child's
  own failure; not 124/137). Bend emitted EXACTLY 'Error:
  an arity over 247' (once) and NO C artifact. Descendants
  NOT OBSERVED per plan. Receipt /tmp/birc-app-splitC.OZd
  1I3Iq (20-line raw log). Emit-only: no CC, no runtime;
  the noop Search app never ran. The run wrote only the
  fresh receipt dir; union/root/base untouched.
  Interpretation per release: the shared-helper removal
  did not change the outcome; this tests reachability
  only -- no unique cause or width attribution, no
  exoneration of any route. One run per release; no
  retry; no further job released. NO PUSH AUTHORIZED
  (restated).
- Historical App-C baseline provenance (verified by direct
  read 2026-10-04, source-only): /private/tmp/scratch_
  emit_469c58f.log raw-byte SHA256:0f9936889d75618a99d6
  e02682345b517b5fed431ae343bfd6fd2271b3f7eb9d shows
  'timeout 300 bend src/bend/app.bend -o build/app.c' ->
  EMIT_app=0 (lines 1-3); the same log shows
  ws_upload_frame failing (SOME PROOFS FAIL, gate.tty
  type error) plus handoff/owner emits 0. Retained
  w-upload-cardsbase/build/app.c is 22721994B raw-byte
  SHA256:f801e065a80f16e7966fbb6b0623aea3c1b12ad7917fd
  8985297652d72feb132, matching TODO 6541-42. Commit
  469c58f0ff757a2e8be7857d97e2e8d4640da273 carries App
  Git blob a53495304a14491530ab2e995b066f28c0de82f8;
  successor 11240490594b6e3096dda0e95957ef23edaebd7b
  changes ONLY tests/bend/ws_upload_frame.bend. LIMITS:
  genuine historical full-App C success; NOT current-22/
  App runtime qualification; NOT an exact original frozen
  whole-tree manifest. NO PUSH AUTHORIZED (restated).
- Narrow old17->base ABI note (text-level, no old-source
  compilation, no width/performance/cause claims): App
  entry byte-identical (blob a5349530 both trees). App
  import closure grew 63->72 modules; the delta is
  EXACTLY the 9 new reachable modules (cap_notify 159
  defs; cards_view 2; dns_query 10; emoji 1;
  history_search 339; history_search_io 32; isupport 238;
  session_cards 48; theme 17). Only view_laws changed
  outside the closure; 28 closure modules byte-identical
  (app args auth_bridge base64 cards channel_policy
  client_laws clock_fmt columns diagnostic dns_wire
  endpoint history_startup history_startup_io ipv6
  message_chunks preferences_io preferences_worker
  server_key startup_headless timui tls transport
  transport_policy upload upload_io utc_time wire_style).
  Import edges: all additive except drafts dropping
  message_chunks; new modules attach at auth client
  cards_net dns links net join_plan session
  session_drafts submit view view_hint preferences
  preferences_runtime workspace; pre-existing modules
  newly reached: clock frame cards wire_style ipv6
  server_key notify notify_io cards_net. Native boundary:
  Bend adds clock net_trace, dns UDP.bind6, and
  history_search_io search_scan/open_private (3 sites);
  C adds clock_ffi +3 fns, dns_ffi +2 fns, tls_ffi fn-set
  unchanged, timui.h +timui_uri_admitted (C-internal;
  timui.bend unchanged), new history_search FFI pair.
  Signature-changed defs: 124 across session 37 dns 26
  actor 20 wsnet 14 workspace 8 client 6 net 5 links 2
  media 2 view 2 drafts 1 submit 1; removed defs 61
  (wsnet 15 session 14 drafts 13 client 12 join_plan 3
  others 4); type-header diffs in actor wsnet drafts irc
  links session workspace. Preserved-22 owners
  (Session/boxes/Theme/Card/Notify) mapped only, no
  revert proposed; cards.bend itself unchanged. Method:
  OLD17 tree extracted read-only from git archive; rq +
  def-block signature/body comparison. NO PUSH AUTHORIZED
  (restated).
- splitD/shared-painter preparation (SOURCE-ONLY 2026-10-
  04; NOT launched, no job): built from frozen BASE at
  /tmp/birc-app-split/splitD. ONLY change is net.bend
  paint_go.hint body (lines 193-197, 5 lines) replaced by
  'T.Timui.frame(ui, Nil{}, "", 0)'; full signature
  177-192 byte-identical; all callers/state/lease/
  completion/admission owners untouched (paint_go:200,
  paint_session.hint:206, paint_session_cards.hint:219
  delegate through the hint; Timui.frame declared
  timui.bend:66, native). Source-observable for review:
  the new body references only ui; all other params
  (including non-+ size/split/hint) unreferenced -- no
  verdict, review decides. NOT a global View prune:
  Session admission, Cards visibility, session_paint_vm,
  DrawOp/native frame, caller continuations remain.
  splitD net.bend raw-byte SHA256:d440a4c5c058875f9d5f
  67819b6438c794faab4980a743a956a121264631affc; exact
  diff splitD-base.diff raw-byte SHA256:8b57f853824a3e9
  8c1472bbf77d49489bcc9e56111ba7f3c8fda5782dbfbda5b;
  live diff -rq shows ONLY net.bend differs; all other
  506 match frozen base. Driver /tmp/birc-app-splitD.
  recipe.sh raw-byte SHA256:d2d5a81cb64bf23eff4ee7d61e
  6aac31228adb13e81c8d4fdc775ef4dc6d4a10 (base app pin +
  NET_SHA gate, manifest-minus-net, minimal-diff) carries
  DO NOT LAUNCH, syntax-checked, NOT run: borrowed C-only
  hard300, fresh /tmp/birc-app-splitD.XXXXXXXX/app.c, no
  CC/runtime/debugger. NEVER run this blank-painter App.
  Base app/net (37d9afc3/8d221db2) and union app
  (37d9afc3) re-verified; root holds only TODO
  checkpoints. SplitC restated: failed reachability test,
  not exoneration. No width estimates, broad boxes,
  compiler/pin/deadline changes. Job HELD for actual
  artifact review. NO PUSH AUTHORIZED (restated).
- splitD/shared-painter result (released run of the
  literal reviewed driver /tmp/birc-app-splitD.recipe.sh
  raw-byte SHA256:d2d5a81cb64bf23eff4ee7d61e6aac31228ad
  b13e81c8d4fdc775ef4dc6d4a10, closed terminal receipt
  2026-10-04): source-note checkpoint confirmed in both
  TODOs before launch; pre-launch recheck matched
  driver/net/diff pins; in-run gates SPLITD-506-OK +
  SPLITD-DIFF-MINIMAL-OK; entry 37d9afc3, net d440a4c5.
  Pins: flake.lock raw-byte SHA256:d205145c50d04c45865a
  3018dd1051d796a081b9e7ffb9b0e9037b967bb50d34, nix
  2.35.2, BEND_BIN vp83vc93fd31ykls5x39mjac3xjh08mw-
  bend/bin/bend. DRIVER pid 65733 pgid 65731; JOB pid
  66200; 18:17:25-18:20:16Z (~171s). Lineage: launch
  timeout->nix; resample inner timeout->bun (sample
  timing, no admission/causation claim). Inner EMIT_EXIT=1
  (child's own failure; not 124/137). Bend emitted
  EXACTLY 'Error: an arity over 247' (once) and NO C
  artifact. Descendants NOT OBSERVED per plan. Receipt
  /tmp/birc-app-splitD.7tGmo5gp (20-line raw log).
  Emit-only: no CC, no runtime; the blank-painter app
  never ran. The run wrote only the fresh receipt dir; no
  production or root source changes (root holds only TODO
  checkpoints). Interpretation per release: the variant
  FAILED, so the painter is NOT exonerated (other View/
  caller paths remain); nothing about a measured segment
  or unique cause. One run per release; no retry; no
  further job released. Stopped for the next source
  decision. NO PUSH AUTHORIZED (restated).
- HANDOVER (authority check 2026-10-04; HELD, not
  completion or abandonment). Five same-text C-only App
  receipts, all inner EMIT_EXIT=1 with EXACTLY 'Error: an
  arity over 247' (once) and NO C artifact. Common pins:
  flake.lock d205145c..., nix 2.35.2, BEND_BIN vp83vc93...
  /bin/bend; base manifest 56e2ddf5 (507 files), base app
  37d9afc3. Full per-run pins live in the receipts above;
  compact index: control driver d5a29ec56760ecee333d2a39
  119d2a1b6fa04b9786b4eb009348b9d2c33e8728 (entry
  37d9afc3) 17:44:26-17:47:01Z driver25027/pgid25024/
  JOB28355, /tmp/birc-app-control.ukby1neK (18 lines);
  SplitA 871cd0aa... (app 95b91bfe, diff 18f0786a)
  17:49:34-17:51:17Z driver69725/pgid69714/JOB71051,
  /tmp/birc-app-splitA.d1FRpQgU (19 lines); SplitB
  a74649f0... (app d3339fbb, diff 02c1af59) 17:56:26-
  17:58:36Z driver54778/pgid54771/JOB63212, /tmp/birc-app-
  splitB.mb1DETOp (18 lines); splitC 8b1f8095... (net
  eb5bda29, diff 38aa079c; reviewed 8efae8de + label fix)
  18:03:12-18:05:02Z driver7787/pgid7785/JOB8767,
  /tmp/birc-app-splitC.OZd1I3Iq (20 lines); splitD
  d2d5a81c... (net d440a4c5, diff 8b57f853) 18:17:25-
  18:20:16Z driver65733/pgid65731/JOB66200, /tmp/birc-app-
  splitD.7tGmo5gp (20 lines). No branch exonerated; no
  offending segment measured. Offending segment/arity kind
  and numeric width UNKNOWN: locked comp.ts2926-2928 fails
  when EITHER entries.params.length>247 OR encoded
  constructor/foreign arity>255, and the observed generic
  diagnostic selects neither kind nor measures a value.
  Historical OLD17 positive: scratch log
  0f993688... EMIT_app=0, retained app.c 22721994B
  f801e065... (TODO 6541-42), commit 469c58f / App blob
  a5349530, successor 1124049 fixture-only; LIMIT: not
  current-22/runtime qualification, not an exact original
  whole-tree manifest. Preservation: union app 37d9afc3,
  base app/net 37d9afc3/8d221db2 + manifest 56e2ddf5;
  root holds only TODO checkpoints; all worktrees (incl.
  w-upload-cardsbase @1124049), splits A-D, OLD17
  extract, and five receipt dirs intact. proof600 run3:
  600s timeout, no verdict. CC envelope: 170s timeout, no
  artifact, no admission ack. HELD: no further ablation
  chain, inspector retries, broad boxing,
  compiler/checker/pin edits, or deadline lifts. Copied-
  compiler width observation ESCALATED to parent; do NOT
  prepare/apply/run without explicit new direction. Main
  heavy lane idle; work list empty, no subagents, no
  terminal jobs outstanding. Source-only proposals stay
  read-only and infer no root cause. Remaining: standard
  final/PTY3/Nix qualifications (make check, native,
  PTY3, Nix app). NO PUSH AUTHORIZED (restated).
- COMPDIAG approval + prep (user-approved this turn; original
  full implementation remains active. PREPARED ONLY -- NOT
  RUN). Approval: ONE temporary copied-compiler
  names-and-widths-only diagnostic. Locked source
  /nix/store/ns9rx4cn8vpd391ml8137d46ynb0cfz1-source;
  orig bend2/comp.ts raw-byte SHA256:eee1bfd161a948d1fbe
  2451526975bc44d237b60d6b469d740f9f702720e0bbb (verified).
  Branch comp.ts2926-2928: 'ars' map + 'if
  (entries.some(params.length>WIDE) || ars.some(n>255))'
  + 'die("an arity over "+WIDE)'; WIDE=247 (line 141);
  Seg{fid:string,def:Name,params:string[]}; Name=string;
  die throws. Frozen copy /tmp/birc-compdiag/toolcopy
  (read-only); copy comp.ts SHA256:620703cec26317040d6c
  45c643a826f9f35dbdc93e4d832cfcf8d3ac1851d9cd; orig
  manifest 1886 files SHA256:49485c6ca6aa5ef6fbb22324ce
  1e4f281974ed6a246b8e6c3d90bdbeeb6106ed; copy manifest
  1886 files SHA256:515ae44be2dd1806fac86972b42c4e3cdf60
  f96e109b9194dcb336a366be899c; rq: ONLY bend2/comp.ts
  differs; exact diff compdiag.diff SHA256:22db413739d1b
  45c4e87da1fc2066584d991164a5423c7ebf348142fa5a3b824
  (27-line pure insertion). Insertion strictly inside the
  if-body before die: if/die lines byte-identical;
  thresholds read (WIDE, 255), never changed; cid rows
  use the EXISTING ars[i] (exact encoded arithmetic
  retained, fractional values unrounded); only rows
  satisfying the original failing thresholds print --
  'seg <fid> <def> <params.length>' and 'cid <k> <raw>
  <encoded>'; names sliced to 128 chars with control-char
  sanitizing; 40-row cap with once-only '...' marker;
  try/catch so a print failure cannot bypass die. Prints
  no source, locals, param values, book, env,
  credentials, or descriptions. Transpile-only 'bun
  build' exit 0 (no execution, no App compile). Wrapper
  bun-wrap.sh SHA256:4de22aa8c9afe69e6775d53c1ce56dff93
  fdc64f5a0f92d2b44130a5df9192b0 (export lines identical
  to stock bin/bend; only main.ts path redirected).
  Driver /tmp/birc-compdiag.recipe.sh SHA256:5f8f73a1e5
  8c8955f5d67af99d68464d5c3045fe532668f59b1801c2a26faa
  83, syntax-checked, DO NOT LAUNCH, NOT run: same
  base507 + entry src/bend/app.bend; gates for entry,
  base manifest, toolcopy manifest, comp SHA, wrapper
  SHA, pinned bun; outer290+k10/inner300; fresh
  /tmp/birc-compdiag-run.XXXXXXXX/app.c; no CC/runtime.
  Gate: read-only reviewers verify the exact artifact
  before any run release. If metadata is informative, the
  smallest production correction needs +/- guards and
  same-frozen-candidate measurement with the UNMODIFIED
  stock compiler before final proof600/check/native/
  PTY3/Nix. If no metadata, report the actual blocker
  with no expanded instrumentation or unchanged retry.
  Installed compiler/checker/pins untouched; base app
  37d9afc3 and locked comp.ts eee1bfd1 re-verified; root
  dirty G3 preserved (only TODO checkpoints); all
  worktrees/receipts intact; no push/destructive cleanup.
  NO PUSH AUTHORIZED (restated).
- COMPDIAG review + recipe fix (source-only 2026-10-04; NOT
  RUN). Wire SOURCE ACCEPT: copied comp.ts 620703ce... and
  diff 22db4137... are exactly 27 inserted metadata lines;
  original arithmetic/condition/die intact. Fresh2 ONE tiny
  recipe hold: MEASURE_DIR was fresh but TMPDIR unscoped,
  so wrapper cache defaults used ambient stock cache. Fix
  applied (approved scoped preparation, not a new user
  gate): driver creates owned '$MEASURE_DIR/tmp' (REFUSE-
  TMPDIR on failure) and runs the single copied-wrapper
  invocation as 'env TMPDIR="$MEASURE_DIR/tmp" timeout
  300 ...' after nix develop; wrapper exports, all bounds
  (outer290+k10/inner300), and wrapper argv unchanged; one
  DIAG_TMP receipt line added. Corrected driver raw-byte
  SHA256:38f71aece420cf9fb09f9f9cf0d76e5377e618d4b6fa79f
  85eb7f68f319f0c1d (supersedes 5f8f73a1), syntax-checked.
  Wrapper 4de22aa8 and toolcopy comp.ts 620703ce verified
  untouched. DO NOT RUN until Fresh2 verifies this exact
  fix. No additional diagnostics or source changes. NO
  PUSH AUTHORIZED (restated).
- COMPDIAG result (root-released single run of exact
  driver 38f71aece420cf9fb09f9f9cf0d76e5377e618d4b6fa79f
  85eb7f68f319f0c1d, closed terminal receipt 2026-10-04):
  preflight matched all pins; in-run gates DIAG-BASE-507-
  OK + DIAG-TOOLCOPY-1886-OK; entry 37d9afc3, TOOLCOMP
  620703ce, WRAPPER 4de22aa8, flake.lock d205145c..., nix
  2.35.2, BUN_BIN ymp115cs.../bin/bun, DIAG_TMP under the
  fresh receipt dir. DRIVER pid 22437 pgid 22431; JOB pid
  22645; 23:12:50-23:15:58Z (~188s). Lineage: launch
  timeout->nix; resample inner timeout->bun (sample
  timing only). Inner EMIT_EXIT=1 (child's own failure;
  not 124/137). Exact 'Error: an arity over 247' once;
  NO C artifact. METADATA (informative, complete -- 40-
  row cap not reached, no truncation marker): 16 seg
  rows, 0 cid rows. session.step_keys.supplied$k4570 270;
  session_drafts.step_keys.route$k7252 258;
  session_drafts.step_keys.route$k7253 274;
  wsnet.ws_media_stage$k9926 253;
  wsnet.ws_media_stage$k9927 254;
  wsnet.ws_media_stage$k9928 359;
  wsnet.ws_media_stage$k9933 361; net.live_step$k13285
  257; wsnet.ws_recv$k14258 290; wsnet.ws_recv$k14274
  282; wsnet.ws_recv$k14287 269; wsnet.ws_recv$k14296
  283; wsnet.ws_recv$k14297 299; wsnet.ws_recv$k14301
  285; wsnet.ws_recv$k14304 280; wsnet.ws_recv$k14305 281.
  Failing kind is segment params.length (253-361) across
  5 source defs; constructor/foreign kind has zero
  failing rows. No cause claimed beyond observed rows.
  Descendants NOT OBSERVED. Receipt /tmp/birc-compdiag-
  run.GBt3oAIo (38-line raw log). Emit-only; scoped
  TMPDIR kept bun cache inside the owned receipt; JOB
  reaped by wait; stock compiler/checker/pins untouched.
  Next per release: source-only parallel review for the
  smallest production correction with +/- guards. NO PUSH
  AUTHORIZED (restated).
- COMPDIAG root verification + fix scope (2026-10-04):
  root verified /private/tmp/birc-compdiag-run.GBt3oAIo/
  recipe.log directly: 23:12:50-23:15:58Z, EMIT_EXIT=1, no
  C, 16 seg rows / 0 cid / no truncation. Captured PIDs
  22437/22645/22650/22779 now absent (not a full census).
  Measured groups: session.step_keys.supplied 270;
  session_drafts.step_keys.route 258/274;
  wsnet.ws_media_stage 253/254/359/361; net.live_step 257;
  wsnet.ws_recv 269-299 (8 rows). UNKNOWN-offender gap
  CLOSED (failing kind = segment params.length); this is
  not implementation qualification. Direction: continue
  full fix scope with parallel disjoint source-only
  corrections/guards for the five measured owners --
  minimal capture/lifetime changes or existing boxing
  patterns justified by the actual backend limit; no
  speculative global rewrite, no new checker/threshold/
  pin changes. Preserve 22 Session+boxes/theme, affine
  Ui/Conn ownership, global Notify/Cards/media/uploads/
  consent/archive/PONG invariants. Freeze the reviewed
  corrected candidate and run the UNMODIFIED stock
  compiler bounded300; final proof600/check/native/PTY3/
  Nix still required. Instrumented-tool outputs are not
  final qual. Root remains sole UI; C8 off. Normal scoped
  production fixes need no new permission; new existing-
  test expectation changes need recorded approval.
  Controller handoff: drive_measured_fresh has sole pane
  control; root/C8 send no UI prompts; Main keeps all
  edits and the one heavy lane; no change to limits,
  pins, laws, or approval scope. NO PUSH AUTHORIZED
  (restated).
- Measured-fix imports (2026-10-05, union production): supplied
  pre-hoist session.bend 9c96d751 (matches root scratch) +
  8 upload/supplied guards in upload_session.bend 3c980697
  (additive only, old assertions intact); Net wait-cell
  net.bend 58af5dfc (recv_wait List-box across Chan.recv,
  Nil via owned shutdown_failed; Ui/affine g outside Data;
  affine-drop verified legal via uses_close join lattice)
  + new net_live_wait_cell.bend 94751a63 registered as
  test-net-live-wait-cell in Make (pure payload guard,
  unrun); media pre-IO hoist wsnet.bend 3e4d6899 (matches
  root scratch, Fresh2-accepted; old_generation/old_after
  Nat scalars replace st across job/jobs; ws2/evt/lease2
  precomputed; None keeps lease; clear-then-spawn order
  unchanged; sole-caller chain verified). Linearity
  verified by reading for all hunks (affine 0-or-1: only
  Many-without-+ fails). Pending: Fresh2 drafts-route
  patch; Main WsRecv correction + remaining behavior
  guards; then freeze + single stock emit. Fixture note:
  cmd_around_stamp_prefixed migration NOT approved, do
  not touch. NO PUSH AUTHORIZED (restated).
- Fixture approval applied (user approved root question
  call_4Y4CEmfKSl791lGE2XTkOWdM 'Approve this fixture
  correction', 2026-10-05): union tests/bend/
  history_search.bend lines 305-306 only --
  cmd_around_stamp_prefixed input and expected wire
  timestamp are now timestamp=2026-10-03T10:00:00.000Z,
  plus a new cmd_around_stamp_prefixed_no_ms assertion
  that bare-seconds timestamp=2026-10-03T10:00:00Z is
  rejected. Every other input/assertion preserved. New
  fixture SHA256:bd7cd66ccf9d405a55ac20e5e50a1324031aa25
  7750a782b35e87184e6910cbc. No job run. NO PUSH
  AUTHORIZED (restated).
- Measured-fix checkpoint (2026-10-05 10:03Z): controller
  drive_measured_fresh still solely owns Muse pane %4. Same
  session survived request steering and transport failures;
  no context restore. C8 scratch attempt failed during remote
  compaction and returned NO patch. Root prepared scratch-only
  supplied/media hunks; Fresh2 independently reviewed them and
  prepared Net. Main alone imports into /tmp/birc-fresh-main/union.
  INTEGRATED, root hash-verified: Session 9c96d751... (original
  upload/presentation hoisted before supplied step), existing
  upload_session fixture 3c980697... (eight additive guards,
  every prior assertion unchanged), Net 58af5dfc... (recursive
  singleton Session carrier held across Chan.recv, directly
  parameter-matched after receive; affine Ui/message stay out).
  Source review ONLY; these guards have not run. Media scratch
  /tmp/birc-media-root.1F7bXyiP/wsnet.bend 3e4d6899... accepted:
  old generation/log sequence hoisted before observation,
  updated Workspace prepared before IO, exact None/Some leases
  and clear-before-spawn preserved. Not imported at this check.
  Drafts scratch assigned Fresh2; WsRecv stays Main-owned. No
  second copied diagnostic, compiler/pin/threshold/deadline/law
  changes, heavy verification job, or push. Stock full-App emit,
  proof600, check, native gates, PTY3, and Nix remain unqualified.
  Separate cmd_around_stamp_prefixed .000Z fixture correction
  explicitly APPROVED by user on 2026-10-05: input and expected
  wire line use .000Z; add bare-seconds rejection. Exact reply:
  "Approve this fixture correction" (question call_4Y4CEmfKSl791lGE2XTkOWdM).
  Prior assertions/inputs otherwise stay unchanged; hold closed.
- Stock correction check (2026-10-05): the frozen ISO-cell
  patch /tmp/birc-iso-freeze/session-iso-candidate.patch
  2b2395b8... received root + Fresh2 finite source acceptance.
  Session c02848bb..., Workspace 4fdac5be..., fixture dd980153...
  preserve 22 fields and original semantics; source verdict ONLY.
  Actual STOCK `make build/birc_bend.c` in the union ran
  11:26:13-11:28:23Z (~130s), with the unchanged rule's
  `timeout 300 bend src/bend/app.bend -o build/birc_bend.c`.
  Bend exit 1, make exit 2: `Error: an arity over 247`;
  NO C artifact. All 97 before/after input hashes identical
  (manifest 742a3215be8747dd60c230f61c4bce50471deaec6d406726d444eda477eb7f8a).
  Raw /tmp/birc-emit300/emit.log + RECEIPT.md retained.
  The shared ISO box was NOT SUFFICIENT for full-App codegen.
  Current remaining continuation names/count are UNKNOWN;
  receipt's initial "four remaining owners/outside authorization"
  claim is unsupported and was explicitly corrected to Main.
  Next: retain ISO temporarily/unqualified; RELEASE reviewed
  Drafts contingency 5ec0b4ab... for Main-only import with its
  14 additive guards; Main owns WsRecv correction. Source-only
  ISO guards a24df093... may import after finished run. No
  unchanged stock retry or copied diagnostic run authorized.
  A ONE-CONDITIONAL same names/widths diagnostic rerun was
  ASKED, only if stock still fails after next targeted fixes;
  user approval pending. Stock proof600/check/native/PTY3/Nix
  still required; no gate/deadline/pin/law change or push.
- Imported correction source review (2026-10-05 11:42Z):
  Drafts r2 is now INTEGRATED and independently SOURCE ACCEPTED.
  Production session_drafts.bend 216ddd0b96cec4fc6c89eae42120e69cf04cce06ef18e5c9df8bd3b618e02041;
  additive fixture session_drafts_demo.bend 5fcb79e40239dcdfc3afc3ce5f9766ff5f6e72e22c3dc2551370913c67aa9478.
  Stable imported bytes match released patch 5ec0b4ab...;
  removing only 14 new guards restores the old fixture exactly.
  Four actual route producers retain the ORIGINAL Session through
  delegated calls; original error/endpoint/rollback and physical
  upload consent remain intact. No fabricated Session on Nil:
  fail closed with no wire output. Tests remain UNRUN.
  ISO guards 60ed16ff... also integrated, unchanged old expectations,
  UNRUN. Immutable import checkpoint: /tmp/birc-imports-freeze,
  imports.patch 6eeb45e8366c1bd4b1f47ea343323023ce799f62049755f160c87e69d8399a65.
  Main still owns the actual WsRecv correction and sole heavy lane;
  Fresh2 prepares a source-only independent minimal-carrier proposal.
  Media coverage gap stays OPEN: wsnet_gates checks pure lease/media
  policy, NOT the changed ws_media_stage/jobs/job or clear-before-spawn
  IO order. Add the smallest actual None/Some native characterization
  with synthetic recording helper once the stock native path works.
  Conditional diagnostic approval remains pending. No current width
  success, final proof/check/native/PTY3/Nix qualification, or push.
- Conditional diagnostic approval (2026-10-05): user explicitly
  approved question call_avgPRips2MSRp8VHB3zwCr1r with
  "Approve one conditional diagnostic run". ONE rerun of the SAME
  reviewed names-and-widths logger is authorized ONLY if the next
  STOCK full-App emit still fails after the Drafts/WsRecv corrections.
  First freeze the corrected candidate and adapt/review only the
  recipe's candidate-path/manifest preflight (old baseline507 is not
  this candidate). Keep the reviewed compiler-copy/logger/wrapper,
  bounds, output privacy, and ownership envelope unchanged. Installed
  tools, compiler limits, pins, laws, and final stock verification stay
  unchanged. This is not an immediate run or repeated-run approval.
- Corrected WsRecv / STOCK#2 checkpoint (2026-10-05 UTC):
  Actual WsNet d49407d4... is SOURCE ACCEPTED: exact original bell
  scalar before post IO; full recursive WsLoop carrier across receive
  and both routed clocks; Ui/message/continuation outside Data;
  accurate Nil failure, no fabricated Session/lease. Frozen patch
  /tmp/birc-wsrecv-freeze/wsrecv.patch 4bff33a1... . Additive bell
  guard cdc0066e... and envelope guard 588c6e2f... preserve all old
  expectations. Root caught/fixed the new guard's wrong LP namespace;
  correct existing PrefLive.initial now used. Tests still UNRUN.
  Auxiliary authoring/replay scripts are UNQUALIFIED records, not a
  build gate; their repair detour was stopped. Actual next STOCK
  `make build/birc_bend.c` ran 12:28:08-12:29:08Z (~60s): Bend1,
  make2, generic `Error: an arity over 247`, NO C artifact. Raw
  /tmp/birc-emit300-stock2/emit.log 49908fa9..., receipt 9528224f...;
  all 100 before/after inputs identical, manifest
  2557a2933b6d1675e75e24fadc3cfc05a1788e7e6af9282f517f789269e7a4f8.
  Root checked current100 + reviewed-tool1886 hashes: both exit0.
  Approved condition now satisfied. ONE diagnostic RELEASED to Main
  via sole controller after read-only manifest freeze: prepared recipe
  /tmp/birc-compdiag-next-review.r5oiREE0/recipe.sh 0cfb220c...,
  exact stock2 before.SHA256SUMS plus above hash as its two arguments.
  Original logger620703ce/wrapper4de22aa/bounds/privacy unchanged;
  no further run/compiler/pin/limit/law change authorized. Candidate
  imports held during measurement. No diagnostic result yet.
  Fresh2 actual stamped/parked native +/- guards SOURCE ACCEPTED,
  scratch /tmp/birc-carrier-native-review.GaRaWUAi/ws-carrier-native-r2.patch
  0e078537... (new fixture + owned PTY driver, exact error/teardown,
  metadata/lease retention, no spawned workers/network). Future Main
  import only after measurement; compile/PTY3 still UNRUN. Actual
  media-stage None/Some IO characterization stays OPEN. Final stock
  proof600/check/native/PTY3/Nix/cache qualification and commits remain
  pending. No push; root source/index changes remain protected.
- Controller lease changed (2026-10-05 17:07Z): diagnostic release
  had not reached the idle Muse pane. Root interrupted
  drive_measured_fresh (status verified interrupted) and explicitly
  revoked its UI/job authority. ROOT is now the sole pane %4 controller;
  do not send UI input from drive/C8 until explicit handback. Main still
  owns source integration and the one heavy lane. Root delivered the
  exact approved conditional invocation directly; it was consumed
  at 17:07Z. No Main build/worker was stopped and no diagnostic result
  exists yet. Protected root source/index hashes remain unchanged.
- Conditional diagnostic / STOCK#3 checkpoint (2026-10-05 UTC):
  The one approved diagnostic was USED, 17:08:17-17:09:10Z.
  Raw receipt /tmp/birc-compdiag-run.HSHFtFUw/recipe.log
  1f711b7d... records EMIT_EXIT=1, no C artifact, and exactly three
  over-wide continuations owned by ws_parked.recv (254/263/249).
  The logger does not identify source branches or captured values.
  No further copied-compiler run is authorized. Installed tools,
  limits, pins, and stock final qualification remain unchanged.
  Main applied a source-equivalent nested-pattern correction,
  WsNet 4032e668..., parked.patch f8970f29... (+2/-4). STOCK#3
  make build/birc_bend.c ran 17:14:14-17:15:09Z (~55s): Bend1,
  make2, generic arity247 error, no C. Root checked raw output and
  identical 100-input before/after manifests (5e7a0e01...). Receipt
  /tmp/birc-emit300-stock3/RECEIPT.md (wording-corrected afc9dfdc...). The correction
  is not sufficient; generic failure does not prove a source cause.
  Fresh2's message-first r3 is SOURCE ACCEPTED: frozen patch
  /tmp/birc-parked-branch-review.3LPgU0Dt/parked-branch-split-r3.patch
  9df76dbb..., post-image c41b7d10..., exact None/head and routed-cell
  retention, all four remaining handlers unchanged, one shared
  missing-state shutdown. STOCK#4 on c41b7d10... failed after55s,
  same generic arity247/noC, identical100inputs. Further SOURCE ACCEPTED
  r4 (f64f82f0..., post4518675c...) matches received g before the
  typed loop head, adapts two production calls, and preserves all Nil
  behavior. STOCK#5 ran17:29:41-17:30:35Z (~54s), Bend1/make2,
  generic arity247/noC, identical100inputs. Neither candidate is
  sufficient; no new failure attribution. Production changes are held.
  Root asked for one extra same-reviewed diagnostic (approval PENDING).
  Seven-case actual native carrier guard87d81bc7... is SOURCE ACCEPTED,
  UNRUN: adds network/tick positives and queued-message/Nil rejection,
  preserving four old cases and exact error/terminal-restoration oracle.
  Main imported the new fixture/driver/standalone Make target. First
  scoped check17:35:13-17:35:17Z failed at a new constructor-binding
  annotation, noC/binary/PTY. Raw /tmp/birc-carrier-test/run1.log.
  SOURCE ACCEPTED combined correction7125f9f3... gives59003911...:
  two explicit types and actual Some-ingress validation; seed values,
  all assertions/seven cases/driver unchanged. Main applied exact5900
  and ran bounded make test-ws-carrier-native run2 at17:39:52-17:40:02Z.
  It failed with `the machine stack overflowed`, Bend1/make2; noC,
  binary, orPTY. Identical76inputs; raw /tmp/birc-carrier-test2/run.log.
  The global RangeError formatter does not identify compiler phase.
  Carrier native qualification remains OPEN. New guards are not in check.
  Four-case actual media IO guard166b06f7... is SOURCE ACCEPTED,
  scratch /tmp/birc-media-stage-review.P8EiT9t8, fixtured6ad063b...
  and driver180861fc..., standalone registration73b8b2f3... . Main
  imported these new files/target. Run1 emitted C but failed native
  compile for missing retained TimUI/DrawOp CIDs. SOURCE ACCEPTED
  public frame-retention deltae2366bc3... gives60bb37be...; four real
  cases/driver unchanged. Run2 emitted C and linked a native binary,
  but its free case failed the exact output oracle. Controlled capture
  /tmp/birc-media-diag/diag.raw.txt measured token LF LF. Pinned
  effs/print.c appends LF; fixture also supplied LF. Main removed only
  that duplicate (actual6e1ae1a8..., one-line diff root checked), driver
  and assertions unchanged. Bounded rerun3 PASSED: make
  test-ws-media-stage-native exit0; all four cases free/blocked/jobs-none/
  jobs-some green with helper counts1/0/0/1. Root read raw
  /tmp/birc-media-test3/run3.raw.txt and checked identical76inputs.
  Actual binary213a0377...; this is scoped media state/lease/event
  qualification, not fullApp/proof/Nix/PTY. It is a headless driver,
  not a PTY test. App/codegen arity blocker and carrier checker stack
  failure remain OPEN. Final gates and root integration remain pending.
  Production app4518 remains frozen. It checks state/lease/event
  ownership with a fake local helper; private clear effect and runtime
  clear-before-spawn order remain explicitly unobserved/source-only.
  Stock check-only carrier check also failed with stack text (~4.7s),
  identical75inputs: /tmp/birc-check-carrier/check.raw.txt. No C/run.
  Media native target is now registered in test-review-pure after its
  four-case pass (Makefile b05e24f8..., only registration/help edits).
  Exact definition-prefix diagnostics ran stock check-only in owned
  /tmp/birc-carrier-prefix-snap, not union: imports-only and first13
  return normal unsafe listings, full25 returns the stack error.
  Raw /tmp/birc-carrier-prefix-run/prefix{00,13,25}.raw.txt; root
  verified identical278inputs before/after. Later exact19/16/14 prefixes
  also fail; root checked their identical before/after manifests.
  First trigger is definition14 run_mode, not an identified cause or
  native verdict. No C/CC/execution/toolcopy. Main saved a compact
  checkpoint at union TODO's final CHECKPOINT 2026-10-05T18:18Z.
  Root verified idle/no owned child jobs, stopped old Muse52283
  (host reported its 2s shutdown timeout, then PID was gone), and
  launched pinned fresh Muse6522 at18:21Z in the union, no resume.
  It reads the compact checkpoint, not old conversation archives.
  Fresh Main's A/B stock diagnostics show first3 selector arms check
  normally, remaining4 stack; both two-arm C/D halves check normally.
  Root read raws and verified identical before/after manifests in
  /tmp/birc-carrier-branch-{ab,cd}-run. Combined-case sensitivity is
  measured, not an identified compiler/handler cause. Source-accepted
  selector-only fixture delta80bda9d6... (16+/8-, post152532c4...)
  retains all seven calls, seeds, callbacks, assertions, driver, and
  final unknown-mode error; two ordered selectors avoid the measured
  large match. Main has release to apply and stock-check this new
  fixture only, then conditional native check. Full stock check still
  stacks (raw /tmp/birc-carrier-split-check/check.raw.txt, make2),
  but exact selector prefix16 now completes checking with only the
  normal unsafe/foreign list. Prefix17 adds unchanged run_case and
  stacks again: /tmp/birc-carrier-split-def17-run/runQ.raw.txt.
  Root verified identical before/after manifests. This proves narrower
  checking progress, not a full fix or exact subexpression/cause.
  Keep the selector split pending the remaining check; carrier is
  UNQUALIFIED, not in check, no native/PTY run. Fresh Main saved final
  compact CHECKPOINT 2026-10-05T18:49Z and is idle, with all further
  jobs/experiments held. One additional same names/widths App diagnostic
  needs the pending new approval; old conditional approval was used.
  Fresh audit's four alleged defects were source-checked: direct jobs
  characterization and CSI/queued-absence limits are scope notes;
  Nil callbacks are intentional poison pills. The contrary claim was
  retracted. No corresponding assertion changes or production edits.
  Check-only validates every imported definition;
  normal unsafe/foreign promise listings must not be mistaken for the
  stack failure. No new checker/compiler instrumentation authorized.
  Dead helper cleanupce17ee4a... (0+/17-, post94a28d5a...) is SOURCE
  ACCEPTED but HELD: remove only unused ws_recv/ws_dispatch, retain
  ws_routed and its upload-frame test; no width claim/import yet.
  Root remains sole UI controller, Main sole writer/heavy
  lane. Native guards/proof/check/PTY3/Nix/cache gates are still pending.

- 2026-10-05T22:43Z continuation: the user's new `yes` approved one
  additional run of the same reviewed App names-and-widths diagnostic.
  This new approval is USED once; Main invoked recipe0cfb220c... against
  the frozen 104-input manifest e9a47053... at
  `/tmp/birc-compdiag-preflight/candidate-inputs.SHA256SUMS`.
  Root checked every input and the 1886-file copied-tool manifest.
  The run has locked Nix, unchanged limits, fresh output/TMPDIR, and
  names/widths only. No further copied run is authorized. Main remains
  the sole writer/heavy lane; two Root agents are doing source-only
  parked-flow and carrier `run_case` reviews. Production stays frozen
  until the raw result is reviewed. Full qualification remains pending.
  Result: inner emit exit1, no C artifact, 47 s (22:42:43–22:43:30Z).
  Raw `/tmp/birc-compdiag-run.xkArzN1Q/recipe.log` SHA f05b3092...
  reports `ws_parked.recv` continuation widths 254/263/249. The triple
  is unchanged from the previous diagnostic: the three source corrections
  were not sufficient and did not reduce these measured widths. Root
  rechecked all 104 candidate inputs. Do not attribute specific branches
  from those names. Stock lowering may fuse a single-site tail callee;
  an added helper name alone is not a guaranteed compilation boundary.
  Two real-effect carrier candidates are source-reviewed, not yet fixed:
  preserve the original loop cell across preferences hhmmss and redial
  command emission. Main is preparing a finite patch for review.
  Separately, the assertion-only carrier diagnostic d2361c2a... also
  stacks (raw `/tmp/birc-carrier-case-preflight-run/runR.raw.txt`, SHA
  e4efadbe...; identical before/after manifests). Ui/channel setup is
  not needed to trigger this failure. Two one-assertion fragments are
  prepared and released for sequential stock checks in the owned snapshot;
  real guards, their two assertions, and all seven modes remain unchanged.
  Subsequent controls also stack: trivial `E.must(..., True{})` and
  open-loop assertion (`/tmp/birc-carrier-controls-run/runT{1,2}.raw.txt`),
  with identical before/after manifests. This does NOT support a closed
  seed-expression cause or assertion-helper extraction. Direct IO.pure
  and single IO.pure-bind controls are the final released stock pair;
  added-definition/do/E.must context remains unlocalized pending results.

- 2026-10-05T23:05Z App candidate: Root and Drive source-accepted corrected
  real-effect carrier patch4c94d654... (r1 had an illegal match inside do
  and was never imported). Main imported only r2 via native Edit. Current
  union WsNet SHA813b4358e345ed2c05a60f2cbb285606050f18ae2b39ab8d3ca882d510c1d3f2.
  One unchanged stock `make build/birc_bend.c` still fails `an arity over 247`
  (make2, no C; `/tmp/birc-app-emit-r2/emit.raw.txt`, SHA1fd540bb...). Root
  verified identical beforeE/afterE. Whole-candidate acceptance is not
  achieved; current failing widths/owners are UNKNOWN, not inferred from
  the pre-r2 observation. Keep this unqualified experiment frozen; no
  additional copied run has approval. Prefs Con/Nil native guards are
  still required; full redial paints and may emit Begin, and is not
  qualified by the existing seven carrier modes or command-only tests.
  Main will save a compact checkpoint after the two final stock controls
  and then HOLD all edits/experiments/jobs. Root source/index hashes
  remain unchanged (a68e0300... / a5f4cf92...); only Root TODO was edited.
  Full proof/check/native/PTY3/Nix/cache gates remain pending.
  Final stock controls completed in the frozen old4518 snapshot:
  P direct `IO.pure` body e888b8a0... STACKS; Q do/pure-bind body
  5b063257... completes checking with the normal 501-def unsafe/foreign
  listing (exit1, NOT a proof pass). Raw outputs are
  `/tmp/birc-carrier-pq-run/runU.raw.txt` and `runV.raw.txt`. Root verified
  exact prefix16 heads, snapshot4518, and both before/after manifests.
  This is syntax/check-context sensitivity, not a localized cause.
  The added P body needs no assertion/seed/Ui/channel work; unchanged
  prefix definitions still contain such work, so do not generalize the
  observation to the entire book. No assertion extraction is justified.
  Fresh Main saved compact CHECKPOINT 2026-10-05T23:08Z and is idle,
  with no owned direct child observed. All further edits/jobs/experiments
  are HELD. New follow-up names/widths measurement needs fresh authority;
  no tools, compiler/checker limits, pins, laws, or existing oracles moved.

- 2026-10-06T07:19Z resume: user `continue!` accepted up to three same
  bounded names-and-widths follow-ups, one per reviewed frozen candidate.
  First USED (1/3): current813b, manifest0568fcfb..., receipt
  `/tmp/birc-compdiag-run.bYk8s2sN/recipe.log` SHA c32d7d38....
  Emit1/no C, 120 s; widths still254/263/249. This falsifies width reduction
  for r2, not branch attribution. All104 candidate and1886 copied-tool
  inputs stayed unchanged. Two follow-ups remain; installed tools, limits,
  pins and laws unchanged. Muse recovered from one provider timeout;
  independent reviewers are preparing small saved-cell and additive guards.
  Final stock/proof/check/native/PTY3/Nix/cache gates remain pending.

- 2026-10-06T07:47Z: exact reviewed UI classifier/shared error leaf647721df
  imported in union (WsNet e94d2d70); two queued prefs guards imported
  (fixture3d610520, drivercb5d8433), still unqualified. Stock App emit
  `/tmp/birc-app-emit-e94d/emit2.raw.txt` SHA00fb5141 fails arity247,
  make2/no C, before/after unchanged. Second follow-up USED (2/3):
  receipt `/tmp/birc-compdiag-run.jFNxs25v/recipe.log` SHA1d89477d,
  manifest76c7fb0c; 92 s, emit1/no C, ALL254/263/249 remain. The UI
  width-reduction hypothesis failed. No segment-owner attribution follows
  from shifted numeric IDs. One same bounded follow-up remains. Tiny
  Base-only direct-pure control9f9e7b45 checks (exit0); full-prefix P
  stacks, so the imported/book context is required, not body alone.
  Tick/shutdown/paint alternatives are source-only and unimported;
  reviewers now inspect full Session retention in ws_history_save.

- 2026-10-06T08:03Z clean checkpoint: third follow-up USED (3/3),
  `/tmp/birc-compdiag-run.7YYAEfk4/recipe.log` SHAf88670ae @518241,
  manifest74a8a4f4. All254/263/249 remain, emit1/no C, 91 s; inputs
  unchanged. The history width hypothesis also failed. Main imported
  exact cleanup1b29ff5b (8+/55−), restoring4518 dispatcher and removing
  eight failed experiment helpers; the four small history snapshots
  remain for readability/DRY only. Current union WsNet9b0e4e2a....
  Stock `make build/birc_bend.c` still fails arity247, make2/no C
  (`/tmp/birc-app-emit-9b0e/emit4.raw.txt` SHA50e0ef42; before/after cmp0).
  Current9b0e widths are UNKNOWN: stock prints none. Last measured
  triple belongs to518241, not inferred for cleanup. Carrier9mode
  fixture3d610520/drivercb5d8433 remain unqualified. Held, unimported:
  UI-error guardscfdccdc, history guardsa436d9d7, tickcc3e, paint/shutdown
  alternatives. Main CHECKPOINT08:02Z is idle; all copied runs exhausted.
  Next proposed scope is one bounded, isolated copied-compiler emission-
  context diagnostic (names only, no captured values/body/environment).
  A recent per-branch Birc definition trail avoids fl.def becoming only
  IO.bind; it is context evidence, not proof of lexical capture cause.
  No new diagnostic preparation/run is approved. Root source/index
  hashes unchanged; final proof/check/native/PTY3/Nix/cache still pending.

- 2026-10-06T12:34Z: user `continue until done!` approved one bounded
  emission-context diagnostic; USED 1/1 after a provider-timeout resume.
  Isolated compiler63eb7100 / recipe2275f4a1 / wrapper1489e539;
  frozen104-input manifest9b7531ea at current union WsNet9b0e4e2a.
  Full receipt `/tmp/birc-compdiag-run.BhWd8K4B/recipe.log` SHAf190e32a:
  49 s, emit1/no C;254=`ws_net_painted.part`,263=`ws_cards.got_on`,
  249=`ws_upload.got`. All104/new1886 inputs stayed unchanged.
  Names describe emission context, not captured values or causal proof.
  These `$k` cuts also arise across pure calls, not only IO. Targeted
  parallel proposals now address early Session expansion in these three
  paths. Card cleanup must retain `Cl.set_now` stamping; discarding the
  temporary Session must not discard client.now. No second copied run,
  compiler-limit/pin/law/oracle change, or root source/index mutation.

- 2026-10-06T13:19Z recovery checkpoint: targeted net Part cells, stamped
  card Client, and upload admission ordering recovered stock App emission.
  Reviewed dead `ws_recv`/`ws_dispatch` deletion leaves union WsNet
  bd575c91. `make build-ui` passed, before/after inputs identical:
  `/tmp/birc-buildui-bd57/build.raw.txt` SHA a7496b02;
  generated C7ee0f751, native executable90a016c9. This is NOT a Nix build.
  `make test-cards-owner-gates` passed, including 11 new guards, with
  unchanged inputs (`/tmp/birc-cardsowner-bd57/check.raw.txt`).
  `check-ws-carrier` completed body checking with the normal foreign/unsafe
  verdict (make2), NOT a proof pass. Native carrier C emission still stacks
  (`/tmp/birc-carriernative-bd57/check.raw.txt`); cause is not established.
  `test-wsnet-gates` exposes an existing 11-field Preferences fixture after
  the theme field was added; no assertions ran. Two independent reviewers
  are checking minimal fixture repairs, preserving all existing oracles.
  Stock proof600, full check, native guards, PTY3, safe root integration,
  meaningful commits, and locked Nix build/cache remain pending. Main is
  sole union writer/heavy lane; root remains sole tmux controller and has
  changed only this TODO. No more copied diagnostics are authorized/needed.

- 2026-10-06T13:41Z: stock `make proof PROOF_TIMEOUT=600` timed out
  without a verdict (timeout124, make2). Full receipt
  `/tmp/birc-proof600-bd57/check.raw.txt` SHA b88b0a1f; before/after
  manifests identical; owned Bun PID29854 exited. CPU was active, but
  no phase or definition cost is established. Stock Bun has default-off
  CPU profiling flags; one unchanged-tool, unchanged-proof, same-budget
  sampled profile is proposed, exact recipe still requires root review.
  No copied compiler, independent kernel, raised limit, or weakened law.
  User approved promotion of the three Notify follow-up tests AFTER they
  pass, including correction of only their temporary standalone oracle.
  Registration audit found 14 required standalone gates outside `check`.
  The merged G3 fixture lost protected `JOIN #other`; reviewed one-line
  restoration preserves all assertions and makes `#birc` inactive for the
  existing unread-alert guards. Canonical root Nix source is 92 production
  files, excluding union's scratch `wsnet.bend.orig`; scratch Nix success
  would not establish default-root cache qualification. Gates stay open.

- 2026-10-06T14:39Z checkpoint: native Cards handoff fixture7465ed62
  passed all three original modes with an owned successful helper;
  `/tmp/birc-cardshandoff-7465/check.raw.txt` SHA e8c95af0, inputs unchanged.
  Same-binary failed/missing-helper handoff checks reject; wrong/quiet must
  remain successful without invoking a helper (full matrix still pending).
  Carrier fixture6c70 emits and compiles with stock tools; its routed case
  passes. Nil emits the exact error once and exits1, but the new driver
  includes TimUI's fixed startup OSC title in its diagnostic oracle. User
  approval for removing exactly one fixed title, and two G3 stored-MODE
  expectations, remains pending. No broader approval is inferred.
  WsNet gate v1/v2 fixture repairs remain unqualified; v2 stops at a flat
  product match before assertions. Reviewed v3 uses existing nested
  parameter-match form; all calls and assertions remain unchanged.
  Stock CPU-profile recipe275dae5e, input manifest8593a3d6 and ten-tool
  manifestb8b294cf were fully reviewed and independently verified. It is
  released for one bounded stock run (max600s); a usage refusal caused by
  an extra argument started no checker. No profiling result exists yet.
  Fresh source review found multi-server shutdown waits for pending
  Connecting/Reconnecting actors unlike the established Net policy. A
  minimal reuse of `Net.shutdown_waits` and +/- guards is proposed but
  not integrated or run. Main remains sole union writer/heavy lane.
  Final proof, full check, PTY3, canonical integration/commits, default
  Nix build and installed/hot-cache qualification remain open.

- 2026-10-06T15:15Z: the one frozen stock CPU profile ended124 with
  unchanged inputs and no profile (`/tmp/birc-proof-cpu-run.zltnvBeC/RECEIPT.txt`,
  SHA243ff10c). The separate owned synchronous-loop inspector smoke started
  profiling and reached busy, but failed its stop/completion gate; no samples
  and no timing attribution (`/tmp/birc-inspector-smoke-run.rGybik/RECEIPT.json`).
  Its receipt cannot distinguish timeout from RPC rejection. Child was reaped;
  four pins unchanged. A names/durations-only copied-checker timing proposal
  requires new user approval; no repeat or copied run is released.
  WsNet gates v3a45dad67 compiles and runs; 13 upload guards precede its
  failing direct-Dial assertion. Source trace finds initial `Connecting`
  reaches the normal connect-in-progress rejection before first boot. Keep
  the expected B/gen1 Dial and physical boot-order oracle; confirm actual
  synthetic command before a first-frame-only repair. Eight later net
  guards remain unrun (`/tmp/birc-gatesjs-a45d/check.raw.txt`, SHA3774d903).
  Cards six-case negative recipe stopped at first exact-output comparison:
  valid mouse-tracking CSI precedes its otherwise exact failure text.
  Remaining five cases are unrun; exact-prefix oracle correction needs
  explicit approval. Carrier title and two G3 MODE corrections also remain
  pending; Notify promotion is approved only after qualifying its tests.
  Fresh arbitration found protected sensitivity-target normalization lost
  in fixed/negotiated MODE privacy and channel normalization lost in shared
  JOIN/PART/KICK logs. Minimal five-expression restoration plus 42 additive
  guards is frozen for review, not integrated. All36 protected law bodies
  and their36 proofs match union; staged/source hashes remain unchanged.
  Multi-server shutdown fix is integrated into scratch and its pure guard
  is green; stock App rebuild and new/old PTY qualification are in progress.
  No canonical merge, commit, full proof/check pass, or Nix cache claim.

- 2026-10-06T15:36Z: Root read the shutdown guard red/green receipts and
  stock native build receipt, and verified each before/after manifest.
  `WsNet`195a1eca builds App2d44124c/Ca2ea32bb successfully. The new
  multi-server startup driver passes three consecutive same-binary runs
  (`/tmp/birc-ptyws-startup{1,2,3}/check.raw.txt`). Original startup and
  single-server recovery controls pass; recovery covers NickServ, SASL,
  and SASL with settings. Original startup rebuilt en route but retained
  that exact binary. These are selected passes, not full qualification.
  New multi-server recovery passes both no-settings auth cases but fails
  at settings-enabled quit in two runs; no third retry or deadline change.
  Source review finds two paths that can discard an active settings-write
  lease across reconnect; runtime attribution and a minimal fix remain open.
  The synthetic direct-Dial diagnostic did not compile; it was reverted
  byte-exact to gates a45dad67, with no executable trace claim. A repaired
  diagnostic and 18-guard first-frame-only fix are source proposals only.
  The copied-checker timing patch and bounded recipe are reviewed but
  unrun, pending explicit user approval and a renewed candidate manifest.
  User approved the temporary notification registration-oracle correction
  only after qualification. Protected G3 restoration TDD is underway in
  scratch. Root index/non-TODO source hashes remain unchanged.

- 2026-10-06T16:12Z: Root verified protected G3 restoration red/red/green
  receipts: 42 additive guards pass without changing legacy expectations.
  Commands73088ca1, Isupport4c1caaa8, Clientf1278a37 retain styled-target
  normalization in MODE privacy and JOIN/PART/KICK membership logs.
  The first-frame-only connect fix is integrated in scratch WsNetaf9a57a0;
  its 18 new guards pass, and existing WsNet gates pass twice. A structural
  NetState helper corrected only the new harness representation; all18
  assertions stayed unchanged. Native App2d44124c is still the earlier195a
  candidate and is not final source qualification.
  Added actual-View G3 guards pass in both fixtures, but traversal stops
  at its preserved styled-image assertion. Source review finds the harness
  omits the production visible-media admission stage. A synthetic bounded
  conjunct diagnostic is queued; no production enqueue rewrite is accepted.
  Preferences retirement R1 (manifest027641cf) is under pure TDD in Main:
  32 new guards, exact-ticket physical retirement, and unchanged failed-save
  accounting. Carried-owner identity and completion-notice admission still
  need their separate reviewed follow-up. Hold the App rebuild until then.
  Notification promotion is approved only after qualification; its stale
  source-name oracle correction is separately pending. MODE2, Carrier title,
  Cards CSI, copied-checker timing, three STATUSMSG expectations, a fourth
  STATUSMSG burst-order expectation, and case-only reconnect corrections
  remain explicitly pending. Unsigned-k privacy was already approved.
  Canonical92-path admission map is frozen at /tmp/birc-admission-map.BbNOmp;
  it is not a merge or package verdict. Preserve current Root TODO and all
  protected working/index changes. HEAD4b4cbef5, staged-diff SHAa5f4cf92,
  and non-TODO working-diff SHAa68e0300 were rechecked unchanged.
  Full stock proof/check, remaining same-binary PTY3, isolated canonical
  integration/commits, installed helper qualification, and the default
  locked Nix build/hot-cache verification remain open.

- 2026-10-06T16:43Z: Root verified the genuine preferences-owner R2
  red/green receipts (`/tmp/birc-r2-red2/check.raw.txt`, SHAfda6b8de;
  `/tmp/birc-r2-green/check.raw.txt`, SHAfec1109e). All162 guards pass,
  preserving the141 prior assertions. Final scratch WsNete0c224f3,
  preferences_runtime346ea8f4 and preferences_live483f4842 match the
  reviewed manifest. The stock `make build-ui` passes and creates native
  candidatec3b721eb; physical reconnect recovery is now being qualified.
  Source-only ownership TDD does not yet prove the physical quit repair.
  The visible-media harness diagnostic confirmed omitted admission;
  its reviewed stage repair preserves56 old calls and adds two controls.
  G3 traversal passes58 guards; actual-View guards preserve the visible
  text boundary. Selected Cards owner/physical/notification, wire View,
  notification archive/busy/follow-up, FFI retain and startup-boundary
  checks pass. These are not a final full-check or package verdict.
  Notify Attr still has a filled-definition compile blocker; its reviewed
  Data adapters preserve all56 assertions. A declaration-order repair
  is being prepared. Upload Escape readiness and ungated DNS AAAA
  restoration are source-reviewed and released, but not yet qualified.
  The user again approved the temporary notification-registration
  assertion only after tests pass; its separate source-name pin remains
  pending. No new authority is inferred for other pending expectations
  or copied-checker timing. Root staged/non-TODO working hashes remain
  a5f4cf92/a68e0300. Full proof/check, PTY3, canonical integration,
  local commits, installed helpers and default Nix hot-cache remain open.

- 2026-10-06T17:02Z: final scratch Appc3b721eb passes three consecutive
  multi-server reconnect runs (raw1107d9e6/4f8a4f52/1f0a8dc4) and three
  startup-connect runs (raw6c22e60e/0f2dbda7/55405c88); original recovery
  controls also pass. Run3's wrapper manifest differs only in the separately
  reviewed upload fixture, not production/recovery inputs or the binary.
  No runtime retry or deadline lift was needed. Root read all six raw verdicts.
  DNS direct AAAA restoration plus exact duplicate-only fixture cleanup now
  passes `make test-ipv6-transport` (rawe23ba6ca); IPv6, fallback, DNS/TCP,
  deadline/supersession and verified TLS positive/negative probes pass.
  Native fixtureb166581d retains every unique oracle and the ungated AAAA
  check; five duplicated definitions and their two repeated assertions alone
  were removed. No oracle expectation or runtime behavior changed.
  Notify Attr declaration-only repaird44e660b compiles, but its original
  `b selected id` assertion fails. Source trace verifies the fixture never
  self-JOINs B; production correctly refuses to create a channel from a stray
  peer message. The real framed B JOIN plus four +/- guards is frozen at
  /tmp/birc-notify-attr-membership.3UoVcd, not released; specific setup approval
  is required. All56 old oracles and worker/channel/deadline calls stay exact.
  Upload fixturebc448293 builds native89dc5520. Its physical stages, Escape
  cancellation, exact-once URL, helper ledgers, closure, exit0 and restoration
  pass, but the final LF-only marker rejects actual postrestore CRLF. A
  final-marker-only flag-aware oracle proposal is in preparation, not approved.
  No unchanged retry or general control stripping is authorized.
  Consolidated pending semantic-oracle and copied-timer questions were sent;
  no new answers yet. Conditional Notify promotion is approved only after
  qualification. Root protected hashes remain a5f4cf92/a68e0300. The reviewed
  installed-helper guard222493a5 is released as standalone only; package,
  full stock proof/check, canonical integration/commits and hot-cache remain
  unqualified. Isolated clone checklist0525c7da preserves both Root patch
  layers and current Root TODO. Muse RSS at16:58Z was423712 KiB, not10GiB.

- 2026-10-06T17:31Z: Root verified actual boot guards pass three consecutive
  same-binary runs (raw 83b4724b/596bfb74/85c49633, native f83896a5), including
  ordinary, keyed, probe and extra-accept cases. The monadic harness repair
  preserves all prior assertions and deadlines. The installed helper guard
  is applied in scratch as a standalone target, but remains unqualified.
  The isolated clone /tmp/birc-final-candidate preserves both Root patch
  layers and all 437 tracked bytes. Root and a fresh reviewer accepted the
  frozen source/Nix admission 844dc725 by exact path/body comparison and
  the reviewed R1/R2 changes; this is not a new full semantic review.
  Muse applied only that admission, verified 102 identities and staged its
  ten new source/Nix files in the clone's own index. The locked default
  `make build-package` is running, not yet a build or hot-cache verdict.
  Latest user approval again covers only the three notification tests'
  registration after passing. Their stale source pin and B JOIN setup,
  the upload final marker and other pending oracle corrections remain held.
  Canonical test/doc/law/Make composition, full stock proof/check, remaining
  PTY3, installed helper tests and local commits remain open. Root index
  bytes 0dd76fb4, staged a5f4cf92 and non-TODO working a68e0300 are unchanged.

- 2026-10-06T17:41Z: isolated default `make build-package` passes in 252 s
  (raw /tmp/birc-final-pkg/build.raw.txt, SHA 7bebb4fd). Derivation an2b0fdy
  realizes /nix/store/spil6w8s06b34356qnx26q9ysz3x42hh-birc-0.1.0.
  Locked default-app eval returns that exact bin/birc, exit 0 (raw 2fc76737).
  Read-only review verifies the filtered package has exactly the 92 intended
  source files; six absolute helper defaults, seven helper source comparisons
  including Cards' image sibling, and Keychain libexec match the clone.
  The four installed package targets pass (raw f807e137): package, Keychain,
  TLS and upload, including all 12 upload PTY cases once. Required same-output
  upload run 2 fails at clean-exit checking (raw ca6a10af); no run 3 or retry.
  Evidence shows QUIT, helper completion and terminal teardown, followed by
  the fixed preferences-save failure diagnostic. Failure versus timeout is
  not yet attributed. Driver inherits HOME/preferences; do not rerun that
  setup or inspect user settings. An owned private-settings characterization
  is under source review, keeping all upload/QUIT/restore/deadline oracles.
  Root read the full 848-line law/proof delta 48cbbb89. It is admitted only
  into the clone with exact posts 1fa45149/48477876; 425 old pairs remain,
  with 110 additive pairs and no since-review drift. This is not a proof pass.
  Additive two-file installed Notify/helpers guard e0295d6f is reviewed and
  released in the clone as standalone targets only. No aggregate promotion,
  Root source/index mutation, commit or push. Three-only conditional Notify
  registration patch 5c6b331c is prepared but held until all three pass.
  All pending semantic-oracle and copied-checker diagnostic questions remain
  unanswered. Full stock proof/check, final test/doc/Make composition, upload
  PTY3, helper qualification, commits and measured hot-cache remain open.
  Root staged/non-TODO working hashes remain a5f4cf92/a68e0300.

- 2026-10-06T18:08Z: the two additive installed-package guards pass
  (`make -j1 test-notify-package test-runtime-helpers-package`, raw
  /tmp/birc-final-pkg6/suites.raw.txt, SHA 84719578). All six selected
  installed suites have now passed on the default spil6w8s output; this
  is not a full-check verdict or the required repeated terminal coverage.
  The renewed stock proof times out, no verdict (raw e83ba640,
  /tmp/birc-proof-run/check.raw.txt): outer `timeout -k 10 590` terminates
  `make proof PROOF_TIMEOUT=600`. The refreshed 53-file closure differs
  from the previous run only in three reviewed protocol modules. Do not
  repeat an unchanged proof. Saved before/after receipt paths are requested;
  console rechecks alone must not be described as saved historical receipts.
  Cards test isolation completes genuine red -> green (new guard rejects
  missing forced-off policy; unchanged target then reports build_config=ok).
  The exact six reviewed posts are applied only in the isolated clone.
  The direct upload failure is not a same-configuration repeat: Make forced
  preferences off, but that invocation inherited the settings policy.
  Its lower-level failure remains unknown; never inspect real settings to
  attribute it. Root reviewed the complete private settings probe 59a24d6d
  and released coalesced success, full owned-scope refusal, then all-mode
  repeated qualification. All paths/accounts/peers are owned test data.
  Three baseline cycles of upload, history images, image marker and deferred
  redraw are also released, with the same installed app and Make test policy.
  New user approval permits only the three notification registrations after
  passing. Remaining listed fixture corrections and a copied timing run
  are still approval-gated. Root staged/non-TODO working/index identities
  remain a5f4cf92/a68e0300/0dd76fb4; no source merge, commit or push.

- 2026-10-06T18:20Z: the four Cards-isolated terminal drivers pass three
  consecutive Make-policy cycles on the same installed spil6w8s app. Root
  read all 12 raw logs under /tmp/birc-baseline: upload 12 cases, history
  images 4, image marker 6, deferred redraw 4 in each cycle. They retain
  exact URLs, unsupported-terminal no-helper/no-placeholder logging, history
  checkpoints, helper ownership, connection-consent invalidation, shutdown
  and terminal-restoration checks. These runs use owned HOME, preferences
  off, image cache off and Cards off, with unchanged runtime deadlines.
  The new private settings probe's first all-mode run fails at reconnect
  after ten cases (raw 203b621b). Its seed incorrectly set autoreconn=false;
  live startup sets true, and settings correctly override it when unedited.
  The owned saved file confirms false. The original case closes its peer
  then awaits automatic accept, so the probe setup conflicts with that case.
  This is not a production reconnect defect or an attribution of the earlier
  ambient quit failure. Main mistakenly repeated the failure twice before
  reading the stop-first rule; those extra runs are not qualification.
  Root reviewed/released the new-probe-only correction f73be831: true seed,
  suitability +/- guards, and helper-written true-state check. All inherited
  assertions and deadlines remain unchanged. Corrected qualification is
  underway; no final private-probe pass yet. Stock proof saved receipts now
  located: BEFORE/AFTER each cover four identical identities (6d441251),
  separate logs contain all 10 stock and 53 closure checksum successes.
  Do not call the four-row receipts full 53-input historical snapshots.
  Pending oracle corrections/timing approval still hold; no proof retry,
  full check, source integration, local commit or push has occurred.

- 2026-10-06T18:42Z: corrected private-settings qualification passes:
  coalesced 3/3, full owned-scope refusal 3/3, and all-mode upload 4/4 on
  the same installed spil6w8s app/helper. Root read the standalone Make
  target raw (4bc4ea1a) and final extra coalesced/full raws
  (90b352f6/716c8f5d) under /tmp/birc-privprobe-target. The full negative
  keeps helper code 2, app exit 1, the fixed log diagnostic, and terminal
  restoration; the probe succeeds because it expects this refusal.
  The complete current identity receipt edee4ea5 is saved at
  /tmp/birc-final-CURRENT-RECEIPT.txt. It is current provenance, not a
  retroactive full before/after snapshot. The 18 API-only fixture updates
  are admitted in the isolated clone: 376 old assertion expressions remain
  byte-identical, and 118 arity-adapted checks retain their expected results.
  Root read ten passing raw logs under /tmp/birc-api-qual (commands,
  server identity, IPv6 glue, runtime args, TLS args, auth privacy, typing,
  media history, message split, submit); remaining released checks continue
  fail-fast. Shutdown and history-search API/private fixture updates are
  reviewed and queued, preserving all old oracles and budgets. The actual
  three notification gates are still held, not these API checks. User
  approval permits their registration only after they pass. Two additional
  CAP handshake expectations need explicit approval to include the already
  implemented draft/chathistory request. The remaining fixture and copied
  checker timing questions are also unanswered. Stock proof still has no
  verdict; no unchanged retry, full check, Root source/index integration,
  commit or push. Root protected hashes remain a5f4cf92/a68e0300/0dd76fb4.

- 2026-10-06T19:18Z: the API batch passes 16 of 17 released targets. The
  actor queue's redial case stops at its old CAP expectation (raw 7a53372f);
  the observed request also includes account-notify, away-notify and
  draft/chathistory. The reviewed two-line oracle delta remains held for
  approval; later redial FIFO checks are not qualified. Shutdown passes
  open, half-closed and idle controls (raw 0f1e8b2f). History search first
  fails on bare seconds, then passes after only the previously approved
  five timestamp migrations and additive rejection guards (raw dab3408b).
  Both suites retain their runtime deadlines and old behavioral checks.
  The two reviewed README additions are admitted only in the clone.
  All four additive suites pass: mode privacy, search, auth profile and
  IRC commands (129 existing checks plus 21 new checks, zero deletions).
  Root read all four raw logs under /tmp/birc-add4.
  Startup profiling passes its selftest and isolated warmed comparison
  (raws dd550f1f/469ed770, /tmp/birc-perf). On the cached spil6w8s app,
  measured first-visible means are 7.93/7.42 ms direct (demo/live) and
  53.90/53.57 ms through cached Nix. Warmup is separate. Empty owned
  settings/history do not reproduce or explain the earlier long delay.
  View timing measures pure Bend View; native phases are separate totals.
  Core-five fixtures and 22 fresh-review guards are admitted (414 checks),
  as standalone targets only. The first native compile fails with
  `an arity over 247` (raw 8d509cb0); no assertions run. Workspace also
  stops before assertions at a missing Client annotation (line 146).
  Source-only agents are preparing minimal fixes without oracle, backend
  or compiler-limit changes. Independent JS targets are released next.
  Fresh review finds no blocking defect in the held copied checker timer,
  but this is not execution approval: nested inclusive spans add overhead,
  an end event is not success, and the 88-source/five-copy receipts are
  not a separate paired 53-input receipt. No diagnostic has run.
  User again approves only notification promotion after all three pass.
  The remaining corrections/timing run are still held; stock proof,
  complete check, Root integration and commits remain open. Root staged,
  non-TODO working and index hashes remain a5f4cf92/a68e0300/0dd76fb4.

- 2026-10-06T19:52Z: the annotation-only workspace/wsnet changes preserve
  every assertion. Wsnet gates pass 170 checks; workspace compiles but fails
  its new routed ASCII guard. Its `:irc` ISUPPORT source is neither a dotted
  server name nor its configured `a.example`; the source correction remains
  approval-gated. This failure does not establish a styled-typing defect.
  Three other core fixtures pass: first-connect 18, shutdown-pending 10,
  and session-drafts 115. The last requires the reviewed total `FxAD` carrier
  in six proof-facing predicates (patch 7d3a79fe, source 0543c95b). Whole-file
  wrapper erasure preserves predicate conditions and ordering; native red
  -> green confirms this test, not a measured compiler-width or speed claim.
  Four supporting suites also pass 93 assertion sites: draft nickname rename,
  outbound transactions, reader PONGs and live wait-cell. Their standalone
  recipes are admitted; aggregate registration remains open.
  The changed-source default package is rebuilt and cached at
  /nix/store/hc6x3y7pl22ykazf7mg2500dhh923d6l-birc-0.1.0. All six selected
  installed suites pass on its launchers (raw 1f421f7c). Its native executable
  is byte-identical to the earlier spil6w8s binary (609e9493), but launchers
  have new store paths. New-output repeated PTY qualification is not claimed.
  Current full entry-script/helper/driver identities are saved in
  /tmp/birc-RECEIPT-current-full.txt; 92 production hashes are saved in
  /tmp/birc-SRC-CURRENT.manifest. Root independently verifies all 92, all
  53 current proof inputs and all 10 stock tool hashes. These are current
  receipts, not retroactive snapshots of earlier runs. The four-row pkg2
  closure and three-hash CURRENT2 receipt remain narrow provenance only.
  The three notification gates are admitted as standalone targets; only
  followup-guards has passed (45 checks). Attr/static retain their known
  setup/pin holds. Fresh agents review four companion witnesses without
  changing old assertions. Both binding B setups need a real self-JOIN;
  this also advances the initial floor, so no floor oracle change is needed.
  A separate approval question covers those two setup corrections.
  One fresh stock proof on the changed carrier source is running under
  TERM590/KILL10 and PROOF_TIMEOUT=600, raw /tmp/birc-proof-run2/check.raw.txt.
  No verdict yet; do not repeat unchanged. The copied timer is still held.
  Root source/index integration, full check, commits and push have not run.

- 2026-10-06T19:55Z: the changed-carrier stock proof reaches the outer
  wall-clock bound again (exit 124, no verdict). Root reads the complete raw
  /tmp/birc-proof-run2/check.raw.txt. Native session-drafts green does not
  establish stock proof success. Do not retry unchanged or infer a cause
  from this silent checker run. Main captures the full closure AFTER receipt
  before the queued companion notification tests and new workspace source
  guard. The copied names/durations timer remains unapproved. Fresh source
  review identifies exact duplicate View theme selectors; a separate minimal
  behavior-preserving DRY proposal is being prepared, not a checker fix.

- 2026-10-06T20:05Z: all three further standalone notification suites pass:
  held (23 sites), order (14 sites: ten retained plus four controls), and
  runtime (65 retained sites, comment-only coverage correction). Root reads
  all raws under /tmp/birc-heldbind and /tmp/birc-order-rt. Earlier physical
  held-blocked (22), full companion witness (251) and workspace-005 source
  guard (7) also pass, with complete raws read. The narrower full-witness
  is not the original three-source full target or full standard check.
  Exact binding source is admitted but deliberately not run: its two B-JOIN
  setup fixes still need approval. All four static companion sources are
  present; the producer pin, Attr setup and three-gate promotion remain held.
  Theme DRY maintenance is implemented only in the clone: View's three public
  adapters now share Theme's selectors; two unused View helper tables are
  removed. Default Dark versus supplied Id and all status predicates stay
  unchanged. Root reads both complete patches and provenance. Fifteen new
  literal boundary guards pass before and after the change, and original
  test-theme passes all three native fixtures (raws 2adbd045/5b43951f/a9e20b86,
  /tmp/birc-theme). View is now e3c16606; Theme is 1d62a8b9 (code unchanged,
  comments corrected). No performance or checker-cause claim follows.
  A new locked package build and six-suite/current-startup qualification are
  released on this changed source. The previous hc6 output qualifies the
  pre-DRY source only. A fresh source-only composition review prepares one
  framed workspace theme-render witness; other missing-target inventory is
  retained for the next approval/composition pass, not a broad overlay.
  Stock proof has no pass; all laws/PROOF/pins remain unchanged. Root staged,
  non-TODO working and index identities remain a5f4cf92/a68e0300/0dd76fb4.

- 2026-10-06T20:13Z: the post-DRY default Nix app is rebuilt and cached at
  /nix/store/ncsafv8i50y4qi06l7a240nr4zc7bi00-birc-0.1.0 (drv y413z5n24,
  build raw d10d697a). Root reads that complete raw, all six installed-suite
  passes (raw 4bd41724) and the current startup selftest/measurement raws
  (f31e2e2a/0e8086b2) under /tmp/birc-perf2. Installed launcher/native/Keychain
  hashes are independently verified: cf0a8f3c/ea759edb/f0133cf9. The previous
  native binary is different, so new-output repeated terminal tests are now
  released rather than claimed from earlier cycles.
  Warmup is separate from the three measured samples per launcher/mode. Current
  first-visible means are 7.226/6.821 ms direct demo/live and 54.082/54.924 ms
  cached Nix demo/live; setup Nix evaluation (863.68 ms) is a separate phase.
  These empty owned settings/history runs neither reproduce nor explain the
  earlier tens-of-seconds delay. No cleanup speedup or delay fix is claimed.
  A manifest-only copied-timer readiness refresh is frozen at
  /tmp/birc-checker-current-preflight.v48RHage: same 88 input paths and fixed
  53 subset, only session_drafts/Theme/View changed since renewed input hashes.
  Root independently verifies all 88 and all 53 current hashes. Recipe, stock
  tools, copied tools, default-off logging bounds and 590+10 heavy wall cap
  stay unchanged. This is current source provenance, not a diagnostic execution
  or proof verdict; the user approval hold remains.
  Root reads the complete framed-theme witness and its follow-up: all 34 original
  checks stay exact; two duplicate span inspectors are removed, six complete
  color-token controls are added, and historical approval/pass prose is replaced
  with permanent pure-coverage comments. It is queued after repeated terminal
  qualification, with original 180/30-second recipe and no aggregate edge.

- 2026-10-06T20:22Z: the current ncsafv8i installed app passes all four terminal
  targets in three consecutive cycles. Root reads all twelve per-target raws
  under /tmp/birc-nc-c1, /tmp/birc-nc-c2 and /tmp/birc-nc-c3. Exact command:
  `make -j1 test-upload-package test-pty-history-images test-pty-image-marker
  test-pty-deferred-redraw PTY_APP=/nix/store/ncsafv8i50y4qi06l7a240nr4zc7bi00-birc-0.1.0/bin/birc`.
  Upload uses the matching build/package-birc link; the other targets use
  PTY_APP without a local rebuild. Runtime limits stay 120/75/60/45 seconds;
  the whole chain has a 1200-second outer limit, including locked Nix entry.
  Cycle 1's four raw files are splits of the successful combined raw cfe8fba9;
  cycles 2 and 3 each retain separate command and exit receipts. No source or
  driver changes occur during the cycles. This qualifies the four released
  drivers, not a new three-run private-preferences probe.
  Original BEFORE b135defe has app plus five driver/probe hashes. Original
  AFTER 3c4389d1 omits the private probe row but matches all five common rows.
  The later /tmp/birc-nc-cycles-AFTER-complete.txt adds that current probe hash;
  Root verifies all six hashes and exact digest-row equality with BEFORE.
  It is a post-cycle receipt, not a retroactive complete contemporaneous
  snapshot of native/helper/source identities. Full current provenance is
  /tmp/birc-FINAL-INSTALLED.txt (05c9e8ef): default app/out-link, launcher,
  Keychain/native/libexec, six helper wrappers and entry sources, all five
  drivers, Make/Nix/lock, laws/PROOF and changed production sources. Root
  reads it and independently verifies all 37 digest rows. Root also reads
  and verifies all 92 current production rows in /tmp/birc-pkg3-SRC.manifest
  (26233a77). No past narrow receipt is relabeled as a full paired snapshot.
  The framed theme-render witness is admitted as standalone only. Its
  original 34 checks pass (raw539f1c7c), then its reviewed DRY/comment cleanup
  and six additional exact-color controls pass (rawfd15e9ae). Root reads both
  complete raws under /tmp/birc-theme-ws. Fixture bc0eec28 preserves all old
  assertion bodies/order; Make is 127d1ea9. This tests framed source and pure
  workspace spans, not native background painting or the preference worker.
  Production sources remain unchanged since the cached post-DRY package.
  Muse is idle after recording project-scoped handover-2026-10-07.md; Root's
  durable continuation is this checklist and the raw/manifest paths above.
  Eleven fixture-correction groups and the single bounded copied-timer run
  still require separate approval. Three-notify promotion is approved only
  after all three gates pass; only followup-guards has passed so far. Twelve
  donor target definitions and aggregate composition remain open. The latest
  stock proof timed out with exit124/no verdict before DRY; no later proof
  was run. No full make check, Root source/index integration, commit or push.
  Root HEAD remains 4b4cbef5; staged/non-TODO working/index hashes are still
  a5f4cf92/a68e0300/0dd76fb4. Clone-only changes are not in Root's nix run .
