# 1090: Keep expense decisions in the database

- Status: accepted
- Date: 2026-11-18

## Context

An expense without reports is one row of `tables.expenses`, often a table of
the app's own that clients also write through RLS. The block's functions
checked who decides, but the row itself trusted its writer: a client could
set `decided_by`, `decided_at`, `reimbursed_by` or the status directly, an
approved expense could go straight back to draft (`withdrawApproved`), its
amount could change after approval, and the user who created an expense for
someone else could approve it. "Already decided" and "already open" failed
with `55000`, which PostgREST answers with 400, so an app could not tell a
stale screen from a broken request. The leave block already had the rule
that the requester decides only when nobody else can
(`selfDecideWhenTopOfChain`, `otherDecider` in `approvals-tenant.ts`), but
apps could not ask it, so CentraKit copied it into SQL of its own.

## Decision

- A `bsb_expense_guard` trigger runs before every insert and update of the
  expenses table, the block's or the app's. It is security invoker, so
  `current_user` tells a client's own write (`authenticated` or `anon`) from
  one through a security definer function. A client can't write the status
  or the stamp columns (`submittedAt`, `approvedAt`, `rejectedAt`,
  `decidedBy`, `decidedAt`, `decisionNote`, `reimbursedAt`, `reimbursedBy`,
  `reimbursement`), and its new row starts as a draft. Every writer moves the
  status only along `draft`/`submitted` both ways, `submitted` to `approved`
  or `rejected`, `rejected` to `draft` or `submitted`, `approved` to
  `submitted` or `reimbursed`, and `reimbursed` to `approved`. The trigger
  stamps `decidedBy`/`decidedAt` and `reimbursedBy`/`reimbursedAt` and
  clears the decision when an expense goes back to submitted or draft. The
  amount, currency, category and owner are frozen from approved onward; the
  owner changes only in draft, and a client needs the create or update key.
  Writes from other triggers (`pg_trigger_depth() > 1`, such as an
  `on delete set null` foreign key) skip the freeze.
- `decide_expense` refuses the owner and the creator (`createdBy`) unless no
  other eligible decider exists: an active member who holds the approve key,
  or, with `approver: "manager"`, an active manager up the owner's chain.
  `otherDecider` takes the creator as `also` and no longer needs the
  employees block without `manager` or `chain`. The audit entry carries
  `selfDecided`. `expense_self_decides(id)` and `leave_self_decides(tenant)`
  expose the rule to apps.
- `reopen_expense(id, reason)` (a decider who isn't the owner, not once
  reimbursed or invoiced through `options.invoicedColumn`) and
  `reverse_expense_reimbursement(id, reason)` (the reimburse key) are the
  only ways back, with the reason in the audit metadata.
  `options.withdrawApproved` is removed, and `withdraw_expense` refuses a
  decided expense.
- A state conflict raises SQLSTATE `PT409` through `conflict()` in
  `src/sql/shared.ts`. PostgREST answers it with 409 and `mapDbError` maps it
  to `conflict`, next to `BS409`. Other blocks adopt it as they are touched.

## Alternatives considered

- Column grants instead of a trigger: they protect only the block's own
  table, and an app's table is the common case.
- Stamping in each function only: a service role or app function writing the
  row directly would skip it, and the trigger is one place for every writer.
- `23505` with a hint for conflicts: PostgREST answers 409 too, but the error
  would claim a unique violation, and `mapDbError` would set no constraint.
- Keeping `withdrawApproved`: it let an approved expense skip a new
  decision, which is what the transition list exists to prevent.

## Consequences

An app that wrote the status or decision columns itself must call the
functions instead. The reports flow (`decide_expense_report`) keeps its rules;
it moves to the same guard when a report app needs it. A custom access model
that can't answer for other users never lets the owner or creator decide.
