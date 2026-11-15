# 1077: Define the block list contract once

- Status: accepted
- Date: 2026-11-15

## Context

Lane Y1 of the example roadmap covers 32 findings that ask for the same thing in different words: a
`page` with a keyset cursor on a list that returns an array (EX-600, EX-901, EX-1100 to EX-1105), a
sort or a list of sorts (EX-033, EX-1101, EX-1105), array-valued filters (EX-1000, EX-401), a text
search `q` (EX-800 to EX-802, EX-1103, EX-1104), `{ value, exact }` from `count` (EX-1205), a facet
list, and `get(id)` on entities that have a list and no get (EX-1215). The generated entity page
(ADR 0859, 0869) and the app reads (ADR 0890) already take all of it, and 195 block folders do not
agree: about 86 blocks still return a bare array, so the example carries five list helpers
(`block-list`, `block-status-list`, `array-list`, `simple-list`, `admin-list`, EX-1294).

The pieces exist: `entityList` (ADR 0749) builds `page`, `facets`, `count` and `export` over one SQL
list function, `PageOptions` carries `q`, `sort` as one term or a list (ADR 0896), `filters` as
lists and the cursor, and `defineEntityListQuery` parses the same options from a URL. What is
missing is one statement of what a block list must offer and a check that a block meets it.

## Decision

A block list is one entity with this surface, and every block moves to it. `apiVersion` stays 1:
each part is additive.

| Read              | Contract                                                                                                                          |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `page(options)`   | A `ListPage`: `items`, `hasMore`, `nextCursor` (null exactly when `hasMore` is false) and, when a sort was asked for, `sorted`    |
| `q`               | Free text over the entity's declared search columns; an entity without `search` returns `invalid_input`                           |
| `sort`            | One declared sort or a list of up to three (ADR 0896); a block that reads fewer terms says so in `sorted.ignored`                 |
| `filters`         | Column to a list of values; a row matches any value of a filter, an empty list leaves it off                                      |
| `after`, `limit`  | The keyset cursor of the applied sort and the page size                                                                           |
| `facets(options)` | The values and counts of each declared facet under the same `q` and filters                                                       |
| `count(options)`  | `{ value, exact }` under the same `q` and filters; `exact` is false only when the count stopped at a cap or came from an estimate |
| `get(id)`         | The row a list returns for that id, or a `not_found` error (never an empty success), for every entity that has a list             |

A block builds these with `entityList`, so `page`, `facets` and `count` read one SQL function and
always agree. The SQL function declares the filters with `filterAny` and the sorts and facets in its
template, ends every sort on the row id, and the manifest's `entities.<key>` carries the same names
(a test already keeps the two equal). `list` stays as the capped convenience and is not removed.

`testBlockList` in `better-supabase/testing` is the conformance helper. It runs against seeded rows
through the same functions an app calls and checks the cursor walk (every row once, in the order of
one big page), the limit, each declared sort and a list of sorts with its report, an array filter as
the union of its single values, `q`, `count` against the page, facet counts against the seeded
counts, and `get` for a known and an unknown id. Each block family's client test runs it, so the
contract is a test and not a convention.

A breaking rename is never part of adopting the contract. A block that returned an array keeps its
call and adds `page`, and the old name is `@deprecated` until the next minor with an entry in the
migration guide.

## Alternatives considered

- Declare the contract as a manifest capability and generate every client: the clients differ in
  row mapping and tenant options, and the audit's refactor 1 covers the manifest separately.
- Bump `apiVersion` to 2: nothing that exists breaks.
- A runtime check inside `entityList`: the contract concerns the SQL function and the seeded data,
  which only a test sees.

## Consequences

Each block family moves in its own PR with SQL functions only where one is missing (a migration that
sorts after main's newest, golden SQL, pgTAP), a test that calls `testBlockList`, its docs page and
a changeset. The example's list helpers go when the blocks they read conform, by moving each page to
a generated entity page or `app.reads`. Lane Y2 and Y6 change the same blocks, so each PR merges
main before it is pushed.
