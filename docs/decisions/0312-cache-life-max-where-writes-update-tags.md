# 0312: Use `cacheLife("max")` where every write calls `updateTag`

- Status: accepted
- Date: 2026-11-07
- Amends: 0310, 0311

## Context

The `nextjs-app-architecture` skill keeps a timer only for data that changes
outside the app's actions. The example app's explicit `cacheLife` calls were
one: `getPlans` with `"hours"`. Reads through `bsb.cached()` take their life
from the library (`stale` 300 seconds, no `revalidate` or `expire` for a
private entry), so the app never chose `max` for any of them.

## Decision

- `getTeams` and `getRoles` call `cacheLife("max")` after `bsb.cached()`: every
  write to the teams calls `updateTag(teamsTag)`, and every permission override
  calls `updateTag(organizationSnapshotTag)`, so the entry has no reason to
  expire on a timer. The comment above the call says so.
- `getPlans` keeps `"hours"` with the reason next to it: the plans change in the
  seed and the Stripe dashboard, outside the app's actions.
- A read gets `cacheLife("max")` only after its writes are listed; a read whose
  rows a webhook, a job or another service writes keeps a shorter profile.

## Consequences

The other reads of the example keep the library's default life. Moving them to
`max` needs the same audit per table, and a library option that names the
profile (`bsb.cached({ life: "max" })`) would let `bsb.cached` apply it, which
is a library change (see `docs/agents/nextjs.md`, "Library specs").
