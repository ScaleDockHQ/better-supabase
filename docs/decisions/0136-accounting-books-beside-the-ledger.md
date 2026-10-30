# 0136: Keep the books in an `accounting` block beside the operational ledger

- Status: accepted
- Date: 2026-10-29

## Context

The `ledger` block (ADR 0065, ADR 0080) keeps balances in any unit: store
credit, stock, leave days and invoice payments. Its accounts are operational
(one per customer, item or employee), its lines sum to zero per unit, and it
has no chart, no periods and no reports. An ERP needs a general ledger in
money: a chart of accounts with types, journals, numbered entries in fiscal
periods that close, a functional currency with exchange rates, tax codes,
dimensions such as project or department, and a trial balance, profit and
loss and balance sheet. Invoices, expenses, stock movements, rent and
donations should then post to it in the same transaction (PR 46).

## Decision

- **A separate block.** `accounting` owns its own tables (`accounting_accounts`,
  `accounting_account_roles`, `accounting_journals`, `accounting_periods`,
  `accounting_entries`, `accounting_entry_lines`, dimensions, FX rates and
  tax codes). The `ledger` stays as it is, for balances in any unit.
- **Money only.** Lines carry `debit` and `credit` in minor units of the
  functional currency (`bigint`, sent as text, ADR 0037), with the
  transaction currency, amount and rate beside them. An entry posts only when
  its debits equal its credits (`ACCOUNTING_ENTRY_UNBALANCED`).
- **Account roles.** Blocks post to a role (`receivable`, `revenue`,
  `tax_payable`, `retained_earnings`, and so on), never to an account code.
  Each organization maps every role to one account; the generic chart maps
  them all, and `chart: "none"` leaves the mapping to the app.
- **Drafts, then posting.** Entries are drafts until `post_accounting_entry`
  checks the balance, the period, the lock date and the dimension values, then
  numbers them per journal and fiscal year (`SAL-2026-00001`) under an
  advisory lock. Posted entries can't change; a reversal posts opposite lines
  and marks the original reversed. `(tenant, source_type, source_id)` is
  unique for entries that aren't reversed, so a document posts once.
- **Periods and years close.** `open_fiscal_year` creates twelve periods from
  the start month. A period closes when it has no drafts and reopens with a
  reason. `close_fiscal_year` moves the year's income and expenses to
  retained earnings in one closing entry, then closes its periods.
- **Settings in the block.** The functional currency, fiscal year start month
  and lock date live in `accounting_settings`, written by `setup_accounting`,
  not in the `settings` block, so posting reads them under the same row
  lock.
- **Reports in SQL.** Trial balance, profit and loss, balance sheet and
  general ledger are `security invoker` functions, so RLS on the entries
  decides what a caller sums.
- **Permissions.** `accounting.read`, `accounting.write`, `accounting.post`,
  `accounting.close` and `accounting.manage`; members hold none by default.

## Alternatives considered

- **Extend the `ledger`.** Adding a chart, periods, currencies and reports to
  the ledger would mix operational units with money, and every stock or
  credit posting would pay for checks it doesn't need.
- **Number entries through the `numbering` block.** Numbering keeps one
  sequence per key and doesn't know fiscal years or journals; the entry
  number depends on the period the posting resolves, so the block numbers
  its own entries inside the posting transaction.
- **Keep settings in the `settings` block.** Settings are tenant JSON with no
  row lock; the lock date must be read in the same transaction that posts.
- **Security definer reports.** They would need their own permission check
  per report; invoker functions reuse the entry policies.

## Consequences

Apps get double-entry books with one `add accounting`. Documents still post
nothing until PR 46 adds the `accounting` contribution, so for now an app
calls `saveEntry` and `postEntry` itself. National charts (RGS and others)
are imported as accounts and role mappings, not shipped. Revisit when
blocks need multi-book accounting (several functional currencies per
organization) or consolidation across organizations.
