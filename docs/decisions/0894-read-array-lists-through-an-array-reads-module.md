# 0894: Read array lists through an array reads module

- Status: accepted
- Date: 2026-11-15

## Context

Deals, pipelines, segments, assignment queues, score models and contracts return their rows as an
array: the block has no list surface, so `page` and `facets` do not exist for them (EX-607,
EX-813, EX-1294). Each overview loaded the array and filtered it in `applyBlockList` with a spec
written beside its component, so none of the six was a declared page and none had indexes or a
scale test. ADR 0890 gave an app entity a reads module, but nothing in the app wrote one for an
array.

## Decision

- `lib/array-reads.ts` exports `arrayReads({ load, spec, facet, wire })`. It loads the array for
  the request's tenant, then searches, filters, sorts and pages it in memory with the same
  `BlockListSpec` the overview uses, and counts the facet after the search. The cursor is the
  offset of the next row. A sort term is the spec's sort name, and a list of terms uses the first
  one, as ADR 0896 describes for a reads module that honors one column.
- `lib/array-list.ts` splits `applyBlockList` into `selectBlockList` (search, facet, sort) and the
  paging, so both the overview and the reads module call the same selection.
- Each list has `features/sales/list-reads/<name>-reads.ts` with its spec, a `…From(db, tenant)`
  loader that returns an `AsyncResult`, and the reads function. The cached loaders call the same
  `…From`, and the overview imports the spec, so there is one copy of each.
- `app.deals`, `app.pipelines`, `app.segments`, `app.queues` (route name `assignment-queues`, because
  `/api/queues` is the job queue), `app.scores` and `app.contracts` are declared with
  `tenantOption: "tenant"` and the block's table, so `gen` writes the list query, route, columns,
  nav item, manifest entry, indexes and `scale_list_<name>.test.sql`.
- Deals and contracts carry `Money`, which JSON cannot hold as a bigint. Their reads module sends
  the amount through `moneyToJson`.

## Alternatives considered

- Give each block a list surface and a SQL list function. That is the lasting fix, but it changes
  six blocks and their SQL; the app can declare the pages now and swap the reads module later.
- Page the array in the database. Deals come from a board call and contracts from one capped list,
  so the rows are already in memory when the page is cut.

## Consequences

The six lists are declared pages with generated indexes and scale tests. The generated route reads
the whole array per request, so its cost is the block call's, and the indexes serve the block's own
list queries rather than this reads module. The overviews still render through `BlockOverview`
(the list kit asks for a page number, not a cursor).
