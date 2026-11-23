# 1214: The open-item store holds every open item of today

- Status: accepted
- Date: 2026-11-23
- Replaces: the 3.1 line of ADR 0441

## Context

`invoice_open_items` keeps today's balance of each open invoice so
`open_items_for_party` and `open_items_page` read one table instead of
replaying the ledger. Feedback BS-02 found four ways it differed from the fold
it stands in for. Its trigger and `rebuild_open_items` listed the open statuses
by hand and left out `credited`, which the fold counts with the
`creditedStatus` flag. The trigger did not fire on a charge, a kind change or a
party change. An invoice issued with a future date was skipped and never
written, because nothing ran on its issue date. Unallocated payments were not
stored, so today's read still scanned the ledger for them with a `union all`.

## Decision

The trigger and the rebuild select with the same `openStatus` and
`invoiceKind` predicates as the fold. The invoice trigger fires on insert,
delete and an update of the status, amounts, dates, kind, currency, party
columns and direction; a row trigger on `invoice_charges` refreshes the
charged invoice. A row is kept for an invoice with any issue date, and the
read and the page filter on `issued_on <= as_of`, so a future-dated invoice
shows on its date without a job.

Unallocated payments are rows with `document_type = 'unallocated_payment'`
and the party credit account as `document_id`. A row trigger on
`ledger_balances` writes the row of an `invoice_party` account that the
invoices block manages, so every writer (allocate, unallocate, party payments
and credit) keeps it current. `document_id` no longer references `invoices`,
and a check limits `document_type` to the two kinds.

`open_items_drift(tenant)` returns at most 100 rows where the store and the
fold over invoices and ledger entries differ, each with both balances.
`import_integrity` reports the count as the `open_items_drift` check, and
doctor rule BS638 lists each organization with drift and names
`rebuild_open_items(tenant)` as the fix. A past or future `as_of` keeps the
fold. The invoices block moves to version 4; the upgrade drops the foreign
key and the module data migration rebuilds every organization's rows.

## Alternatives considered

Writing the unallocated rows from `allocate_payment`, `unallocate_payment`,
`record_party_payment` and `apply_party_credit` would have needed a call in
four functions and in every future writer of a credit account. The balances
trigger covers them all, at the cost of one indexed lookup per ledger entry.
A nightly job for future-dated invoices was rejected: the read filter needs no
schedule. A separate table for unallocated payments would have kept the
foreign key but split the page read in two.

## Consequences

On the local stack, 5,000 open invoices over 50 parties read in 67 ms stored
against 81 ms folded for the whole organization, and 1.4 ms against 2.6 ms for
one party (`supabase/tests/scale/scale_open_items_store.test.sql`).
`supabase/tests/database/open_items_store_parity.test.sql` checks that the
drift is empty after a partial payment with credit, a charge, a full credit
note and a future-dated invoice, and that `rebuild_open_items` repairs a lost
row. Breaking: `invoice_open_items` holds unallocated payment rows, so a query
on it that expects only invoices filters on `document_type`.
