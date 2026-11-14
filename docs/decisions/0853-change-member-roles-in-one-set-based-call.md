# 0853: Change member roles in one set-based call

- Status: accepted
- Date: 2026-11-14

## Context

EX-515: the members table changed a role with one `update_member_role` request
per member, so 200 members were 200 round trips and a half-finished state when
the tab closed.

## Decision

The organizations module adds `update_member_roles(organization, members uuid[],
role text) returns jsonb`. It runs `update_member_role` for each distinct member
in its own subtransaction, so every check of the single call (permission, own
role, role ceiling, owner rule, suspended organization) and its event, audit row
and hook still apply per member. It returns `{ succeeded, failed: [{ id, code,
message }] }`, and more than 500 members raise `BULK_TOO_MANY` (22023). The client
method `organizations.updateMemberRoles({ organizationId, userIds, role })`
returns the common `BulkReport` and emits `organization.role_changed` for each
success. The migration is `20270117120012_l_update_member_roles.sql`.

## Alternatives considered

- A set-based `update` without the per-member function: it would repeat the
  checks and drift from `update_member_role`.
- Put the checks in the client: the database must stay the authority.

## Consequences

One round trip for the table. A refused member does not undo the others, which
is what a bulk bar shows. The members controller keeps its per-member
`setRole` until an app asks for a multi-select.
