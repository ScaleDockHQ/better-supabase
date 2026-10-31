# 0153: Reconcile bank statements in SQL against invoices and the books

- Status: accepted
- Date: 2026-10-31

## Context

Invoices record payments and accounting books them, but nothing read what the
bank says happened. Teams import camt.053 or MT940 files, or pull transactions
from an aggregator, then match each line to the invoice it pays or book it as a
fee or transfer. Collections (ADR 0151) owns how invoice payments and party
credit work, so banking uses the payment functions rather than changing them.

## Decision

- **Five tables.** `bank_accounts` (an IBAN per tenant, an optional journal),
  `bank_statements` (one per `external_id` and account, with opening and
  closing balances), `bank_transactions` (amounts in bigint minor units, signed
  by direction), `bank_matches` (a transaction to an invoice, accounting entry
  or expense report, with an amount) and `bank_rules`. Every foreign key has an
  index.
- **Imports are idempotent.** `import_bank_statement` skips a statement whose
  `external_id` it already has, and a transaction whose `external_id` (or a
  hash of its fields when the file has none) already exists for the account.
  A feed sync reuses it.
- **Parsers in TypeScript.** `parseCamt053` reads camt.053.001.02 and .08
  through `fast-xml-parser`, a lazy optional peer. `parseMt940` is written in
  house, since the format is line based. Both return the same
  `BankStatementInput`, and the versions are pinned in `SPEC_PINS` with
  ISO 11649.
- **Suggestions in SQL.** `suggest_bank_matches` scores open invoices by an RF
  creditor reference or Dutch betalingskenmerk in the structured reference,
  the invoice number in the remittance text, the open balance and a
  counterparty IBAN the party paid from before.
- **Matching uses the invoice payment functions.** An invoice match calls
  `record_invoice_payment`; unmatching refunds it. The amounts must add up to
  the transaction's (`BANK_TRANSACTION_MATCH_INVALID`). The invoices block keeps
  its contract, and collections owns payments that leave a credit.
- **Rules are filter trees.** A bank rule's conditions are a rules filter tree
  over the transaction, compiled to SQL. A rule with an account posts an entry
  in the bank account's journal (source `bank_transaction`); one without
  ignores the transaction. Unmatching reverses that entry.
- **Bank feeds are a port.** `BankFeed` (`apiVersion: 1`, `listAccounts`,
  `transactions(accountRef, since)`) is implemented by provider packages over
  `fetch`. better-supabase bundles none and depends on no bank SDK.
- **Permissions.** `banking.read`, `banking.import`, `banking.reconcile` and
  `banking.manage`; members read and reconcile by default.

## Alternatives considered

- **Parse statements in SQL.** XML in plpgsql is slow to write and test, and an
  app often parses files before it has a database round trip to spend.
- **Bundle an aggregator SDK.** It ties the core to one vendor and breaks
  invariant 1; a port over `fetch` keeps every provider optional.
- **Match against accounting entries only.** Invoices would stay open after the
  bank shows the payment, and the receivable would need a second match.

## Consequences

- Reconciliation compares the latest statement balance with the journal
  account's ledger balance when accounting is installed.
- A partial payment is a match for less than the open balance; the invoice
  stays open until the rest arrives.
- Collections and dunning can read `bank_transactions` for payments that
  arrived but aren't matched yet.
