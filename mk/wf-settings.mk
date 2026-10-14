# SPDX-License-Identifier: Apache-2.0
# wf-settings: nicks-setting plumbing gates (fragment; include after Makefile).

.PHONY: test-settings-nicks test-settings-nicks-helper

test-settings-nicks: $(BLDDIR)/settings_nicks_demo ## Nicks setting: /set//toggle, durable intent, legacy-tolerant roundtrip.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh scripts/check-golden.sh settings_nicks_demo=ok timeout 15 ./$(BLDDIR)/settings_nicks_demo

test-settings-nicks-helper: ## Nicks launcher wire/TOML roundtrip with legacy default-fill.
	$(NIXRUN) timeout 45 python3 tests/settings_nicks.py

test-review-pure: test-settings-nicks test-settings-nicks-helper
