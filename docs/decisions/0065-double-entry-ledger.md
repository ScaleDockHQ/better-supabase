# 0065: Keep balances in one double-entry ledger

- Status: accepted
- Date: 2026-10-22

## Context

Three blocks kept their own balance tables: inventory wrote stock movements
to `stock_movements`, leave wrote grants, accruals and requests to
`leave_ledger`, and invoices wrote payments and refunds to
`invoice_payments`. Each had its own append-only trigger, its own idempotency
rule and its own way to sum a balance. The next blocks on the plan (store
credit, loyalty points, gift cards, trust balances, prepaid hours) each
needed the same again. A single-entry table can't show where an amount came
from, and nothing checked that a transfer left as much as it added.

## Decision

The `ledger` module (`src/sql/modules/ledger.ts`, `ledger-functions.ts`,
client `better-supabase/blocks/ledger`) keeps double-entry accounts per
tenant. An account has one unit: an ISO 4217 currency in minor units
(`Money`, ADR 0037) or a custom unit with a fixed scale. A transaction's
entries sum to zero per unit, checked by a deferred constraint trigger;
entries and transactions are append-only and corrected by a reversal.
`ledger_balances` keeps the running balance and the amount held, so reading
a balance is one row. Holds reserve part of the available balance and are
captured into a transaction or released.

Blocks post through `ledger_post` and open their accounts through
`ledger_account_for`; both are internal (not granted to clients). An account
with `managed_by` refuses client postings, so only its block moves it.
Reading follows `ledger.read`, the account's `read_permission` or its
`owner_id`; the read policy uses the set-returning `ledger_read_grants()` so
it doesn't call `can()` per row.

Inventory (stock per variant and location, kind `stock.<reason>`), leave
(an account per member, type and year, kinds `leave.*`) and invoices (a
receivable per invoice and a cash account per currency, kinds
`invoice.payment` and `invoice.refund`) move onto it. This is breaking: each
module bumps its version with an upgrade that copies the old rows into
ledger transactions with the same ids and drops the old table. Their public
functions keep their names and results. Credits, loyalty, gift cards and
trust are account kinds, not modules.

## Alternatives considered

- A balance column per block with a movement log, as before: every new
  balance type repeats the triggers and nothing proves transfers balance.
- A generic single-entry `adjustments` table: simpler, but a transfer
  between two holders becomes two unrelated rows.
- An external ledger service (such as a payments provider's balance API):
  adds a runtime dependency to the core (invariant 1) and can't take part in
  the block's transaction.

## Consequences

New balance types are an account kind and a few `ledger_post` calls. Reports
can join one entries table. Blocks that post pay one extra insert per line
and a deferred check per transaction. Apps that adopted `stock_movements`,
`leave_ledger` or `invoice_payments` lose that mapping and read the ledger
instead (see the 0.13 to 0.14 upgrade guide). We would revisit this if a
block needs entries in two units in one line, which the per-unit balance
check refuses.
