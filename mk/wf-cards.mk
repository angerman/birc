# Unit wf-cards: URL-only cards paint zero rows; image-only keeps one row.
.PHONY: test-cards-empty-rows
test-cards-empty-rows: $(BLDDIR)/cards_empty_rows ## URL-only cards paint zero rows in both cascades.
	@mkdir -p $(BLDDIR)
	$(NIXRUN) sh scripts/check-golden.sh cards_empty_rows=ok ./$(BLDDIR)/cards_empty_rows

test-review-pure: test-cards-empty-rows
