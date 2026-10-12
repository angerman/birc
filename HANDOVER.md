# birc pickup — 2026-10-08

## Start here

This is a local work checkpoint, not a release or a claim that all checks pass.
Read this file, `AGENTS.md`, and the relevant Makefile targets first. Do not load
the full conversation or the whole `TODO.md`. Use `TODO.md` only for a specific
historical receipt. It contains superseded results as well as current results.

Two trees must stay distinct:

- `master`: the user's current working tree, now prebuilt. It includes the
  pending IRC wire-style changes and their laws and regression fixtures.
- `checkpoint/birc-final-candidate-2026-10-08`: a separate, unmerged snapshot of
  `/tmp/birc-final-candidate`, plus recovery material. This is not a verified
  replacement for `master`. Its source changes need review and qualification.
  Immutable recovery commit: `8c03cab1a5a0a984e56362c41f7157f281302763`.

The checkpoint preserves both original Root diff layers as
`handover-recovery/root-staged.patch` and `root-unstaged.patch`. The actual
candidate index and files are not changed by the snapshot. Recovery files are
only on the checkpoint branch, not in the installed application.

## Prebuild and validation of master

- `make -j1 build-package`: **PASS**, 93.95 s including Nix provisioning.
  Both the Nix client and package build have wall-clock bounds. Pins are unchanged.
- Installed output: `/nix/store/vznfyvnf6xkr74zhjmc9f4pi7hn306bd-birc-0.1.0`.
  `build/package-birc` points to this output. The unrelated `result` link was
  not changed.
- `make -j1 proof PROOF_TIMEOUT=600`: **PASS**, `ALL PROOFS CHECK`,
  133.14 s including Nix provisioning. This tree has 425 laws; the candidate
  has 535. No independent kernel was invoked.
- Focused checks: **PASS**, 44.92 s total, in one locked `nix develop` shell:
  `make -j1 BIRC_NIX_SHELL=1 test-wire-style test-g3-framed test-g3-traversal
  test-package test-keychain-package test-tls-package`. All six named golden
  or package markers passed. The outer run was bounded at 480 s.
- The complete `make check` was not run for this checkpoint. A proof pass and
  package build do not qualify all runtime, PTY and sanitizer paths.
- `git diff --check HEAD`: **PASS**. Astra also reviewed the handover's
  proof/native claims and found no material errors.

Run the prebuilt package without another flake evaluation:

```sh
./build/package-birc/bin/birc --demo
./build/package-birc/bin/birc --connect irc.libera.chat:6697 --nick angerman
```

TLS is the default. Only `--plain` selects plaintext. A port does not select
transport mode. This checkpoint does not test a real IRC account or Keychain.

## Implemented baseline

The main tree has verified TLS, `host:port` parsing, SASL/NickServ support and a
macOS Keychain launcher; persisted non-secret settings; reconnect/rejoin logic;
word-boundary wrapping, nested formatting and emoji aliases; a lazy `*log*`
buffer; automatic image previews, animation where supported, and private image
caching shared by visible live/history messages; and per-file confirmed uploads.
See `README.md` for invocation and security details. Implementation is not the
same as complete regression qualification.

The candidate adds further workspace/multi-server, history, notification,
Cards, routing and runtime work. Its previously built package is older than
its latest Session/proof changes. Do not call that candidate “prebuilt”.

## Current candidate evidence

These results apply to the frozen candidate, not automatically to master:

| Check | Result | Scope |
|---|---|---|
| Complete isolation proposition, stock checker | PASS, 12.832 s | Current Session/AD dependencies; actual integrated lemma route |
| Complete generation law alone, stock checker | PASS, 1.627 s | Does not qualify the epoch law or full book |
| Complete epoch law alone | Timeout, 60.504 s | No verdict; no measured subphase cause |
| `make -j1 check PROOF_TIMEOUT=600` | Proof timeout, 601.480 s total | No subsequent tests, lint or paste checks ran |
| Shared multiline Session regression | PASS, 488 assertions, 5.264 s | 473 original assertions preserved; 15 new controls |
| Media import/visible-stage witnesses | PASS | Live/history admission and native/headless stages |
| Native Carrier witness | PASS, three consecutive PTY runs | Exact candidate witness and binary, not all runtime tests |
| Isolation runtime fixture | Compile timeout, 180 s | Its ten assertions did not run |

The earlier `aa\nbb` → `aabb` multiline defect is fixed in the candidate.
The older RED receipt is superseded; native/proof qualification is still open.

Large-`Nat` normalization is a hypothesis, not the established full-book cause.
Astra independently reviewed the evidence and the integrated symbolic
prefix-cancellation/equality-transport strategy. Do not weaken propositions,
change arbitrary-`Nat` semantics or the `2^44` ranges, remove overflow/rollback
checks, add axioms, alter pins/compiler limits, or introduce a new proof kernel.

Native fixture timeouts are a separate investigation. The retained old upload
C compiled to an object in 127.988 s. This does not qualify the original full
fixture or explain its earlier compiler timeout. A metadata-only linker check
planned one linker job; no real link ran. Its environment-equivalence claim
was withdrawn: the added gate masked seeds and missed suffixed wrapper flags.
Keep that gate as evidence of a failed approach, not a reusable qualification.

## Remaining work, in order

1. Develop the complete proof-facing epoch factorization proposed by Astra.
   Keep both scenarios and all 12 conjuncts. Derive the actual first Online
   `/connect` result and strict-cap admission. Preserve its Workspace, drafts,
   sequence and retired mark through remove/re-add. The final `/connect`
   starts **Connecting**: it returns a busy diagnostic plus `Cont`, not another
   `Dial`. Preserve both overflow branches and prove the actual final goal.
2. Qualify runtime isolation, workspace and reconnect-endpoint fixtures.
   Their compile timeouts are not test passes or named defects. Do not repeat
   unchanged heavyweight checks without a new diagnostic or changed candidate.
3. Finish the separate native stale-socket and upload-frame gates. Before
   releasing real linking, review and commit a strict, default-off environment
   capture at the Make recipe boundary, after TLS exports. Record set/unset
   values exactly, use actual pinned-wrapper variable names, and make a fresh
   metadata baseline. Do not repair historical raw evidence.
4. Compose and qualify history/ISUPPORT fixtures: STATUSMSG controls,
   unsigned-key redaction, mixed live/imported rows, ceiling/drain and combined
   history tests. Apply only the exact approved expectation corrections.
5. Finish Cards handoff/common-build guards, its six-mode negative matrix,
   and the three standalone Cards gates. Bind the negative runner to a recorded
   current-source binary, not the old donor binary or a self-computed identity.
6. Qualify exact-one-PONG socket ownership with self-tests and three PTY runs.
   Session must not emit a second PONG. Finish the net-trace PTY gate separately.
7. Finish notification binding repairs, real self-JOIN controls and the last
   two notification fixtures. Three earlier notification gates are already
   promoted; other standalone registrations remain conditional on passing.
8. Review and integrate source changes into master without wholesale scratch
   Makefile replacement. Then run the complete stock proof and `make -j1 check`,
   remaining standalone gates, installed-package suites, and a fresh default
   Nix prebuild. Measure warmed startup separately. Do not transfer old results
   across changed dependencies.

Serialize heavyweight jobs. Use the Makefile and wall-clock bounds. A changed
PTY test needs three consecutive passes. Add positive/negative regression
controls. Instrument before performance changes. No public image fetches,
0x0.st uploads, real credentials, Keychain writes, or upstream pushes in tests.

## Durable recovery and worker state

Create an owned temporary directory, then use a separate Git worktree to inspect
the checkpoint branch. Do not switch master over the user's current files.

```sh
git log -1 checkpoint/birc-final-candidate-2026-10-08
git diff master checkpoint/birc-final-candidate-2026-10-08 -- src nix flake.nix Makefile LAWS.bend PROOF.bend tests
git ls-tree -r --name-only checkpoint/birc-final-candidate-2026-10-08 handover-recovery
```

The recovery subtree stores the original checkpoint, reviewed donor packets,
proof/native diagnostic source packets, and selected raw receipts under their
original `/tmp` basenames. It does not store generated C/IR, objects, binaries,
download caches, or credentials. Some old packet ledgers say “unrun”; the later
raw receipts and this file state what actually ran. Rebased paths and guards
need fresh review before any packet is executed.

Exact Root prebuild, proof and focused-check logs are archived in
`handover-recovery/root-checks/` on the checkpoint branch. The original staging
split is preserved byte-for-byte; both layers are combined in the master pickup
commit. No unrelated source was replaced and no lock file changed.

At handover, all review agents are finished and the Muse pane is gone. Do not
restore its old conversation; start a fresh session with this file. Assign one
integration coordinator. Workers may review or edit disjoint source areas
concurrently, but only the coordinator releases heavy checks. No work is pushed
upstream.

## Branch and worktree cleanup — 2026-10-12

Only `master` and `checkpoint/birc-final-candidate-2026-10-08` remain as
branches; there are no linked worktrees. The 183 other branches, 22 detached
worktree HEADs and 17 uncommitted worktree states were recorded first under
`refs/archive/2026-10-12/{heads,detached,wip}/`. `git branch` does not show
them. A `wip/` ref is a commit on top of the old HEAD; `detached-w-final7295`
keeps its staged layer as a separate parent commit.

```sh
git for-each-ref refs/archive                                  # list
git branch NAME refs/archive/2026-10-12/heads/NAME             # restore one
git for-each-ref --format='delete %(refname)' refs/archive | git update-ref --stdin   # drop all
```
