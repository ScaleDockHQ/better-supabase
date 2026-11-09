# 0596: Bump authorization versions when role defaults change

- Status: accepted
- Date: 2026-11-09
- Amends: 0521

## Context

`hook_plan` returns `reuse` when `authz_ver` is current. Membership and
override changes bumped that version. A change to `role_permissions` or
`platform_roles` did not, so a refresh kept the previous permission claim.
Override bumps ran once per row, so a statement that changed many keys bumped
the same member many times. A refresh also reused permissions built for a
different tenant than `app_metadata.tenant_id`.

## Decision

Statement-level triggers bump every member who holds a role whose default keys
changed, and every user whose platform assignment changed. Override bumps are
one statement, not one row. `hook_plan` returns `full` when the permissions
object is non-empty and does not contain the current `app_metadata.tenant_id`.
The browser client calls `refreshSession` on `visibilitychange` when the
access token is inside the 60 second leeway.

## Alternatives considered

- Bumping every user on any role change: cheap to write, and it forces a full
  hook read for people the change does not affect.
- Leaving reuse as it was: a role edit would not show up until something else
  bumped the version.

## Consequences

A role-default edit invalidates reuse for the members of that role. The
fixture schema carries the same triggers so the example database matches the
generator before the next full SQL render.
