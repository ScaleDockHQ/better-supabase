# 0216: App table column groups check a permission in a trigger

- Status: accepted
- Date: 2026-11-03

## Context

ADR 0051 restricts a column for every signed-in user with Postgres column
grants. Apps also need the opposite shape: members may edit a row, but only
those with a stricter permission may change some of its columns, such as a
budget or a cost rate. A grant is the same for every `authenticated` caller, so
it can't depend on a permission that is checked per tenant.

## Decision

`tables.<name>.columnGroups` maps a group name to `{ columns, update }`, where
`update` is a permission key. `sql sync` renders one `before update` trigger
function per table (`app-table-groups.ts`). For each group it raises `42501`
when a listed column changes (`is distinct from`) and
`ctx.scope.can(old.<tenant>, key)` is false. The check runs only when
`current_user` is `authenticated` or `anon`, so the service role, migrations
and security definer functions owned by other roles are not blocked. The
permission is read for the old row's tenant, so a row can't be moved to a
tenant where the caller holds it. The table needs tenant scope, a column
belongs to one group, and every column is one of the table's own.

The pgTAP file checks that the trigger exists. Doctor reports an update policy
whose permission key ends in `.read` or `.view` (BS362), since it lets every
reader write every column.

## Alternatives considered

Column grants (ADR 0051) can't take a permission. A second table for the
restricted columns forces a join and a second policy set. A check in each
`update_*` function misses writes through the Data API.

## Consequences

The trigger adds one function call per updated row and raises the SQLSTATE
that grants raise, so clients handle both alike. A caller that sets a column to
its current value passes. Revisit if Postgres adds permission-aware column
privileges.
