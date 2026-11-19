# 1091: Close the expense decision gaps

- Status: accepted
- Date: 2026-11-18
- Amended by: [1093](1093-a-missing-expense-creator-keeps-nobody-out.md)

## Context

The first adoption of ADR 1090 left gaps. `created_by` was neither stamped nor
frozen on a client's own write, so an approver could insert a claim for a
colleague through PostgREST with an empty creator and then decide it. A list
called `expense_self_decides` once per row. `EXPENSE_LOCKED` and
`EXPENSE_TRANSITION_INVALID` still raised `55000`, which `mapDbError` reports
as unknown, and so did other "already" refusals across the blocks. The
"nobody else can decide" rule ignored an app's chain of managers, which the
leave block counts. `invoicedColumn` counted an expense on a cancelled invoice
as invoiced. The approvals queue listed the creator, whose decision was then
refused. Reports had none of the write guards.

## Decision

- The expenses guard stamps `createdBy` with `auth.uid()` on a client's
  insert and refuses a client's change to it. A trusted writer (the service
  role, a security definer function) may name the creator; without one the
  caller, then the owner, is recorded. `createExpense` takes `createdBy`
  from the service role, and `fields.<created_by column>` when the table has
  extra columns. An expense whose creator is null counts the decider as its
  creator, so the decision and `reopen_expense` fail closed: they are allowed
  only when nobody else can decide.
- `expense_self_decides_many(ids)` returns the ids the caller decides as
  owner or creator; `expenseSelfDecidesMany` reads it.
- `options.decider` (`schema.function`, as in leave) lets more callers
  decide a standalone expense, and makes the "nobody else" rule count the
  active managers up the owner's chain. Per approver mode the rule counts: any
  other active member with the approve key; with `approver: "manager"` also
  the direct manager; with a `decider` also every active manager up the chain.
- `options.invoicedCheck` (`schema.function`, `(expense_id uuid) returns
  boolean`) replaces `invoicedColumn` when the invoice's status matters. A
  null answer counts as invoiced.
- A policy snapshot of the approvals block may carry `excludedUserIds`. Those
  users are out of `approval_eligible`, `approval_eligible_ids`, the
  required-all holders and the notifications, and their decision is refused.
  Expenses put the creator there while someone else can decide; it needs the
  policy column.
- The reports flow gets the same guard: `bsb_expense_report_guard` refuses a
  client's write to the stamp columns and the owner, allows only the report
  transitions, stamps `decidedBy` and clears a decision on resubmission, and
  freezes owner and currency from approved onward (for a client, from
  submitted). `bsb_expense_line_guard` freezes lines of an approved,
  reimbursed or cancelled report, and a client's writes to lines of a
  submitted one.
- Conflicts with a record's state raise `PT409` through `conflict()`: the
  expense and report locks and transitions, and the "already" refusals of
  other blocks (51 raises in 26 files).

## Alternatives considered

- Refusing every decision on a null creator: it strands expenses that a
  service import filed without one, even when the decider is the only one.
- A separate `excluded_users` argument on `open_approval`: the snapshot
  already carries per-request facts such as `managerOf`, and a new argument
  would change a function many modules call.
- A free SQL predicate for `invoicedColumn`: a function name keeps the
  config free of SQL text, like `decider`.

## Consequences

The expenses module moves to version 2, whose upgrade step backfills an
empty `created_by` with the owner's user, so only rows whose owner has no user
keep failing closed. `reopen_expense` follows the same "nobody else can"
escape as `decide_expense`. Voiding a credit note restores the original
invoice's derived status from this release on; credit notes voided earlier
are not restored. Apps that catch
`55000` for the converted codes now get `PT409` (HTTP 409, `conflict`).
