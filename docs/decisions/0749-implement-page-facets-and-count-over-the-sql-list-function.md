# 0749: Implement page, facets and count over the SQL list function

- Status: accepted
- Date: 2026-11-13

## Context

ADR 0689 and 0690 fixed the list contract types (`PageOptions`, `ListPage`,
`FacetResult`, `Count`) and left the implementation to lane G. Nine blocks
(`agent-checkout`, `appraisals`, `dam`, `lims`, `maintenance`, `rfqs`, `risks`,
`tills`, `warehouse`) already page by keyset through the SQL list template
(ADR 0637), each with its own option names: one value per filter, a fixed sort,
`total: true` for a count, and no facets. A multi-select cost one call per value
in the app (EX-1203), there was no sort option (EX-1201), no facet counts
(EX-1202), and `count` did not say when it was capped (EX-1205). `sso` pages
its SCIM resources by `startIndex` and `count` as RFC 7644 requires, so it is
not an entity list and keeps that protocol.

## Decision

One SQL list function serves the three reads, so a page, its facet counts and
its count always describe the same rows. `src/sql/list-template.ts` gains:

- `filterAny(key, expr, type)`, a predicate that matches any value of a list
  filter and takes a scalar as a list of one. A missing, null or empty filter
  matches every row, and the cast is on the list so an index on the column stays
  usable. `filterFlag` and `filterFirst` read a flag and a single value.
- `sorts`, a name to its keys. The list renders one read per sort and
  direction, so each order seeks into its own index, and `filters.direction`
  replaces the first key's direction. The last key stays the row id.
- `facets`, a name to a SQL expression. `filters.facet` returns `{ facet,
  values }` counted under the list's own predicates.
- `filters.count`, which returns `{ value, exact }`.

A list that declares `sorts` or `facets` gets these statements and their
variables; every other list renders byte for byte as before. Facet and count
scan at most `totalCap` rows (10,000 by default) and report `exact: false` when
they stopped there; a facet returns at most 100 values.

`src/core/entity-list.ts` ships `entityList({ entity, surface, call, tenant, fn,
rowOf })`, which returns `page`, `facets` and `count`. It checks `sort.by`,
`filters`, `q` and the facets against the entity's declared surface and returns
an `invalid_input` error without calling the database. `EntitySurface` gains
`filters`, the names `page` accepts. The names live in each block's `lists.ts`,
the manifest spreads them into `entities`, and
`tests/blocks/list-surface.test.ts` fails when the manifest and the rendered SQL
name different sorts, facets or filters.

The nine blocks move onto it, each with its own method names kept (`sessionPage`,
`mandatePage`, `rightPage`, `samplePage`, `rfqPage`, `pickListPage`, `planPage`,
`calibrationPage`, `appraisalPage`, `risks.page`) plus `<x>Facets` and
`<x>Count`. Their page option types and `total` and `totalCap` are removed;
`count` replaces the total. Only `risks` declares `search`, because the others
have no search column the SQL reads yet. The `list` methods keep their scalar
options, which the SQL still accepts.

The recipe for the other blocks is in `apps/docs/content/docs/(reference)/extending/blocks.mdx`
under "The list contract" and in `docs/agents/blocks.md`.

## Alternatives considered

- Facets and count as their own SQL functions. Rejected: each would repeat the
  list's predicates, and the two could drift from the page they sit beside.
- One dynamic `order by` with a `case` per sort. Rejected: it cannot use an
  index on the sort keys, and the lists exist to seek into one.
- A PostgREST query on the table instead of the function. Rejected: the
  functions carry the tenant checks, guest rules and row JSON of each block, and
  a table read would bypass them.
- Keeping the scalar filters beside the list ones. Rejected for `page`: two
  shapes per filter is what EX-1203 reports. `list` keeps them for callers that
  have not moved.

## Consequences

The nine blocks that page now take the same options and answer the same
questions. G2 to G5 add the contract to the other blocks by the recipe, and lane
M generates the missing indexes for the sorts. A cursor is valid only for the
sort it came from, because it holds the key values and not the sort name. The
example's `block-list.ts` helpers can go once lane M4 moves it onto this.
Revisit the 100-value facet limit when a facet needs a search box.
