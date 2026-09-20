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
PROTO := src/bend/main.bend
CFLAGS ?= -std=c99 -Wall -Wextra -Wpedantic -O2 -pthread
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
  CFLAGS += -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700
endif

.PHONY: help bootstrap shell update doctor build build-proto build-ui \
        test test-proto test-ui test-feed test-submit test-frame test-net test-dns \
        test-args test-cli test-live proto-parity proof check run run-demo clean ffi-smoke

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

BEND_CFLAGS ?= -std=c11 -Wall -Wextra -O2 -pthread
# Bend's emitted C is huge and trips -Wall/-Wextra noisily; silence only that TU.
BEND_CORE_CFLAGS ?= -std=c11 -O2 -pthread -w
FFI_HELLO := tests/ffi/timui_hello.bend

ffi-smoke: ## M0.5/M0.6: Bend TimUI.hello foreign effect (3 frames).
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend $(FFI_HELLO) -o $(BLDDIR)/timui_hello.c
	$(NIXRUN) sh -c '$$CC $(BEND_CFLAGS) -Isrc/ui $(BLDDIR)/timui_hello.c -o $(BLDDIR)/timui_hello'
	$(NIXRUN) ./$(BLDDIR)/timui_hello

build-proto: ## Build the Bend protocol self-test binary.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend $(PROTO) -o $(BLDDIR)/birc-proto

# Bend emits one C TU for the whole program; rename main → bend_main and link argv shim.
# build/birc_core.c is a build artefact (not source): Bend runtime + app, ~500KB.
BEND_UI_SRCS := $(wildcard src/bend/*.bend) src/ffi/timui_ffi.c src/ffi/dns_ffi.c src/ffi/clock_ffi.c src/ffi/birc_main.c

# Bend program object (slow). Shim is linked separately so argv/DNS edits stay cheap.
$(BLDDIR)/birc_core.o: $(APP) $(filter-out src/ffi/birc_main.c,$(BEND_UI_SRCS))
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend $(APP) -o $(BLDDIR)/birc_bend.c
	$(NIXRUN) sh -c 'sed "s/^int main(/int bend_main(/" $(BLDDIR)/birc_bend.c > $(BLDDIR)/birc_core.c'
	$(NIXRUN) sh -c '$$CC $(BEND_CORE_CFLAGS) -Isrc/ui -Isrc/ffi -c $(BLDDIR)/birc_core.c -o $(BLDDIR)/birc_core.o'

$(BLDDIR)/birc_main.o: src/ffi/birc_main.c
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c '$$CC $(BEND_CFLAGS) -Isrc/ui -Isrc/ffi -c src/ffi/birc_main.c -o $(BLDDIR)/birc_main.o'

$(BLDDIR)/birc: $(BLDDIR)/birc_core.o $(BLDDIR)/birc_main.o
	$(NIXRUN) sh -c '$$CC $(BEND_CFLAGS) $(BLDDIR)/birc_core.o $(BLDDIR)/birc_main.o -o $(BLDDIR)/birc'

build-ui: $(BLDDIR)/birc ## Build Bend TimUI client (src/bend/app.bend).

build: build-proto build-ui ## Build protocol harness and TimUI client.

test-proto: build-proto ## Run Bend protocol golden harness.
	$(NIXRUN) ./$(BLDDIR)/birc-proto

test-feed: ## M1 feed goldens.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/feed_demo.bend -o $(BLDDIR)/feed_demo
	$(NIXRUN) ./$(BLDDIR)/feed_demo

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
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/proto_parity.bend -o $(BLDDIR)/proto_parity
	$(NIXRUN) ./$(BLDDIR)/proto_parity

test-ui: build-ui ## Headless TimUI smoke (--demo --frames 3).
	$(NIXRUN) ./$(BLDDIR)/birc --demo --frames 3
	$(NIXRUN) ./$(BLDDIR)/birc --replay fixtures/demo.irc --frames 1

test-cli: build-ui ## Binary argv errors (no TimUI).
	$(NIXRUN) sh -c './$(BLDDIR)/birc --frames xyz >/dev/null 2>&1; test $$? -eq 2'
	$(NIXRUN) sh -c './$(BLDDIR)/birc --connect >/dev/null 2>&1; test $$? -eq 2'
	$(NIXRUN) sh -c './$(BLDDIR)/birc --help >/dev/null 2>&1; test $$? -eq 2'
	$(NIXRUN) sh -c './$(BLDDIR)/birc --replay >/dev/null 2>&1; test $$? -eq 2'
	$(NIXRUN) sh -c './$(BLDDIR)/birc --replay /no/such/birc.replay >/dev/null 2>&1; test $$? -eq 1'

test-live: build-ui ## Local mock: register + PONG + birc=ok, bounded timeout.
	$(NIXRUN) python3 tests/live_mock.py ./$(BLDDIR)/birc

test: test-proto test-feed test-submit test-frame test-net test-dns test-args proto-parity test-ui test-cli test-live ## Protocol + pure + net + DNS + args + fixtures + UI + live mock.

proof: ## Check LAWS via PROOF.bend (Bend proof checker).
	$(NIXRUN) bend PROOF.bend

check: proof test ## Proofs + protocol tests + UI smoke.

run-demo: build-ui ## Offline TimUI demo with canned IRC transcript.
	$(NIXRUN) ./$(BLDDIR)/birc --demo

run: ## Live IRC client (needs HOST=…; rebuilds only if Bend/FFI sources changed).
	@test -n "$(HOST)" || { printf '%s\n' 'usage: make run HOST=irc.example.net [NICK=birc] [CHAN=#birc] [PORT=6667]' >&2; exit 2; }
	@$(MAKE) build-ui
	$(NIXRUN) ./$(BLDDIR)/birc --connect "$(HOST)" --port "$(PORT)" --nick "$(NICK)" --channel "$(CHAN)"

clean: ## Remove build artefacts (not sources or flake.lock).
	rm -rf $(BLDDIR)
