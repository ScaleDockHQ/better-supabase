# 0143: Compute and report tax in a `tax` block

- Status: accepted
- Date: 2026-10-30
- Amended: 2026-10-31 (implementation, PR 7 of the ERP import readiness plan)

## Context

Tax codes live in `accounting` (`accounting_tax_codes`, ADR 0136), and only
quotes keep tax lines (`quote_tax_lines`). Invoices store a total and no
breakdown. Real documents need rates that change over time, several tax
treatments (zero, exempt, reverse charge, intra-EU goods and services, export,
margin scheme), a reduced base for customers with a credit restriction, tax
returns by period and legal entity, and an EU sales list. These belong to
selling and buying as much as to the books, so they can't stay inside
`accounting`.

## Decision

- **A `tax` block.** `tax_codes` (type, sales and purchase accounts, return
  boxes, optional legal entity), `tax_rates` with `valid_from` and `valid_to`
  and `tax_rate_on(code, date)`, `invoice_tax_lines` in the shape of
  `quote_tax_lines`, `tax_returns` built by `prepare_tax_return`, and
  `eu_sales_list_lines` per customer VAT number.
- **One computation.** `compute_document_tax(lines, on_date,
  prices_include_tax, credit_restriction_bps)` returns totals per code.
  The margin scheme taxes the margin (price minus cost) and flags the
  document to show no tax; a credit restriction taxes the reduced base.
  Invoices and quotes both call it. Amounts stay `bigint` minor units
  (ADR 0024, ADR 0037).
- **Tax codes move (breaking).** `accounting_tax_codes` rows copy into
  `tax_codes`, a codemod renames references, and `accounting.tax_report` reads
  from the `tax` block. `accounting` keeps posting to the accounts a code
  names.
- **Accounting requires `tax`.** Keeping accounting usable without `tax` would
  mean two homes for codes and a second `tax_report` path, so the accounting
  module requires `tax` and `accounting_entry_lines.tax_code_id` references
  `tax_codes`. The migration copies each row with its id, so existing lines
  stay valid.
- **Invoices resolve codes at issue.** Invoice lines gain optional
  `tax_code_id` and `unit_cost` columns and keep `tax_code` text and
  `tax_rate_bps`. `issue_invoice` resolves a line's code by id or by text
  (the invoice's legal entity first), takes the rate valid on the issue date,
  falls back to the line's own rate when no code matches, and writes
  `invoice_tax_lines`. A margin scheme line is stored with a rate of 0, so the
  margin tax appears in `invoice_tax_lines` and the return, not in the ledger
  postings. Quote lines keep their text and rate only.
- **The computation runs as the caller.** `tax_compute_lines` is
  `security invoker`, so a caller prices lines only with the codes row level
  security lets them read.
- **Imports take stored totals as given.** A historical document keeps its
  tax totals per code; they are compared with `compute_document_tax` and
  reported on mismatch, never silently replaced (ADR 0141).

## Alternatives considered

- **Keep codes in `accounting`.** Selling without books would need the whole
  accounting block for a tax rate.
- **Compute tax in TypeScript.** SQL documents and imports need the same
  result in the same transaction.
- **A tax provider port only.** A port suits rate lookups from outside; the
  repo still needs the data model and the margin and credit rules.

## Consequences

- Rates are history, so a document created last year re-computes with last
  year's rate.
- Breaking for code that reads `accounting_tax_codes`; the upgrade guide
  covers it.
- Country returns beyond the box mapping and ICP stay an app or adapter
  concern. Revisit if a second country needs a different return shape.
