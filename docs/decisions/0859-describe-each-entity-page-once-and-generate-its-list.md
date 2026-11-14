# 0859: Describe each entity page once and generate its list

- Status: accepted
- Date: 2026-11-14

## Context

The example wrote a `defineListQuery` by hand per table, a `/api/<entity>/list`
route per page and five list helpers for block tables (EX-001, EX-002, EX-1260,
EX-1261, EX-1294). Block entities already declare their `sorts`, `facets`,
`filters` and `search` in the manifest (ADR 0689) and answer `page` and `facets`
(ADR 0749), so the list contract is known. Nothing read it to write the app's
side. The audit program names a page descriptor read by every generator as
proposed ADR 7 and item 9 of the refactor list. Lanes M2 to M4 add columns,
detail pages and forms, seed rows, navigation and the example on top of the
output, so the first slice has to be a shape they can extend.

## Decision

`defineEntityPage` in `better-supabase/list` returns the descriptor of one page:
`entity` (`<block>.<entity>`), `route`, and optional `name`, `reads`, `methods`
and `list`. It also accepts `area`, `columns`, `sections` and `seed`, which lane
M1 only validates; M2 and M3 read them, so their descriptors do not change when
those generators land. The descriptor carries `apiVersion: 1`.

The descriptors go in `gen.entityPages.pages`, next to `appDir`, `server` and
`scaleDir`. The config is the one place `gen` reads, so a page needs no import
resolution from the CLI. `gen` resolves each page against the installed block:
the manifest's list surface (a new `entityLists` field in the preset catalog,
filled by `catalog:check`'s generator), the table and its tenant column.

Output goes through `ENTITY_PAGE_OUTPUTS` in `src/cli/gen/entity-pages.ts`. An
output is `{ apiVersion: 1, id, render(context) }`, where the context holds the
config, the resolved pages, the runtime import and the folder of the page
modules, and `render` returns generated files. Lane M1 registers `list-query`
(`pages/<name>.list.ts`), `list-route` (`<appDir>/api/<name>/list/route.ts`) and
`scale-test` (ADR 0860). The index migration is not an output because it is one
file for all pages; `gen` writes it through the same managed-migration list as
the permission catalog.

`defineEntityListQuery` is the runtime half. It takes the surface and an entity
name, and returns `parse` (URL state), `schema` (a Standard Schema over typed
input), `toSearchParams` and `run`, which reads `page` and `facets` in one wave
under the same filters. It never touches the database itself: the route hands it
the reads, so the generated code does not depend on a block's type.

Extending it, for lanes M2 to M4:

- M2 appends outputs for columns, the detail frame and forms. They read
  `page.columns` and `page.sections` from the resolved page and write
  `pages/<name>.columns.tsx` and the like beside the list module, importing
  `<name>List` for the row type.
- M3 appends outputs for seed rows, the nav item, the route manifest entry, the
  coverage entry and message keys. They read `area` and `seed`.
- M4 switches the example's pages to `gen.entityPages` and deletes the five app
  list helpers.
- A new key in the descriptor is added to `EntityPage`, the valibot schema in
  `src/cli/config-schema-entity-page.ts` and the docs table together. A change
  to the meaning of an existing key, or to `EntityPageOutput`, needs
  `apiVersion: 2`.

## Alternatives considered

- Read descriptors from `*.page.ts` files by glob. This needs the CLI to import
  app code, which `gen` avoids everywhere else.
- A `declare module` registry of pages. Rejected by architecture invariant 2.
- Extend `defineListQuery` to block entities. It builds SQL over the app's
  models and PostgREST; a block entity reads through its SQL list function, so
  the two contracts stay apart.
- Guess `page` and `facets` method names per block. The blocks name them per
  entity (`periodPage`), and the catalog does not carry client method names, so
  the descriptor names them in `methods` and the generated route's typecheck
  catches a wrong name.

## Consequences

A page is a four-line descriptor, and a block's declared surface is the single
source for the list query, its route and its indexes. The generated route has
the same shape as the hand-written ones, so M4 can delete the helpers without a
behavior change. The surface is read from the catalog, so a block upgrade that
changes its sorts changes the generated files on the next `gen`. The cost is
that a page whose entity has several list reads needs `methods` until the
catalog carries them; revisit that when M4 moves the remaining pages.
