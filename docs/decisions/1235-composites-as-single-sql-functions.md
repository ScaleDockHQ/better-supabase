# 1235: Run a composite's all-or-nothing steps as one SQL function

- Status: accepted
- Date: 2026-11-25

## Context

ADR 0196 decision 5 says an all-or-nothing helper is a SQL function. The
composites in `saas`, `people`, `finance` and the other composite blocks still
chain their parts in TypeScript. `saas.inviteWithinSeats` made 10 database calls
in 6 waves in the Next.js example: it read the members, read the `seats`
entitlement and invited, each through a hooked part client, and a failure in the
last step left nothing to undo but also nothing atomic.

## Decision

A composite moves to one SQL function when its steps are set-based and run in
one transaction. The function counts, reads and writes inside the database; the
composite's TypeScript method becomes one call to it.

`invite_within_seats(tenant, email, role, valid_for)` is the first. It runs with the
caller's rights (`invite_member` checks the invite permission), counts the memberships, reads the `seats`
entitlement through `tenant_entitlement_value` and then calls `invite_member`.
A plan without a numeric `seats` value has no cap. `organizations.inviteWithinSeats`
runs it, and `saas.inviteWithinSeats` delegates to that method.

Hook behaviour changes. The parts' TypeScript hooks (`organizations.members`,
`entitlements.seatsLeft`, `organizations.invite`) no longer fire inside the
composite, because the work happens in the database. The composite's own hook
(`saas.inviteWithinSeats`) fires once, and `organizations.inviteWithinSeats`
fires its own hook. The SQL hooks of `invite_member` still run. `canInvite`
still runs before the call. The `seats` meter port, which applies to
`organizations.invite`, is not consulted: the function enforces the same limit
from the entitlement and answers `invalid_request` (SQLSTATE 22023,
`INVITATION_NO_SEAT`) instead of `quota_exceeded`.

## Alternatives considered

- Keep the TypeScript chain and batch the reads: still 3 calls and not atomic.
- Add a new SQL module per composite: dozens of generated files for one
  function; the function sits in the module that owns its main write.

## Consequences

The invite is one call, and two concurrent invites cannot both take the last
seat when the database serialises them on the count. `invitations` now lists
`entitlements` as an optional integration. The `invite_within_seats` function is
public API on the `invitations` module (migration
`20270120010072_invite_within_seats.sql`).

## offboardEmployee

`offboard_with_work(employee, end_date, reason, window_days)` is the second
function, in the `employees` module when `enrollments` and `shifts` are also
installed. It offboards the employee, cancels their active enrollments (not the
onboarding ones, whose program key holds a `:`) and unassigns their open shifts
in the next `window_days` days, and returns the three results. `people.offboard`
makes this one call when the caller passes no id lists, and keeps the step by
step path when it does. The parts' TypeScript hooks (`employees.offboard`,
`enrollments.cancel`, `shifts.unassign`) no longer fire for that path; the
composite's hook does and the SQL hooks of the three functions still run.

Both functions are `security invoker`, so the count of security definer
functions per module does not grow (`practices-baseline.json` is unchanged).
Migration `20270120010073_offboard_with_work.sql` also redefines
`invite_within_seats` as invoker.

## reconcileAccount

`reconcile_bank_account(account, min_score, line_limit)` sits in the `banking`
module. It lists the unmatched transactions, takes the first suggestion of
`suggest_bank_matches` and calls `match_bank_transaction` inside a savepoint, so
a failed match is reported in `failed` and the rest stay. `finance.reconcile`
delegates to the new `banking.reconcile`. The hooks of `banking.reviewQueue` and
`banking.acceptBestMatch` no longer fire there.
