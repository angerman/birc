# SPDX-License-Identifier: Apache-2.0
# birc — IRC client (Bend 2 protocol + timui.h UI).
SHELL := /bin/sh
.DEFAULT_GOAL := help
.DELETE_ON_ERROR:

NIX ?= nix
CONFIRM ?= no
NIX_FEATURES := --extra-experimental-features 'nix-command flakes'
HOST ?=
NICK ?= birc
CHAN ?= \#birc
PORT ?= 6667

ifeq ($(BIRC_NIX_SHELL),1)
NIXRUN :=
else
NIXRUN := $(NIX) $(NIX_FEATURES) develop --no-update-lock-file . --command
endif

BLDDIR := build
APP := src/bend/app.bend
PROTO := tests/bend/proto_demo.bend

test%: export BIRC_HISTORY ?= none
check: export BIRC_HISTORY ?= none
test%: export BIRC_IMAGES ?= off
check: export BIRC_IMAGES ?= off
.PHONY: help bootstrap shell update doctor build build-proto build-ui \
        test test-proto test-ui test-feed test-feed-bench test-submit test-search test-preview test-split test-typing test-frame test-net test-dns \
        test-args test-cli test-live test-pty test-pty-flood test-pty-rows \
        test-pty-restore test-pty-composer test-pty-eof test-pty-connect \
        test-pty-demo-nick test-pty-linger test-pty-utf8 test-pty-minus \
        test-pty-tall test-pty-redial test-pty-rst test-pty-tinyquit test-pty-tabcut test-pty-paste50 \
        test-pty-bpaste test-pty-mixburst \
        test-pty-quitcap test-pty-tickrate test-pty-paintwake test-pty-joinlat \
        test-pty-manyeof test-pty-geneof test-pty-closequit test-pty-stall test-pty-escup \
        test-pty-tabswitch test-pty-alerts test-pty-linkclick test-pty-softwrap test-pty-mouseselect test-pty-preview test-pty-resize test-pty-settings test-pty-history test-pty-autoreconnect test-pty-disconnect-cleanup test-pty-split test-pty-typing \
        test-pty-hostile lint-ffi test-utf8-fit test-paste-harness proto-parity proof check \
        test-asan test-ubsan test-sanitizers test-perf-gates check-hardening \
        run run-demo clean \
        test-perf-cpu test-perf-tickrate test-perf-search test-perf-hardening test-perf-output \
        test-dns-live test-dns-timeout

help: ## Show the public targets (default).
	@awk 'BEGIN { FS = ":.*## " ; print "birc — IRC client (Bend 2 + timui.h)\n" } /^[a-zA-Z0-9_-]+:.*## / { printf "  %-18s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

bootstrap: ## Create flake.lock and seed the tool shell.
	@command -v $(NIX) >/dev/null 2>&1 || { printf '%s\n' 'Nix must already be installed; do not use sudo make.' >&2; exit 2; }
	$(NIX) $(NIX_FEATURES) flake lock
	$(NIX) $(NIX_FEATURES) develop --no-update-lock-file . --command bend version
	@printf '%s\n' 'Bootstrap ok. Review/commit flake.lock when ready.'

shell: ## Enter the locked project shell (no pin updates).
	$(NIX) $(NIX_FEATURES) develop --no-update-lock-file .

update: ## Deliberately update Nix inputs: make update CONFIRM=yes
	@test "$(CONFIRM)" = yes || { printf '%s\n' 'Refusing implicit update. Use CONFIRM=yes after reviewing scope.' >&2; exit 2; }
	$(NIX) $(NIX_FEATURES) flake update
	@printf '%s\n' 'Review changed pins; requalify affected checks.'

doctor: ## Report pinned Bend / clang identities.
	@$(NIXRUN) sh -c 'printf "bend-rev=%s\n" "$${BIRC_BEND_REV:-unknown}"; bend version; printf "CC=%s\n" "$$CC"; "$$CC" --version | head -1'

# Bend's emitted C is huge and trips -Wall/-Wextra noisily; silence only that TU.
BEND_CORE_CFLAGS ?= -std=c11 -O2 -pthread -w

build-proto: ## Build the Bend protocol self-test binary.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend $(PROTO) -o $(BLDDIR)/birc-proto

# Bend emits one C TU (runtime + app). --help is Bend's runtime CLI;
# birc usage is --help-irc (args.bend).
BEND_UI_SRCS := $(wildcard src/bend/*.bend src/ffi/*.c src/ffi/*.h) src/ui/timui.h
BUILD_INPUTS := Makefile flake.nix flake.lock nix/birc.nix

.PHONY: FORCE test-golden-runner test-build-config test-pty-deadlines test-dns-tcp test-socket-deadline test-state test-history test-links test-auth test-commands test-server-time test-pty-output-stall
.PHONY: test-media-image test-media-policy test-media-view test-media-anchor test-media-native test-media-portable test-media-native-ubsan test-pty-media test-pty-diagnostic test-formatting test-formatting-painter test-diagnostic test-diagnostic-buffer test-diagnostic-submit test-diagnostic-session test-diagnostic-restore test-diagnostic-io test-history-save-errors test-reader-errors test-clipboard-errors

test-media-image: ## Check synthetic image formats, animation, fetch bounds, and public-host policy.
	$(NIXRUN) timeout 30 python3 tests/media_image.py

test-server-time: ## IRCv3 time tags reach parsed message timestamps.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/server_time_demo.bend -o $(BLDDIR)/server_time_demo
	$(NIXRUN) sh scripts/check-golden.sh server_time_demo=ok ./$(BLDDIR)/server_time_demo

test-diagnostic: test-diagnostic-buffer test-diagnostic-submit test-diagnostic-session test-diagnostic-restore test-diagnostic-io test-diagnostic-wire ## Log bounds, privacy, wire isolation, commands, retention, and IO controls.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/diagnostic_demo.bend -o $(BLDDIR)/diagnostic_demo
	$(NIXRUN) sh scripts/check-golden.sh diagnostic_demo=ok ./$(BLDDIR)/diagnostic_demo

.PHONY: test-diagnostic-wire
test-diagnostic-buffer test-diagnostic-submit test-diagnostic-session test-diagnostic-restore test-diagnostic-io test-diagnostic-wire:
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/$(subst -,_,$(patsubst test-%,%,$@)).bend -o $(BLDDIR)/$(subst -,_,$(patsubst test-%,%,$@))
	$(NIXRUN) sh scripts/check-golden.sh $(subst -,_,$(patsubst test-%,%,$@))=ok timeout 15 ./$(BLDDIR)/$(subst -,_,$(patsubst test-%,%,$@))

test-history-save-errors: ## Surface failed history saves; preserve successful, empty, and disabled writes.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/history_save_errors.bend -o $(BLDDIR)/history_save_errors
	$(NIXRUN) timeout 30 python3 tests/history_save_errors.py ./$(BLDDIR)/history_save_errors

test-reader-errors: ## Socket-read failure, orderly EOF, and no-data branch controls.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/reader_errors.bend -o $(BLDDIR)/reader_errors
	$(NIXRUN) sh scripts/check-golden.sh reader_errors=ok timeout 15 ./$(BLDDIR)/reader_errors

test-clipboard-errors: ## Clipboard helper success, failure, timeout, and privacy controls.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/clipboard_errors.bend -o $(BLDDIR)/clipboard_errors
	$(NIXRUN) timeout 30 python3 tests/clipboard_errors.py ./$(BLDDIR)/clipboard_errors

test-media-policy: ## Bounded image requests, opt-out, stale results, and exact URL eligibility.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/media_policy.bend -o $(BLDDIR)/media_policy
	$(NIXRUN) sh scripts/check-golden.sh media_policy=ok ./$(BLDDIR)/media_policy

test-media-view: ## Image rows share wrapping, scrolling, split panes, and resize coordinates.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/media_view.bend -o $(BLDDIR)/media_view
	$(NIXRUN) sh scripts/check-golden.sh media_view=ok ./$(BLDDIR)/media_view

test-media-anchor: ## Manual error/completion anchors and distinct split-pane image clipping.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/media_anchor.bend -o $(BLDDIR)/media_anchor
	$(NIXRUN) sh scripts/check-golden.sh media_anchor=ok timeout 15 ./$(BLDDIR)/media_anchor

.PHONY: test-media-branches test-viewport-tail test-input-wake test-pty-esc-resize-wake
test-media-branches: ## Exact fallback rows and multi-link image partitioning.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/media_branches.bend -o $(BLDDIR)/media_branches
	$(NIXRUN) sh scripts/check-golden.sh media_branches=ok timeout 15 ./$(BLDDIR)/media_branches

test-viewport-tail: ## Compare live-bottom and paused viewports against complete legacy rows.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/viewport_tail.bend -o $(BLDDIR)/viewport_tail
	$(NIXRUN) sh scripts/check-golden.sh viewport_tail=ok timeout 15 ./$(BLDDIR)/viewport_tail

test-media-native: ## Image payload ownership, terminal animation, clipping, and pending-frame guards.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'set -eu; for guard in media_cache media_animation media_ffi; do timeout 60 $$CC -std=c11 -O0 -Wall -Wextra -Werror -pthread -Isrc/ui -Isrc/ffi tests/$$guard.c -o $(BLDDIR)/$$guard; sh scripts/check-golden.sh $$guard=ok timeout 15 ./$(BLDDIR)/$$guard; done'

test-media-portable: ## TimUI animation API remains C99, including TIMUI_NO_IMAGES fallback.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'set -eu; for mode in images no_images; do flag=; if [ "$$mode" = no_images ]; then flag=-DTIMUI_NO_IMAGES; fi; timeout 60 $$CC -std=c99 -O0 -Werror=vla -Wall -Wextra -Werror $$flag -isystem src/ui tests/media_animation.c -o $(BLDDIR)/media_animation_$$mode; sh scripts/check-golden.sh media_animation=ok timeout 15 ./$(BLDDIR)/media_animation_$$mode; done'

test-media-native-ubsan: ## UBSan: decoded media ownership and actual FFI replacement/cleanup.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'set -eu; for guard in media_cache media_animation media_ffi; do timeout 60 $$CC -std=c11 -O0 -g -fno-omit-frame-pointer -Wall -Wextra -Werror -pthread -fsanitize=undefined -fno-sanitize-recover=undefined -Isrc/ui -Isrc/ffi tests/$$guard.c -o $(BLDDIR)/$${guard}_ubsan; UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 sh scripts/check-golden.sh $$guard=ok timeout 15 ./$(BLDDIR)/$${guard}_ubsan; done'

test-pty-media: build-ui ## Pty: automatic/explicit images, animation, opt-out, stale results, and stalled output.
	$(NIXRUN) timeout 75 python3 tests/pty/media.py ./$(BLDDIR)/birc

test-pty-diagnostic: build-ui ## Pty: private log copies, helper errors, endpoint retention, and nonrecursive save failures.
	$(NIXRUN) timeout 75 python3 tests/pty/diagnostic.py ./$(BLDDIR)/birc

test-pty-esc-resize-wake: build-ui ## Pty: lone Esc after resize, with bounded trace and raw-screen evidence.
	$(NIXRUN) timeout 120 python3 tests/pty/esc_resize_wake.py ./$(BLDDIR)/birc

test-formatting: ## Rich style composition, emoji aliases, exact URLs, and raw-source guards.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/formatting_demo.bend -o $(BLDDIR)/formatting_demo
	$(NIXRUN) sh scripts/check-golden.sh formatting_demo=ok ./$(BLDDIR)/formatting_demo

test-formatting-painter: build-ui ## Actual terminal attributes, aliases, and opaque hyperlink targets.
	$(NIXRUN) timeout 15 python3 tests/formatting_painter.py ./$(BLDDIR)/birc fixtures/formatting.irc
FORCE:

$(BLDDIR)/build-config: FORCE scripts/build-config.sh
	$(NIXRUN) sh scripts/build-config.sh $@ '$(BEND_CORE_CFLAGS)' '$(SANITIZER_CFLAGS)'

$(BLDDIR)/birc_bend.c: $(APP) $(BEND_UI_SRCS) $(BUILD_INPUTS) $(BLDDIR)/build-config
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 300 bend $(APP) -o $(BLDDIR)/birc_bend.c

$(BLDDIR)/birc: $(BLDDIR)/birc_bend.c $(BLDDIR)/build-config
	$(NIXRUN) timeout 300 sh -c '$$CC $(BEND_CORE_CFLAGS) -Isrc/ui -Isrc/ffi $(BLDDIR)/birc_bend.c -o $(BLDDIR)/birc'

build-ui: $(BLDDIR)/birc ## Build Bend TimUI client (src/bend/app.bend).

build: build-proto build-ui ## Build protocol harness and TimUI client.

.PHONY: build-package test-package
build-package: ## Build the installed Nix package and helper without changing pins (15-minute bound).
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 900 $(NIX) $(NIX_FEATURES) build --no-update-lock-file .\#birc --out-link $(BLDDIR)/package-birc

test-package: build-package ## Check installed helper overrides, local images, trust, and clean-environment startup.
	$(NIXRUN) timeout 75 python3 tests/package.py ./$(BLDDIR)/package-birc

test-proto: build-proto ## Run Bend protocol golden harness.
	$(NIXRUN) sh scripts/check-golden.sh proto_demo=ok ./$(BLDDIR)/birc-proto

test-golden-runner: ## Reject failing, missing-token, and timed-out golden programs.
	$(NIXRUN) sh tests/golden_runner.sh

test-build-config: ## Verify header dependencies and changed/unchanged compiler flags.
	$(NIXRUN) timeout 30 python3 tests/build_config.py

test-pty-deadlines: ## Require finite outer deadlines for every planned terminal test.
	$(NIXRUN) timeout 30 python3 tests/pty_deadlines.py

test-feed: test-feed-bench ## M1 feed goldens + X1 buf_find linear bound.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/feed_demo.bend -o $(BLDDIR)/feed_demo
	$(NIXRUN) sh scripts/check-golden.sh feed_demo=ok ./$(BLDDIR)/feed_demo

test-feed-bench: ## Run the existing feed bound independently of feed goldens.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/feed_bench.bend -o $(BLDDIR)/feed_bench
	$(NIXRUN) sh scripts/check-golden.sh feed_bench=ok timeout 2 ./$(BLDDIR)/feed_bench

test-submit: ## M2 submit goldens.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/submit_demo.bend -o $(BLDDIR)/submit_demo
	$(NIXRUN) sh scripts/check-golden.sh submit_demo=ok ./$(BLDDIR)/submit_demo

test-search: ## M16.3 parallel scrollback search goldens.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/search_demo.bend -o $(BLDDIR)/search_demo
	$(NIXRUN) sh scripts/check-golden.sh search_demo=ok ./$(BLDDIR)/search_demo

test-split: ## M16.2 split-view state, focus, geometry, and routing goldens.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/split_demo.bend -o $(BLDDIR)/split_demo
	$(NIXRUN) sh scripts/check-golden.sh split_demo=ok ./$(BLDDIR)/split_demo

test-preview: ## M16.1 local PNG preview command and DrawOp goldens.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/preview_demo.bend -o $(BLDDIR)/preview_demo
	$(NIXRUN) sh scripts/check-golden.sh preview_demo=ok ./$(BLDDIR)/preview_demo

test-typing: ## M16.4 IRCv3 +typing parser, expiry, bounds, and view goldens.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/typing_demo.bend -o $(BLDDIR)/typing_demo
	$(NIXRUN) sh scripts/check-golden.sh typing_demo=ok ./$(BLDDIR)/typing_demo

test-frame: ## M4 CRLF framer goldens.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/frame_demo.bend -o $(BLDDIR)/frame_demo
	$(NIXRUN) sh scripts/check-golden.sh frame_demo=ok ./$(BLDDIR)/frame_demo

test-net: ## M4 loopback TCP.send/recv + register/pong goldens.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/net_demo.bend -o $(BLDDIR)/net_demo
	$(NIXRUN) sh scripts/check-golden.sh net_demo=ok ./$(BLDDIR)/net_demo

test-dns: ## UDP A lookup identity + parse edges (no network).
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/dns_demo.bend -o $(BLDDIR)/dns_demo
	$(NIXRUN) sh scripts/check-golden.sh dns_demo=ok ./$(BLDDIR)/dns_demo
	@! grep -F 'Dns.resolve("one.one.one.one")' tests/bend/dns_demo.bend

test-dns-live: ## Live A lookup of one.one.one.one (not in check).
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/dns_live.bend -o $(BLDDIR)/dns_live
	$(NIXRUN) sh scripts/check-golden.sh dns_live=ok ./$(BLDDIR)/dns_live

test-dns-timeout: ## K3: blackhole nameserver returns timeout, does not park.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/dns_timeout.bend -o $(BLDDIR)/dns_timeout
	$(NIXRUN) sh scripts/check-golden.sh dns_timeout=ok timeout 15 ./$(BLDDIR)/dns_timeout

test-dns-tcp: ## DNS TCP segmentation, length validation, and deadlines.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/dns_tcp.bend -o $(BLDDIR)/dns_tcp
	$(NIXRUN) timeout 60 python3 tests/dns/tcp.py ./$(BLDDIR)/dns_tcp

test-socket-deadline: ## Socket deadlines: exact writes, stalled peers, refused connects.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/socket_deadline.bend -o $(BLDDIR)/socket_deadline
	$(NIXRUN) timeout 60 python3 tests/dns/socket_deadline.py ./$(BLDDIR)/socket_deadline

test-base64: ## Base64 and SASL PLAIN golden tests.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/base64_demo.bend -o $(BLDDIR)/base64_demo
	$(NIXRUN) sh scripts/check-golden.sh base64_demo=ok ./$(BLDDIR)/base64_demo

test-auth: ## Parsed SASL exchange, phase gating, and forged chat regression.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/auth_demo.bend -o $(BLDDIR)/auth_demo
	$(NIXRUN) sh scripts/check-golden.sh auth_demo=ok ./$(BLDDIR)/auth_demo

test-state: ## Bounded logging and structural state regressions.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/state_demo.bend -o $(BLDDIR)/state_demo
	$(NIXRUN) sh scripts/check-golden.sh state_demo=ok ./$(BLDDIR)/state_demo

.PHONY: test-state-review test-state-review-identity test-state-review-send test-state-review-history
test-state-review: test-state-review-identity test-state-review-send test-state-review-history ## Canonical targets, exact outgoing echoes, recent restores, and close/focus transitions.

test-state-review-identity test-state-review-send test-state-review-history test-runtime-dns test-runtime-reconnect test-runtime-args:
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/$(subst -,_,$(patsubst test-%,%,$@)).bend -o $(BLDDIR)/$(subst -,_,$(patsubst test-%,%,$@))
	$(NIXRUN) sh scripts/check-golden.sh $(subst -,_,$(patsubst test-%,%,$@))=ok timeout 15 ./$(BLDDIR)/$(subst -,_,$(patsubst test-%,%,$@))

.PHONY: test-runtime-review test-runtime-dns test-runtime-reconnect test-runtime-args test-cli-nick test-replay-stream
test-runtime-review: test-runtime-dns test-runtime-reconnect test-runtime-args test-cli-nick test-replay-stream ## Reconnect intent, absolute DNS names, explicit nicks, and complete replay.

test-cli-nick: build-ui ## Loopback: explicit nickname precedence and SASL-derived defaults.
	$(NIXRUN) timeout 75 python3 tests/net/cli_nick.py ./$(BLDDIR)/birc

test-replay-stream: build-ui ## Replay all records across and beyond one-MiB read boundaries.
	$(NIXRUN) timeout 90 python3 tests/net/replay_stream.py ./$(BLDDIR)/birc

.PHONY: test-ui-review-view test-ui-review-output test-ui-review-native test-ui-review-native-ubsan test-pty-ui-review-selection test-pty-ui-review-media
test-ui-review-view: ## Production previews are helper-only; preserve isolated legacy proof adapters.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/ui_review_view.bend -o $(BLDDIR)/ui_review_view
	$(NIXRUN) sh scripts/check-golden.sh ui_review_view=ok timeout 15 ./$(BLDDIR)/ui_review_view

test-ui-review-output: build-ui ## Actual painter preserves Unicode clusters and complete OSC8 targets.
	$(NIXRUN) timeout 30 python3 tests/ui_review_output.py ./$(BLDDIR)/birc

test-ui-review-native: ## Native cluster/selection fidelity, exact hyperlinks, and buffer ownership.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'timeout 60 $$CC -std=c11 -O0 -Wall -Wextra -Werror -pthread -Isrc/ui -Isrc/ffi tests/ui_review_native.c -o $(BLDDIR)/ui_review_native'
	$(NIXRUN) sh scripts/check-golden.sh ui_review_native=ok timeout 15 ./$(BLDDIR)/ui_review_native

test-ui-review-native-ubsan: ## UBSan: cluster arenas, cell-buffer swaps, selection, and hyperlink bounds.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'timeout 60 $$CC -std=c11 -O0 -g -fno-omit-frame-pointer -Wall -Wextra -Werror -pthread -fsanitize=undefined -fno-sanitize-recover=undefined -Isrc/ui -Isrc/ffi tests/ui_review_native.c -o $(BLDDIR)/ui_review_native_ubsan'
	$(NIXRUN) sh -c 'UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 sh scripts/check-golden.sh ui_review_native=ok timeout 15 ./$(BLDDIR)/ui_review_native_ubsan'

test-pty-ui-review-selection: build-ui ## Pty: Escape clears selected cells without quitting or copying blank text.
	$(NIXRUN) timeout 30 python3 tests/pty/ui_review_selection.py ./$(BLDDIR)/birc

test-pty-ui-review-media: build-ui ## Pty: actual helper rejection blocks raw PNG/APNG upload; accepted data is normalized.
	$(NIXRUN) timeout 40 python3 tests/pty/ui_review_media.py ./$(BLDDIR)/birc

test-history: ## Stable log identities, authored lines, and typed reconnect markers.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/history_demo.bend -o $(BLDDIR)/history_demo
	$(NIXRUN) sh scripts/check-golden.sh history_demo=ok ./$(BLDDIR)/history_demo

test-history-io: ## Streaming history keeps the newest records beyond one MiB.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/history_io.bend -o $(BLDDIR)/history_io
	$(NIXRUN) sh scripts/check-golden.sh history_io=ok ./$(BLDDIR)/history_io

test-link-commands: ## Repeated link enumeration and opening preserve numbering.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/link_commands_demo.bend -o $(BLDDIR)/link_commands_demo
	$(NIXRUN) sh scripts/check-golden.sh link_commands_demo=ok ./$(BLDDIR)/link_commands_demo

test-wrap: ## Styled, linked, wide, and combining spans wrap without losing targets.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/wrap_demo.bend -o $(BLDDIR)/wrap_demo
	$(NIXRUN) sh scripts/check-golden.sh wrap_demo=ok ./$(BLDDIR)/wrap_demo

test-columns-width: ## Exhaustive scalar-width parity with the actual TimUI implementation.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/columns_width.bend -o $(BLDDIR)/columns_width
	$(NIXRUN) timeout 60 python3 tests/columns_width.py ./$(BLDDIR)/columns_width

test-scroll: ## Wrapped-row navigation and stable arrival/resize anchors.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/scroll_demo.bend -o $(BLDDIR)/scroll_demo
	$(NIXRUN) sh scripts/check-golden.sh scroll_demo=ok ./$(BLDDIR)/scroll_demo

test-actor: ## Outbound batch boundaries, finite budgets, and FIFO queue behavior.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/actor_demo.bend -o $(BLDDIR)/actor_demo
	$(NIXRUN) sh scripts/check-golden.sh actor_demo=ok ./$(BLDDIR)/actor_demo

test-actor-queue: ## Local sockets: per-turn caps, close flush, and self-pump safety.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/actor_queue.bend -o $(BLDDIR)/actor_queue
	$(NIXRUN) timeout 120 python3 tests/net/actor_queue.py ./$(BLDDIR)/actor_queue

test-links: ## Shared URL lexer: boundaries, punctuation, and code spans.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/links_demo.bend -o $(BLDDIR)/links_demo
	$(NIXRUN) sh scripts/check-golden.sh links_demo=ok ./$(BLDDIR)/links_demo

test-commands: ## Local commands offline/connecting and read-only wire target guards.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/command_demo.bend -o $(BLDDIR)/command_demo
	$(NIXRUN) sh scripts/check-golden.sh command_demo=ok ./$(BLDDIR)/command_demo

test-args: ## CLI flag parse (missing values, bad numbers, --connect).
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/args_demo.bend -o $(BLDDIR)/args_demo
	$(NIXRUN) sh scripts/check-golden.sh args_demo=ok ./$(BLDDIR)/args_demo
	@! grep -F 'def seed_bit' src/bend/session.bend
	@! grep -F 'CopyMany' src/bend/args.bend
	@! grep -F 'def is_433_line' src/bend/irc.bend
	@! grep -F 'def submit_part.chan' src/bend/submit.bend

proto-parity: ## M3 fixture corpus Bend golden tags (fail closed if fixtures missing).
	@test -f fixtures/demo.irc || { printf '%s\n' 'BLOCKED: fixtures/demo.irc missing' >&2; exit 2; }
	@test -f fixtures/welcome.irc || { printf '%s\n' 'BLOCKED: fixtures/welcome.irc missing' >&2; exit 2; }
	@test -f fixtures/action.irc || { printf '%s\n' 'BLOCKED: fixtures/action.irc missing' >&2; exit 2; }
	@test -f fixtures/odd_casing.irc || { printf '%s\n' 'BLOCKED: fixtures/odd_casing.irc missing' >&2; exit 2; }
	@test -f fixtures/adversarial.irc || { printf '%s\n' 'BLOCKED: fixtures/adversarial.irc missing' >&2; exit 2; }
	@grep -F -x ':irc.birc.dev 001 me :Welcome' fixtures/demo.irc >/dev/null || { printf '%s\n' 'BLOCKED: fixtures/demo.irc drifted' >&2; exit 2; }
	@grep -F -x ':irc.example.net 001 me :Welcome to the network' fixtures/welcome.irc >/dev/null || { printf '%s\n' 'BLOCKED: fixtures/welcome.irc drifted' >&2; exit 2; }
	@grep -F 'PiNg :xyz' fixtures/odd_casing.irc >/dev/null || { printf '%s\n' 'BLOCKED: fixtures/odd_casing.irc drifted' >&2; exit 2; }
	@python3 -c "p=open('fixtures/action.irc','rb').read(); assert b'\\x01ACTION waves\\x01' in p" || { printf '%s\n' 'BLOCKED: fixtures/action.irc missing CTCP SOH' >&2; exit 2; }
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/proto_parity.bend -o $(BLDDIR)/proto_parity
	$(NIXRUN) sh scripts/check-golden.sh proto_parity=ok ./$(BLDDIR)/proto_parity

test-ui: build-ui ## Headless TimUI smoke (--demo --frames 3).
	$(NIXRUN) ./$(BLDDIR)/birc --demo --frames 3 </dev/null
	$(NIXRUN) ./$(BLDDIR)/birc --replay fixtures/demo.irc --frames 1 </dev/null

test-cli: build-ui ## Binary argv errors (no TimUI).
	$(NIXRUN) sh -c './$(BLDDIR)/birc --frames xyz >/dev/null 2>&1; test $$? -eq 2'
	$(NIXRUN) sh -c './$(BLDDIR)/birc --connect >/dev/null 2>&1; test $$? -eq 2'
	$(NIXRUN) sh -c './$(BLDDIR)/birc --help-irc >/dev/null 2>&1; test $$? -eq 2'
	$(NIXRUN) sh -c './$(BLDDIR)/birc --replay >/dev/null 2>&1; test $$? -eq 2'
	$(NIXRUN) sh -c './$(BLDDIR)/birc --replay /no/such/birc.replay >/dev/null 2>&1; test $$? -eq 1'

test-live: build-ui ## Local mock: register + PONG + birc=ok, bounded timeout.
	$(NIXRUN) python3 tests/live_mock.py ./$(BLDDIR)/birc

test-pty-flood: build-ui ## Pty: 400 server chunks (C1 deadlock).
	$(NIXRUN) timeout 150 python3 tests/pty/chunk_flood.py ./$(BLDDIR)/birc 400

test-pty-rows: build-ui ## Pty: newest body line is painted (C3).
	$(NIXRUN) timeout 150 python3 tests/pty/body_rows.py ./$(BLDDIR)/birc

test-pty-tall: build-ui ## Pty: newest line on 40- and 90-row terminals (R6).
	$(NIXRUN) timeout 150 python3 tests/pty/tall_rows.py ./$(BLDDIR)/birc 40 80
	$(NIXRUN) timeout 150 python3 tests/pty/tall_rows.py ./$(BLDDIR)/birc 90 120

test-pty-restore: build-ui ## Pty: cooked mode after exit (C2 atexit/close).
	$(NIXRUN) timeout 150 python3 tests/pty/restore.py ./$(BLDDIR)/birc

test-pty-composer: build-ui ## Pty: composer length, history clear, and Ctrl-A/Ctrl-K.
	$(NIXRUN) timeout 150 python3 tests/pty/composer_pty.py ./$(BLDDIR)/birc

test-pty-eof: build-ui ## Pty: server close keeps the UI alive (H3).
	$(NIXRUN) timeout 150 python3 tests/pty/eof_pty.py ./$(BLDDIR)/birc

test-pty-connect: build-ui ## Pty: /connect does not freeze the UI (H4).
	$(NIXRUN) timeout 150 python3 tests/pty/connect_pty.py ./$(BLDDIR)/birc

test-pty-demo-nick: build-ui ## Pty: --demo --nick bob registers as bob (H5).
	$(NIXRUN) timeout 150 python3 tests/pty/demo_nick.py ./$(BLDDIR)/birc

test-pty-linger: build-ui ## Pty: boot_clock does not linger 8 s after quit (H6).
	$(NIXRUN) timeout 150 python3 tests/pty/linger.py ./$(BLDDIR)/birc

test-pty-utf8: build-ui ## Pty: UTF-8 split + Latin-1 fallback + CJK (H7).
	$(NIXRUN) timeout 150 python3 tests/pty/utf8_split_pty.py ./$(BLDDIR)/birc

test-pty-minus: build-ui ## Pty: connect refused, 433 retry, close mid-line (T7).
	$(NIXRUN) timeout 150 python3 tests/pty/live_minus.py ./$(BLDDIR)/birc

test-pty-redial: build-ui ## Pty: partial line then Eof; /connect 001 sends JOIN in 100 ms (A1).
	$(NIXRUN) timeout 150 python3 tests/pty/redial.py ./$(BLDDIR)/birc

test-pty-rst: build-ui ## Pty: TCP RST keeps the UI alive (A3).
	$(NIXRUN) timeout 150 python3 tests/pty/rst.py ./$(BLDDIR)/birc

test-pty-tinyquit: build-ui ## Pty: /quit at 1-2 cols and after resize-back (A6).
	$(NIXRUN) timeout 150 python3 tests/pty/tinyquit.py ./$(BLDDIR)/birc

test-pty-tabcut: build-ui ## Pty: long UTF-8 tab label cut on a code point (A7).
	$(NIXRUN) timeout 150 python3 tests/pty/tab_cut.py ./$(BLDDIR)/birc

test-pty-paste50: build-ui ## Pty: burst paste 50/100/300 lines, then /quit (X3).
	$(NIXRUN) timeout 150 python3 tests/pty/paste50.py ./$(BLDDIR)/birc 50
	$(NIXRUN) timeout 150 python3 tests/pty/paste50.py ./$(BLDDIR)/birc 100
	$(NIXRUN) timeout 150 python3 tests/pty/paste50.py ./$(BLDDIR)/birc 300

test-pty-bpaste: build-ui ## Pty: bracketed paste 10/60/300 lines, then /quit (B1).
	$(NIXRUN) timeout 150 python3 tests/pty/bpaste.py ./$(BLDDIR)/birc 10
	$(NIXRUN) timeout 150 python3 tests/pty/bpaste.py ./$(BLDDIR)/birc 60
	$(NIXRUN) timeout 150 python3 tests/pty/bpaste.py ./$(BLDDIR)/birc 300

test-pty-mixburst: build-ui ## Pty: text+Backspace+arrows+Enter burst (B3).
	$(NIXRUN) timeout 150 python3 tests/pty/mixburst.py ./$(BLDDIR)/birc 200

test-pty-quitcap: build-ui ## Pty: /quit after a SEND_CAP burst still sends QUIT (X2).
	$(NIXRUN) timeout 150 python3 tests/pty/quitcap.py ./$(BLDDIR)/birc

test-pty-tickrate: build-ui ## Pty: parked --demo idle CPU <= 1.0% (K2).
	$(NIXRUN) timeout 150 python3 tests/pty/tickrate.py ./$(BLDDIR)/birc

test-pty-geneof: build-ui ## Pty: late Eof from the old server does not drop the new one.
	$(NIXRUN) timeout 150 python3 tests/pty/gen_eof.py ./$(BLDDIR)/birc

test-pty-closequit: build-ui ## Pty: server close then /quit exits (12 runs).
	$(NIXRUN) timeout 150 python3 tests/pty/close_then_quit.py ./$(BLDDIR)/birc

test-pty-stall: build-ui ## Pty: PONG while the terminal is not read (F1).
	$(NIXRUN) timeout 150 python3 tests/pty/stall.py ./$(BLDDIR)/birc

test-pty-output-stall: build-ui ## Pty: bounded bells/selection and nonblocking clipboard.
	$(NIXRUN) timeout 40 python3 tests/pty/output_stall.py ./$(BLDDIR)/birc

test-pty-send-stall: build-ui ## Pty: quit stays usable with a saturated non-reading IRC peer.
	$(NIXRUN) timeout 40 python3 tests/pty/send_stall.py ./$(BLDDIR)/birc

test-pty-wrapped-spans: build-ui ## Pty: wrapped links and wide styled text survive resize.
	$(NIXRUN) timeout 40 python3 tests/pty/wrapped_spans.py ./$(BLDDIR)/birc

test-pty-reconnect-nick: build-ui ## Pty: reconnect snapshots the acknowledged nickname.
	$(NIXRUN) timeout 40 python3 tests/pty/reconnect_nick.py ./$(BLDDIR)/birc

test-pty-scroll-wrap: build-ui ## Pty: PageUp reaches the first row of a wrapped message.
	$(NIXRUN) timeout 40 python3 tests/pty/scroll_wrap.py ./$(BLDDIR)/birc

test-pty-frame-links: build-ui ## Pty: every paint returns exact clicked URLs and frame effects.
	$(NIXRUN) timeout 40 python3 tests/pty/frame_links.py ./$(BLDDIR)/birc

test-pty-launchers: build-ui ## Pty: owned launchers are reaped and cannot block network/UI work.
	$(NIXRUN) timeout 40 python3 tests/pty/launchers.py ./$(BLDDIR)/birc

test-pty-startup-connect: build-ui ## Pty: pending initial connects paint and keep the UI usable.
	$(NIXRUN) timeout 25 python3 tests/pty/startup_connect.py ./$(BLDDIR)/birc

test-pty-history-endpoints: build-ui ## Pty: server/port histories and reload checkpoints stay isolated.
	$(NIXRUN) timeout 120 python3 tests/pty/history_endpoints.py ./$(BLDDIR)/birc

test-scroll-edits: ## Purge, query merge, and link-list edits preserve scroll identity.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/scroll_edits_demo.bend -o $(BLDDIR)/scroll_edits_demo
	$(NIXRUN) sh scripts/check-golden.sh scroll_edits_demo=ok ./$(BLDDIR)/scroll_edits_demo

test-history-errors: ## History IO errors are visible; sparse size probes never scan large files.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/history_errors.bend -o $(BLDDIR)/history_errors
	$(NIXRUN) timeout 60 python3 tests/history_errors.py ./$(BLDDIR)/history_errors

test-startup-actor: ## Initial actor success/failure can continue to a queued dial.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/startup_actor.bend -o $(BLDDIR)/startup_actor
	$(NIXRUN) timeout 15 python3 tests/net/startup_actor.py ./$(BLDDIR)/startup_actor

test-session-links: ## Session opening echoes cannot amplify links or persisted history.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/session_links_demo.bend -o $(BLDDIR)/session_links_demo
	$(NIXRUN) sh scripts/check-golden.sh session_links_demo=ok ./$(BLDDIR)/session_links_demo

test-pty-session-links: build-ui ## Pty: runtime open/list uses stable link sources and fake launchers.
	$(NIXRUN) timeout 40 python3 tests/pty/session_links.py ./$(BLDDIR)/birc

test-pty-split-identity: build-ui ## Pty: a query named server retains its pane and send identity.
	$(NIXRUN) timeout 45 python3 tests/pty/split_identity.py ./$(BLDDIR)/birc

test-ui-input-queue: ## Synthetic wakes cannot block acknowledgement or a full event queue.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/ui_input_queue.bend -o $(BLDDIR)/ui_input_queue.c
	$(NIXRUN) timeout 180 sh -c '$$CC $(BEND_CORE_CFLAGS) -Isrc/ui -Isrc/ffi $(BLDDIR)/ui_input_queue.c -o $(BLDDIR)/ui_input_queue'
	$(NIXRUN) sh scripts/check-golden.sh ui_input_queue=ok timeout 15 ./$(BLDDIR)/ui_input_queue

test-pty-input-fairness: build-ui ## Pty: mixed input/inbound traffic keeps PONG and quit responsive.
	$(NIXRUN) timeout 45 python3 tests/pty/input_fairness.py ./$(BLDDIR)/birc

test-demo-identity: ## Demo data preserves the requested nick and current Dial identity.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/demo_identity.bend -o $(BLDDIR)/demo_identity.c
	$(NIXRUN) timeout 180 sh -c '$$CC $(BEND_CORE_CFLAGS) -Isrc/ui -Isrc/ffi $(BLDDIR)/demo_identity.c -o $(BLDDIR)/demo_identity'
	$(NIXRUN) sh scripts/check-golden.sh demo_identity=ok ./$(BLDDIR)/demo_identity

test-mute-scope: ## Scoped mutes filter status targets and all supported channel types.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/mute_scope_demo.bend -o $(BLDDIR)/mute_scope_demo
	$(NIXRUN) sh scripts/check-golden.sh mute_scope_demo=ok timeout 15 ./$(BLDDIR)/mute_scope_demo

test-split-rename: ## Query NICK changes preserve pane identity and focus.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/split_rename_demo.bend -o $(BLDDIR)/split_rename_demo
	$(NIXRUN) sh scripts/check-golden.sh split_rename_demo=ok timeout 15 ./$(BLDDIR)/split_rename_demo

test-action-budget: ## CTCP ACTION retains its envelope and echoes the transmitted UTF-8 body.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/bend/action_budget_demo.bend -o $(BLDDIR)/action_budget_demo
	$(NIXRUN) sh scripts/check-golden.sh action_budget_demo=ok timeout 15 ./$(BLDDIR)/action_budget_demo

test-richtext-model: ## Literal unmatched markup and code styling survive wrapping.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 90 bend tests/bend/richtext_demo.bend -o $(BLDDIR)/richtext_demo
	$(NIXRUN) sh scripts/check-golden.sh richtext_demo=ok timeout 15 ./$(BLDDIR)/richtext_demo

test-richtext-painter: build-ui ## Actual native painter emits dim code and literal unmatched text.
	$(NIXRUN) timeout 15 python3 tests/richtext_painter.py ./$(BLDDIR)/birc fixtures/richtext.irc

test-headless-startup: build-ui ## Headless startup fails closed and completes healthy registration.
	$(NIXRUN) timeout 30 python3 tests/net/headless_startup.py ./$(BLDDIR)/birc

test-pty-output-recovery: build-ui ## Pty: short frames recover without blocking PONG or quit.
	$(NIXRUN) timeout 40 python3 tests/pty/output_recovery.py ./$(BLDDIR)/birc

test-pty-escup: build-ui ## Pty: Esc split across reads is one Up, lone Esc quits (F2).
	$(NIXRUN) timeout 150 python3 tests/pty/esc_up.py ./$(BLDDIR)/birc

test-pty-paintwake: build-ui ## Pty: incoming line paints within 100 ms after idle (P1).
	$(NIXRUN) timeout 150 python3 tests/pty/paint_wake.py ./$(BLDDIR)/birc

test-pty-joinlat: build-ui ## Pty: 001 to JOIN under 100 ms (P1 handshake).
	$(NIXRUN) timeout 150 python3 tests/pty/join_latency.py ./$(BLDDIR)/birc

test-pty-manyeof: build-ui ## Pty: 12 one-write /connect after FIN/RST idle (note 16).
	$(NIXRUN) timeout 150 python3 tests/pty/many_eof.py ./$(BLDDIR)/birc

test-pty-tabswitch: build-ui ## Pty: 1-press / 1-click tab switching.
	$(NIXRUN) timeout 150 python3 tests/pty/tab_switch.py ./$(BLDDIR)/birc

test-pty-alerts: build-ui ## Pty: bell events and visual background-tab alerts.
	$(NIXRUN) timeout 150 python3 tests/pty/alerts.py ./$(BLDDIR)/birc

test-pty-linkclick: build-ui ## Pty: a body-link click opens its exact URL.
	$(NIXRUN) timeout 150 python3 tests/pty/link_click.py ./$(BLDDIR)/birc

test-pty-softwrap: build-ui ## Pty: long chat lines wrap and reflow after resize.
	$(NIXRUN) timeout 150 python3 tests/pty/softwrap.py ./$(BLDDIR)/birc

test-pty-mouseselect: build-ui ## Pty: in-app mouse selection and Esc dismissal.
	$(NIXRUN) timeout 150 python3 tests/pty/mouse_select.py ./$(BLDDIR)/birc

test-pty-preview: build-ui ## Pty: local PNG preview emits Kitty transmit and placement escapes.
	$(NIXRUN) timeout 150 python3 tests/pty/preview_kitty.py ./$(BLDDIR)/birc

test-pty-resize: build-ui ## Pty: dynamic window resize expand and shrink.
	$(NIXRUN) timeout 150 python3 tests/pty/resize.py ./$(BLDDIR)/birc

test-pty-settings: build-ui ## Pty: /settings panel, /set, and /toggle commands.
	$(NIXRUN) timeout 150 python3 tests/pty/settings.py ./$(BLDDIR)/birc

test-pty-history: build-ui ## Pty: history persistence, reconnect markers, and BIRC_HISTORY.
	$(NIXRUN) timeout 150 python3 tests/pty/history_pty.py ./$(BLDDIR)/birc

test-pty-autoreconnect: build-ui ## Pty: live disconnect reconnects on the saved host and port.
	$(NIXRUN) timeout 150 python3 tests/pty/autoreconnect.py ./$(BLDDIR)/birc

test-pty-disconnect-cleanup: build-ui ## Pty: reconnect-off disconnect releases the dead writer socket.
	$(NIXRUN) timeout 150 python3 tests/pty/disconnect_cleanup.py ./$(BLDDIR)/birc

test-pty-hostile: build-ui ## M7.6: combined hostile wire, resize, cap, and recovery corpus.
	$(NIXRUN) timeout 120 python3 tests/pty/hostile.py ./$(BLDDIR)/birc

test-pty-split: build-ui ## Pty: visible split geometry/content, focus keys, selection, and tiny resize.
	$(NIXRUN) timeout 150 python3 tests/pty/split_pty.py ./$(BLDDIR)/birc

test-pty-typing: build-ui ## Pty: IRCv3 typing lifecycle, timeout, pause, and muted clear.
	$(NIXRUN) timeout 150 python3 tests/pty/typing.py ./$(BLDDIR)/birc

test-pty: test-pty-flood test-pty-restore test-pty-rows test-pty-tall test-pty-composer test-pty-eof test-pty-connect test-pty-demo-nick test-pty-linger test-pty-utf8 test-pty-minus test-pty-redial test-pty-rst test-pty-tinyquit test-pty-tabcut test-pty-paste50 test-pty-bpaste test-pty-mixburst test-pty-quitcap test-pty-tickrate test-pty-paintwake test-pty-joinlat test-pty-manyeof test-pty-geneof test-pty-closequit test-pty-stall test-pty-escup test-pty-tabswitch test-pty-alerts test-pty-linkclick test-pty-softwrap test-pty-mouseselect test-pty-preview test-pty-resize test-pty-settings test-pty-history test-pty-autoreconnect test-pty-disconnect-cleanup test-pty-split test-pty-typing test-pty-hostile ## Pty loop tests.

.PHONY: test-review-pure
test-pty: test-pty-output-stall test-pty-send-stall test-pty-wrapped-spans test-pty-reconnect-nick test-pty-scroll-wrap test-pty-frame-links test-pty-launchers test-pty-startup-connect test-pty-session-links test-pty-history-endpoints test-pty-split-identity test-pty-input-fairness test-pty-output-recovery test-pty-output-progress test-pty-output-failure
test-pty: test-pty-media test-pty-diagnostic test-pty-esc-resize-wake
test-pty: test-pty-ui-review-selection test-pty-ui-review-media

.PHONY: test-review-pure test-golden-runner test-build-config test-auth test-commands test-state test-history test-history-io test-links test-link-commands test-wrap test-columns-width test-scroll test-dns-tcp test-socket-deadline test-pty-output-stall test-pty-send-stall test-pty-wrapped-spans test-pty-reconnect-nick proof-kernel
.PHONY: test-pty-scroll-wrap
.PHONY: test-pty-frame-links test-pty-launchers
.PHONY: test-pty-startup-connect test-pty-history-endpoints test-scroll-edits test-history-errors
.PHONY: test-actor test-actor-queue test-startup-actor test-session-links test-pty-session-links
.PHONY: test-pty-split-identity
.PHONY: test-ui-input-queue test-pty-input-fairness
.PHONY: test-demo-identity test-headless-startup test-pty-output-recovery
.PHONY: test-mute-scope test-action-budget test-richtext-model test-richtext-painter
.PHONY: test-split-rename
.PHONY: test-output-shutdown test-output-progress test-pty-output-progress test-pty-output-failure
.PHONY: test-png-bounds test-png-bounds-ubsan

test-review-pure: test-golden-runner test-build-config test-auth test-commands test-state test-history test-history-io test-history-errors test-links test-link-commands test-session-links test-wrap test-columns-width test-scroll test-scroll-edits test-dns-tcp test-socket-deadline test-actor test-actor-queue test-startup-actor test-ui-input-queue test-demo-identity test-output-utf8 test-output-shutdown test-output-progress test-png-bounds test-mute-scope test-action-budget test-richtext-model test-split-rename test-formatting test-media-image ## Adversarial review regression gates.
test-review-pure: test-media-policy test-media-view test-media-anchor test-media-branches test-viewport-tail test-media-native test-media-portable test-diagnostic test-server-time test-history-save-errors test-reader-errors test-clipboard-errors test-pty-deadlines test-view-profile test-input-wake
test-review-pure: test-state-review test-runtime-review test-ui-review-native test-ui-review-view test-ui-review-output

test: test-review-pure test-proto test-feed test-submit test-search test-preview test-split test-typing test-frame test-net test-dns test-dns-timeout test-base64 test-args proto-parity test-ui test-cli test-live test-headless-startup test-richtext-painter test-formatting-painter test-pty ## Protocol + pure + net + DNS + args + fixtures + UI + live mock + pty.

proof: ## Check LAWS via PROOF.bend (Bend proof checker).
	$(NIXRUN) timeout 180 bend PROOF.bend

.PHONY: proof-kernel
proof-kernel: ## Independently check proofs with BendTT (requires Lean or BENDTT).
	$(NIXRUN) timeout 300 bend PROOF.bend --verdict

LINT_FFI_CFLAGS := -std=c11 -Wall -Wextra -Werror -pedantic -Wshadow -Wconversion -Wsign-conversion -Wcast-qual -Wno-unused-command-line-argument -fsyntax-only
lint-ffi: test-utf8-fit ## Syntax-only warning lint of src/ffi (real build stays -w).
	$(NIXRUN) sh -c '$$CC $(LINT_FFI_CFLAGS) -I tests/lint-ffi -I src/ffi -isystem src/ui tests/lint-ffi/lint_timui.c'
	$(NIXRUN) sh -c '$$CC $(LINT_FFI_CFLAGS) -I tests/lint-ffi -I src/ffi -isystem src/ui tests/lint-ffi/lint_clock.c'
	$(NIXRUN) sh -c '$$CC $(LINT_FFI_CFLAGS) -I tests/lint-ffi -I src/ffi -isystem src/ui tests/lint-ffi/lint_dns.c'
	@awk 'BEGIN{u=0;b=0;p=0;q=0} /if \(!ui\) \{/{p=1} p&&/birc_drop_ops/{u=1} p&&/return birc_uikeys/{p=0} /if \(!timui_begin/{q=1} q&&/birc_drop_ops/{b=1} q&&/return birc_uikeys/{q=0} END{if(!(u&&b)){print "drop_ops: early returns must consume ops"; exit 1}}' src/ffi/timui_ffi.c
	@! grep -E 'rows[[:space:]]*-[[:space:]]*6' src/ffi/timui_ffi.c
	@awk '/^def reader_stop\(/{p=1} p&&/Eof/{e=1} p&&/Socket.close\(dup\)/{c=1} p&&/^def / && !/^def reader_stop/{p=0} END{if(!(e&&c)){print "reader_stop: Eof then close the dup only"; exit 1}}' src/bend/actor.bend
	@! grep -F 'Chan.close(Sess.UiMsg' src/bend/net.bend
	@! grep -F 'birc_wait_fds' src/ffi/timui_ffi.c
	@! grep -F 'wake_poke' src/ffi/*.c
	@! grep -F 'fd_hint' src/ffi/dns_ffi.c
	@grep -q 'O_NONBLOCK' src/ffi/timui_ffi.c
	@! grep -F 'poll(p, 1, 0)' src/ffi/timui_ffi.c
	@! grep -F 'while (n < sizeof buf && term_aux(xs)' src/ffi/dns_ffi.c
	@awk '/timui_open\(&cfg/{p=1} p&&/free\(st\)/{c=1} p&&/return io_fail/{p=0} END{if(!c){print "timui_open fail must free st"; exit 1}}' src/ffi/timui_ffi.c
	@grep -q 'io_eff(CID_RECV_OCTETS, recv_octets_run, IO_READ)' src/ffi/dns_ffi.c
	@grep -q 'io_eff(CID_RECV_NB, recv_nb_run, 0)' src/ffi/dns_ffi.c
	@grep -q 'if (max > 4096u)' src/ffi/dns_ffi.c
	@grep -q 'code == (u32)EINTR' src/ffi/dns_ffi.c
	@awk '/^def wait_ans/{p=1} p&&/recv_nb\(sock/{n=1} p&&/recv_octets\(sock/{b=1} p&&/^def / && !/^def wait_ans/{p=0} END{if(!n||b){print "wait_ans must call recv_nb, not recv_octets"; exit 1}}' src/bend/dns.bend

test-utf8-fit: ## A7: tab-label 63-byte cap is a UTF-8 boundary.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c '$$CC -std=c11 -Wall -Wextra -Werror -I src/ffi -o $(BLDDIR)/utf8_fit_cap tests/utf8_fit_cap.c'
	$(NIXRUN) sh scripts/check-golden.sh utf8_fit_cap=ok ./$(BLDDIR)/utf8_fit_cap
	@grep -F 'birc_utf8_fit(s, (size_t)len < 63 ? (size_t)len : (size_t)63)' src/ffi/timui_ffi.c >/dev/null

.PHONY: test-output-utf8
test-output-utf8: ## Preserve partial UTF-8 scalars across bounded output retries.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 60 sh -c '$$CC -std=c11 -Wall -Wextra -Werror -pthread -I src/ui -o $(BLDDIR)/output_utf8 tests/output_utf8.c'
	$(NIXRUN) sh scripts/check-golden.sh output_utf8=ok ./$(BLDDIR)/output_utf8

test-output-shutdown: ## Final output settles UTF-8, framing, and sync debt before status.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 60 sh -c '$$CC -std=c11 -Wall -Wextra -Werror -pthread -I src/ui -I src/ffi -o $(BLDDIR)/output_shutdown tests/output_shutdown.c'
	$(NIXRUN) sh scripts/check-golden.sh output_shutdown=ok timeout 15 ./$(BLDDIR)/output_shutdown

test-output-progress: ## One serialized frame drains exactly across short writes and resize.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 60 sh -c '$$CC -std=c11 -Wall -Wextra -Werror -pthread -I src/ui -I src/ffi -o $(BLDDIR)/output_progress tests/output_progress.c'
	$(NIXRUN) sh scripts/check-golden.sh output_progress=ok timeout 15 ./$(BLDDIR)/output_progress

.PHONY: test-view-profile
test-view-profile: ## Default-off pure View timing and exact mark ownership.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 60 sh -c '$$CC -std=c11 -Wall -Wextra -Werror -pthread -I src/ui -I src/ffi -o $(BLDDIR)/view_profile tests/view_profile.c'
	$(NIXRUN) sh scripts/check-golden.sh view_profile=ok timeout 15 ./$(BLDDIR)/view_profile

test-input-wake: ## Actual FFI: timed input survives non-key paints and an already parked tty watcher.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 60 sh -c '$$CC -std=c11 -Wall -Wextra -Werror -pthread -I src/ui -I src/ffi -o $(BLDDIR)/input_wake tests/input_wake.c'
	$(NIXRUN) sh scripts/check-golden.sh input_wake=ok timeout 15 ./$(BLDDIR)/input_wake

test-pty-output-progress: build-ui ## Pty: large and paced frames finish; partial-frame quit stays bounded.
	$(NIXRUN) timeout 45 python3 tests/pty/output_progress.py ./$(BLDDIR)/birc

$(BLDDIR)/birc-output-limit: $(BLDDIR)/birc_bend.c $(BLDDIR)/build-config
	$(NIXRUN) timeout 300 sh -c '$$CC $(BEND_CORE_CFLAGS) -DBIRC_OUTPUT_LIMIT=4096 -Isrc/ui -Isrc/ffi $(BLDDIR)/birc_bend.c -o $(BLDDIR)/birc-output-limit'

test-pty-output-failure: build-ui $(BLDDIR)/birc-output-limit ## Pty: capture refusal closes the connected actor and fails after tty restore.
	$(NIXRUN) timeout 30 python3 tests/pty/output_failure.py ./$(BLDDIR)/birc ./$(BLDDIR)/birc-output-limit

PNG_TEST_CFLAGS := -std=c99 -O1 -Werror=vla -pedantic -Wall -Wextra -Werror -isystem src/ui
test-png-bounds: ## Bound local Sixel PNG allocation/inflation and retry transient failures.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 60 sh -c '$$CC $(PNG_TEST_CFLAGS) tests/png_bounds.c -o $(BLDDIR)/png_bounds'
	$(NIXRUN) timeout 30 python3 tests/png_bounds.py ./$(BLDDIR)/png_bounds

test-png-bounds-ubsan: ## UBSan: PNG layouts, malformed cache, and allocation-denial cleanup.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 60 sh -c '$$CC $(PNG_TEST_CFLAGS) -g -fsanitize=undefined -fno-sanitize-recover=all tests/png_bounds.c -o $(BLDDIR)/png_bounds_ubsan'
	$(NIXRUN) sh -c 'UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 timeout 30 python3 tests/png_bounds.py ./$(BLDDIR)/png_bounds_ubsan'

test-paste-harness: ## F3/F4: paste UTF-8 lossless hold and tail.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c '$$CC -std=c11 -Wall -Wextra -Werror -I src/ui -o $(BLDDIR)/paste_harness tests/paste_harness.c'
	$(NIXRUN) sh scripts/check-golden.sh paste_harness=ok ./$(BLDDIR)/paste_harness

test-perf-cpu: build-ui ## 15 s idle/flood CPU (not in check).
	$(NIXRUN) python3 tests/perf/cpu_pty.py ./$(BLDDIR)/birc

test-perf-tickrate: build-ui ## 600-frame idle tickrate (not in check).
	$(NIXRUN) python3 tests/perf/tickrate_pty.py ./$(BLDDIR)/birc 600 30 100

test-perf-search: ## Profile serial/parallel search at 16 x 1024 lines (not in check).
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/perf/search_profile.bend -o $(BLDDIR)/search_profile
	$(NIXRUN) sh -c 'for mode in serial parallel parallel serial serial parallel parallel serial serial parallel; do BIRC_SEARCH_PROFILE=$$mode ./$(BLDDIR)/search_profile; done'

test-perf-hardening: build-ui ## Profile production frame phases with scale replay (not in check).
	$(NIXRUN) timeout 120 python3 tests/perf/hardening_profile.py ./$(BLDDIR)/birc

test-perf-output: build-ui ## Measure stalled-output View/native phases and PONG latency (not in check).
	$(NIXRUN) timeout 90 python3 tests/perf/output_profile.py ./$(BLDDIR)/birc

.PHONY: test-perf-media-wrap
MEDIA_PROFILE_MODE ?= empty
MEDIA_PROFILE_LINKS ?= 0
MEDIA_PROFILE_SAMPLES ?= 128
MEDIA_PROFILE_LINES ?= 128
test-perf-media-wrap: ## Measure consumed batches; set MEDIA_PROFILE_MODE/LINKS/SAMPLES/LINES (not in check).
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/perf/media_wrap_profile.bend -o $(BLDDIR)/media_wrap_profile
	$(NIXRUN) timeout 15 ./$(BLDDIR)/media_wrap_profile $(MEDIA_PROFILE_MODE) $(MEDIA_PROFILE_LINKS) $(MEDIA_PROFILE_SAMPLES) $(MEDIA_PROFILE_LINES)

SANITIZER_CFLAGS := -std=c11 -O1 -g -fno-omit-frame-pointer -pthread -w

$(BLDDIR)/birc_ubsan: $(BLDDIR)/birc_bend.c $(BLDDIR)/build-config
	$(NIXRUN) timeout 300 sh -c '$$CC $(SANITIZER_CFLAGS) -fsanitize=undefined -fno-sanitize-recover=undefined -Isrc/ui -Isrc/ffi $(BLDDIR)/birc_bend.c -o $(BLDDIR)/birc_ubsan'

test-asan: ## M7.3: bounded ASan gate (explicit skip for broken runtimes).
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 30 sh -c '$$CC -std=c11 -O0 -g -fno-omit-frame-pointer -Wall -Wextra -Werror -fsanitize=address -fno-sanitize-recover=all -I src/ffi tests/utf8_fit_cap.c -o $(BLDDIR)/utf8_fit_cap_asan'
	$(NIXRUN) timeout 15 python3 tests/sanitize/asan_gate.py ./$(BLDDIR)/utf8_fit_cap_asan

test-ubsan: $(BLDDIR)/birc_ubsan ## M7.4: full-app UBSan through the hostile pty corpus.
	$(NIXRUN) sh -c 'UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 timeout 120 python3 tests/pty/hostile.py ./$(BLDDIR)/birc_ubsan'

.PHONY: test-ubsan-native
test-ubsan-native: ## UBSan: output progress, real signals, and final status ownership.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'set -eu; for guard in output_utf8 output_shutdown output_progress; do timeout 60 $$CC -std=c11 -O0 -g -fno-omit-frame-pointer -Wall -Wextra -Werror -pthread -fsanitize=undefined -fno-sanitize-recover=undefined -I src/ui -I src/ffi tests/$$guard.c -o $(BLDDIR)/$${guard}_ubsan; UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 sh scripts/check-golden.sh $$guard=ok timeout 15 ./$(BLDDIR)/$${guard}_ubsan; done'

test-sanitizers: test-asan test-ubsan test-ubsan-native test-png-bounds-ubsan test-media-native-ubsan test-ui-review-native-ubsan ## M7.3/M7.4: all repeatable sanitizer gates.

test-perf-gates: test-pty-tickrate test-pty-paintwake test-pty-joinlat test-perf-hardening ## M7.5: idle, latency, and scale gates.

check-hardening: proof proto-parity test-pty-hostile test-sanitizers test-perf-gates ## M7.3-M7.6 hardening gates.

check: proof test lint-ffi test-paste-harness ## Proofs + protocol tests + UI smoke + FFI lint + paste harness.

run-demo: build-ui ## Offline TimUI demo with canned IRC transcript.
	$(NIXRUN) ./$(BLDDIR)/birc --demo

run: ## Live IRC client (needs HOST=…; rebuilds only if Bend/FFI sources changed).
	@test -n "$(HOST)" || { printf '%s\n' 'usage: make run HOST=irc.example.net [NICK=birc] [CHAN=#birc] [PORT=6667]' >&2; exit 2; }
	@$(MAKE) build-ui
	$(NIXRUN) ./$(BLDDIR)/birc --connect "$(HOST)" --port "$(PORT)" --nick "$(NICK)" --channel "$(CHAN)"

clean: ## Remove build artefacts (not sources or flake.lock).
	rm -rf $(BLDDIR)
