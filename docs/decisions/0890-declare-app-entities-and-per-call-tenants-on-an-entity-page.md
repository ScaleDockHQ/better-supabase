# 0890: Declare app entities and per-call tenants on an entity page

- Status: accepted
- Date: 2026-11-14

## Context

Lane M4 (ADR 0889) could not declare three pages of the Next.js example. `customers` is an app table,
so no block manifest names its surface. `incidents` takes `organizationId` on every call (a
`RequiredTenantOption`), which the generated route did not pass. The coverage map was checked against
the manifest but still written by hand (EX-1267).

## Decision

`EntityPage` gains two optional fields and `ENTITY_PAGE_OUTPUTS` one output; `apiVersion` stays 1,
because a page without them generates what it did.

- `tenantOption: "organizationId"` names the per-call option a block takes for the organization. The
  list and export routes read `tenant` from the route context and pass it to `page` and `facets`.
- `app` declares an entity no block owns. The entity is named `app.<key>`, and `app` holds the
  `surface` (sorts, facets, filters, search), an optional `table` (so `gen` writes the indexes and the
  scale test) and `reads`, a module and export whose function takes the route's `db` and returns
  `{ page, facets }`. The routes call it in place of `db.<block>.page`. An app entity has no input
  schema, so it writes no form or seed file, and it belongs to no block, so it writes no coverage entry.
- `coverage` writes `pages/coverage.ts`, `pageCoverage`: each block's declared routes. It imports
  nothing, so the example's coverage script loads it, and the hand-written map no longer repeats a
  declared page's route.

The free multi-column sort (EX-033) is not part of this change. `PageOptions.sort` is one column and
each block's `page` reads it, so a list of sorts changes the contract of every entity.

## Alternatives considered

- Teach `defineEntityPage` a table name and build `page` itself: it would move the query compiler into
  the generator and duplicate `defineListQuery`.
- A flag in the catalog for blocks that need `organizationId`: the app already knows, and the
  descriptor is where the other per-page facts sit.

## Consequences

An app table or a block with a per-call tenant is declared like any other page and gets the list,
route, indexes, scale test, columns, nav item and manifest. The reads module is app code, so the
app still owns how its table answers `page`.
