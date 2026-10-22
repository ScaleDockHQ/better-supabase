# 0080: Post recurring charges on the ledger, once per period

- Status: accepted
- Date: 2026-10-22

## Context

The leases, expenses and donations blocks all move money on a schedule or
after a decision: rent every period, a deposit held for the length of a
lease, an approved expense report owed to a member, a pledge charged every
month. Each block could keep its own balance columns (rent due, deposit
held, amount owed, raised per fund), but then every balance exists twice,
once in the block and once in the books, and the two drift as soon as a
posting fails halfway or a job runs twice. The ledger block (ADR 0024,
ADR 0037) already gives append-only, double-entry transactions in bigint
minor units, holds, and an idempotency key per transaction.

Recurring work also runs from schedulers that retry. A rent job that runs
twice, or a charge run that stops after the provider charged a card but
before the database recorded it, must not post or charge a period twice.

## Decision

Balances live only on the ledger. The blocks store what was agreed (the
lease terms, the report lines, the pledge) and the ledger transaction each
posting made, never a running total.

- Each recurring posting is one row per period with a unique key on the
  owner and the period start: `lease_charges (lease, period_start)` and
  `donations (pledge, period_start)`. Its ledger transaction carries a key
  built from the same pair (`leases.rent:<id>:<period start>`), so a second
  run finds the row and posts nothing. `post_due_rent` and
  `due_pledge_installments` walk the periods from the start date and skip
  the ones that have a row.
- A lease's balance due is the balance of its receivable account
  (`leases.rent:<id>`); payments move money off it. A deposit is posted to
  the lease's deposit account and held with `ledger_hold`. Termination
  captures the deduction into rent income, releases the rest and posts the
  refund.
- An expense report posts when its approval in the approvals block is
  final: approvals calls `approve_expense_report`, which books each
  category's total against the member's payable account under the key
  `expense:<id>:approved`. Reimbursement settles the payable from cash under
  `expense:<id>:reimbursed`.
- A pledge installment opens its gift row first and charges the provider
  with the idempotency key `pledge:<id>:<period start>`. A gift opened but
  never charged stays due, and the next run charges it under the same key,
  which the provider deduplicates. A declined charge marks the gift failed
  and isn't retried; any other error leaves it pending. Charges go through
  the versioned `PaymentProvider` interface, so the block imports no SDK.

## Alternatives considered

- **Balance columns on the block's tables.** Faster to read, but every
  balance would need a trigger or a job to stay in step with the ledger, and
  the blocks would disagree with the books after a partial failure.
- **A ledger transaction key without a period row.** The key alone stops a
  second posting, but the block could no longer list the periods it charged
  or tell which periods are due without scanning ledger metadata.
- **Charging the provider before opening the gift row.** A crash between
  the two leaves a charged card with no gift; opening the row first leaves a
  pending gift the next run charges under the same key.

## Consequences

Reports and balances come from one place, and a scheduled job can run as
often as it likes. Reading a balance costs a ledger query instead of a
column read, which the blocks do inside the same function that returns the
row. A lease charges whole periods only: a period that starts before the
lease ends posts in full, and a lease without an end runs until it is
terminated. Offline pledges show up as due and are skipped by the charge
run. Proration, or a provider without idempotency keys, would make us
revisit this.
