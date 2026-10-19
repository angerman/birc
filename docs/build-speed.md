# Build speed quick wins

Nix provisions dependencies; the root Makefile is the sole driver.
These wins keep BUILD-mode iteration fast.

## Quick wins

1. **Enter `make shell` once, stay there.** Outside the locked shell,
   `NIXRUN` (Makefile:25-28) prefixes every command with a fresh
   `nix develop` startup. Inside, `BIRC_NIX_SHELL=1` and commands run
   directly. Run `scripts/check-shell.sh` to verify; add it as a guard
   to slow targets so a missing shell fails fast with the exact next
   command instead of burning minutes.
2. **Serialize heavy builds when the host is busy.** Use `make -j1`
   for proof/codegen/compile batches on loaded machines; parallel
   flags only help when cores are actually free.
3. **Keep the Bun cache warm.** Do not clear Bun caches between runs;
   proof and Bend builds reuse them across invocations in the same
   shell.
4. **Gate the proof via shards.** `make proof` runs
   `scripts/run-proof-shards.sh` (one law per book under `build/proof`).
   Do not check `PROOF.bend` as one file — that closure does not finish
   under Bun GC. Do not commit generated shards. Design notes live in
   the `PROOF.bend` header.
5. **Cheap LAWS IO import-closure gate.** Before paying for `make proof`,
   run `make lint-laws-io` (or `sh scripts/check-laws-io.sh`). It walks
   the `LAWS.bend` / `PROOF.bend` import closures and fails if any
   IO/effect module from the AGENTS.md row appears
   (`actor`/`net`/`wsnet`/`timui`/`clock`/`tls`/`transport`/`dns.bend`/
   `*_io`/`*_live`/`*_worker`/`*_runtime`). Self-check:
   `sh scripts/check-laws-io.sh --self-test` (synthetic `notify_io`
   import must fail). Wired into `lint-ffi` and therefore `make check`.

## Batch discipline

- **One relevant gate per batch.** Pick the smallest command that
  proves the user action you changed; run the broad gate once on the
  integrated batch.
- **Carry evidence forward.** Do not rerun green checks for unchanged
  inputs. Repeat only changed inputs, failures, or unresolved risk.
- **Bound everything.** Wrap heavyweight commands in timeouts and
  keep owned child processes bounded so a stuck step fails instead of
  hanging the session.

## Provision reminder

```sh
make shell       # enter the locked shell (no pin updates)
make -n check    # dry-run the integrated batch gate before paying for it
```

Routine Nix work uses `--no-update-lock-file`. Only
`make update CONFIRM=yes` may move pins. Never `sudo make`.
