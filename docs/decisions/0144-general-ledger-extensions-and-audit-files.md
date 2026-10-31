# 0144: Extend `accounting` into a general ledger and exchange audit files

- Status: accepted
- Date: 2026-10-30

## Context

`accounting` (ADR 0136) has accounts, journals, periods, entries, dimensions,
FX and reports. Moving a company's books in, and running them, needs more:
account levels and roll-ups, locked periods, opening balances and a year-end
carry forward, open items per party with allocation, aging, work in progress
valuation, purchase approval, payment batches, and files accountants and tax
authorities exchange (SAF-T and the Dutch XAF). The `ledger` block stays the
operational store for balances in any unit (ADR 0065), so none of this goes
there.

## Decision

- **Extend `accounting`, don't add a block.** Accounts gain `normal_side`,
  `level`, `parent_id`, `default_tax_code_id` and `active`. Periods gain
  `locked`; posting into one fails with `ACCOUNTING_PERIOD_LOCKED`. Journals
  gain a contra and a bank account, lines gain `tax_amount`, and cost center
  and cost object become two built-in dimensions.
- **Opening balances and carry forward.** `accounting_opening_balances` and
  `close_fiscal_year` carry balance accounts into the next year's opening
  entry. Reports add `column_balance` and `journal_listing`, and
  `wip_valuation(tenant, as_of)` sums unbilled time and materials at cost.
- **Open items.** `accounting_open_items` per receivable and payable line,
  `allocate_open_items` for partial, over and write-off payments within
  `options.writeOffThreshold`, exchange differences to `fx_gain` and
  `fx_loss`, and `aging(tenant, side, as_of)`. Purchase invoices wait for an
  `approvals` step before booking. `payment_batches` export SEPA
  pain.001.001.09 and pain.008.001.08 from TypeScript, both pinned in
  `SPEC_PINS`.
- **Import into closed periods, never locked ones.** The ledger import target
  (ADR 0141) posts journals, entries and opening balances in import mode.
  A closed period accepts them, a locked one refuses.
- **Audit files are an adapter subpath.** `better-supabase/audit-files` exposes
  `AuditFileAdapter` (`apiVersion: 1`, `export(books)`, `import(xml)`) with
  SAF-T 2.0 and XAF 3.2 adapters over the lazy `fast-xml-parser` peer. Import
  goes through `import_upsert_batch`, so it is repeatable. The SAF-T and XAF
  versions are pinned in `SPEC_PINS`. It is a runtime entry with no Node
  built-ins.

## Alternatives considered

- **A second `general-ledger` block.** It would duplicate accounts, periods and
  entries that `accounting` owns.
- **Put open items on the `ledger`.** Its lines sum to zero per unit and carry
  no party, period or tax data.
- **Audit files in the CLI.** An app needs to export on a schedule and import
  in a job, so the code ships as a library subpath.

## Consequences

- Imported books and native books share one set of tables and reports.
- Round trip is testable: export, import into a fresh organization, export
  again, compare after canonicalization.
- Country audit formats beyond SAF-T and XAF come as adapters under the same
  interface. Revisit the lock model if a country needs per-journal locks.

## As built: general ledger (PR 11)

- **Carry forward stores rows, not an entry.** Reports sum all posted lines, so
  an opening entry on the next year's first day would count the balances twice.
  `close_fiscal_year` writes `carried` rows to `accounting_opening_balances` for
  the next year. Imported rows (`source = 'imported'`) post as one entry with
  `post_accounting_opening_balances`, which is idempotent.
- **Locked beats import mode.** A closed period accepts an import-mode post, a
  locked one refuses, and the lock date still applies to both.
- **`wip_valuation` covers unbilled time only.** Materials are costed on the
  ledger and booked by the accounting postings, so adding them would count
  them twice. The function returns hours, uncosted hours, unrated hours and
  cost and billable totals per currency.
- **`trial_balance` per period** is `accounting_period_trial_balance(period_id)`
  over the existing function. `accounting_column_balance` and
  `accounting_journal_listing` are new.
- **Import entities:** `accounting_account`, `accounting_journal`,
  `accounting_entry`, `accounting_opening_balance`.
