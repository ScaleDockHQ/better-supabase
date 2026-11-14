# 0896: Accept a list of sorts in `PageOptions`

- Status: accepted
- Date: 2026-11-14

## Context

EX-033 asked for a free multi-column sort on the generated lists. ADR 0869 and ADR 0890 left it out
because `PageOptions.sort` is one `{ by, direction? }` and every block's `page` reads it, which looked
like an `apiVersion` 2 change of every entity. The blocks do not read `sort` themselves, though: each
builds its `page` with `entityList`, and the SQL list function behind it implements one named sort
per branch (ADR 0749). Only `entityList` and the list query in `better-supabase/list` touch the field.

## Decision

`PageOptions.sort` accepts `PageSort | readonly PageSort[]`, at most three terms (`MAX_PAGE_SORTS`),
each a declared sort and no column twice. `apiVersion` stays 1 on `EntityPage`: every existing
input is still valid and the single form still parses to the single form.

- `defineEntityListQuery` reads `sort=a:asc,b:desc` or repeated `sort` parameters, checks every term,
  and `toSearchParams` writes the list back. One term stays the object form.
- `entityList` validates the list and sends the SQL function the first term, because the function
  orders by one named sort. The page it returns has `sorted: { applied, ignored }`, so a block that
  honors one term says which terms it left out. The CSV export goes through `page` and follows it.
- The keyset cursor is the cursor of the applied term. A list therefore pages the same rows as its
  first term alone, and `after` from one is valid for the other.
- `EntityPage.sortLists` names the multi-column sorts a page offers. `gen` writes one btree index on
  `(tenant, a, b, id)` for each, the scale file leaves them out, and doctor rule BS636 reports a list
  with no btree index that starts with its columns in that order.
- An app entity (`app.reads`, ADR 0890) owns its `page`, so it can read every term and set `sorted`
  itself.

## Alternatives considered

- Make the SQL list functions order by a list: each function is a fixed set of branches, so a free
  list means dynamic SQL in every block module and a new migration for each. A block adopts the list
  when its function does.
- Bump `apiVersion` to 2: nothing that exists breaks, so the bump would only force every app to
  regenerate.
- Drop the extra terms without a report: a header sort would show an order the rows do not have.

## Consequences

A list of sorts is accepted everywhere and honored by the first term in every block today, and the
page says so. The header-sort UI on the example is not part of this change: the risks page reads the
block's `page`, so a header that adds a second column would show an order the rows do not have, and
the list kit's state (`RecordListUrlQuery.sort`) is one string shared by eight lists. EX-033 stays
partly fixed until a block's SQL list function reads the list.

The size baseline of four block entries (`courses`, `dam`, `events`, `cms`) rises by about 3 KB gzip
each, measured with `pnpm --filter @better-supabase/bundle run update` (the four bundle `entityList`,
which now checks a list of sorts and reports `sorted`); `./list` does not move because
the sort helpers live in a module of their own (`core/page-sort.ts`) with no imports.
