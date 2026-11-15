# 0895: List an app page's blocks and read every risk sort term

- Status: accepted
- Date: 2026-11-15

## Context

`pageCoverage` lists the route of an entity page under its block, which an `app.*` entity has none
of: ADR 0890 wrote no coverage entry for it, so the app kept those entries by hand (EX-1267). The
generator also wrote no seed for the incidents page, because the page declared none (EX-1264).
ADR 0896 accepted a list of sorts in `PageOptions`, but the risks block orders by its first term, so
the register's header could not offer a second column without showing an order the rows lack
(EX-033).

## Decision

- `EntityAppSource.blocks` names the blocks whose screen an app page is. `pageCoverage` lists the
  route under each, `defineEntityPage` refuses a blank name, and the strict config schema accepts
  the key. An app page without it writes no entry, as before. The example sets it on the eight app
  pages it declares, so their coverage entries are generated.
- The incidents page declares `seed: { demo: 3, tiers: ["demo"] }`; its block takes a title in
  `attrs`, so `pnpm db:seed:pages` applies the generated rows through `open_incident`.
- The risk register reads its rows through `features/risks/risk-reads.ts`, a reads module in the
  shape of ADR 0890 (`EntityListReads`). It asks the block for the risks that match the search and
  the filters, orders them by every sort term and then by number, and pages them with an offset
  cursor. At most 2,000 risks are read per request. Facets stay the block's.
- The page keeps `risks.risk` as a block entity, not an `app.*` one: the detail page, the form and
  the generated `/api/risks/list` come from the block, and the register's own
  `/api/risks/register` route is the one that reads through the module.
- `RecordListUrlQuery.sort` stays a string, now the URL value as written (`number:desc,nextReviewOn`).
  `RecordListView` follows the first term in the toolbar select, and an optional `sorting` prop
  gives the grid header sorting: the URL owns the state, `manualSorting` is on, and a click reports
  the next terms. A click sorts by one column, a second click flips it, a shift-click adds a
  column, up to three. Lists that pass no `sorting` are unchanged.

## Alternatives considered

- Convert the risks page to an `app.risks` entity: it loses the generated detail, form and route
  that come from the block entity, for a list that only needs a different `page`.
- Page by the block's keyset and sort the ties in memory: the tie groups of a score from 1 to 25
  span many pages on a large register, so a page would hold a variable number of rows.
- Add a second sort parameter to the list kit state: one string already carries the terms in the
  form the generated list query reads.

## Consequences

The register's multi-column sort is exact up to 2,000 risks per request, which is far above what a
register holds. Past it the oldest rows by score are the ones sorted. EX-033 is fixed for the risks
register; other lists still sort by their first term until their block's SQL list function reads
the list. The generated `/api/risks/list` still orders by the first term and reports the rest in
`sorted.ignored`.

The Next.js example's first-load baselines rise by about 1 KB raw on 117 routes and the server
baselines of eight entries by a few bytes to 1.2 KB; the values are the ones CI measured.
