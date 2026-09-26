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
        test-pty-bpaste test-pty-mixburst \
        test-pty-quitcap test-pty-tickrate test-pty-paintwake test-pty-joinlat \
        test-pty-manyeof test-pty-geneof test-pty-closequit test-pty-stall test-pty-escup \
        test-pty-tabswitch test-pty-resize test-pty-settings \
        lint-ffi test-utf8-fit test-paste-harness proto-parity proof check run run-demo clean \
        test-perf-cpu test-perf-tickrate test-dns-live test-dns-timeout

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

$(BLDDIR)/birc: $(APP) $(BEND_UI_SRCS) src/ui/timui.h
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend $(APP) -o $(BLDDIR)/birc_bend.c
	$(NIXRUN) sh -c '$$CC $(BEND_CORE_CFLAGS) -Isrc/ui -Isrc/ffi $(BLDDIR)/birc_bend.c -o $(BLDDIR)/birc'

build-ui: $(BLDDIR)/birc ## Build Bend TimUI client (src/bend/app.bend).

build: build-proto build-ui ## Build protocol harness and TimUI client.

test-proto: build-proto ## Run Bend protocol golden harness.
	$(NIXRUN) ./$(BLDDIR)/birc-proto | grep -qx proto_demo=ok

test-feed: ## M1 feed goldens + X1 buf_find linear bound.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/feed_demo.bend -o $(BLDDIR)/feed_demo
	$(NIXRUN) ./$(BLDDIR)/feed_demo | grep -qx feed_demo=ok
	$(NIXRUN) bend tests/bend/feed_bench.bend -o $(BLDDIR)/feed_bench
	$(NIXRUN) timeout 2 ./$(BLDDIR)/feed_bench | grep -qx feed_bench=ok

test-submit: ## M2 submit goldens.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/submit_demo.bend -o $(BLDDIR)/submit_demo
	$(NIXRUN) ./$(BLDDIR)/submit_demo | grep -qx submit_demo=ok

test-frame: ## M4 CRLF framer goldens.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/frame_demo.bend -o $(BLDDIR)/frame_demo
	$(NIXRUN) ./$(BLDDIR)/frame_demo | grep -qx frame_demo=ok

test-net: ## M4 loopback TCP.send/recv + register/pong goldens.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/net_demo.bend -o $(BLDDIR)/net_demo
	$(NIXRUN) ./$(BLDDIR)/net_demo | grep -qx net_demo=ok

test-dns: ## UDP A lookup identity + parse edges (no network).
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/dns_demo.bend -o $(BLDDIR)/dns_demo
	$(NIXRUN) ./$(BLDDIR)/dns_demo | grep -qx dns_demo=ok
	@! grep -F 'Dns.resolve("one.one.one.one")' tests/bend/dns_demo.bend

test-dns-live: ## Live A lookup of one.one.one.one (not in check).
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/dns_live.bend -o $(BLDDIR)/dns_live
	$(NIXRUN) ./$(BLDDIR)/dns_live | grep -qx dns_live=ok

test-dns-timeout: ## K3: blackhole nameserver returns timeout, does not park.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/dns_timeout.bend -o $(BLDDIR)/dns_timeout
	$(NIXRUN) timeout 15 ./$(BLDDIR)/dns_timeout | grep -qx dns_timeout=ok

test-args: ## CLI flag parse (missing values, bad numbers, --connect).
	@mkdir -p $(BLDDIR)
	$(NIXRUN) bend tests/bend/args_demo.bend -o $(BLDDIR)/args_demo
	$(NIXRUN) ./$(BLDDIR)/args_demo | grep -qx args_demo=ok
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
	$(NIXRUN) ./$(BLDDIR)/proto_parity | grep -qx proto_parity=ok

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

test-pty-redial: build-ui ## Pty: partial line then Eof; /connect 001 sends JOIN in 100 ms (A1).
	$(NIXRUN) python3 tests/pty/redial.py ./$(BLDDIR)/birc

test-pty-rst: build-ui ## Pty: TCP RST keeps the UI alive (A3).
	$(NIXRUN) python3 tests/pty/rst.py ./$(BLDDIR)/birc

test-pty-tinyquit: build-ui ## Pty: /quit at 1-2 cols and after resize-back (A6).
	$(NIXRUN) python3 tests/pty/tinyquit.py ./$(BLDDIR)/birc

test-pty-tabcut: build-ui ## Pty: long UTF-8 tab label cut on a code point (A7).
	$(NIXRUN) python3 tests/pty/tab_cut.py ./$(BLDDIR)/birc

test-pty-paste50: build-ui ## Pty: burst paste 50/100/300 lines, then /quit (X3).
	$(NIXRUN) python3 tests/pty/paste50.py ./$(BLDDIR)/birc 50
	$(NIXRUN) python3 tests/pty/paste50.py ./$(BLDDIR)/birc 100
	$(NIXRUN) python3 tests/pty/paste50.py ./$(BLDDIR)/birc 300

test-pty-bpaste: build-ui ## Pty: bracketed paste 10/60/300 lines, then /quit (B1).
	$(NIXRUN) python3 tests/pty/bpaste.py ./$(BLDDIR)/birc 10
	$(NIXRUN) python3 tests/pty/bpaste.py ./$(BLDDIR)/birc 60
	$(NIXRUN) python3 tests/pty/bpaste.py ./$(BLDDIR)/birc 300

test-pty-mixburst: build-ui ## Pty: text+Backspace+arrows+Enter burst (B3).
	$(NIXRUN) python3 tests/pty/mixburst.py ./$(BLDDIR)/birc 200

test-pty-quitcap: build-ui ## Pty: /quit after a SEND_CAP burst still sends QUIT (X2).
	$(NIXRUN) python3 tests/pty/quitcap.py ./$(BLDDIR)/birc

test-pty-tickrate: build-ui ## Pty: parked --demo idle CPU <= 1.0% (K2).
	$(NIXRUN) python3 tests/pty/tickrate.py ./$(BLDDIR)/birc

test-pty-geneof: build-ui ## Pty: late Eof from the old server does not drop the new one.
	$(NIXRUN) python3 tests/pty/gen_eof.py ./$(BLDDIR)/birc

test-pty-closequit: build-ui ## Pty: server close then /quit exits (12 runs).
	$(NIXRUN) python3 tests/pty/close_then_quit.py ./$(BLDDIR)/birc

test-pty-stall: build-ui ## Pty: PONG while the terminal is not read (F1).
	$(NIXRUN) python3 tests/pty/stall.py ./$(BLDDIR)/birc

test-pty-escup: build-ui ## Pty: Esc split across reads is one Up, lone Esc quits (F2).
	$(NIXRUN) python3 tests/pty/esc_up.py ./$(BLDDIR)/birc

test-pty-paintwake: build-ui ## Pty: incoming line paints within 100 ms after idle (P1).
	$(NIXRUN) python3 tests/pty/paint_wake.py ./$(BLDDIR)/birc

test-pty-joinlat: build-ui ## Pty: 001 to JOIN under 100 ms (P1 handshake).
	$(NIXRUN) python3 tests/pty/join_latency.py ./$(BLDDIR)/birc

test-pty-manyeof: build-ui ## Pty: 12 one-write /connect after FIN/RST idle (note 16).
	$(NIXRUN) python3 tests/pty/many_eof.py ./$(BLDDIR)/birc

test-pty-tabswitch: build-ui ## Pty: 1-press / 1-click tab switching.
	$(NIXRUN) python3 tests/pty/tab_switch.py ./$(BLDDIR)/birc

test-pty-resize: build-ui ## Pty: dynamic window resize expand and shrink.
	$(NIXRUN) python3 tests/pty/resize.py ./$(BLDDIR)/birc

test-pty-settings: build-ui ## Pty: /settings panel, /set, and /toggle commands.
	$(NIXRUN) python3 tests/pty/settings.py ./$(BLDDIR)/birc

test-pty: test-pty-flood test-pty-restore test-pty-rows test-pty-tall test-pty-composer test-pty-eof test-pty-connect test-pty-demo-nick test-pty-linger test-pty-utf8 test-pty-minus test-pty-redial test-pty-rst test-pty-tinyquit test-pty-tabcut test-pty-paste50 test-pty-bpaste test-pty-mixburst test-pty-quitcap test-pty-tickrate test-pty-paintwake test-pty-joinlat test-pty-manyeof test-pty-geneof test-pty-closequit test-pty-stall test-pty-escup test-pty-tabswitch test-pty-resize test-pty-settings ## Pty loop tests.

test: test-proto test-feed test-submit test-frame test-net test-dns test-dns-timeout test-args proto-parity test-ui test-cli test-live test-pty ## Protocol + pure + net + DNS + args + fixtures + UI + live mock + pty.

proof: ## Check LAWS via PROOF.bend (Bend proof checker).
	$(NIXRUN) bend PROOF.bend

LINT_FFI_CFLAGS := -std=c11 -Wall -Wextra -pedantic -Wshadow -Wconversion -Wsign-conversion -Wcast-qual -Wno-unused-command-line-argument -fsyntax-only
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
	$(NIXRUN) sh -c '$$CC -std=c11 -Wall -Wextra -Werror -I src/ffi -o $(BLDDIR)/utf8_fit_cap tests/utf8_fit_cap.c && ./$(BLDDIR)/utf8_fit_cap | grep -qx utf8_fit_cap=ok'
	@grep -F 'birc_utf8_fit(s, (size_t)len < 63 ? (size_t)len : (size_t)63)' src/ffi/timui_ffi.c >/dev/null

test-paste-harness: ## F3/F4: paste UTF-8 lossless hold and tail.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh -c '$$CC -std=c11 -Wall -Wextra -Werror -I src/ui -o $(BLDDIR)/paste_harness tests/paste_harness.c && ./$(BLDDIR)/paste_harness | grep -qx paste_harness=ok'

test-perf-cpu: build-ui ## 15 s idle/flood CPU (not in check).
	$(NIXRUN) python3 tests/perf/cpu_pty.py ./$(BLDDIR)/birc

test-perf-tickrate: build-ui ## 600-frame idle tickrate (not in check).
	$(NIXRUN) python3 tests/perf/tickrate_pty.py ./$(BLDDIR)/birc 600 30 100

check: proof test lint-ffi test-paste-harness ## Proofs + protocol tests + UI smoke + FFI lint + paste harness.

run-demo: build-ui ## Offline TimUI demo with canned IRC transcript.
	$(NIXRUN) ./$(BLDDIR)/birc --demo

run: ## Live IRC client (needs HOST=…; rebuilds only if Bend/FFI sources changed).
	@test -n "$(HOST)" || { printf '%s\n' 'usage: make run HOST=irc.example.net [NICK=birc] [CHAN=#birc] [PORT=6667]' >&2; exit 2; }
	@$(MAKE) build-ui
	$(NIXRUN) ./$(BLDDIR)/birc --connect "$(HOST)" --port "$(PORT)" --nick "$(NICK)" --channel "$(CHAN)"

clean: ## Remove build artefacts (not sources or flake.lock).
	rm -rf $(BLDDIR)
