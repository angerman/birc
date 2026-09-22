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
.PHONY: help bootstrap shell update doctor build build-proto build-ui \
        test test-proto test-ui test-feed test-submit test-frame test-net test-dns \
        test-args test-cli test-live test-pty test-pty-flood test-pty-rows \
        test-pty-restore test-pty-composer test-pty-eof test-pty-connect \
        test-pty-demo-nick test-pty-linger test-pty-utf8 test-pty-minus \
        test-pty-tall test-pty-redial test-pty-rst test-pty-tinyquit test-pty-tabcut test-pty-paste50 \
        test-pty-quitcap test-pty-tickrate test-pty-paintwake \
        lint-ffi test-utf8-fit proto-parity proof check run run-demo clean

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
	$(NIXRUN) bend $(PROTO) -o $(BLDDIR)/birc-proto

# Bend emits one C TU (runtime + app). --help is Bend's runtime CLI;
# birc usage is --help-irc (args.bend).
BEND_UI_SRCS := $(wildcard src/bend/*.bend) src/ffi/timui_ffi.c src/ffi/dns_ffi.c src/ffi/clock_ffi.c

$(BLDDIR)/birc: $(APP) $(BEND_UI_SRCS)
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend $(APP) -o $(BLDDIR)/birc_bend.c
	$(NIXRUN) sh -c '$$CC $(BEND_CORE_CFLAGS) -Isrc/ui -Isrc/ffi $(BLDDIR)/birc_bend.c -o $(BLDDIR)/birc'

build-ui: $(BLDDIR)/birc ## Build Bend TimUI client (src/bend/app.bend).

build: build-proto build-ui ## Build protocol harness and TimUI client.

test-proto: build-proto ## Run Bend protocol golden harness.
	$(NIXRUN) ./$(BLDDIR)/birc-proto

test-feed: ## M1 feed goldens + X1 buf_find linear bound.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/feed_demo.bend -o $(BLDDIR)/feed_demo
	$(NIXRUN) ./$(BLDDIR)/feed_demo
	$(NIXRUN) bend tests/bend/feed_bench.bend -o $(BLDDIR)/feed_bench
	$(NIXRUN) timeout 2 ./$(BLDDIR)/feed_bench

test-submit: ## M2 submit goldens.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/submit_demo.bend -o $(BLDDIR)/submit_demo
	$(NIXRUN) ./$(BLDDIR)/submit_demo

test-frame: ## M4 CRLF framer goldens.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/frame_demo.bend -o $(BLDDIR)/frame_demo
	$(NIXRUN) ./$(BLDDIR)/frame_demo

test-net: ## M4 loopback TCP.send/recv + register/pong goldens.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/net_demo.bend -o $(BLDDIR)/net_demo
	$(NIXRUN) ./$(BLDDIR)/net_demo

test-dns: ## UDP A lookup (identity + parse edges; live A may time out offline).
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/dns_demo.bend -o $(BLDDIR)/dns_demo
	$(NIXRUN) ./$(BLDDIR)/dns_demo

test-args: ## CLI flag parse (missing values, bad numbers, --connect).
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/args_demo.bend -o $(BLDDIR)/args_demo
	$(NIXRUN) ./$(BLDDIR)/args_demo

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
	$(NIXRUN) ./$(BLDDIR)/proto_parity

test-ui: build-ui ## Headless TimUI smoke (--demo --frames 3).
	$(NIXRUN) ./$(BLDDIR)/birc --demo --frames 3
	$(NIXRUN) ./$(BLDDIR)/birc --replay fixtures/demo.irc --frames 1

test-cli: build-ui ## Binary argv errors (no TimUI).
	$(NIXRUN) sh -c './$(BLDDIR)/birc --frames xyz >/dev/null 2>&1; test $$? -eq 2'
	$(NIXRUN) sh -c './$(BLDDIR)/birc --connect >/dev/null 2>&1; test $$? -eq 2'
	$(NIXRUN) sh -c './$(BLDDIR)/birc --help-irc >/dev/null 2>&1; test $$? -eq 2'
	$(NIXRUN) sh -c './$(BLDDIR)/birc --replay >/dev/null 2>&1; test $$? -eq 2'
	$(NIXRUN) sh -c './$(BLDDIR)/birc --replay /no/such/birc.replay >/dev/null 2>&1; test $$? -eq 1'

test-live: build-ui ## Local mock: register + PONG + birc=ok, bounded timeout.
	$(NIXRUN) python3 tests/live_mock.py ./$(BLDDIR)/birc

test-pty-flood: build-ui ## Pty: 400 server chunks (C1 deadlock).
	$(NIXRUN) python3 tests/pty/chunk_flood.py ./$(BLDDIR)/birc 400

test-pty-rows: build-ui ## Pty: newest body line is painted (C3).
	$(NIXRUN) python3 tests/pty/body_rows.py ./$(BLDDIR)/birc

test-pty-tall: build-ui ## Pty: newest line on 40- and 90-row terminals (R6).
	$(NIXRUN) python3 tests/pty/tall_rows.py ./$(BLDDIR)/birc 40 80
	$(NIXRUN) python3 tests/pty/tall_rows.py ./$(BLDDIR)/birc 90 120

test-pty-restore: build-ui ## Pty: cooked mode after exit (C2 atexit/close).
	$(NIXRUN) python3 tests/pty/restore.py ./$(BLDDIR)/birc

test-pty-composer: build-ui ## Pty: composer length + history Down clears (C8).
	$(NIXRUN) python3 tests/pty/composer_pty.py ./$(BLDDIR)/birc

test-pty-eof: build-ui ## Pty: server close keeps the UI alive (H3).
	$(NIXRUN) python3 tests/pty/eof_pty.py ./$(BLDDIR)/birc

test-pty-connect: build-ui ## Pty: /connect does not freeze the UI (H4).
	$(NIXRUN) python3 tests/pty/connect_pty.py ./$(BLDDIR)/birc

test-pty-demo-nick: build-ui ## Pty: --demo --nick bob registers as bob (H5).
	$(NIXRUN) python3 tests/pty/demo_nick.py ./$(BLDDIR)/birc

test-pty-linger: build-ui ## Pty: boot_clock does not linger 8 s after quit (H6).
	$(NIXRUN) python3 tests/pty/linger.py ./$(BLDDIR)/birc

test-pty-utf8: build-ui ## Pty: UTF-8 split + Latin-1 fallback + CJK (H7).
	$(NIXRUN) python3 tests/pty/utf8_split_pty.py ./$(BLDDIR)/birc

test-pty-minus: build-ui ## Pty: connect refused, 433 retry, close mid-line (T7).
	$(NIXRUN) python3 tests/pty/live_minus.py ./$(BLDDIR)/birc

test-pty-redial: build-ui ## Pty: partial line then Eof; /connect 001 sends JOIN (A1).
	$(NIXRUN) python3 tests/pty/redial.py ./$(BLDDIR)/birc

test-pty-rst: build-ui ## Pty: TCP RST keeps the UI alive (A3).
	$(NIXRUN) python3 tests/pty/rst.py ./$(BLDDIR)/birc

test-pty-tinyquit: build-ui ## Pty: /quit at 1-2 cols and after resize-back (A6).
	$(NIXRUN) python3 tests/pty/tinyquit.py ./$(BLDDIR)/birc

test-pty-tabcut: build-ui ## Pty: long UTF-8 tab label cut on a code point (A7).
	$(NIXRUN) python3 tests/pty/tab_cut.py ./$(BLDDIR)/birc

test-pty-paste50: build-ui ## Pty: 50-line paste all reach the server (M17).
	$(NIXRUN) python3 tests/pty/paste50.py ./$(BLDDIR)/birc

test-pty-quitcap: build-ui ## Pty: /quit after a SEND_CAP burst still sends QUIT (X2).
	$(NIXRUN) python3 tests/pty/quitcap.py ./$(BLDDIR)/birc

test-pty-tickrate: build-ui ## Pty: idle <= 2 ticks/s and CPU <= 0.5% (P1).
	$(NIXRUN) python3 tests/pty/tickrate.py ./$(BLDDIR)/birc

test-pty-paintwake: build-ui ## Pty: incoming line paints within 100 ms after idle (P1).
	$(NIXRUN) python3 tests/pty/paint_wake.py ./$(BLDDIR)/birc

test-pty: test-pty-flood test-pty-restore test-pty-rows test-pty-tall test-pty-composer test-pty-eof test-pty-connect test-pty-demo-nick test-pty-linger test-pty-utf8 test-pty-minus test-pty-redial test-pty-rst test-pty-tinyquit test-pty-tabcut test-pty-paste50 test-pty-quitcap test-pty-tickrate test-pty-paintwake ## Pty loop tests.

test: test-proto test-feed test-submit test-frame test-net test-dns test-args proto-parity test-ui test-cli test-live test-pty ## Protocol + pure + net + DNS + args + fixtures + UI + live mock + pty.

proof: ## Check LAWS via PROOF.bend (Bend proof checker).
	$(NIXRUN) bend PROOF.bend

LINT_FFI_CFLAGS := -std=c11 -Wall -Wextra -pedantic -Wshadow -Wconversion -Wno-unused-command-line-argument -fsyntax-only
lint-ffi: test-utf8-fit ## Syntax-only warning lint of src/ffi (real build stays -w).
	$(NIXRUN) sh -c '$$CC $(LINT_FFI_CFLAGS) -I tests/lint-ffi -I src/ffi -isystem src/ui tests/lint-ffi/lint_timui.c'
	$(NIXRUN) sh -c '$$CC $(LINT_FFI_CFLAGS) -I tests/lint-ffi -I src/ffi -isystem src/ui tests/lint-ffi/lint_clock.c'
	$(NIXRUN) sh -c '$$CC $(LINT_FFI_CFLAGS) -I tests/lint-ffi -I src/ffi -isystem src/ui tests/lint-ffi/lint_dns.c'
	@awk 'BEGIN{u=0;b=0;p=0;q=0} /if \(!ui\) \{/{p=1} p&&/birc_drop_ops/{u=1} p&&/return birc_frame_out/{p=0} /if \(!timui_begin/{q=1} q&&/birc_drop_ops/{b=1} q&&/return birc_frame_out/{q=0} END{if(!(u&&b)){print "drop_ops: early returns must consume ops"; exit 1}}' src/ffi/timui_ffi.c
	@! grep -E 'rows[[:space:]]*-[[:space:]]*6' src/ffi/timui_ffi.c

test-utf8-fit: ## A7: tab-label 63-byte cap is a UTF-8 boundary.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c '$$CC -std=c11 -Wall -Wextra -Werror -o $(BLDDIR)/utf8_fit_cap tests/utf8_fit_cap.c && ./$(BLDDIR)/utf8_fit_cap'
	@grep -F 'birc_utf8_fit(s ? s : "", (size_t)len < 63 ? (size_t)len : (size_t)63)' src/ffi/timui_ffi.c >/dev/null

check: proof test lint-ffi ## Proofs + protocol tests + UI smoke + FFI lint.

run-demo: build-ui ## Offline TimUI demo with canned IRC transcript.
	$(NIXRUN) ./$(BLDDIR)/birc --demo

run: ## Live IRC client (needs HOST=…; rebuilds only if Bend/FFI sources changed).
	@test -n "$(HOST)" || { printf '%s\n' 'usage: make run HOST=irc.example.net [NICK=birc] [CHAN=#birc] [PORT=6667]' >&2; exit 2; }
	@$(MAKE) build-ui
	$(NIXRUN) ./$(BLDDIR)/birc --connect "$(HOST)" --port "$(PORT)" --nick "$(NICK)" --channel "$(CHAN)"

clean: ## Remove build artefacts (not sources or flake.lock).
	rm -rf $(BLDDIR)
