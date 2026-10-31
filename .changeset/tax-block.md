---
"better-supabase": minor
---

The new `tax` block (`better-supabase/blocks/tax`, category commerce) keeps tax codes per organization
and legal entity, with a type (`sales`, `purchase`, `exempt`, `zero`, `reverse_charge`,
`intra_eu_goods`, `intra_eu_services`, `export` or `margin`), the accounts a code posts to and its
return boxes. Rates are dated: `saveRate` adds one, `rateOn(codeId, date)` reads the one valid on a
day, and a document uses the rate of its date. `computeDocumentTax` returns the totals per code; the
margin scheme taxes the margin (price less cost) and shows no tax amount, and `creditRestrictionBps`
taxes a reduced base. Issuing an invoice resolves its lines to codes (`tax_code_id`, or the
`tax_code` text) and writes `invoice_tax_lines`. `prepareReturn` builds a tax return with box totals
and the intra-EU sales list per customer VAT number, and `fileReturn` freezes it. Imports gain the
`tax_code` and `tax_rate` targets, events `tax_code.created`, `tax_code.updated` and
`tax_return.prepared`, and permissions `tax.read` and `tax.manage`.

Breaking: tax codes moved out of `accounting`. The `accounting_tax_codes` table, the
`saveTaxCode` and `taxCodes` methods and the `save_accounting_tax_code` and
`list_accounting_tax_codes` functions are gone, `accounting` now requires `tax`, and
`accounting.taxReport` reads from `tax_codes`. Call `tax.saveCode` and `tax.codes` instead, and run
`better-supabase upgrade` and `db diff`. The migration guide has the SQL that copies the rows with
their ids. `better-supabase codemod 0.47` lists the old names.
