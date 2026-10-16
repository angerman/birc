# SPDX-License-Identifier: Apache-2.0
# mk/pty-shard.mk: PTY suite sharding/caching harness (include fragment).
#
# Shards `test-pty` (PTY_SUITE_TARGETS) across N sequential shards; each shard runs
# its targets via `$(MAKE)` so every recipe keeps its own `timeout` bound
# (25-150 s) and owned loopback peers. Success stamps under $(PTY_SHARD_DIR)
# skip shards whose inputs (binary, selector, tests/pty/*.py) are unchanged.
#
# Wiring (one line in the root Makefile, e.g. after the test-pty block):
#   include mk/pty-shard.mk
#
# Usage:
#   make test-pty-sharded PTY_SHARDS=4   # all shards, sequential, cached
#   PTY_SHARD=1/4 make test-pty-shard    # one shard (fail-closed if unset)
#   make test-pty-shards-list            # dry-run listing of every shard
#   make test-pty-sharded-clean          # drop stamps to force re-run

ifndef BLDDIR
$(error mk/pty-shard.mk requires BLDDIR from the root Makefile)
endif

PTY_SHARDS ?= 4
PTY_SHARD_SCRIPT ?= scripts/shard-pty.sh
PTY_SHARD_DIR ?= $(BLDDIR)/pty-shards
PTY_SHARD_CACHE ?= 1

.PHONY: test-pty-shard test-pty-sharded test-pty-shards-list test-pty-sharded-clean

test-pty-shard: build-ui ## Pty: run one shard selected by PTY_SHARD=I/N (fail-closed).
	set -eu; \
	s='$(PTY_SHARD_SCRIPT)'; \
	test -r "$$s" || { printf '%s\n' "pty-shard: missing $$s" >&2; exit 2; }; \
	case "$${PTY_SHARD:-}" in '') printf '%s\n' 'pty-shard: PTY_SHARD is unset (want I/N, 0-based)' >&2; exit 2;; esac; \
	test -d tests/pty || { printf '%s\n' 'pty-shard: missing tests/pty' >&2; exit 2; }; \
	d='$(PTY_SHARD_DIR)'; mkdir -p "$$d"; \
	stamp="$$d/$$(sh "$$s" --stamp).ok"; \
	if [ '$(PTY_SHARD_CACHE)' = 1 ] && [ -f "$$stamp" ] \
	    && [ "$$stamp" -nt '$(BLDDIR)/birc' ] && [ "$$stamp" -nt "$$s" ] \
	    && ! find tests/pty -name '*.py' -newer "$$stamp" -print | grep -q .; then \
	  printf '%s\n' "pty-shard: cached $$stamp"; exit 0; \
	fi; \
	rm -f "$$stamp"; \
	targets="$$(sh "$$s" --print)"; \
	if [ -z "$$targets" ]; then printf '%s\n' 'pty-shard: empty shard, nothing to run'; touch "$$stamp"; exit 0; fi; \
	$(MAKE) $$targets; \
	touch "$$stamp"

test-pty-sharded: build-ui ## Pty: run all PTY_SHARDS shards sequentially with stamp caching.
	set -eu; \
	s='$(PTY_SHARD_SCRIPT)'; \
	test -r "$$s" || { printf '%s\n' "pty-shard: missing $$s" >&2; exit 2; }; \
	n='$(PTY_SHARDS)'; \
	case "$$n" in ''|*[!0-9]*) printf '%s\n' "pty-shard: PTY_SHARDS is not a number: $$n" >&2; exit 2;; esac; \
	test "$$n" -ge 1 || { printf '%s\n' 'pty-shard: PTY_SHARDS must be >= 1' >&2; exit 2; }; \
	i=0; while [ "$$i" -lt "$$n" ]; do \
	  env -u PTY_SHARDS -u PTY_TOTAL -u PTY_N PTY_SHARD="$$i/$$n" $(MAKE) test-pty-shard; \
	  i=$$((i + 1)); \
	done

test-pty-shards-list: ## Pty: dry-run listing of every shard's targets.
	set -eu; \
	s='$(PTY_SHARD_SCRIPT)'; \
	test -r "$$s" || { printf '%s\n' "pty-shard: missing $$s" >&2; exit 2; }; \
	n='$(PTY_SHARDS)'; \
	case "$$n" in ''|*[!0-9]*) printf '%s\n' "pty-shard: PTY_SHARDS is not a number: $$n" >&2; exit 2;; esac; \
	test "$$n" -ge 1 || { printf '%s\n' 'pty-shard: PTY_SHARDS must be >= 1' >&2; exit 2; }; \
	i=0; while [ "$$i" -lt "$$n" ]; do \
	  printf '%s\n' "--- shard $$i/$$n ---"; \
	  env -u PTY_SHARDS -u PTY_TOTAL -u PTY_N PTY_SHARD="$$i/$$n" sh "$$s" --print; \
	  i=$$((i + 1)); \
	done

test-pty-sharded-clean: ## Pty: drop shard success stamps to force re-run.
	rm -f '$(PTY_SHARD_DIR)'/shard-*-of-*.ok
