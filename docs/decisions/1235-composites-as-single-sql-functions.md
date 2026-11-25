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

`invite_within_seats(tenant, email, role, valid_for)` is the first. It checks the
caller's invite permission, counts the memberships, reads the `seats`
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
