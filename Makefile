# SPDX-License-Identifier: Apache-2.0
# birc — IRC client (Bend 2 protocol + timui.h UI).
SHELL := /bin/sh
.DEFAULT_GOAL := help
.DELETE_ON_ERROR:

# Default to two jobs per three cores unless the caller already chose a -j.
# Not one job per core: a single `bend` compile runs at 117-165% CPU because Bun
# is internally multi-threaded, so -j$(nproc) oversubscribes and targets that fit
# their deadline serially die with Error 124 in parallel. Measured on an idle
# 8-core host at -j1: live_context 58s, net_demo 84s, deferred_frame.c 41s,
# mss_stale_socket.c 42s — all inside their 180/300s bounds alone, all killed
# under -j6. Raising those bounds would hide real hangs; sizing -j does not.
# GNU make 3.81 leaves command-line -j out of $(MAKEFLAGS) while the makefile is
# parsed; an exported MAKEFLAGS is visible to the shell. `make update` stays
# serial: a pin move must not race itself.
BIRC_JOB_FLAGS := $(MAKEFLAGS) $(shell printf '%s' "$$MAKEFLAGS")
BIRC_NCPU := $(shell sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 1)
BIRC_JOBS := $(shell echo "$(BIRC_NCPU)" | awk '{n=int($$1*2/3); if (n<1) n=1; print n}')
ifeq (,$(findstring j,$(BIRC_JOB_FLAGS)))
MAKEFLAGS += -j$(BIRC_JOBS)
endif
update: MAKEFLAGS := $(filter-out -j%,$(MAKEFLAGS))

NIX ?= nix
CONFIRM ?= no
NIX_FEATURES := --extra-experimental-features 'nix-command flakes'
HOST ?=
NICK ?= birc
CHAN ?= \#birc
PORT ?=
TRANSPORT ?= tls
PROFILE ?=
CONFIG ?=
PREFS_HELPER ?= birc-preferences
# Generated-C link bound (birc/deferred_frame/ws_upload_frame): calm-host -O2
# link 143s, loaded laptop ~280s; 600 restores ~2x margin over worst
# observed. BUILD_TIMEOUT=900 override stays for extreme load.
BUILD_TIMEOUT ?= 600
PROOF_TIMEOUT ?= 180
PACKAGE_PLAN_TIMEOUT ?= 45

ifeq ($(BIRC_NIX_SHELL),1)
NIXRUN :=
else
NIXRUN := $(NIX) $(NIX_FEATURES) develop --no-update-lock-file . --command
ifeq ($(shell command -v bend >/dev/null 2>&1 && printf '%s' yes),)
$(warning birc: bend is not on PATH and BIRC_NIX_SHELL is unset; each recipe re-enters nix develop (~1.2-1.6s). Run make shell first.)
endif
endif

BLDDIR := build
# Directory of this Makefile, so `make -f` from another cwd (test-nix-preflight)
# still finds fragments. `wildcard` is cwd-relative and would miss them.
BIRC_MAKE_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
# Resolve prerequisites from the Makefile's own directory when driven via
# `make -f` from elsewhere (test-nix-preflight runs proto-parity in a temp
# dir). In-tree builds resolve locally first; VPATH is only a fallback.
VPATH := $(dir $(lastword $(MAKEFILE_LIST)))
APP := src/bend/app.bend
PROTO := tests/bend/proto_demo.bend
PTY_APP ?= ./$(BLDDIR)/birc
PTY_BUILD = $(if $(filter ./$(BLDDIR)/birc,$(PTY_APP)),build-ui)
# Single source for `make test-pty` and scripts/shard-pty.sh. Standalone
# targets (auth, deadlines, recovery-settings, upload-preferences-private,
# composer-scroll) are intentionally not in this suite.
PTY_SUITE_TARGETS := \
	test-pty-alerts \
	test-pty-autoreconnect \
	test-pty-bpaste \
	test-pty-closequit \
	test-pty-composer \
	test-pty-connect \
	test-pty-deferred-redraw \
	test-pty-demo-nick \
	test-pty-diagnostic \
	test-pty-disconnect-cleanup \
	test-pty-eof \
	test-pty-esc-resize-wake \
	test-pty-escup \
	test-pty-flood \
	test-pty-frame-links \
	test-pty-geneof \
	test-pty-history \
	test-pty-history-endpoints \
	test-pty-history-images \
	test-pty-hostile \
	test-pty-image-marker \
	test-pty-input-fairness \
	test-pty-joinlat \
	test-pty-launchers \
	test-pty-linger \
	test-pty-linkclick \
	test-pty-local-time \
	test-pty-m20-media-cache \
	test-pty-manyeof \
	test-pty-media \
	test-pty-minus \
	test-pty-mixburst \
	test-pty-mouseselect \
	test-pty-output-failure \
	test-pty-output-progress \
	test-pty-output-recovery \
	test-pty-output-stall \
	test-pty-paintwake \
	test-pty-paste50 \
	test-pty-preferences \
	test-pty-preferences-history \
	test-pty-preview \
	test-pty-preview-retry \
	test-pty-quitcap \
	test-pty-reconnect-nick \
	test-pty-reconnect-recovery \
	test-pty-redial \
	test-pty-resize \
	test-pty-restore \
	test-pty-rows \
	test-pty-rst \
	test-pty-scroll-wrap \
	test-pty-send-stall \
	test-pty-session-links \
	test-pty-settings \
	test-pty-softwrap \
	test-pty-split \
	test-pty-split-composer \
	test-pty-split-identity \
	test-pty-stall \
	test-pty-startup-connect \
	test-pty-tabcut \
	test-pty-tabswitch \
	test-pty-tall \
	test-pty-tickrate \
	test-pty-tinyquit \
	test-pty-tls \
	test-pty-typing \
	test-pty-ui-review-media \
	test-pty-ui-review-selection \
	test-pty-upload \
	test-pty-upload-diagnostics \
	test-pty-utf8 \
	test-pty-wrapped-spans
export PTY_SUITE_TARGETS
test-pty: $(PTY_SUITE_TARGETS) ## Pty loop tests.

.PHONY: test-pty-server-multiserver
test-pty-server-multiserver: $(PTY_BUILD) ## Two loopback servers: part routing, F7 drafts, dual-generation quit.
	$(NIXRUN) timeout 90 python3 tests/pty/server_multiserver.py $(PTY_APP)

test%: export BIRC_HISTORY ?= none
check: export BIRC_HISTORY ?= none
test%: export BIRC_IMAGES ?= off
check: export BIRC_IMAGES ?= off
test%: export BIRC_CARDS := off
check: export BIRC_CARDS := off
test%: export BIRC_PREFERENCES := none
check: export BIRC_PREFERENCES := none
test%: export BIRC_IMAGE_CACHE := none
check: export BIRC_IMAGE_CACHE := none
.PHONY: help bootstrap shell update doctor build build-proto build-ui \
        test test-proto test-ui test-feed test-feed-bench test-submit test-search test-preview test-split test-typing test-frame test-net test-dns \
        test-args test-cli test-live test-pty test-pty-flood test-pty-rows \
        test-pty-restore test-pty-composer test-pty-composer-scroll test-pty-eof test-pty-connect \
        test-pty-demo-nick test-pty-linger test-pty-utf8 test-pty-minus \
        test-pty-tall test-pty-redial test-pty-rst test-pty-tinyquit test-pty-tabcut test-pty-paste50 \
        test-pty-bpaste test-pty-mixburst \
        test-pty-quitcap test-pty-tickrate test-pty-paintwake test-pty-joinlat \
        test-pty-manyeof test-pty-geneof test-pty-closequit test-pty-stall test-pty-escup \
        test-pty-tabswitch test-pty-alerts test-pty-linkclick test-pty-softwrap test-pty-mouseselect test-pty-preview test-pty-resize test-pty-settings test-pty-history test-pty-autoreconnect test-pty-disconnect-cleanup test-pty-split test-pty-split-composer test-pty-typing \
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

# Bend chooses one CC executable and supplies fixed arguments. Use Nix's
# salted flag seam for every generated binary, including actor test harnesses.
# A captured shell may lack HOST role markers, which ignore unsalted flags.
BIRC_TLS_CFLAGS ?= $(if $(BIRC_OPENSSL_DEV),-isystem $(BIRC_OPENSSL_DEV)/include)
BIRC_TLS_LDFLAGS ?= $(if $(BIRC_OPENSSL_LIB),-L$(BIRC_OPENSSL_LIB)/lib -rpath $(BIRC_OPENSSL_LIB)/lib -lssl -lcrypto)
OPENSSL ?= $(if $(BIRC_OPENSSL_BIN),$(BIRC_OPENSSL_BIN)/bin/openssl,openssl)
append_tls_flags = $(1)$(if $(2),$(if $(findstring $(2),$(1)),, $(2)))
ifneq ($(BIRC_NIX_CC_SUFFIX),)
export NIX_CFLAGS_COMPILE_$(BIRC_NIX_CC_SUFFIX) := $(call append_tls_flags,$(NIX_CFLAGS_COMPILE_$(BIRC_NIX_CC_SUFFIX)),$(BIRC_TLS_CFLAGS))
export NIX_LDFLAGS_$(BIRC_NIX_CC_SUFFIX) := $(call append_tls_flags,$(NIX_LDFLAGS_$(BIRC_NIX_CC_SUFFIX)),$(BIRC_TLS_LDFLAGS))
endif

build-proto: $(BLDDIR)/birc-proto ## Build the Bend protocol self-test binary.

# Bend emits one C TU (runtime + app). --help is Bend's runtime CLI;
# birc usage is --help-irc (args.bend).
BEND_UI_SRCS := $(wildcard src/bend/*.bend src/ffi/*.c src/ffi/*.h) src/ui/timui.h
BUILD_INPUTS := Makefile flake.nix flake.lock nix/birc.nix nix/media.nix nix/upload.nix nix/preferences.nix

# Incremental + parallel Bend builds (BUILD mode).
# Every Bend test binary is a real file target under $(BLDDIR)/ with prerequisites
# on its own tests/bend/<stem>.bend plus the import closure in
# build/<stem>.bend.d (scripts/bend-deps.sh). Until that file exists,
# BEND_SRC_DEPS is the fail-closed fallback. Phony test targets
# depend on those files and only run the golden/driver, so fresh outputs skip
# recompile. Missing sources fail closed (no rule / nonzero exit).
# Parallelism: the default above is one job per core. `make -jN check` overrides
# it. Each binary writes
# a distinct file, mkdir -p is parallel-safe, and check-golden logs use
# mktemp. `proof` has no file outputs and is safe to run concurrently with
# builds. Local iteration: `make -j$(nproc) check`. CI/bounded hosts:
# `MAKEFLAGS=-j2 make check`. Do not use `make -j` with `update` (pin move).
# .bend files inline C (`import "../ffi/*.c"`). BEND_SRC_DEPS is the
# fallback closure (every Bend and FFI input) used until a per-entry
# build/<stem>.bend.d exists. Link rules list BEND_UI_SRCS directly.
BEND_SRC_DEPS := $(BEND_UI_SRCS)
# Default native Bend test binary (180s bound).
$(BLDDIR)/%: tests/bend/%.bend $(BLDDIR)/%.bend.d
	$(NIXRUN) timeout 180 bend $< -o $@
# JS backend fixtures (180s bound).
$(BLDDIR)/%.js: tests/bend/%.bend $(BLDDIR)/%.bend.d
	$(NIXRUN) timeout 180 bend $< -o $@
# Second-backend review fixtures: build/<guard>_review.js from tests/bend/<guard>.bend.
$(BLDDIR)/%_review.js: tests/bend/%.bend $(BLDDIR)/%.bend.d
	$(NIXRUN) timeout 180 bend $< -o $@
# Generated C intermediates (default 300s bound; 180s overrides below).
$(BLDDIR)/%.c: tests/bend/%.bend $(BLDDIR)/%.bend.d
	$(NIXRUN) timeout 300 bend $< -o $@
# Import closure. Missing imports fail the script (nonzero) before mv.
# Through $(NIXRUN) like every other recipe: the scanner execs python3, and
# test-nix-preflight puts a `python3` on PATH that exits 77 so no rule can
# reach for an ambient interpreter. Regeneration only happens when a test
# source or the scanner changes, so the re-entry is not on the steady-state path.
$(BLDDIR)/%.bend.d: tests/bend/%.bend $(BIRC_MAKE_DIR)/scripts/bend-deps.sh
	@mkdir -p $(dir $@)
	BLDDIR='$(BLDDIR)' $(NIXRUN) sh $(BIRC_MAKE_DIR)/scripts/bend-deps.sh $< > $@.tmp
	mv $@.tmp $@
$(BLDDIR)/golden-layers.mk: $(BIRC_MAKE_DIR)/scripts/bend-deps.sh $(wildcard tests/bend/*.bend)
	@mkdir -p $(dir $@)
	BLDDIR='$(BLDDIR)' $(NIXRUN) sh $(BIRC_MAKE_DIR)/scripts/bend-deps.sh --layers > $@.tmp
	mv $@.tmp $@
# Keep closure files. A pattern-only prerequisite is otherwise intermediate
# and Make deletes it, which drops the next build back to the full fallback.
.SECONDARY: $(patsubst tests/bend/%.bend,$(BLDDIR)/%.bend.d,$(wildcard tests/bend/*.bend)) $(BLDDIR)/birc-proto.bend.d
$(BLDDIR)/birc-proto.bend.d: $(PROTO) $(BIRC_MAKE_DIR)/scripts/bend-deps.sh
	@mkdir -p $(dir $@)
	BLDDIR='$(BLDDIR)' $(NIXRUN) sh $(BIRC_MAKE_DIR)/scripts/bend-deps.sh $(PROTO) birc-proto > $@.tmp
	mv $@.tmp $@
# Absent closure files fall back to every Bend and FFI input.
define bend_dep_fallback
ifeq ($$(wildcard $(BLDDIR)/$(1).bend.d),)
$(BLDDIR)/$(1) $(BLDDIR)/$(1).js $(BLDDIR)/$(1).c $(BLDDIR)/$(1)_review.js: $$(BEND_SRC_DEPS)
endif
endef
$(foreach stem,$(patsubst tests/bend/%.bend,%,$(wildcard tests/bend/*.bend)),$(eval $(call bend_dep_fallback,$(stem))))
ifeq ($(wildcard $(BLDDIR)/birc-proto.bend.d),)
$(BLDDIR)/birc-proto: $(BEND_SRC_DEPS)
endif
# Slow compiles share one recipe. The seconds are expanded into `make -n`
# output; tests/build_deadlines.py reads that, not these call lines.
# auth_privacy: calm-host Bend build 92s, loaded laptop ~180s at the default
# 180s bound; 360 restores ~2x margin over worst observed.
define bend_slow_compile
$$(BLDDIR)/$(1): tests/bend/$(2).bend $$(BLDDIR)/$(2).bend.d
	$$(NIXRUN) timeout $(3) bend $$< -o $$@
endef
$(eval $(call bend_slow_compile,irc_commands,irc_commands,900))
$(eval $(call bend_slow_compile,message_split,message_split,900))
$(eval $(call bend_slow_compile,reconnect_recovery,reconnect_recovery,900))
$(eval $(call bend_slow_compile,reconnect_auth,reconnect_auth,900))
$(eval $(call bend_slow_compile,mode_privacy,mode_privacy,900))
$(eval $(call bend_slow_compile,reconnect_echoes,reconnect_echoes,900))
$(eval $(call bend_slow_compile,auth_privacy,auth_privacy,360))
$(eval $(call bend_slow_compile,composer_help,composer_help,900))
$(eval $(call bend_slow_compile,ipv6_transport_native,ipv6_transport_native,300))
$(eval $(call bend_slow_compile,richtext_demo,richtext_demo,90))
$(eval $(call bend_slow_compile,ui_input_queue.c,ui_input_queue,180))
$(eval $(call bend_slow_compile,demo_identity.c,demo_identity,180))
# Native binaries whose `bend -o` step also runs clang over a 10-13 MB generated
# C file. Calm-host measurements on an idle 8-core lane at -j1: live_context 58s
# (C 10.1 MB), net_demo 84s (C 13.0 MB). Each compile wants ~165% CPU because Bun
# is internally threaded, so at -j5 they exceed the 180s default. 360s follows the
# auth_privacy precedent (92s calm -> 360s, ~4x) rather than inventing a margin.
$(eval $(call bend_slow_compile,live_context,live_context,360))
$(eval $(call bend_slow_compile,net_demo,net_demo,360))
# Protocol self-test binary (file target; build-proto phony depends on it).
$(BLDDIR)/birc-proto: $(PROTO) $(BLDDIR)/birc-proto.bend.d
	$(NIXRUN) timeout 180 bend $(PROTO) -o $(BLDDIR)/birc-proto
# Generated-C link rules. $(4) is the shutdown-alias string, empty when unused.
define bend_cc_link
$$(BLDDIR)/$(1): $$(BLDDIR)/$(1).c $$(BEND_UI_SRCS) $$(BLDDIR)/build-config
	$$(NIXRUN) timeout $(2) sh -c '$$$$CC $(3) $(4) -Isrc/ui -Isrc/ffi $$(BLDDIR)/$(1).c -o $$(BLDDIR)/$(1)'
endef
$(eval $(call bend_cc_link,live_context_io,300,$$(BEND_CORE_CFLAGS),$$(SHUTDOWN_FFI_ALIASES)))
$(eval $(call bend_cc_link,deferred_actor,300,$$(BEND_CORE_CFLAGS),$$(SHUTDOWN_FFI_ALIASES)))
$(eval $(call bend_cc_link,deferred_frame,$$(BUILD_TIMEOUT),$$(DEFERRED_FRAME_CFLAGS),$$(SHUTDOWN_FFI_ALIASES)))
$(eval $(call bend_cc_link,shutdown_flush,300,$$(BEND_CORE_CFLAGS),$$(SHUTDOWN_FFI_ALIASES)))
$(eval $(call bend_cc_link,notify_attr_blocked,300,$$(BEND_CORE_CFLAGS),$$(SHUTDOWN_FFI_ALIASES)))
$(eval $(call bend_cc_link,notify_held_blocked,300,$$(BEND_CORE_CFLAGS),$$(SHUTDOWN_FFI_ALIASES)))
$(eval $(call bend_cc_link,ui_input_queue,180,$$(BEND_CORE_CFLAGS),))
$(eval $(call bend_cc_link,demo_identity,180,$$(BEND_CORE_CFLAGS),))
$(eval $(call bend_cc_link,ws_media_stage_native,300,$$(BEND_CORE_CFLAGS),$$(SHUTDOWN_FFI_ALIASES)))
$(eval $(call bend_cc_link,mss_stale_socket,300,$$(BEND_CORE_CFLAGS),$$(SHUTDOWN_FFI_ALIASES)))
$(eval $(call bend_cc_link,ws_carrier_native,300,$$(BEND_CORE_CFLAGS),$$(SHUTDOWN_FFI_ALIASES)))
$(eval $(call bend_cc_link,ws_upload_frame,$$(BUILD_TIMEOUT),$$(BEND_CORE_CFLAGS),$$(SHUTDOWN_FFI_ALIASES)))

.PHONY: test-irc-commands test-message-split test-reconnect-recovery test-reconnect-auth test-mode-privacy test-preferences test-preferences-pure test-preferences-helper test-preferences-io test-keychain-channels test-utc-time test-clock-local test-clock-local-native test-clock-local-native-ubsan

test-irc-commands: $(BLDDIR)/irc_commands
test-message-split: $(BLDDIR)/message_split
test-reconnect-recovery: $(BLDDIR)/reconnect_recovery
test-reconnect-auth: $(BLDDIR)/reconnect_auth
test-mode-privacy: $(BLDDIR)/mode_privacy
test-irc-commands test-message-split test-reconnect-recovery test-reconnect-auth test-mode-privacy: ## Recovery, trusted authentication, strict commands, and lossless message guards.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh scripts/check-golden.sh $(subst -,_,$(patsubst test-%,%,$@))=ok timeout 15 ./$(BLDDIR)/$(subst -,_,$(patsubst test-%,%,$@))

test-preferences-pure: $(BLDDIR)/preferences_demo $(BLDDIR)/preferences_io_demo ## Durable settings roundtrip without changing credentials or live state.
	$(NIXRUN) sh scripts/check-golden.sh preferences_demo=ok timeout 15 ./$(BLDDIR)/preferences_demo
	$(NIXRUN) sh scripts/check-golden.sh preferences_io_demo=ok timeout 15 ./$(BLDDIR)/preferences_io_demo

test-preferences-helper: ## Owned private files, safe atomic replacement, and strict schemas.
	$(NIXRUN) timeout 45 python3 tests/preferences.py

test-preferences-io: $(BLDDIR)/preferences_io_driver ## Real bounded helper IO, safe diagnostics, and disabled no-write control.
	$(NIXRUN) timeout 45 python3 tests/preferences_io.py ./$(BLDDIR)/preferences_io_driver

test-keychain-channels: ## Saved channel names and exact explicit CLI override, without JOIN keys.
	$(NIXRUN) timeout 30 python3 tests/keychain_channels.py

test-preferences: test-preferences-pure test-preferences-helper test-preferences-io test-keychain-channels ## Private preferences and saved endpoint channel names.

test-utc-time: $(BLDDIR)/utc_time ## Valid complete UTC dates and invalid/missing/duplicate server-time tags.
	$(NIXRUN) sh scripts/check-golden.sh utc_time=ok timeout 15 ./$(BLDDIR)/utc_time

test-clock-local: test-utc-time test-clock-local-native $(BLDDIR)/clock_local_demo ## Local log timestamps use the event date and preserve raw protocol input.
	$(NIXRUN) env TZ=Asia/Seoul sh scripts/check-golden.sh clock_local_demo=ok timeout 15 ./$(BLDDIR)/clock_local_demo

test-clock-local-native: ## libc date conversion, DST boundaries, leap seconds, and numeric FFI tuple ABI.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 60 sh -c '$$CC -std=c11 -O0 -Werror=vla -pedantic -Wall -Wextra -Werror -Itests/lint-ffi tests/clock_local.c -o $(BLDDIR)/clock_local'
	$(NIXRUN) sh scripts/check-golden.sh clock_local=ok timeout 15 ./$(BLDDIR)/clock_local

test-clock-local-native-ubsan: ## UBSan qualification of native local timestamp conversion.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 60 sh -c '$$CC -std=c11 -O0 -g -Werror=vla -pedantic -Wall -Wextra -Werror -fsanitize=undefined -fno-sanitize-recover=undefined -Itests/lint-ffi tests/clock_local.c -o $(BLDDIR)/clock_local_ubsan'
	$(NIXRUN) env UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 sh scripts/check-golden.sh clock_local=ok timeout 15 ./$(BLDDIR)/clock_local_ubsan

test-review-pure: test-irc-commands test-message-split test-reconnect-recovery test-reconnect-auth test-mode-privacy test-preferences test-clock-local
test-sanitizers: test-clock-local-native-ubsan

.PHONY: test-pty-local-time
test-pty-local-time: $(PTY_BUILD) ## Loopback event-local timestamps; PTY_APP can select an installed build.
	$(NIXRUN) timeout 30 python3 tests/pty/local_time.py $(PTY_APP)

.PHONY: test-reconnect-preferences test-preferences-runtime test-preferences-global
.PHONY: test-reconnect-registration
test-reconnect-registration: $(BLDDIR)/reconnect_registration ## First-welcome nickname assignment, forged controls, and authenticated full-room recovery.
	$(NIXRUN) sh scripts/check-golden.sh reconnect_registration=ok timeout 15 ./$(BLDDIR)/reconnect_registration
test-review-pure: test-reconnect-registration

.PHONY: test-join-plan test-pty-reconnect-recovery
test-join-plan: $(BLDDIR)/join_plan_demo ## Bounded desired channels, exact runtime keys, once-only flush, and auth diagnostics.
	$(NIXRUN) sh scripts/check-golden.sh join_plan_demo=ok timeout 15 ./$(BLDDIR)/join_plan_demo

test-pty-reconnect-recovery: $(PTY_BUILD) ## Manual/automatic SASL and NickServ recovery; settings and keyed channel guards.
	$(NIXRUN) timeout 60 python3 tests/pty/reconnect_recovery.py $(PTY_APP)
test-review-pure: test-join-plan

test-reconnect-preferences: $(BLDDIR)/reconnect_preferences ## Async channel loading, runtime key revisions, offline removal, and auth barrier.
	$(NIXRUN) sh scripts/check-golden.sh reconnect_preferences=ok timeout 15 ./$(BLDDIR)/reconnect_preferences

test-preferences-runtime: $(BLDDIR)/preferences_runtime_demo ## Bounded coalescing, stale completion isolation, and edit-wins loading.
	$(NIXRUN) sh scripts/check-golden.sh preferences_runtime_demo=ok timeout 15 ./$(BLDDIR)/preferences_runtime_demo

test-preferences-global: ## Offline global settings never create a fabricated server profile.
	$(NIXRUN) timeout 45 python3 tests/preferences_global.py

test-preferences: test-preferences-runtime test-preferences-global
test-review-pure: test-reconnect-preferences

.PHONY: test-reconnect-echoes test-upload-diagnostics test-preferences-live test-preferences-channels test-preferences-package
test-reconnect-echoes: $(BLDDIR)/reconnect_echoes ## Delayed membership echoes preserve intent and valid server prefixes authenticate.
	$(NIXRUN) sh scripts/check-golden.sh reconnect_echoes=ok timeout 15 ./$(BLDDIR)/reconnect_echoes

test-upload-diagnostics: $(BLDDIR)/upload_diagnostics ## Numeric HTTP rejection details without exposing helper bodies or paths.
	$(NIXRUN) sh scripts/check-golden.sh upload_diagnostics=ok timeout 15 ./$(BLDDIR)/upload_diagnostics
	$(NIXRUN) timeout 45 python3 tests/upload_diagnostics.py

test-preferences-live: $(BLDDIR)/preferences_live_demo.js ## Stored channel scope, explicit overrides, and Session preference application.
	$(NIXRUN) sh scripts/check-golden.sh preferences_live_demo=ok timeout 30 bun $(BLDDIR)/preferences_live_demo.js

.PHONY: test-preferences-return-live
test-preferences-return-live: $(BLDDIR)/preferences_return_live.js ## A returning endpoint restores cached names and releases held JOINs once.
	$(NIXRUN) sh scripts/check-golden.sh preferences_return_live=ok timeout 30 bun $(BLDDIR)/preferences_return_live.js
test-preferences: test-preferences-return-live

.PHONY: test-history-startup test-history-startup-divider test-startup-headless test-startup-headless-io test-action-budget-admission
test-history-startup: $(BLDDIR)/history_startup.js
test-history-startup-divider: $(BLDDIR)/history_startup_divider.js
test-startup-headless: $(BLDDIR)/startup_headless.js
test-history-startup test-history-startup-divider test-startup-headless: ## Startup snapshot preservation, bounded dividers, and once-only settings.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh scripts/check-golden.sh $(subst -,_,$(patsubst test-%,%,$@))=ok timeout 30 bun $(BLDDIR)/$(subst -,_,$(patsubst test-%,%,$@)).js

test-startup-headless-io: $(BLDDIR)/startup_headless_io.js ## Owned archive and one fake helper resolve history policy before headless registration.
	$(NIXRUN) timeout 45 python3 tests/startup_headless.py bun $(BLDDIR)/startup_headless_io.js
test-action-budget-admission: $(BLDDIR)/action_budget.js ## Reject zero ACTION body budgets and malformed wire targets.
	$(NIXRUN) sh scripts/check-golden.sh action_budget=ok timeout 30 bun $(BLDDIR)/action_budget.js
test-review-pure: test-history-startup test-history-startup-divider test-startup-headless test-startup-headless-io test-action-budget-admission

.PHONY: test-join-capacity
test-join-capacity: $(BLDDIR)/join_capacity.js ## Raw/local JOIN admission is atomic at the 14-channel recovery limit.
	$(NIXRUN) sh scripts/check-golden.sh join_capacity=ok timeout 30 bun $(BLDDIR)/join_capacity.js
test-review-pure: test-join-capacity

.PHONY: test-live-context test-live-context-io test-history-startup-io test-deferred-actor
test-live-context: $(BLDDIR)/live_context.js ## Generation-scoped startup gate and stale archive admission guards.
	$(NIXRUN) sh scripts/check-golden.sh live_context=ok timeout 30 bun $(BLDDIR)/live_context.js

test-live-context-io: $(BLDDIR)/live_context_io ## Native archive completions, no-write controls, and import checkpoint effects.
	$(NIXRUN) timeout 180 python3 tests/live_context.py ./$(BLDDIR)/live_context_io

test-history-startup-io: $(BLDDIR)/history_startup_io.js ## Owned archive worker preserves exact endpoint and typed request identity.
	$(NIXRUN) timeout 35 python3 tests/history_startup_io.py bun $(BLDDIR)/history_startup_io.js

.PHONY: test-history-startup-boundary
test-history-startup-boundary: $(BLDDIR)/history_startup_boundary.js ## Full 1024-row startup snapshots retain their oldest allowed archive record.
	$(NIXRUN) timeout 45 python3 tests/history_startup_boundary.py bun $(BLDDIR)/history_startup_boundary.js

test-deferred-actor: $(BLDDIR)/deferred_actor ## Held and canceled native actors close without dialing and acknowledge the writer.
	$(NIXRUN) sh scripts/check-golden.sh deferred_actor=ok timeout 20 ./$(BLDDIR)/deferred_actor

.PHONY: test-deferred-frame test-deferred-frame-native
# Keep this callback diagnostic unoptimized; the actual application and
# burst-command PTY guard are separately qualified with the normal -O2 build.
DEFERRED_FRAME_CFLAGS ?= -std=c11 -O0 -pthread -w
test-deferred-frame: ## Last-frame changes defer one repaint, preserving ACK, output, idle, and halt policy.
	@mkdir -p $(BLDDIR)
	$(MAKE) test-deferred-frame-native

test-deferred-frame-native: $(BLDDIR)/deferred_frame ## Compile/run the existing generated callback guard; BUILD_TIMEOUT bounds retries.
	@test -s $(BLDDIR)/deferred_frame.c
	$(NIXRUN) sh scripts/check-golden.sh 'deferred_frame=ok cases=8' timeout 20 ./$(BLDDIR)/deferred_frame
test-review-pure: test-deferred-frame

test-review-pure: test-live-context test-live-context-io test-history-startup-io test-history-startup-boundary test-deferred-actor

test-preferences-channels: ## Channel prefixes require a name and never contain persisted JOIN keys.
	$(NIXRUN) timeout 45 python3 tests/preferences_channels.py

test-preferences-package: ## Provisioned preference helper uses literal arguments and private synthetic files.
	$(NIXRUN) timeout 60 python3 tests/preferences_package.py $(PREFS_HELPER)

.PHONY: test-session-preferences-intent
test-session-preferences-intent: $(BLDDIR)/session_preferences_intent ## Accepted settings commands retain explicit intent even when values do not change.
	$(NIXRUN) sh scripts/check-golden.sh session_preferences_intent=ok timeout 15 ./$(BLDDIR)/session_preferences_intent

test-preferences: test-preferences-live test-preferences-channels test-preferences-package
test-review-pure: test-reconnect-echoes test-upload-diagnostics test-session-preferences-intent

.PHONY: test-launch-channels test-reconnect-endpoint
test-launch-channels: $(BLDDIR)/launch_channels
test-reconnect-endpoint: $(BLDDIR)/reconnect_endpoint
test-launch-channels test-reconnect-endpoint: ## Names-only CSV launch lists and exact host/port runtime scope.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh scripts/check-golden.sh $(subst -,_,$(patsubst test-%,%,$@))=ok timeout 15 ./$(BLDDIR)/$(subst -,_,$(patsubst test-%,%,$@))
test-review-pure: test-launch-channels test-reconnect-endpoint
test-review-pure: test-server-id test-ipv6 test-ipv6-glue test-ipv6-transport
test-review-pure: test-drafts
test-review-pure: test-media-cards test-cards-policy test-cards-view test-session-cards

.PHONY: test-pty-upload-diagnostics
test-pty-upload-diagnostics: $(PTY_BUILD) ## Actual log shows only canonical HTTP status and accepts synthetic HTML success.
	$(NIXRUN) timeout 40 python3 tests/pty/upload_diagnostics.py $(PTY_APP)

.PHONY: test-pty-preferences
test-pty-preferences: $(PTY_BUILD) ## Delayed preference read, same-value edits, channel scope, and latest-save quit.
	$(NIXRUN) timeout 90 python3 tests/pty/preferences.py $(PTY_APP)

.PHONY: test-pty-preferences-history
test-pty-preferences-history: $(PTY_BUILD) ## Saved history policy and caps apply before restore, without duplicate appends.
	$(NIXRUN) timeout 100 python3 tests/pty/preferences_history.py $(PTY_APP)

.PHONY: test-pty-recovery-settings
test-pty-recovery-settings: test-pty-local-time test-pty-reconnect-recovery test-pty-upload-diagnostics test-pty-preferences test-pty-preferences-history test-pty-deferred-redraw ## Recovery/settings terminal qualification; optional PTY_APP selects the app.

.PHONY: test-pty-deferred-redraw
test-pty-deferred-redraw: $(PTY_BUILD) ## Last burst command paints, with bounded idle frames and restored shutdown.
	$(NIXRUN) timeout 45 python3 tests/pty/deferred_redraw.py $(PTY_APP)

.PHONY: test-pty-image-marker
test-pty-image-marker: $(PTY_BUILD) ## Ghostty images, no-graphics/multiplexer fallback, and rejected helper diagnostics.
	$(NIXRUN) timeout 60 python3 tests/pty/image_marker.py $(PTY_APP)

.PHONY: FORCE test-golden-runner test-build-config test-pty-deadlines test-dns-tcp test-socket-deadline test-state test-history test-links test-auth test-commands test-server-time test-pty-output-stall
.PHONY: test-keychain-tls test-build-tls test-tls-args test-endpoint test-connect-endpoint test-pty-tls test-tls test-tls-native test-tls-native-ubsan lint-tls
test-keychain-tls: ## Offline TLS profile selection, credential isolation, and literal child argv.
	$(NIXRUN) timeout 30 python3 tests/keychain_tls.py

test-build-tls: ## TLS compiler flags reach Bend binaries and invalidate cached builds correctly.
	$(NIXRUN) timeout 30 python3 tests/build_tls.py

test-tls-args: $(BLDDIR)/tls_args ## Secure defaults, mode conflicts, explicit-port order, and plaintext controls.
	$(NIXRUN) sh scripts/check-golden.sh tls_args=ok timeout 15 ./$(BLDDIR)/tls_args

test-endpoint: $(BLDDIR)/endpoint_demo ## Shared host:port syntax, DNS bounds, and conflicting-port controls.
	$(NIXRUN) sh scripts/check-golden.sh endpoint_demo=ok timeout 15 ./$(BLDDIR)/endpoint_demo

test-connect-endpoint: $(BLDDIR)/connect_endpoint ## Slash host:port parsing and saved-port inheritance without transport inference.
	$(NIXRUN) sh scripts/check-golden.sh connect_endpoint=ok timeout 15 ./$(BLDDIR)/connect_endpoint

test-pty-tls: build-ui ## Owned loopback TLS: certificate/name checks, auth, reconnect, and bounded quit.
	$(NIXRUN) timeout 120 python3 -u tests/pty/tls.py ./$(BLDDIR)/birc $(OPENSSL)

TLS_NATIVE_CFLAGS := -std=c11 -O0 -Werror=vla -pedantic -Wall -Wextra -Werror
test-tls-native: ## OpenSSL certificate, retry, deadline, affine ownership, and actual IO queue controls.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'set -eu; for guard in tls_native tls_ffi; do timeout 60 $$CC $(TLS_NATIVE_CFLAGS) tests/$$guard.c -o $(BLDDIR)/$$guard; sh scripts/check-golden.sh $$guard=ok timeout 30 ./$(BLDDIR)/$$guard; done'

test-tls-native-ubsan: ## UBSan: native TLS verification, retry buffers, and effect/queue ownership.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'set -eu; for guard in tls_native tls_ffi; do timeout 60 $$CC $(TLS_NATIVE_CFLAGS) -g -fsanitize=undefined -fno-sanitize-recover=undefined tests/$$guard.c -o $(BLDDIR)/$${guard}_ubsan; UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 sh scripts/check-golden.sh $$guard=ok timeout 30 ./$(BLDDIR)/$${guard}_ubsan; done'

lint-tls: ## Strict syntax-only lint of the actual TLS bridge and effect ABI fixture.
	$(NIXRUN) timeout 60 sh -c '$$CC $(LINT_FFI_CFLAGS) -Werror=vla tests/tls_ffi.c'

test-tls: test-keychain-tls test-build-tls test-tls-args test-endpoint test-connect-endpoint test-tls-native test-pty-tls ## TLS policy, tooling, and loopback qualification; no public IRC or credentials.
test-review-pure: test-keychain-tls test-build-tls test-tls-args test-endpoint test-connect-endpoint test-tls-native
test-sanitizers: test-tls-native-ubsan
lint-ffi: lint-tls
.PHONY: test-media-image test-media-policy test-media-view test-media-anchor test-media-native test-media-portable test-media-native-ubsan test-pty-media test-pty-diagnostic test-formatting test-formatting-painter test-wire-style test-theme test-diagnostic test-diagnostic-buffer test-diagnostic-submit test-diagnostic-session test-diagnostic-restore test-diagnostic-io test-history-save-errors test-reader-errors test-clipboard-errors

test-media-image: ## Check synthetic image formats, animation, fetch bounds, and public-host policy.
	$(NIXRUN) timeout 30 python3 tests/media_image.py

test-media-cards: ## Bounded OpenGraph cards: fetch policy, shared cache budget, final-base hits.
	$(NIXRUN) timeout 120 python3 tests/media_cards.py

test-cards-policy: $(BLDDIR)/cards_policy ## Card eligibility, scheduling, and fullscreen policy goldens.
	$(NIXRUN) sh scripts/check-golden.sh cards_policy=ok ./$(BLDDIR)/cards_policy

test-cards-view: $(BLDDIR)/cards_view ## Card visible scheduling and fullscreen view goldens.
	$(NIXRUN) sh scripts/check-golden.sh cards_view=ok ./$(BLDDIR)/cards_view

.PHONY: test-session-cards
test-session-cards: $(BLDDIR)/session_cards_demo.js ## Cards/fullscreen Session adapter goldens (JS): scheduling, worker, stale paths, closure, wire.
	$(NIXRUN) sh scripts/check-golden.sh session_cards_demo=ok timeout 60 bun $(BLDDIR)/session_cards_demo.js

.PHONY: test-media-image-cache
test-media-image-cache: ## Private bounded cache reuses validated remote assets without a network fetch.
	$(NIXRUN) timeout 30 python3 tests/media_image_cache.py

test-review-pure: test-media-image-cache

.PHONY: test-upload test-upload-helper test-upload-policy test-upload-session test-upload-io test-upload-hint test-upload-native test-upload-native-ubsan test-pty-upload test-upload-package
test-upload-helper: ## Offline upload transport: source, TLS, streaming, deadlines, and safe URL output.
	$(NIXRUN) timeout 30 python3 tests/upload.py

test-upload-policy: $(BLDDIR)/upload_demo ## Local path parsing, per-file consent, single-worker ownership, and stale results.
	$(NIXRUN) sh scripts/check-golden.sh upload_demo=ok timeout 15 ./$(BLDDIR)/upload_demo

test-upload-session: $(BLDDIR)/upload_session ## Session consent, ordinary drafts/history/completion, and private dropped paths.
	$(NIXRUN) sh scripts/check-golden.sh upload_session=ok timeout 15 ./$(BLDDIR)/upload_session

.PHONY: test-composer-help
test-composer-help: $(BLDDIR)/composer_help ## Composer ghost/menu; typed shortcodes stay raw; Tab/Right accept glyphs.
	$(NIXRUN) sh scripts/check-golden.sh composer_help=ok timeout 30 ./$(BLDDIR)/composer_help

test-review-pure: test-composer-help

.PHONY: test-upload-dispatch
test-upload-dispatch: $(BLDDIR)/upload_dispatch ## Unknown slash commands keep priority over ambiguous local drops.
	$(NIXRUN) sh scripts/check-golden.sh upload_dispatch=ok timeout 15 ./$(BLDDIR)/upload_dispatch

test-review-pure: test-upload-dispatch

test-upload-io: $(BLDDIR)/upload_io_demo ## Literal helper selection and numeric-only failure diagnostics.
	$(NIXRUN) sh scripts/check-golden.sh upload_io_demo=ok timeout 15 ./$(BLDDIR)/upload_io_demo

test-upload-hint: $(BLDDIR)/upload_hint ## Transient public-upload status preserves the ordinary composer draft.
	$(NIXRUN) sh scripts/check-golden.sh upload_hint=ok timeout 15 ./$(BLDDIR)/upload_hint

test-upload-native: ## Actual FFI returns Esc/F8 to Bend without bypassing fatal-output cleanup.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'timeout 60 $$CC -std=c11 -O0 -Werror=vla -pedantic -Wall -Wextra -Werror -pthread -Isrc/ui -Isrc/ffi tests/upload_keys.c -o $(BLDDIR)/upload_keys'
	$(NIXRUN) sh scripts/check-golden.sh upload_keys=ok timeout 15 ./$(BLDDIR)/upload_keys

test-upload-native-ubsan: ## UBSan: raw upload keys and fatal-output cleanup ownership.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'timeout 60 $$CC -std=c11 -O0 -g -Werror=vla -pedantic -Wall -Wextra -Werror -pthread -fsanitize=undefined -fno-sanitize-recover=undefined -Isrc/ui -Isrc/ffi tests/upload_keys.c -o $(BLDDIR)/upload_keys_ubsan'
	$(NIXRUN) sh -c 'UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 sh scripts/check-golden.sh upload_keys=ok timeout 15 ./$(BLDDIR)/upload_keys_ubsan'

test-pty-upload: build-ui ## Loopback upload consent, paste refusal, drafts, stale scope, and bounded quit.
	$(NIXRUN) timeout 120 python3 tests/pty/upload.py ./$(BLDDIR)/birc

.PHONY: test-pty-upload-preferences-private
test-pty-upload-preferences-private: $(PTY_BUILD) ## Owned settings-enabled upload and refusal; standalone, optional PTY_APP selects app.
	$(NIXRUN) sh -c 'set -eu; helper="$$(command -v birc-preferences)"; for mode in coalesced full all; do timeout 120 python3 tests/pty/upload_preferences_private.py "$$1" "$$helper" "$$mode"; done' sh "$(PTY_APP)"

test-upload: test-upload-helper test-upload-policy test-upload-session test-upload-dispatch test-upload-io test-upload-hint test-upload-native test-pty-upload ## Offline and actual-loop public-upload qualification; never uploads to the public service.
test-review-pure: test-upload-helper test-upload-policy test-upload-session test-upload-io test-upload-hint test-upload-native
test-sanitizers: test-upload-native-ubsan

test-server-time: $(BLDDIR)/server_time_demo ## IRCv3 time tags reach parsed message timestamps.
	$(NIXRUN) sh scripts/check-golden.sh server_time_demo=ok ./$(BLDDIR)/server_time_demo

test-diagnostic: test-diagnostic-buffer test-diagnostic-submit test-diagnostic-session test-diagnostic-restore test-diagnostic-io test-diagnostic-wire $(BLDDIR)/diagnostic_demo ## Log bounds, privacy, wire isolation, commands, retention, and IO controls.
	$(NIXRUN) sh scripts/check-golden.sh diagnostic_demo=ok ./$(BLDDIR)/diagnostic_demo

.PHONY: test-diagnostic-wire
test-diagnostic-buffer: $(BLDDIR)/diagnostic_buffer
test-diagnostic-submit: $(BLDDIR)/diagnostic_submit
test-diagnostic-session: $(BLDDIR)/diagnostic_session
test-diagnostic-restore: $(BLDDIR)/diagnostic_restore
test-diagnostic-io: $(BLDDIR)/diagnostic_io
test-diagnostic-wire: $(BLDDIR)/diagnostic_wire
test-diagnostic-buffer test-diagnostic-submit test-diagnostic-session test-diagnostic-restore test-diagnostic-io test-diagnostic-wire:
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh scripts/check-golden.sh $(subst -,_,$(patsubst test-%,%,$@))=ok timeout 15 ./$(BLDDIR)/$(subst -,_,$(patsubst test-%,%,$@))

test-history-save-errors: $(BLDDIR)/history_save_errors ## Surface failed history saves; preserve successful, empty, and disabled writes.
	$(NIXRUN) timeout 30 python3 tests/history_save_errors.py ./$(BLDDIR)/history_save_errors

.PHONY: test-ws-history-enqueue
test-ws-history-enqueue: $(BLDDIR)/ws_history_enqueue ## Full HistJob channel sync-appends; sync-fail keeps extract baseline.
	$(NIXRUN) timeout 60 python3 tests/ws_history_enqueue.py ./$(BLDDIR)/ws_history_enqueue

test-reader-errors: $(BLDDIR)/reader_errors ## Socket-read failure, orderly EOF, and no-data branch controls.
	$(NIXRUN) sh scripts/check-golden.sh reader_errors=ok timeout 15 ./$(BLDDIR)/reader_errors

test-clipboard-errors: $(BLDDIR)/clipboard_errors ## Clipboard helper success, failure, timeout, and privacy controls.
	$(NIXRUN) timeout 30 python3 tests/clipboard_errors.py ./$(BLDDIR)/clipboard_errors

test-media-policy: $(BLDDIR)/media_policy ## Bounded image requests, opt-out, stale results, and exact URL eligibility.
	$(NIXRUN) sh scripts/check-golden.sh media_policy=ok ./$(BLDDIR)/media_policy

.PHONY: test-media-terminal
test-media-terminal: $(BLDDIR)/media_terminal.js ## Unsupported terminals preserve URLs, skip helpers, and log once.
	$(NIXRUN) sh scripts/check-golden.sh media_terminal=ok timeout 30 bun $(BLDDIR)/media_terminal.js

test-review-pure: test-media-terminal

.PHONY: test-media-history test-pty-history-images
test-media-history: $(BLDDIR)/media_history.js ## Visible restored images share live admission without changing history or focus.
	$(NIXRUN) sh scripts/check-golden.sh media_history=ok timeout 30 bun $(BLDDIR)/media_history.js

test-pty-history-images: $(PTY_BUILD) ## Pty: async visible history images, shared worker, opt-out, and stale results.
	$(NIXRUN) timeout 75 python3 tests/pty/history_images.py $(PTY_APP)

test-review-pure: test-media-history

.PHONY: test-media-regressions-js
# Existing pure assertions use a second backend without repeated native
# optimization. The production app and terminal guards still use normal -O2.
test-media-regressions-js: $(BLDDIR)/media_policy_review.js $(BLDDIR)/media_view_review.js $(BLDDIR)/media_anchor_review.js $(BLDDIR)/media_branches_review.js $(BLDDIR)/viewport_tail_review.js $(BLDDIR)/m20_media_review.js $(BLDDIR)/m20_state_review.js $(BLDDIR)/ui_review_view_review.js ## Run unchanged media, viewport, and state fixtures with the JS backend.
	$(NIXRUN) sh -c 'set -eu; for guard in media_policy media_view media_anchor media_branches viewport_tail m20_media m20_state ui_review_view; do sh scripts/check-golden.sh $${guard}=ok timeout 30 bun $(BLDDIR)/$${guard}_review.js; done'

test-media-view: $(BLDDIR)/media_view ## Image rows share wrapping, scrolling, split panes, and resize coordinates.
	$(NIXRUN) sh scripts/check-golden.sh media_view=ok ./$(BLDDIR)/media_view

test-media-anchor: $(BLDDIR)/media_anchor ## Manual error/completion anchors and distinct split-pane image clipping.
	$(NIXRUN) sh scripts/check-golden.sh media_anchor=ok timeout 15 ./$(BLDDIR)/media_anchor

.PHONY: test-media-branches test-viewport-tail test-input-wake test-pty-esc-resize-wake
test-media-branches: $(BLDDIR)/media_branches ## Exact fallback rows and multi-link image partitioning.
	$(NIXRUN) sh scripts/check-golden.sh media_branches=ok timeout 15 ./$(BLDDIR)/media_branches

test-viewport-tail: $(BLDDIR)/viewport_tail ## Compare live-bottom and paused viewports against complete legacy rows.
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

test-formatting: $(BLDDIR)/formatting_demo ## Rich style composition, emoji aliases, exact URLs, and raw-source guards.
	$(NIXRUN) sh scripts/check-golden.sh formatting_demo=ok ./$(BLDDIR)/formatting_demo

test-theme: $(BLDDIR)/theme_demo $(BLDDIR)/theme_emoji $(BLDDIR)/theme_notify ## Theme palettes, desktop-notification policy, and extended emoji aliases.
	$(NIXRUN) sh scripts/check-golden.sh theme_demo=ok timeout 30 ./$(BLDDIR)/theme_demo
	$(NIXRUN) sh scripts/check-golden.sh theme_emoji=ok timeout 30 ./$(BLDDIR)/theme_emoji
	$(NIXRUN) sh scripts/check-golden.sh theme_notify=ok timeout 30 ./$(BLDDIR)/theme_notify

test-formatting-painter: build-ui ## Actual terminal attributes, aliases, and opaque hyperlink targets.
	$(NIXRUN) timeout 15 python3 tests/formatting_painter.py ./$(BLDDIR)/birc fixtures/formatting.irc

test-wire-style: $(BLDDIR)/wire_style ## Native IRC wire formatting, mIRC colors, safe controls, exact URLs.
	$(NIXRUN) sh scripts/check-golden.sh wire_style=ok timeout 15 ./$(BLDDIR)/wire_style

.PHONY: test-g3-framed test-g3-traversal
test-g3-framed: $(BLDDIR)/g3_framed.js ## Styled MODE/credential/mention/KICK/media framed Feed/History guards (JS).
	$(NIXRUN) sh scripts/check-golden.sh g3_framed=ok timeout 60 bun $(BLDDIR)/g3_framed.js

test-g3-traversal: $(BLDDIR)/g3_traversal.js ## Fr->Session traversal + live media path for G3 pairs (JS).
	$(NIXRUN) sh scripts/check-golden.sh g3_traversal=ok timeout 60 bun $(BLDDIR)/g3_traversal.js
test-review-pure: test-g3-framed test-g3-traversal
FORCE:

$(BLDDIR)/build-config: FORCE scripts/build-config.sh
	$(NIXRUN) sh scripts/build-config.sh $@ '$(BEND_CORE_CFLAGS)' '$(SANITIZER_CFLAGS)'

# Cache lookups need `bend` on PATH. Outside the dev shell that means one
# nix develop when BIRC_UI_CACHE=1; left off, restore is a local miss.
ifeq ($(BIRC_UI_CACHE),1)
BIRC_UI_CACHE_RUN := $(NIXRUN)
else
BIRC_UI_CACHE_RUN :=
endif
# Client codegen measured 761s wall on a loaded host (2026-10-18, 33MB C).
# A 300s cap dies with Error 124 before bend prints anything. 1200 leaves
# margin for that load without treating a quiet type error as a hang.
$(BLDDIR)/birc_bend.c: $(APP) $(BEND_UI_SRCS) $(BUILD_INPUTS) $(BLDDIR)/build-config
	@rc=0; $(BIRC_UI_CACHE_RUN) sh $(BIRC_MAKE_DIR)/scripts/build-ui-cache.sh restore $(BLDDIR) || rc=$$?; \
	if [ $$rc -eq 0 ]; then \
	  touch $(BLDDIR)/birc $(BLDDIR)/birc_bend.c; \
	elif [ $$rc -eq 1 ]; then \
	  $(NIXRUN) timeout 1200 bend $(APP) -o $(BLDDIR)/birc_bend.c; \
	else \
	  exit $$rc; \
	fi

$(BLDDIR)/birc: $(BLDDIR)/birc_bend.c $(BLDDIR)/build-config
	@rc=0; $(BIRC_UI_CACHE_RUN) sh $(BIRC_MAKE_DIR)/scripts/build-ui-cache.sh restore $(BLDDIR) || rc=$$?; \
	if [ $$rc -eq 0 ]; then \
	  touch $(BLDDIR)/birc; \
	elif [ $$rc -eq 1 ]; then \
	  $(NIXRUN) timeout $(BUILD_TIMEOUT) sh -c '$$CC $(BEND_CORE_CFLAGS) -Isrc/ui -Isrc/ffi $(BLDDIR)/birc_bend.c -o $(BLDDIR)/birc'; \
	  $(BIRC_UI_CACHE_RUN) sh $(BIRC_MAKE_DIR)/scripts/build-ui-cache.sh store $(BLDDIR); \
	else \
	  exit $$rc; \
	fi

build-ui: $(BLDDIR)/birc ## Build Bend TimUI client (src/bend/app.bend).

build: build-proto build-ui ## Build protocol harness and TimUI client.

.PHONY: build-package test-package test-keychain-package test-tls-package test-notify-package test-runtime-helpers-package
build-package: ## Build the installed Nix package and helper without changing pins (15-minute bound).
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 900 $(NIX) $(NIX_FEATURES) build --option timeout 900 --no-update-lock-file .\#birc --out-link $(BLDDIR)/package-birc

test-package: build-package ## Check installed helper overrides, local images, trust, and clean-environment startup.
	$(NIXRUN) timeout 75 python3 tests/package.py ./$(BLDDIR)/package-birc

test-keychain-package: build-package ## Installed launcher provenance, clean help, and pre-Keychain refusal controls.
	$(NIXRUN) timeout 30 python3 tests/keychain_package.py ./$(BLDDIR)/package-birc

test-tls-package: build-package ## Installed TLS trust, pinned OpenSSL linkage, and clean-PATH fail-closed controls.
	$(NIXRUN) timeout 45 sh -c 'python3 tests/package_tls.py ./$(BLDDIR)/package-birc "$$BIRC_OPENSSL_LIB"'

test-upload-package: build-package ## Installed uploader provenance, CA trust, clean PATH, and loopback override controls.
	$(NIXRUN) timeout 30 python3 tests/upload_package.py ./$(BLDDIR)/package-birc
	$(NIXRUN) timeout 120 python3 tests/pty/upload.py ./$(BLDDIR)/package-birc/bin/birc

test-notify-package: build-package ## Installed notify helper provenance, clean-PATH delivery, and quiet no-helper retention.
	$(NIXRUN) timeout 600 python3 tests/notify_package.py ./$(BLDDIR)/package-birc

test-runtime-helpers-package: build-package ## Installed cards/search/preferences provenance and local dispatch (standalone until qualified).
	$(NIXRUN) timeout 120 python3 tests/runtime_helpers_package.py ./$(BLDDIR)/package-birc

test-proto: build-proto ## Run Bend protocol golden harness.
	$(NIXRUN) sh scripts/check-golden.sh proto_demo=ok ./$(BLDDIR)/birc-proto

test-golden-runner: ## Reject failing, missing-token, and timed-out golden programs.
	$(NIXRUN) sh tests/golden_runner.sh

test-build-config: ## Verify header dependencies and changed/unchanged compiler flags.
	$(NIXRUN) timeout 30 python3 tests/build_config.py

.PHONY: test-build-deadlines test-m20-state test-m20-media test-m20-native test-m20-native-ubsan test-m20 test-pty-m20-media-cache test-pty-preview-retry
test-build-deadlines: ## Require a positive deadline on every Bend compiler recipe.
	$(NIXRUN) timeout 30 python3 tests/build_deadlines.py

test-m20-state: $(BLDDIR)/m20_state ## Canonical identities, reconnect members, AUTH, split, and command metadata.
	$(NIXRUN) sh scripts/check-golden.sh m20_state=ok timeout 30 ./$(BLDDIR)/m20_state

test-m20-media: $(BLDDIR)/m20_media ## Bend retained image tokens for refresh, capacity, failures, and stale targets.
	$(NIXRUN) sh scripts/check-golden.sh m20_media=ok timeout 30 ./$(BLDDIR)/m20_media

test-m20-native: ## Complete large selection and native payload ownership follow Bend policy.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'set -eu; for guard in m20_selection m20_media_cache ghost_width; do timeout 60 $$CC -std=c11 -O0 -Werror=vla -Wall -Wextra -Werror -pthread -Isrc/ui -Isrc/ffi tests/$$guard.c -o $(BLDDIR)/$$guard; sh scripts/check-golden.sh $$guard=ok timeout 15 ./$(BLDDIR)/$$guard; done'

test-m20-native-ubsan: ## UBSan: large-cluster selection and payload-retention boundaries.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'set -eu; for guard in m20_selection m20_media_cache ghost_width; do timeout 60 $$CC -std=c11 -O0 -g -fno-omit-frame-pointer -Werror=vla -Wall -Wextra -Werror -pthread -fsanitize=undefined -fno-sanitize-recover=undefined -Isrc/ui -Isrc/ffi tests/$$guard.c -o $(BLDDIR)/$${guard}_ubsan; UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 sh scripts/check-golden.sh $$guard=ok timeout 15 ./$(BLDDIR)/$${guard}_ubsan; done'

test-m20: test-build-deadlines test-m20-state test-m20-media test-m20-native ## Fresh deep-review correctness and cleanup gates.
test-m20: test-dns-validation test-cli-diagnostics test-ui-review-columns test-ui-review-widgets test-png-16bit-oom
test-m20: test-shutdown-ack test-shutdown-flush

.PHONY: test-shutdown-ack test-shutdown-flush
test-shutdown-ack: $(BLDDIR)/shutdown_ack ## Only the current writer completion can acknowledge UI shutdown.
	$(NIXRUN) sh scripts/check-golden.sh shutdown_ack=ok timeout 15 ./$(BLDDIR)/shutdown_ack

# The pinned compiler namespaces constructors by the fixture import path.
# Keep these test-only aliases out of the production thin FFI.
SHUTDOWN_FFI_ALIASES := $(foreach op,COL LNK SPN OPBOX OPSPLIT OPTEXT OPTABS OPLINE OPIMAGE OPMEDIA OPGHOST,-DCID_VIEW_$(op)=CID_______SRC_BEND_VIEW_$(op))
test-shutdown-flush: $(BLDDIR)/shutdown_flush ## Actual socket half-close/stale EOF cannot bypass queued QUIT or idle writer completion.
	$(NIXRUN) timeout 15 python3 tests/net/shutdown_flush.py ./$(BLDDIR)/shutdown_flush

.PHONY: test-dns-validation test-cli-diagnostics test-ui-review-columns test-ui-review-widgets test-png-16bit-oom test-ui-review-widgets-ubsan test-png-16bit-oom-ubsan
test-dns-validation: $(BLDDIR)/dns_validation ## Reject opcode and truncated-reply identity errors before TCP fallback.
	$(NIXRUN) sh scripts/check-golden.sh dns_validation=ok timeout 30 ./$(BLDDIR)/dns_validation

test-cli-diagnostics: build-ui ## Exact single CLI error diagnostics and normal headless startup.
	$(NIXRUN) timeout 30 python3 tests/cli_diagnostics.py ./$(BLDDIR)/birc

test-ui-review-widgets: ## Whole-cluster tab geometry and code-widget painting/style guards.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'timeout 60 $$CC -std=c11 -O0 -Werror=vla -pedantic -Wall -Wextra -Werror -Isrc/ui tests/ui_review_widgets.c -o $(BLDDIR)/ui_review_widgets'
	$(NIXRUN) sh scripts/check-golden.sh ui_review_widgets=ok timeout 15 ./$(BLDDIR)/ui_review_widgets

test-ui-review-columns: test-ui-review-widgets $(BLDDIR)/ui_review_columns ## Bend/native whole-cluster width and boundary parity, plus wrapping.
	$(NIXRUN) sh scripts/check-golden.sh ui_review_columns=ok timeout 30 ./$(BLDDIR)/ui_review_columns
	$(NIXRUN) timeout 40 python3 tests/ui_review_columns.py ./$(BLDDIR)/ui_review_columns ./$(BLDDIR)/ui_review_widgets

test-png-16bit-oom: ## 16-bit decoder allocation failure releases bytes and never flips NULL.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'timeout 60 $$CC -std=c11 -O0 -Werror=vla -pedantic -Wall -Wextra -Werror -Isrc/ui tests/png_16bit_oom.c -o $(BLDDIR)/png_16bit_oom'
	$(NIXRUN) timeout 30 python3 tests/png_16bit_oom.py ./$(BLDDIR)/png_16bit_oom

test-ui-review-widgets-ubsan: ## UBSan: whole-cluster tabs and code-widget cells.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'timeout 60 $$CC -std=c11 -O0 -g -fno-omit-frame-pointer -Werror=vla -pedantic -Wall -Wextra -Werror -fsanitize=undefined -fno-sanitize-recover=undefined -Isrc/ui tests/ui_review_widgets.c -o $(BLDDIR)/ui_review_widgets_ubsan'
	$(NIXRUN) sh -c 'UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 sh scripts/check-golden.sh ui_review_widgets=ok timeout 15 ./$(BLDDIR)/ui_review_widgets_ubsan'

test-png-16bit-oom-ubsan: ## UBSan: every 16-bit decoder allocation with vertical flip enabled.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'timeout 60 $$CC -std=c11 -O0 -g -fno-omit-frame-pointer -Werror=vla -pedantic -Wall -Wextra -Werror -fsanitize=undefined -fno-sanitize-recover=undefined -Isrc/ui tests/png_16bit_oom.c -o $(BLDDIR)/png_16bit_oom_ubsan'
	$(NIXRUN) sh -c 'UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 timeout 30 python3 tests/png_16bit_oom.py ./$(BLDDIR)/png_16bit_oom_ubsan'

test-pty-m20-media-cache: build-ui ## Pty: seven inline results survive a full-cache manual refresh without refetch.
	$(NIXRUN) timeout 45 python3 tests/pty/m20_media_cache.py ./$(BLDDIR)/birc

test-pty-preview-retry: build-ui ## Pty: delayed helper failure completes before an identical manual retry.
	$(NIXRUN) timeout 40 python3 tests/pty/preview_retry.py ./$(BLDDIR)/birc

test-pty-deadlines: ## Require finite outer deadlines for every planned terminal test.
	$(NIXRUN) timeout 30 python3 tests/pty_deadlines.py

test-feed: test-feed-bench $(BLDDIR)/feed_demo ## M1 feed goldens + X1 buf_find linear bound.
	$(NIXRUN) sh scripts/check-golden.sh feed_demo=ok ./$(BLDDIR)/feed_demo

test-feed-bench: $(BLDDIR)/feed_bench ## Run the existing feed bound independently of feed goldens.
	$(NIXRUN) sh scripts/check-golden.sh feed_bench=ok timeout 2 ./$(BLDDIR)/feed_bench

test-submit: $(BLDDIR)/submit_demo ## M2 submit goldens.
	$(NIXRUN) sh scripts/check-golden.sh submit_demo=ok ./$(BLDDIR)/submit_demo

.PHONY: test-session-isupport-submit
test-session-isupport-submit: $(BLDDIR)/session_isupport_submit.js ## Negotiated channel commands reach the production Session Enter seam.
	$(NIXRUN) sh scripts/check-golden.sh session_isupport_submit=ok timeout 30 bun $(BLDDIR)/session_isupport_submit.js

test-review-pure: test-session-isupport-submit

test-pend: $(BLDDIR)/pend_demo ## Optimistic-send record/overlay/confirm/timeout/fail goldens.
	$(NIXRUN) sh scripts/check-golden.sh pend_demo=ok ./$(BLDDIR)/pend_demo

test-server-id: $(BLDDIR)/server_id_demo ## Multiserver routing, isolation, and generation goldens.
	$(NIXRUN) sh scripts/check-golden.sh server_id_demo=ok ./$(BLDDIR)/server_id_demo

test-ipv6: $(BLDDIR)/server_id_ipv6 ## Bracketed IPv6 endpoints, AAAA DNS, and dial-plan goldens.
	$(NIXRUN) sh scripts/check-golden.sh server_id_ipv6=ok ./$(BLDDIR)/server_id_ipv6

test-ipv6-glue: $(BLDDIR)/ipv6_transport.js ## AAAA-first query dispatch goldens via the JS backend.
	$(NIXRUN) sh scripts/check-golden.sh ipv6_transport=ok timeout 30 bun $(BLDDIR)/ipv6_transport.js

test-ipv6-transport: $(BLDDIR)/ipv6_transport_native ## Dual fallback, prod DNS/TCP, v6 UDP, stream deadlines, verified TLS/SNI.
	$(NIXRUN) timeout 120 python3 tests/ipv6_transport.py ./$(BLDDIR)/ipv6_transport_native $(OPENSSL)
test-drafts: $(BLDDIR)/drafts_demo ## Per-buffer drafts + multiline composition goldens.
	$(NIXRUN) sh scripts/check-golden.sh drafts_demo=ok ./$(BLDDIR)/drafts_demo

.PHONY: test-notify-followup-guards
test-notify-followup-guards: $(BLDDIR)/notify_followup_guards.js ## notify follow-up pure guards: reconnect floor/lease, chained threading (JS backend; standalone until heavy-lane green).
	$(NIXRUN) sh scripts/check-golden.sh notify_followup_guards=ok timeout 30 bun $(BLDDIR)/notify_followup_guards.js

.PHONY: test-notify-attr-blocked
test-notify-attr-blocked: $(BLDDIR)/notify_attr_blocked ## notify blocked attribution qual: START/release barrier, retire/reuse, B-failure-only-B, all9 drain, replay quiet (C backend; standalone until heavy-lane green).
	$(NIXRUN) sh -c 'set -eu; d=$$(mktemp -d); trap "rm -rf $$d" EXIT INT TERM; printf "#!/bin/sh\nlog=\"\$$0.log\"\nprintf \"start %%s\\\\n\" \"\$$*\" >> \"\$$log\"\nrel=\"\$$0.release\"\ni=0\nwhile [ \"\$$i\" -lt 18 ] && [ ! -e \"\$$rel\" ]; do sleep 0.05; i=\$$((i + 1)); done\nif [ -e \"\$$rel\" ]; then printf \"done %%s\\\\n\" \"\$$*\" >> \"\$$log\"; else printf \"expired %%s\\\\n\" \"\$$*\" >> \"\$$log\"; exit 1; fi\n" > "$$d/notify-send"; chmod +x "$$d/notify-send"; BIRC_NOTIFY_HELPER="$$d/notify-send" sh scripts/check-golden.sh notify_attr_blocked=ok timeout 90 ./$(BLDDIR)/notify_attr_blocked'

.PHONY: test-notify-followup-static
test-notify-followup-static: ## notify follow-up lightweight static pins (no compiler; standalone).
	bash scripts/check-notify-followup.sh

.PHONY: test-notify-order
test-notify-order: $(BLDDIR)/notify_order.js ## Notify order-independent dispatch subcheck (JS backend; standalone).
	$(NIXRUN) sh scripts/check-golden.sh notify_order=ok timeout 30 bun $(BLDDIR)/notify_order.js

.PHONY: test-notify-runtime
test-notify-runtime: $(BLDDIR)/notify_runtime.js ## Notify policy, queue and argv seams subcheck (JS backend; standalone; no worker delivery).
	$(NIXRUN) sh scripts/check-golden.sh notify_runtime=ok timeout 30 bun $(BLDDIR)/notify_runtime.js

.PHONY: test-notify-held-blocked
test-notify-held-blocked: $(BLDDIR)/notify_held_blocked ## R1 held-lease latch: latch-blocked helper (start ACK + release, inside 2s) + teardowns/wrong-ticket never spawn 2, received exact completion runs FIFO once (C backend).
	$(NIXRUN) sh -c 'set -eu; d=$$(mktemp -d); trap "rm -rf $$d" EXIT INT TERM; printf "#!/bin/sh\nlog=\"\$$0.log\"\nprintf \"start %%s\\\\n\" \"\$$*\" >> \"\$$log\"\nrel=\"\$$0.release\"\ni=0\nwhile [ \"\$$i\" -lt 18 ] && [ ! -e \"\$$rel\" ]; do sleep 0.05; i=\$$((i + 1)); done\nif [ -e \"\$$rel\" ]; then printf \"done %%s\\\\n\" \"\$$*\" >> \"\$$log\"; else printf \"expired %%s\\\\n\" \"\$$*\" >> \"\$$log\"; exit 1; fi\n" > "$$d/notify-send"; chmod +x "$$d/notify-send"; mkdir "$$d/unreleased"; printf "#!/bin/sh\nlog=\"\$$0.log\"\nprintf \"start %%s\\\\n\" \"\$$*\" >> \"\$$log\"\nrel=\"\$$0.release\"\ni=0\nwhile [ \"\$$i\" -lt 2 ] && [ ! -e \"\$$rel\" ]; do sleep 0.05; i=\$$((i + 1)); done\nif [ -e \"\$$rel\" ]; then printf \"done %%s\\\\n\" \"\$$*\" >> \"\$$log\"; else printf \"expired %%s\\\\n\" \"\$$*\" >> \"\$$log\"; exit 1; fi\n" > "$$d/unreleased/notify-send"; chmod +x "$$d/unreleased/notify-send"; BIRC_NOTIFY_HELPER="$$d/notify-send" BIRC_NOTIFY_HELPER_UNREL="$$d/unreleased/notify-send" sh scripts/check-golden.sh notify_held_blocked=ok timeout 90 ./$(BLDDIR)/notify_held_blocked'

.PHONY: test-notify-full-witness
test-notify-full-witness: $(BLDDIR)/notify_full.js ## Notify full companion witness only (JS; excludes notify_order/notify_runtime; standalone).
	$(NIXRUN) sh -c 'set -eu; d=$$(mktemp -d); trap "rm -rf $$d" EXIT INT TERM; printf "#!/bin/sh\nprintf \"%%s\\\\n\" \"\$$*\" >> \"\$$0.log\"\n" > "$$d/notify-send"; chmod +x "$$d/notify-send"; BIRC_NOTIFY_HELPER="$$d/notify-send" sh scripts/check-golden.sh notify_full=ok timeout 60 bun $(BLDDIR)/notify_full.js'

test-search: $(BLDDIR)/search_demo ## M16.3 parallel scrollback search goldens.
	$(NIXRUN) sh scripts/check-golden.sh search_demo=ok ./$(BLDDIR)/search_demo

test-split: $(BLDDIR)/split_demo ## M16.2 split-view state, focus, geometry, and routing goldens.
	$(NIXRUN) sh scripts/check-golden.sh split_demo=ok ./$(BLDDIR)/split_demo

test-preview: $(BLDDIR)/preview_demo ## M16.1 local PNG preview command and DrawOp goldens.
	$(NIXRUN) sh scripts/check-golden.sh preview_demo=ok ./$(BLDDIR)/preview_demo

test-typing: $(BLDDIR)/typing_demo ## M16.4 IRCv3 +typing parser, expiry, bounds, and view goldens.
	$(NIXRUN) sh scripts/check-golden.sh typing_demo=ok ./$(BLDDIR)/typing_demo

test-frame: $(BLDDIR)/frame_demo ## M4 CRLF framer goldens.
	$(NIXRUN) sh scripts/check-golden.sh frame_demo=ok ./$(BLDDIR)/frame_demo

test-net: $(BLDDIR)/net_demo ## M4 loopback TCP.send/recv + register/pong goldens.
	$(NIXRUN) sh scripts/check-golden.sh net_demo=ok ./$(BLDDIR)/net_demo

test-dns: $(BLDDIR)/dns_demo ## UDP A lookup identity + parse edges (no network).
	$(NIXRUN) sh scripts/check-golden.sh dns_demo=ok ./$(BLDDIR)/dns_demo
	@! grep -F 'Dns.resolve("one.one.one.one")' tests/bend/dns_demo.bend

test-dns-live: $(BLDDIR)/dns_live ## Live A lookup of one.one.one.one (not in check).
	$(NIXRUN) sh scripts/check-golden.sh dns_live=ok ./$(BLDDIR)/dns_live

test-dns-timeout: $(BLDDIR)/dns_timeout ## K3: blackhole nameserver returns timeout, does not park.
	$(NIXRUN) sh scripts/check-golden.sh dns_timeout=ok timeout 15 ./$(BLDDIR)/dns_timeout

test-dns-tcp: $(BLDDIR)/dns_tcp ## DNS TCP segmentation, length validation, and deadlines.
	$(NIXRUN) timeout 60 python3 tests/dns/tcp.py ./$(BLDDIR)/dns_tcp

test-socket-deadline: $(BLDDIR)/socket_deadline ## Socket deadlines: exact writes, stalled peers, refused connects.
	$(NIXRUN) timeout 60 python3 tests/dns/socket_deadline.py ./$(BLDDIR)/socket_deadline

test-base64: $(BLDDIR)/base64_demo ## Base64 and SASL PLAIN golden tests.
	$(NIXRUN) sh scripts/check-golden.sh base64_demo=ok ./$(BLDDIR)/base64_demo

test-auth: $(BLDDIR)/auth_demo ## Parsed SASL exchange, phase gating, and forged chat regression.
	$(NIXRUN) sh scripts/check-golden.sh auth_demo=ok ./$(BLDDIR)/auth_demo

.PHONY: test-auth-profile test-auth-args test-auth-privacy test-auth-notice test-actor-auth-scope test-keychain-wrapper test-auth-bridge test-auth-bridge-ubsan test-pty-auth test-auth-profiles
test-auth-profile: $(BLDDIR)/auth_profile
test-auth-args: $(BLDDIR)/auth_args
test-auth-privacy: $(BLDDIR)/auth_privacy
test-auth-notice: $(BLDDIR)/auth_notice
test-actor-auth-scope: $(BLDDIR)/actor_auth_scope
test-auth-profile test-auth-args test-auth-privacy test-auth-notice test-actor-auth-scope: ## Authentication profile, flag, actor scope, and credential privacy guards.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh scripts/check-golden.sh $(subst -,_,$(patsubst test-%,%,$@))=ok timeout 15 ./$(BLDDIR)/$(subst -,_,$(patsubst test-%,%,$@))

test-keychain-wrapper: ## Fake Keychain helper: private launch, safe prompt, and save only on verified success.
	$(NIXRUN) timeout 60 python3 tests/keychain_birc.py

test-auth-bridge: ## Strict C11: inherited secret/event pipe bounds, privacy, and one-shot ownership.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'timeout 60 $$CC -std=c11 -O0 -Werror=vla -pedantic -Wall -Wextra -Werror -Isrc/ffi tests/auth_bridge.c -o $(BLDDIR)/auth_bridge'
	$(NIXRUN) sh scripts/check-golden.sh auth_bridge=ok timeout 15 ./$(BLDDIR)/auth_bridge

test-auth-bridge-ubsan: ## UBSan: inherited authentication descriptors and UTF-8 bounds.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'timeout 60 $$CC -std=c11 -O0 -g -Werror=vla -pedantic -Wall -Wextra -Werror -fsanitize=undefined -fno-sanitize-recover=undefined -Isrc/ffi tests/auth_bridge.c -o $(BLDDIR)/auth_bridge_ubsan'
	$(NIXRUN) sh scripts/check-golden.sh auth_bridge=ok timeout 15 ./$(BLDDIR)/auth_bridge_ubsan

test-pty-auth: build-ui ## Actual SASL/NickServ, identity probes, hostile replies, and private success pipes.
	$(NIXRUN) timeout 60 python3 tests/pty/auth_profile.py ./$(BLDDIR)/birc

test-auth-profiles: test-auth-profile test-auth-args test-auth-privacy test-auth-notice test-actor-auth-scope test-keychain-wrapper test-auth-bridge test-pty-auth ## Authentication and secure launcher qualification.

test-review-pure: test-auth-profile test-auth-args test-auth-privacy test-auth-notice test-actor-auth-scope test-keychain-wrapper test-auth-bridge
test: test-pty-auth

test-state: $(BLDDIR)/state_demo ## Bounded logging and structural state regressions.
	$(NIXRUN) sh scripts/check-golden.sh state_demo=ok ./$(BLDDIR)/state_demo

.PHONY: test-buffer-spines
test-buffer-spines: $(BLDDIR)/buffer_spines ## Dual-spine Buffer invariant and structural view_same.
	$(NIXRUN) sh scripts/check-golden.sh buffer_spines=ok timeout 15 ./$(BLDDIR)/buffer_spines

test-review-pure: test-buffer-spines

.PHONY: test-state-review test-state-review-identity test-state-review-send test-state-review-history
test-state-review: test-state-review-identity test-state-review-send test-state-review-history ## Canonical targets, exact outgoing echoes, recent restores, and close/focus transitions.

test-state-review-identity: $(BLDDIR)/state_review_identity
test-state-review-send: $(BLDDIR)/state_review_send
test-state-review-history: $(BLDDIR)/state_review_history
test-runtime-dns: $(BLDDIR)/runtime_dns
test-runtime-reconnect: $(BLDDIR)/runtime_reconnect
test-runtime-args: $(BLDDIR)/runtime_args
test-state-review-identity test-state-review-send test-state-review-history test-runtime-dns test-runtime-reconnect test-runtime-args:
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh scripts/check-golden.sh $(subst -,_,$(patsubst test-%,%,$@))=ok timeout 15 ./$(BLDDIR)/$(subst -,_,$(patsubst test-%,%,$@))

.PHONY: test-runtime-review test-runtime-dns test-runtime-reconnect test-runtime-args test-cli-nick test-replay-stream
test-runtime-review: test-runtime-dns test-runtime-reconnect test-runtime-args test-cli-nick test-replay-stream ## Reconnect intent, absolute DNS names, explicit nicks, and complete replay.

test-cli-nick: build-ui ## Loopback: explicit nickname precedence and SASL-derived defaults.
	$(NIXRUN) timeout 75 python3 tests/net/cli_nick.py ./$(BLDDIR)/birc

test-replay-stream: build-ui ## Replay all records across and beyond one-MiB read boundaries.
	$(NIXRUN) timeout 90 python3 tests/net/replay_stream.py ./$(BLDDIR)/birc

.PHONY: test-ui-review-view test-ui-review-output test-ui-review-native test-ui-review-native-ubsan test-pty-ui-review-selection test-pty-ui-review-media
test-ui-review-view: $(BLDDIR)/ui_review_view ## Production previews are helper-only; preserve isolated legacy proof adapters.
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

test-day-bar: $(BLDDIR)/day_bar.js ## Local day dividers and same-day dedupe.
	$(NIXRUN) sh scripts/check-golden.sh day_bar=ok timeout 30 bun $(BLDDIR)/day_bar.js

test-history: $(BLDDIR)/history_demo ## Stable log identities, authored lines, and typed reconnect markers.
	$(NIXRUN) sh scripts/check-golden.sh history_demo=ok ./$(BLDDIR)/history_demo

test-history-io: $(BLDDIR)/history_io ## Streaming history keeps the newest records beyond one MiB.
	$(NIXRUN) sh scripts/check-golden.sh history_io=ok ./$(BLDDIR)/history_io

test-history-search: $(BLDDIR)/history_search $(BLDDIR)/history_search_io ## Disk-history search/paging and draft/chathistory policy goldens.
	$(NIXRUN) sh scripts/check-golden.sh history_search=ok ./$(BLDDIR)/history_search
	$(NIXRUN) sh scripts/check-golden.sh history_search_io=ok ./$(BLDDIR)/history_search_io
test-review-pure: test-day-bar test-history-search

test-link-commands: $(BLDDIR)/link_commands_demo ## Repeated link enumeration and opening preserve numbering.
	$(NIXRUN) sh scripts/check-golden.sh link_commands_demo=ok ./$(BLDDIR)/link_commands_demo

test-wrap: $(BLDDIR)/wrap_demo ## Styled, linked, wide, and combining spans wrap without losing targets.
	$(NIXRUN) sh scripts/check-golden.sh wrap_demo=ok ./$(BLDDIR)/wrap_demo

.PHONY: test-m21-view
test-m21-view: $(BLDDIR)/m21_view ## Word boundaries, styled clusters, safe headers, and history display fallbacks.
	$(NIXRUN) sh scripts/check-golden.sh m21_view=ok timeout 15 ./$(BLDDIR)/m21_view

.PHONY: test-m21-runtime test-m21-sasl-env test-media-image-bounds test-m21-native-clusters test-m21-native-clusters-ubsan test-m21-clusters-output test-nix-preflight
test-m21-runtime: $(BLDDIR)/m21_runtime ## DNS reply identity and terminated/unterminated replay equivalence.
	$(NIXRUN) sh scripts/check-golden.sh m21_runtime=ok timeout 15 ./$(BLDDIR)/m21_runtime

test-m21-sasl-env: $(BLDDIR)/m21_sasl_env ## SASL environment fallback and explicit CLI precedence.
	$(NIXRUN) timeout 50 python3 tests/sasl_env.py ./$(BLDDIR)/m21_sasl_env

test-media-image-bounds: ## Synthetic expanding GIF limits and APNG fallback decode accounting.
	$(NIXRUN) timeout 30 python3 tests/media_image_bounds.py

test-m21-native-clusters: ## Actual FFI: complete-cluster tab caps, painting, and click indices.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'timeout 60 $$CC -std=c11 -O0 -Werror=vla -pedantic -Wall -Wextra -Werror -pthread -Isrc/ui -Isrc/ffi tests/m21_native_clusters.c -o $(BLDDIR)/m21_native_clusters'
	$(NIXRUN) sh scripts/check-golden.sh m21_native_clusters=ok timeout 15 ./$(BLDDIR)/m21_native_clusters

test-m21-native-clusters-ubsan: ## UBSan: actual FFI cluster clipping and painting.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'timeout 60 $$CC -std=c11 -O0 -g -Werror=vla -pedantic -Wall -Wextra -Werror -pthread -fsanitize=undefined -fno-sanitize-recover=undefined -Isrc/ui -Isrc/ffi tests/m21_native_clusters.c -o $(BLDDIR)/m21_native_clusters_ubsan'
	$(NIXRUN) sh -c 'UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 sh scripts/check-golden.sh m21_native_clusters=ok timeout 15 ./$(BLDDIR)/m21_native_clusters_ubsan'

test-m21-clusters-output: build-ui ## Synthetic replay: actual terminal paint across source style boundaries.
	$(NIXRUN) timeout 30 python3 tests/m21_clusters_output.py ./$(BLDDIR)/birc

test-nix-preflight: ## Fixture guard uses provisioned Python, not the host interpreter.
	$(NIXRUN) timeout 30 python3 tests/nix_preflight.py

.PHONY: test-m21-targets test-m21-session test-m21-color test-m21-typing test-m21-history-private
test-m21-targets: $(BLDDIR)/m21_targets
test-m21-session: $(BLDDIR)/m21_session
test-m21-color: $(BLDDIR)/m21_color
test-m21-typing: $(BLDDIR)/m21_typing
test-m21-targets test-m21-session test-m21-color test-m21-typing:
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh scripts/check-golden.sh $(subst -,_,$(patsubst test-%,%,$@))=ok timeout 15 ./$(BLDDIR)/$(subst -,_,$(patsubst test-%,%,$@))

test-m21-history-private: $(BLDDIR)/m21_history_private ## Private history modes, owned-file repair, path safety, and disabled controls.
	$(NIXRUN) timeout 30 python3 tests/history_private.py ./$(BLDDIR)/m21_history_private

.PHONY: test-m21-history-native test-m21-history-native-ubsan
M21_HISTORY_CFLAGS := -std=c11 -O0 -Werror=vla -pedantic -Wall -Wextra -Werror -Wshadow -Wconversion -Wsign-conversion -Wcast-qual
test-m21-history-native: ## Actual history FFI ownership, permission checks, and partial/error writes.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'timeout 60 $$CC $(M21_HISTORY_CFLAGS) tests/m21_history_native.c -o $(BLDDIR)/m21_history_native'
	$(NIXRUN) sh scripts/check-golden.sh m21_history_native=ok timeout 15 ./$(BLDDIR)/m21_history_native

test-m21-history-native-ubsan: ## UBSan: history allocation ownership, descriptor policy, and write failures.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c 'timeout 60 $$CC $(M21_HISTORY_CFLAGS) -g -fno-omit-frame-pointer -fsanitize=undefined -fno-sanitize-recover=undefined tests/m21_history_native.c -o $(BLDDIR)/m21_history_native_ubsan'
	$(NIXRUN) sh -c 'UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 sh scripts/check-golden.sh m21_history_native=ok timeout 15 ./$(BLDDIR)/m21_history_native_ubsan'

.PHONY: test-m21
test-m21: test-m21-view test-m21-runtime test-m21-sasl-env test-media-image-bounds test-m21-native-clusters test-m21-clusters-output test-nix-preflight test-m21-targets test-m21-session test-m21-color test-m21-typing test-m21-history-private ## Review fixes: routing, private history, DNS, replay, clusters, and word wrapping.

test-review-pure: test-m21
test-m21: test-m21-history-native
test-sanitizers: test-m21-native-clusters-ubsan test-m21-history-native-ubsan

test-columns-width: $(BLDDIR)/columns_width ## Exhaustive scalar-width parity with the actual TimUI implementation.
	$(NIXRUN) timeout 60 python3 tests/columns_width.py ./$(BLDDIR)/columns_width

test-scroll: $(BLDDIR)/scroll_demo ## Wrapped-row navigation and stable arrival/resize anchors.
	$(NIXRUN) sh scripts/check-golden.sh scroll_demo=ok ./$(BLDDIR)/scroll_demo

test-actor: $(BLDDIR)/actor_demo ## Outbound batch boundaries, finite budgets, and FIFO queue behavior.
	$(NIXRUN) sh scripts/check-golden.sh actor_demo=ok ./$(BLDDIR)/actor_demo

test-actor-queue: $(BLDDIR)/actor_queue ## Local sockets: per-turn caps, close flush, and self-pump safety.
	$(NIXRUN) timeout 120 python3 tests/net/actor_queue.py ./$(BLDDIR)/actor_queue

test-links: $(BLDDIR)/links_demo ## Shared URL lexer: boundaries, punctuation, and code spans.
	$(NIXRUN) sh scripts/check-golden.sh links_demo=ok ./$(BLDDIR)/links_demo

test-commands: $(BLDDIR)/command_demo ## Local commands offline/connecting and read-only wire target guards.
	$(NIXRUN) sh scripts/check-golden.sh command_demo=ok ./$(BLDDIR)/command_demo

test-args: $(BLDDIR)/args_demo ## CLI flag parse (missing values, bad numbers, --connect).
	$(NIXRUN) sh scripts/check-golden.sh args_demo=ok ./$(BLDDIR)/args_demo
	@! grep -F 'def seed_bit' src/bend/session.bend
	@! grep -F 'CopyMany' src/bend/args.bend
	@! grep -F 'def is_433_line' src/bend/irc.bend
	@! grep -F 'def submit_part.chan' src/bend/submit.bend

proto-parity: $(BLDDIR)/proto_parity ## M3 fixture corpus Bend golden tags (fail closed if fixtures missing).
	@test -f fixtures/demo.irc || { printf '%s\n' 'BLOCKED: fixtures/demo.irc missing' >&2; exit 2; }
	@test -f fixtures/welcome.irc || { printf '%s\n' 'BLOCKED: fixtures/welcome.irc missing' >&2; exit 2; }
	@test -f fixtures/action.irc || { printf '%s\n' 'BLOCKED: fixtures/action.irc missing' >&2; exit 2; }
	@test -f fixtures/odd_casing.irc || { printf '%s\n' 'BLOCKED: fixtures/odd_casing.irc missing' >&2; exit 2; }
	@test -f fixtures/adversarial.irc || { printf '%s\n' 'BLOCKED: fixtures/adversarial.irc missing' >&2; exit 2; }
	@grep -F -x ':irc.birc.dev 001 me :Welcome' fixtures/demo.irc >/dev/null || { printf '%s\n' 'BLOCKED: fixtures/demo.irc drifted' >&2; exit 2; }
	@grep -F -x ':irc.example.net 001 me :Welcome to the network' fixtures/welcome.irc >/dev/null || { printf '%s\n' 'BLOCKED: fixtures/welcome.irc drifted' >&2; exit 2; }
	@grep -F 'PiNg :xyz' fixtures/odd_casing.irc >/dev/null || { printf '%s\n' 'BLOCKED: fixtures/odd_casing.irc drifted' >&2; exit 2; }
	@$(NIXRUN) python3 -c "p=open('fixtures/action.irc','rb').read(); assert b'\\x01ACTION waves\\x01' in p" || { printf '%s\n' 'BLOCKED: fixtures/action.irc CTCP validation failed' >&2; exit 2; }
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
	$(NIXRUN) timeout 45 python3 tests/live_mock.py ./$(BLDDIR)/birc

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

test-pty-composer-scroll: build-ui ## Pty: overlong drafts scroll horizontally, cursor stays visible, Home/End rescroll.
	$(NIXRUN) timeout 150 python3 tests/pty/composer_scroll.py ./$(BLDDIR)/birc

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

test-scroll-edits: $(BLDDIR)/scroll_edits_demo ## Purge, query merge, and link-list edits preserve scroll identity.
	$(NIXRUN) sh scripts/check-golden.sh scroll_edits_demo=ok ./$(BLDDIR)/scroll_edits_demo

test-history-errors: $(BLDDIR)/history_errors ## History IO errors are visible; sparse size probes never scan large files.
	$(NIXRUN) timeout 60 python3 tests/history_errors.py ./$(BLDDIR)/history_errors

test-startup-actor: $(BLDDIR)/startup_actor ## Initial actor success/failure can continue to a queued dial.
	$(NIXRUN) timeout 15 python3 tests/net/startup_actor.py ./$(BLDDIR)/startup_actor

test-session-links: $(BLDDIR)/session_links_demo ## Session opening echoes cannot amplify links or persisted history.
	$(NIXRUN) sh scripts/check-golden.sh session_links_demo=ok ./$(BLDDIR)/session_links_demo

test-pty-session-links: build-ui ## Pty: runtime open/list uses stable link sources and fake launchers.
	$(NIXRUN) timeout 40 python3 tests/pty/session_links.py ./$(BLDDIR)/birc

test-pty-split-identity: build-ui ## Pty: a query named server retains its pane and send identity.
	$(NIXRUN) timeout 45 python3 tests/pty/split_identity.py ./$(BLDDIR)/birc

test-ui-input-queue: $(BLDDIR)/ui_input_queue ## Synthetic wakes cannot block acknowledgement or a full event queue.
	$(NIXRUN) sh scripts/check-golden.sh ui_input_queue=ok timeout 15 ./$(BLDDIR)/ui_input_queue

test-pty-input-fairness: build-ui ## Pty: mixed input/inbound traffic keeps PONG and quit responsive.
	$(NIXRUN) timeout 45 python3 tests/pty/input_fairness.py ./$(BLDDIR)/birc

test-demo-identity: $(BLDDIR)/demo_identity ## Demo data preserves the requested nick and current Dial identity.
	$(NIXRUN) sh scripts/check-golden.sh demo_identity=ok ./$(BLDDIR)/demo_identity

test-mute-scope: $(BLDDIR)/mute_scope_demo ## Scoped mutes filter status targets and all supported channel types.
	$(NIXRUN) sh scripts/check-golden.sh mute_scope_demo=ok timeout 15 ./$(BLDDIR)/mute_scope_demo

test-split-rename: $(BLDDIR)/split_rename_demo ## Query NICK changes preserve pane identity and focus.
	$(NIXRUN) sh scripts/check-golden.sh split_rename_demo=ok timeout 15 ./$(BLDDIR)/split_rename_demo

test-action-budget: $(BLDDIR)/action_budget_demo ## CTCP ACTION retains its envelope and echoes the transmitted UTF-8 body.
	$(NIXRUN) sh scripts/check-golden.sh action_budget_demo=ok timeout 15 ./$(BLDDIR)/action_budget_demo

test-richtext-model: $(BLDDIR)/richtext_demo ## Literal unmatched markup and code styling survive wrapping.
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

test-pty-split-composer: build-ui ## Pty: one <nick> prefix in the split widget pane, widget seated after it, degenerate-pane survival.
	$(NIXRUN) timeout 150 python3 tests/pty/split_composer.py ./$(BLDDIR)/birc

test-pty-typing: build-ui ## Pty: IRCv3 typing lifecycle, timeout, pause, and muted clear.
	$(NIXRUN) timeout 150 python3 tests/pty/typing.py ./$(BLDDIR)/birc


.PHONY: test-review-pure

.PHONY: test-review-pure test-golden-runner test-build-config test-auth test-commands test-state test-day-bar test-history test-history-io test-history-search test-links test-link-commands test-wrap test-columns-width test-scroll test-dns-tcp test-socket-deadline test-pty-output-stall test-pty-send-stall test-pty-wrapped-spans test-pty-reconnect-nick proof-kernel
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

test-review-pure: test-golden-runner test-build-config test-auth test-commands test-state test-history test-history-io test-history-errors test-links test-link-commands test-session-links test-wrap test-columns-width test-scroll test-scroll-edits test-dns-tcp test-socket-deadline test-actor test-actor-queue test-startup-actor test-ui-input-queue test-demo-identity test-output-utf8 test-output-shutdown test-output-progress test-png-bounds test-mute-scope test-action-budget test-richtext-model test-split-rename test-formatting test-theme test-media-image ## Adversarial review regression gates.
test-review-pure: test-media-policy test-media-view test-media-anchor test-media-branches test-viewport-tail test-media-native test-media-portable test-diagnostic test-server-time test-history-save-errors test-ws-history-enqueue test-reader-errors test-clipboard-errors test-pty-deadlines test-view-profile test-input-wake
test-review-pure: test-state-review test-runtime-review test-ui-review-native test-ui-review-view test-ui-review-output test-wire-style
test-review-pure: test-m20

test: test-review-pure test-proto test-feed test-submit test-search test-preview test-split test-typing test-frame test-net test-dns test-dns-timeout test-base64 test-args proto-parity test-ui test-cli test-live test-headless-startup test-richtext-painter test-formatting-painter test-pty ## Protocol + pure + net + DNS + args + fixtures + UI + live mock + pty.

proof: ## Check LAWS via generated one-law shards under build/proof (bend PROOF.bend alone does not finish).
	@test "$(PROOF_TIMEOUT)" -gt 0 2>/dev/null || { printf '%s\n' 'PROOF_TIMEOUT must be a positive number of seconds' >&2; exit 2; }
	PROOF_TIMEOUT='$(PROOF_TIMEOUT)' $(NIXRUN) sh scripts/run-proof-shards.sh

.PHONY: proof-kernel
proof-kernel: ## Same as proof with bend --verdict on each shard (not the monolithic book).
	@test "$(PROOF_TIMEOUT)" -gt 0 2>/dev/null || { printf '%s\n' 'PROOF_TIMEOUT must be a positive number of seconds' >&2; exit 2; }
	PROOF_TIMEOUT='$(PROOF_TIMEOUT)' PROOF_FLAGS='--verdict' $(NIXRUN) sh scripts/run-proof-shards.sh

LINT_FFI_CFLAGS := -std=c11 -Wall -Wextra -Werror -pedantic -Wshadow -Wconversion -Wsign-conversion -Wcast-qual -Wno-unused-command-line-argument -fsyntax-only
lint-ffi: test-utf8-fit ## Syntax-only warning lint of src/ffi (real build stays -w).
	$(NIXRUN) sh -c '$$CC $(LINT_FFI_CFLAGS) -I tests/lint-ffi -I src/ffi -isystem src/ui tests/lint-ffi/lint_timui.c'
	$(NIXRUN) sh -c '$$CC $(LINT_FFI_CFLAGS) -I tests/lint-ffi -I src/ffi -isystem src/ui tests/lint-ffi/lint_clock.c'
	$(NIXRUN) sh -c '$$CC $(LINT_FFI_CFLAGS) -I tests/lint-ffi -I src/ffi -isystem src/ui tests/lint-ffi/lint_dns.c'
	$(NIXRUN) sh -c '$$CC $(LINT_FFI_CFLAGS) -I tests/lint-ffi -I src/ffi -isystem src/ui tests/lint-ffi/lint_history.c'
	$(NIXRUN) sh -c '$$CC $(LINT_FFI_CFLAGS) -I tests/lint-ffi -I src/ffi -isystem src/ui tests/lint-ffi/lint_auth_bridge.c'
	$(NIXRUN) sh -c '$$CC $(LINT_FFI_CFLAGS) -I tests/lint-ffi -I src/ffi -isystem src/ui tests/lint-ffi/lint_tls.c'
	$(NIXRUN) sh -c '$$CC $(LINT_FFI_CFLAGS) -I tests/lint-ffi -I src/ffi -isystem src/ui tests/lint-ffi/lint_history_search.c'
	@awk 'BEGIN{u=0;b=0;p=0;q=0} /if \(!ui\) \{/{p=1} p&&/birc_drop_ops/{u=1} p&&/return birc_uikeys/{p=0} /if \(!timui_begin/{q=1} q&&/birc_drop_ops/{b=1} q&&/return birc_uikeys/{q=0} END{if(!(u&&b)){print "drop_ops: early returns must consume ops"; exit 1}}' src/ffi/timui_ffi.c
	@! grep -E 'rows[[:space:]]*-[[:space:]]*6' src/ffi/timui_ffi.c
	@awk '/^def reader_stop\(/{p=1} p&&/Eof/{e=1} p&&/Tr.close\(dup\)/{c=1} p&&/^def / && !/^def reader_stop/{p=0} END{if(!(e&&c)){print "reader_stop: Eof then close the dup only"; exit 1}}' src/bend/actor.bend
	@! grep -F 'Chan.close(Sess.UiMsg' src/bend/net.bend
	@! grep -F 'birc_wait_fds' src/ffi/timui_ffi.c
	@! grep -F 'wake_poke' src/ffi/*.c
	@! grep -F 'fd_hint' src/ffi/dns_ffi.c
	@grep -q 'O_NONBLOCK' src/ffi/timui_ffi.c
	@! grep -F 'poll(p, 1, 0)' src/ffi/timui_ffi.c
	@! grep -F 'while (n < sizeof buf && term_aux(xs)' src/ffi/dns_ffi.c
	@awk '/timui_open\(&cfg/{p=1} p&&/free\(st\)/{c=1} p&&/return io_fail/{p=0} END{if(!c){print "timui_open fail must free st"; exit 1}}' src/ffi/timui_ffi.c
	@grep -q 'io_eff(CID_RECV_OCTETS, recv_octets_run)' src/ffi/dns_ffi.c
	@grep -q 'io_eff(CID_RECV_NB, recv_nb_run)' src/ffi/dns_ffi.c
	@grep -q 'if (max > 65536u)' src/ffi/dns_ffi.c
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

# Opt-in PTY sharding/caching harness (additive targets only; `test-pty` unchanged).
# Fail closed if a fragment is missing: `-include` used to drop its targets from
# test-review-pure → test → check while `make check` still exited 0.
# BIRC_ALLOW_MISSING_MK=1 skips the fragments only for the test-nix-preflight
# temp-dir invocation. In-tree builds include the files next to this Makefile.
ifeq ($(BIRC_ALLOW_MISSING_MK),1)
else
ifeq ($(wildcard $(BIRC_MAKE_DIR)/mk/pty-shard.mk),)
$(error missing mk/pty-shard.mk; set BIRC_ALLOW_MISSING_MK=1 only for the test-nix-preflight temp-dir invocation)
endif
ifeq ($(wildcard $(BIRC_MAKE_DIR)/mk/wf-cards.mk),)
$(error missing mk/wf-cards.mk; set BIRC_ALLOW_MISSING_MK=1 only for the test-nix-preflight temp-dir invocation)
endif
ifeq ($(wildcard $(BIRC_MAKE_DIR)/mk/wf-settings.mk),)
$(error missing mk/wf-settings.mk; set BIRC_ALLOW_MISSING_MK=1 only for the test-nix-preflight temp-dir invocation)
endif
ifeq ($(wildcard $(BIRC_MAKE_DIR)/mk/wf-filter.mk),)
$(error missing mk/wf-filter.mk; set BIRC_ALLOW_MISSING_MK=1 only for the test-nix-preflight temp-dir invocation)
endif
include $(BIRC_MAKE_DIR)/mk/pty-shard.mk
include $(BIRC_MAKE_DIR)/mk/wf-cards.mk
include $(BIRC_MAKE_DIR)/mk/wf-settings.mk
include $(BIRC_MAKE_DIR)/mk/wf-filter.mk
endif
# Exact import closures. Only files that already exist are included, so a
# clean tree keeps the BEND_SRC_DEPS fallback above. In-tree only: a temp
# cwd (test-nix-preflight) has no tests/bend and must not scan the world.
ifneq ($(wildcard tests/bend/expect.bend),)
-include $(wildcard $(BLDDIR)/*.bend.d)
-include $(BLDDIR)/golden-layers.mk
endif

.PHONY: focus
focus: ## Run one target: make focus T=test-utc-time
	@test -n "$(T)" || { printf '%s\n' 'focus: set T=<target>' >&2; exit 2; }
	$(MAKE) $(T)

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
	$(NIXRUN) timeout 120 python3 tests/perf/cpu_pty.py ./$(BLDDIR)/birc

test-perf-tickrate: build-ui ## 600-frame idle tickrate (not in check).
	$(NIXRUN) python3 tests/perf/tickrate_pty.py ./$(BLDDIR)/birc 600 30 100

test-perf-search: ## Profile serial/parallel search at 16 x 1024 lines (not in check).
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/perf/search_profile.bend -o $(BLDDIR)/search_profile
	$(NIXRUN) sh -c 'for mode in serial parallel parallel serial serial parallel parallel serial serial parallel; do BIRC_SEARCH_PROFILE=$$mode ./$(BLDDIR)/search_profile; done'

test-perf-hardening: build-ui ## Profile production frame phases with scale replay (not in check).
	$(NIXRUN) timeout 120 python3 tests/perf/hardening_profile.py ./$(BLDDIR)/birc

test-perf-output: build-ui ## Measure stalled-output View/native phases and PONG latency (not in check).
	$(NIXRUN) timeout 90 python3 tests/perf/output_profile.py ./$(BLDDIR)/birc

.PHONY: test-startup-profile test-perf-startup test-perf-cleanup
test-perf-cleanup: ## Owned PTY harness children and descriptors close on failed accept/send.
	$(NIXRUN) timeout 30 python3 tests/perf_cleanup.py

test-review-pure: test-perf-cleanup

test-startup-profile: ## Check bounded startup timing, failure evidence, and child cleanup with owned mocks.
	$(NIXRUN) timeout 60 python3 tests/perf/startup_profile.py --self-test

test-perf-startup: ## Measure cached nix run versus its installed app; refuses an unbuilt output (not in check).
	$(NIXRUN) timeout 240 python3 tests/perf/startup_profile.py --nix-run --samples 3

.PHONY: test-perf-media-wrap
MEDIA_PROFILE_MODE ?= empty
MEDIA_PROFILE_LINKS ?= 0
MEDIA_PROFILE_SAMPLES ?= 128
MEDIA_PROFILE_LINES ?= 128
test-perf-media-wrap: ## Measure consumed batches; set MEDIA_PROFILE_MODE/LINKS/SAMPLES/LINES (not in check).
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 180 bend tests/perf/media_wrap_profile.bend -o $(BLDDIR)/media_wrap_profile
	$(NIXRUN) timeout 15 ./$(BLDDIR)/media_wrap_profile $(MEDIA_PROFILE_MODE) $(MEDIA_PROFILE_LINKS) $(MEDIA_PROFILE_SAMPLES) $(MEDIA_PROFILE_LINES)

.PHONY: paint-footprint
PAINT_FOOTPRINT_PASSES ?= 32
paint-footprint: ## Repaint one SCROLL_CAP rich buffer and sample physical footprint (not in check).
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 600 bend tests/perf/paint_footprint.bend -o $(BLDDIR)/paint_footprint
	$(NIXRUN) timeout 180 python3 tests/perf/paint_footprint.py ./$(BLDDIR)/paint_footprint $(PAINT_FOOTPRINT_PASSES)

.PHONY: test-paint-slope
test-paint-slope: ## Deterministic slope-verdict checks for the footprint probe (no binary, no pty).
	$(NIXRUN) timeout 30 python3 tests/perf/paint_slope_check.py

SANITIZER_CFLAGS := -std=c11 -O1 -g -fno-omit-frame-pointer -pthread -w

$(BLDDIR)/birc_ubsan: $(BLDDIR)/birc_bend.c $(BLDDIR)/build-config
	$(NIXRUN) timeout 600 sh -c '$$CC $(SANITIZER_CFLAGS) -fsanitize=undefined -fno-sanitize-recover=undefined -Isrc/ui -Isrc/ffi $(BLDDIR)/birc_bend.c -o $(BLDDIR)/birc_ubsan'

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
test-sanitizers: test-m20-native-ubsan
test-sanitizers: test-ui-review-widgets-ubsan test-png-16bit-oom-ubsan

# Hardening profiler is optional smoke (no wall/phase fail thresholds).
# Keep real PTY latency/idle gates only so this target cannot soft-pass.
test-perf-gates: test-pty-tickrate test-pty-paintwake test-pty-joinlat ## M7.5: idle and latency gates.


check-hardening: proof proto-parity test-pty-hostile test-sanitizers test-perf-gates ## M7.3-M7.6 hardening gates.

check: proof test lint-ffi test-paste-harness ## Proofs + protocol tests + UI smoke + FFI lint + paste harness.

run-demo: build-ui ## Offline TimUI demo with canned IRC transcript.
	$(NIXRUN) ./$(BLDDIR)/birc --demo

run: ## Verified TLS IRC (HOST=host[:port]; TRANSPORT=plain explicitly selects plaintext).
	@test -n "$(HOST)" || { printf '%s\n' 'usage: make run HOST=irc.example.net[:port] [NICK=birc] [CHAN=#birc] [PORT=6697] [TRANSPORT=tls|plain]' >&2; exit 2; }
	@case "$(TRANSPORT)" in tls|plain) ;; *) printf '%s\n' 'TRANSPORT must be tls or plain' >&2; exit 2 ;; esac
	@$(MAKE) build-ui
	$(NIXRUN) ./$(BLDDIR)/birc --$(TRANSPORT) --connect "$(HOST)" $(if $(strip $(PORT)),--port "$(PORT)") --nick "$(NICK)" --channel "$(CHAN)"

run-auth: ## Keychain-backed IRC (HOST=host; PROFILE defaults to HOST; missing profiles are created from HOST/NICK; CHAN/PORT override when given).
	@test -n "$(HOST)" || { printf '%s\n' 'usage: make run-auth HOST=irc.example.net [PROFILE=name] [NICK=nick] [CHAN=#chan] [PORT=6697] [TRANSPORT=tls|plain] [CONFIG=path]' >&2; exit 2; }
	@case "$(HOST)" in *:*) printf '%s\n' 'run-auth: HOST must not include a port; set PORT=... or use the profile port' >&2; exit 2 ;; esac
	@case "$(TRANSPORT)" in tls|plain) ;; *) printf '%s\n' 'TRANSPORT must be tls or plain' >&2; exit 2 ;; esac
	@$(MAKE) build-ui
	$(NIXRUN) env BIRC_PROGRAM=./$(BLDDIR)/birc python3 src/launcher/keychain_birc.py --profile "$(if $(strip $(PROFILE)),$(strip $(PROFILE)),$(strip $(HOST)))" --create "$(strip $(HOST))" $(if $(strip $(CONFIG)),--config "$(CONFIG)") --$(TRANSPORT) $(if $(strip $(PORT)),--port "$(strip $(PORT))") $(if $(filter command line environment override,$(origin NICK)),--nick "$(NICK)") $(if $(filter command line environment override,$(origin CHAN)),--channel "$(CHAN)")

clean: ## Remove build artefacts (not sources or flake.lock).
	rm -rf $(BLDDIR)

.PHONY: build-package-profiled test-package-build-profile
build-package-profiled: ## Measure Nix codegen/native stages; separate package, not the default app cache.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) timeout 900 $(NIX) $(NIX_FEATURES) build --option timeout 900 --keep-failed --no-update-lock-file -L .\#birc-profiled --out-link $(BLDDIR)/package-birc-profiled

test-package-build-profile: ## Default-off Nix timers preserve command order and fail-closed status.
	$(NIXRUN) timeout 360 python3 tests/package_build_profile.py --eval-timeout $(PACKAGE_PLAN_TIMEOUT)

.PHONY: test-bend-telemetry
test-bend-telemetry: ## Offline compiler/Bun telemetry opt-out guards.
	$(NIXRUN) timeout 15 python3 tests/bend_telemetry.py
test-review-pure: test-bend-telemetry

.PHONY: test-cap-notify
test-cap-notify: $(BLDDIR)/cap_notify_demo.js ## Standalone CAP registry, handshake, notify and typing guards.
	$(NIXRUN) sh scripts/check-golden.sh cap_notify_demo=ok timeout 30 bun $(BLDDIR)/cap_notify_demo.js

.PHONY: test-capnotify
test-capnotify: $(BLDDIR)/capnotify_demo.js ## CAP NEW/DEL lifetime updates through the CAP trust gate.
	$(NIXRUN) sh scripts/check-golden.sh capnotify_demo=ok timeout 30 bun $(BLDDIR)/capnotify_demo.js
test-review-pure: test-capnotify

.PHONY: test-echo-message
test-echo-message: $(BLDDIR)/echo_message.js ## IRCv3 echo-message: gated local echo, single wire render, hostile CAP rejection.
	$(NIXRUN) sh scripts/check-golden.sh echo_message=ok timeout 30 bun $(BLDDIR)/echo_message.js
test-review-pure: test-echo-message

.PHONY: test-extended-join
test-extended-join: $(BLDDIR)/extended_join.js ## IRCv3 extended-join + account-tag guards.
	$(NIXRUN) sh scripts/check-golden.sh extended_join=ok timeout 30 bun $(BLDDIR)/extended_join.js
test-review-pure: test-extended-join

.PHONY: test-labeled-response
test-labeled-response: $(BLDDIR)/labeled_response.js ## Labeled-response cap, outbound tags, ACK correlation and label counter.
	$(NIXRUN) sh scripts/check-golden.sh labeled_response=ok timeout 30 bun $(BLDDIR)/labeled_response.js
test-review-pure: test-labeled-response

.PHONY: test-stdreply
test-stdreply: $(BLDDIR)/stdreply_demo.js ## IRCv3 standard replies FAIL/WARN/NOTE server-log routing.
	$(NIXRUN) sh scripts/check-golden.sh stdreply_demo=ok timeout 30 bun $(BLDDIR)/stdreply_demo.js
test-review-pure: test-stdreply

# Admitted runtime core fixtures: standalone until canonical-source qualification.
.PHONY: test-session-drafts test-workspace test-wsnet-gates test-ws-first-connect test-ws-shutdown-pending
test-session-drafts: $(BLDDIR)/session_drafts_demo ## Session/drafts wiring goldens (focus gates, endpoint replace, submit clearing, multiline, modal stash).
	$(NIXRUN) sh scripts/check-golden.sh session_drafts_demo=ok ./$(BLDDIR)/session_drafts_demo

test-workspace: $(BLDDIR)/workspace_demo ## Multiserver workspace wiring goldens (partitions, routing, generations, scopes).
	$(NIXRUN) sh scripts/check-golden.sh workspace_demo=ok ./$(BLDDIR)/workspace_demo

test-wsnet-gates: $(BLDDIR)/wsnet_gates.js ## wsnet G2/G4/M1-M3 envelope, union gate, and first-frame/load guards (JS backend).
	$(NIXRUN) sh scripts/check-golden.sh wsnet_gates=ok timeout 30 bun $(BLDDIR)/wsnet_gates.js

test-ws-first-connect: $(BLDDIR)/ws_first_connect.js ## Startup-only pending endpoint override, credentials/drafts/upload, and unchanged live busy guards (JS backend).
	$(NIXRUN) sh scripts/check-golden.sh ws_first_connect=ok timeout 30 bun $(BLDDIR)/ws_first_connect.js

test-ws-shutdown-pending: $(BLDDIR)/ws_shutdown_pending.js ## WsNet pending Dials skip shutdown wait; ready and default states retain it (JS backend).
	$(NIXRUN) sh scripts/check-golden.sh ws_shutdown_pending=ok timeout 30 bun $(BLDDIR)/ws_shutdown_pending.js

# Supporting runtime fixtures: standalone until canonical-source qualification.
.PHONY: test-draft-nick-rename test-outbound-txn test-reader-pongs test-net-live-wait-cell
test-draft-nick-rename: $(BLDDIR)/draft_nick_rename.js ## CM NICK-to-draft rename: store semantics plus live-arrival guards (JS backend).
	$(NIXRUN) sh scripts/check-golden.sh draft_nick_rename=ok timeout 30 bun $(BLDDIR)/draft_nick_rename.js

test-outbound-txn: $(BLDDIR)/outbound_txn.js ## Trace txn helpers (repeat/split/next) via the JS backend.
	$(NIXRUN) sh scripts/check-golden.sh outbound_txn=ok timeout 30 bun $(BLDDIR)/outbound_txn.js

test-reader-pongs: $(BLDDIR)/reader_pongs ## Reader-owned PONG purity: exact replies, split reassembly, overlong silence.
	$(NIXRUN) sh scripts/check-golden.sh reader_pongs=ok ./$(BLDDIR)/reader_pongs

test-net-live-wait-cell: $(BLDDIR)/net_live_wait_cell ## Live-step wait-cell payload characterization (pure shape, no channel).
	$(NIXRUN) sh scripts/check-golden.sh net_live_wait_cell=ok timeout 15 ./$(BLDDIR)/net_live_wait_cell

.PHONY: test-notify-binding-gates
test-notify-binding-gates: $(BLDDIR)/notify_binding_gates.js ## notify gates 1-4 + attribution over framed bursts with a fake-helper barrier (JS backend).
	$(NIXRUN) sh -c 'set -eu; d=$$(mktemp -d); trap "rm -rf $$d" EXIT INT TERM; printf "#!/bin/sh\nlog=\"\$$0.log\"\nprintf \"start %%s\\\\n\" \"\$$*\" >> \"\$$log\"\nprintf \"done %%s\\\\n\" \"\$$*\" >> \"\$$log\"\n" > "$$d/notify-send"; chmod +x "$$d/notify-send"; BIRC_NOTIFY_HELPER="$$d/notify-send" sh scripts/check-golden.sh notify_binding_gates=ok timeout 60 bun $(BLDDIR)/notify_binding_gates.js'

.PHONY: test-notify-held
test-notify-held: $(BLDDIR)/notify_held.js ## R1 held-helper lease: blocked + reset/off/on/cancel never spawns 2, old exact runs FIFO once (JS backend).
	$(NIXRUN) sh -c 'set -eu; d=$$(mktemp -d); trap "rm -rf $$d" EXIT INT TERM; printf "#!/bin/sh\nlog=\"\$$0.log\"\nprintf \"start %%s\\\\n\" \"\$$*\" >> \"\$$log\"\nsleep 0.2\nprintf \"done %%s\\\\n\" \"\$$*\" >> \"\$$log\"\n" > "$$d/notify-send"; chmod +x "$$d/notify-send"; BIRC_NOTIFY_HELPER="$$d/notify-send" sh scripts/check-golden.sh notify_held=ok timeout 60 bun $(BLDDIR)/notify_held.js'

.PHONY: test-workspace-005-source
test-workspace-005-source: $(BLDDIR)/workspace_005_source.js ## Live 005 source/recipient and CHANMODES certainty guards (JS backend).
	$(NIXRUN) env TEST_TIMEOUT_SECONDS=30 sh scripts/check-golden.sh workspace_005_source=ok timeout 30 bun $(BLDDIR)/workspace_005_source.js

.PHONY: test-theme-selector-boundaries
test-theme-selector-boundaries: $(BLDDIR)/theme_selector_boundaries.js ## Fixed/default and themed status boundary colors (JS backend).
	$(NIXRUN) env TEST_TIMEOUT_SECONDS=30 sh scripts/check-golden.sh theme_selector_boundaries=ok timeout 30 bun $(BLDDIR)/theme_selector_boundaries.js

.PHONY: test-theme-ws-render
test-theme-ws-render: $(BLDDIR)/theme_ws_render.js ## Framed end-to-end theme guard (retained wire styles, Ws paint under Dark/Light/Mono).
	$(NIXRUN) sh scripts/check-golden.sh theme_ws_render=ok timeout 30 bun $(BLDDIR)/theme_ws_render.js

.PHONY: test-ws-media-stage-native
test-ws-media-stage-native: $(BLDDIR)/ws_media_stage_native ## Actual media None/Some stages and exact physical/event ownership (native).
	$(NIXRUN) timeout 60 python3 tests/native/ws_media_stage.py ./$(BLDDIR)/ws_media_stage_native

.PHONY: test-mss-stale-held
test-mss-stale-held: $(BLDDIR)/mss_stale_socket ## Held stale 903 drops by generation fence over real sockets.
	$(NIXRUN) timeout 60 python3 tests/net/mss_stale_socket.py ./$(BLDDIR)/mss_stale_socket

.PHONY: test-sessws-s1s5
test-sessws-s1s5: $(BLDDIR)/sessws_s1s5_demo.js ## SessWS S1-S5 repair guards plus G1-G5 completion/history/seam/FIFO/runtime goldens (JS backend).
	$(NIXRUN) sh scripts/check-golden.sh sessws_s1s5_demo=ok timeout 30 bun $(BLDDIR)/sessws_s1s5_demo.js

# SOURCE UNRUN: standalone until compile/native/three PTY runs qualify.
.PHONY: test-ws-carrier-native
test-ws-carrier-native: $(BLDDIR)/ws_carrier_native ## Actual routed/parked carrier +/- callbacks and owned PTY teardown (standalone).
	$(NIXRUN) sh scripts/check-golden.sh ws_carrier_native=ok timeout 60 python3 tests/pty/ws_carrier_native.py $(BLDDIR)/ws_carrier_native

.PHONY: test-ws-upload-frame
test-ws-upload-frame: $(BLDDIR)/ws_upload_frame ## True upload frame qual: physical AD keys through ws_first.frame/ws_paint/ws_routed + owned fake helper (native CC PTY; standalone until heavy-lane green; Main registers after green).
	$(NIXRUN) sh -c 'set -eu -o pipefail; for token in "ws_first.frame" "WsNet.ws_paint" "WsNet.ws_routed" "T.Timui.open" "T.Timui.close" "T.Timui.tty" "T.Tty.ready" "Chan.recv" "App.main()"; do grep -q "$$token" tests/bend/ws_upload_frame.bend || { printf "%s\n" "frame entry missing: $$token" >&2; exit 1; }; done; for token in "UiKeys" "UploadFetched" "ws_first.painted" "ws_frame" "T.Timui.frame" "session_upload_key" "session_upload_take" "session_upload_present(" "step_enter" "live_step_keys" "upload_spawn" "session_upload_complete" "ws_upload.keyed" "ws_upload.presented" "ws_upload.restored" "Up.offer" "Up.confirm" "Up.take_job" "Up.finish" "Up.cancel" "U.offer" "U.confirm" "U.take_job" "U.finish" "U.cancel" "@unsafe"; do ! grep -q "$$token" tests/bend/ws_upload_frame.bend || { printf "%s\n" "injected-state bypass present: $$token" >&2; exit 1; }; done'
	$(NIXRUN) timeout 120 python3 tests/pty/ws_upload_frame.py ./$(BLDDIR)/ws_upload_frame

# Conditional Notify promotion: apply only after exact runtime/static qualification.
test-review-pure: test-notify-followup-guards test-notify-attr-blocked test-notify-followup-static

.PHONY: test-nix-eval-selftest
test-nix-eval-selftest: ## Synthetic run_phase fixture: orphan timeout verdict and owned-group kill.
	$(NIXRUN) timeout 60 python3 tests/nix_eval_profile.py --self-test

.PHONY: test-workspace-isolation-step
test-workspace-isolation-step: $(BLDDIR)/workspace_isolation_step.js ## Workspace isolation criteria and one-result step projections (JS backend).
	$(NIXRUN) env TEST_TIMEOUT_SECONDS=30 sh scripts/check-golden.sh workspace_isolation_step=ok timeout 30 bun $(BLDDIR)/workspace_isolation_step.js

.PHONY: test-cards-live
test-cards-live: $(BLDDIR)/cards_live.js ## C8 live integration goldens (JS): boundary seam, Session scheduling, worker, endpoint, fullscreen, rows.
	$(NIXRUN) sh scripts/check-golden.sh cards_live=ok timeout 60 bun $(BLDDIR)/cards_live.js

# Bend programs not reachable from `check`. Kept out of test-review-pure until
# one has actually passed. test-dns-live contacts a public resolver; it is
# listed here and is not part of check.
.PHONY: test-orphans
test-orphans: \
	test-cap-notify \
	test-cards-live \
	test-dns-live \
	test-mss-stale-held \
	test-net-live-wait-cell \
	test-notify-binding-gates \
	test-notify-full-witness \
	test-notify-held \
	test-notify-held-blocked \
	test-notify-order \
	test-notify-runtime \
	test-pend \
	test-reader-pongs \
	test-session-drafts \
	test-sessws-s1s5 \
	test-theme-selector-boundaries \
	test-theme-ws-render \
	test-workspace \
	test-workspace-005-source \
	test-workspace-isolation-step \
	test-ws-carrier-native \
	test-ws-first-connect \
	test-ws-media-stage-native \
	test-ws-upload-frame \
	test-wsnet-gates \
	$(BLDDIR)/cards_handoff_native \
	$(BLDDIR)/isupport \
	$(BLDDIR)/isupport_adapters \
	$(BLDDIR)/preferences_history_characterization \
	$(BLDDIR)/preferences_runtime_typecheck

# Passed a focused run; the rest of test-orphans has not been executed.
# sessws-s1s5 carries workspace epoch/composer/runtime oracles that cannot
# normalize as one-law shards under Bun GC; keep them on the check path.
test-review-pure: test-outbound-txn test-draft-nick-rename test-ws-shutdown-pending test-sessws-s1s5
