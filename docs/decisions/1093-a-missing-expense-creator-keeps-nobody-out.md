# 1093: A missing expense creator keeps nobody out

- Status: accepted
- Date: 2026-11-19
- Amends: [1091](1091-close-the-expense-decision-gaps.md)

## Context

ADR 1091 counted the decider as the creator of an expense whose `createdBy`
is null, so the decision failed closed: it was allowed only when nobody else
could decide. A company expense has no owner, and one recorded by the service
role or a job has no creator either. Every approver then counted as its
creator, and with two or more approvers each one saw the other as someone
else who could decide, so nobody could decide it.

## Decision

- An expense whose creator is null has no creator to keep out. The owner rule
  is unchanged, and an expense with a creator keeps the rule of ADR 1091: the
  owner or creator decides only when nobody else can.
- `decide_expense`, `reopen_expense`, `expense_approval_decided`,
  `expense_self_decides` and `expense_self_decides_many` follow it.

## Alternatives considered

- Keeping the fail-closed rule and asking apps to stamp a creator on company
  expenses. A service job has no user to stamp, and the version 2 upgrade
  already fills the creator from the owner where there is one, so the only
  rows left without a creator are those with no person to keep out.

## Consequences

An approver may decide an owner-less expense nobody created as a user, like
any other expense. Rows from before the creator stamp that have an owner
still get the owner's user as creator through the version 2 upgrade.

Two cases are left with a null creator, and in both the creator rule no longer
applies:

- The service role calls `create_expense` on behalf of a user without
  `created_by`. The block can't tell who acted, so that user may decide the
  expense unless they are its owner. A service caller acting for a
  user must pass `created_by` (`createExpense({ createdBy })`).
- Owner-less company expenses from before the creator stamp. The version 2
  upgrade has no owner to copy, so they keep a null creator and any approver
  may decide them.
