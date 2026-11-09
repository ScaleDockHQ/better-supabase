# 0441: Import brief items that are verified, measured away or still open

- Status: accepted
- Date: 2026-11-09
- Amends: 0141

## Context

The import brief (areas 1.1 to 11.3) lives outside the repository; the plan names
each item in one line. This record says, per item that did not become code, why.

## Verified as already shipped (no change)

- **5.1 location fallback and 5.2 supplier and item fallbacks.** `import_stock_count`
  (inventory-counts) takes `locationId` or the location's `code`, a line's variant by
  `variantId` or `sku`, its bin and lot by code at that location and variant, and
  refuses each miss with `IMPORT_ITEM_INVALID`. The catalog target `supplier_item`
  resolves supplier and item by code. pgTAP `discount_matrix_stock_counts` runs
  the stock count import and `catalog_identifiers` and `erp_import_04_no_side_effects`
  the supplier item target.
- **1.3 dry-run cancel cleanup and 7.4 back-to-back runs.** Tests added in
  `import_run_edges` (ADR 0432).

## Measured away

- **1.25 set-based classify.** Classifying 3,000 unchanged items one by one (a record
  lookup, a hash compare and one conditional update each) takes 58 to 278 ms in one
  `import_upsert_batch` call, 0.02 to 0.09 ms per item (local stack). The write path
  costs 0.12 ms per item in the one-row target and the batch target alike (ADR 0436).
  A set-based classify would save at most that floor, so it is not built.
- **1.9 five times faster.** Not reproduced; see ADR 0436.

## Still open, with the reason

- **6.2 localized seeds, 1.22 ordered-series warning, 3.1 open-items fast path,
  9.4 `indexes.skip`, 8.2 notNull and 4.6 `sanitizeText` packs.** The plan gives one
  line for each and the brief text is not in the repository, so the behaviour to build
  is not defined here. They need their brief paragraph before code; each is a small
  slice once it exists.
- **The medium items** (7.6, 7.1, 7.2, 1.7, 1.23, 1.24, 1.21, 1.4, 1.10, 1.15 to 1.18,
  4.1, 4.2, 5.3, 3.2, 9.3, 8.1, 8.3, 8.5, 1.27, 6.3, 11.1, 11.3 and the carried
  items), **1.11 to 1.14, 1.19, 3.3, 3.4, 4.3 to 4.5, 5.4, 10.1 to 10.9, 9.5, 9.6 and
  11.2**: not started in this branch. 9.5 waits for PermDock's compact snapshot.

## Consequences

Nothing changes in the library. When the brief paragraphs are added to the repository
(or pasted into an issue), each open item becomes its own slice with a pgTAP test.
