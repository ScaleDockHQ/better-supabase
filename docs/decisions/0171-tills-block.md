# 0171: Tills run shifts and post their counts to accounting and banking

- Status: accepted
- Date: 2026-10-31

## Context

A point of sale takes cash. `orders` and `invoices` record the sale, `accounting`
holds the books and `banking` holds the bank statement, but nothing recorded the
drawer: how much cash a shift started with, what moved in and out, what the
cashier counted at the end of the day, and which bank deposit that cash became.

## Decision

`tills` is a block (`better-supabase/blocks/tills`) with five tables: `tills`,
`till_sessions`, `till_movements`, `till_counts` and `till_deposits`. All are
adoptable (ADR 0098). The `pos` preset installs it.

- A till has a currency and an optional accounting cash account. Without the
  account it books nothing. Its currency never changes.
- A till has at most one open session, enforced by a unique partial index. A
  session starts with an opening float in minor units (ADR 0037).
- Movements are `cash_sale` and `cash_in` (added) or `cash_refund` and `cash_out`
  (removed). A refund or cash out cannot take more than the drawer holds, so the
  expected cash never goes below zero. Movements are rows, never edited.
- `close_till_session` counts the drawer from denominations or a total, stores
  the expected cash, the counted cash and the variance, and closes the session.
  A non-zero variance is booked through `accounting_post_source` as the till
  account against the suspense role, an overage as a debit on the till and a
  shortage the other way round.
- `deposit_till_cash` takes counted cash to the bank from a closed session. The
  deposits of a session never exceed its count. The deposit is booked as the bank
  role against the till account and stays `pending`.
- `reconcile_till_deposit` matches a pending deposit to a bank transaction by
  calling banking's `match_bank_transaction` with an `accounting_entry` target,
  then marks the deposit `reconciled`. Banking owns the matching rules.
- The permission keys are `tills.read`, `tills.write` (sessions and movements)
  and `tills.manage` (tills, deposits and reconciliation).

## Alternatives considered

- Posting every cash sale to accounting from the drawer: rejected, since the sale
  already posts through its invoice or order and the drawer would double count.
- Storing the variance as an adjustment movement: rejected, since the count is
  the record of the difference and the accounting entry is its booking.
- Reconciling inside `tills` without banking: rejected, since banking owns
  statements, matching and idempotence.

## Consequences

Cashiers get a traceable shift from float to bank, and the books see only the
difference and the deposit. A till without a cash account keeps the drawer
records and posts nothing. Cash counted in a currency other than the till's is
not supported; each currency is its own till.
