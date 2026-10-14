# wf-filter: retroactive presence/nick row filtering fixtures.
.PHONY: test-wf-filter test-wf-filter-toggle test-wf-filter-history

test-wf-filter-toggle: $(BLDDIR)/wf_filter_toggle ## Presence toggle roundtrip: hide, vanish, show identical ids.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh scripts/check-golden.sh wf_filter_toggle=ok timeout 15 ./$(BLDDIR)/wf_filter_toggle

test-wf-filter-history: $(BLDDIR)/wf_filter_history ## Presence history tags: PRS/NCK persist and restore.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh scripts/check-golden.sh wf_filter_history=ok timeout 15 ./$(BLDDIR)/wf_filter_history

test-wf-filter: test-wf-filter-toggle test-wf-filter-history ## Both presence filter fixtures.

test-review-pure: test-wf-filter-toggle test-wf-filter-history
