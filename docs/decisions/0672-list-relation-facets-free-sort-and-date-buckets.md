# 0672: Add relation facets, a free sort and date buckets to the list

- Status: accepted
- Date: 2026-11-11
- Amends: 0637, 0662

## Context

ADR 0662 left three parts of `defineListQuery` undone: filters on a related table, grouping by a date
bucket, and a sort the caller composes. Each changes the parsed query, the URL parsers, the OpenAPI and
JSON Schema output and the filter builder. The `list` entry is also a bundle baseline, so none of them
may grow it much.

## Decision

**Relation facets are facets.** A `facets` entry may be `{ relation, column }` instead of a column name.
The relation and the column are typed from the schema. A to-many relation filters with `some` and a
to-one relation with the related row, both through the `where` the list already builds. No new query
field, URL key or parser is needed, so `ListQuery` and its generics do not change. A relation facet has
no counts: its `facetCounts` entry is an empty object, and `nullable` is false, so `__unset__` is refused.

**The free sort is a plugin in its own entry.** `freeSort(betterSupabase, table, { sortable, tiebreak })`
from `better-supabase/list/order` is passed as `defineListQuery`'s `freeSort`. The caller sends up to
three `column:direction` pairs as the `order` URL parameter or `order` input. `ListQuery.order` holds
them, replaces `sort` while set, and ends in the tiebreak column (default the primary key) so keyset
pages stay stable. The core keeps only the hooks (check, order by, serialize, parser, OpenAPI and JSON
Schema fragments), and the checking code ships only to apps that import the entry. Without it, `order`
is not reserved and `order` input is an issue.

**Date buckets are a tag and a helper.** PostgREST aggregates cannot group by a truncated date, so the
`@bsb buckets` tag renders `<table>_date_buckets(unit, tz, from_at, to_at, equals)`, a `security invoker`
function (row security decides the rows) that returns `[{ bucket, count }]`. The unit is checked
against a list, the columns come from the tag and are quoted identifiers, and `equals` narrows by
columns the tag lists, compared as text. `listDateBuckets` in `better-supabase/list/buckets` calls the
function through a callback and turns a list query's facet values into `equals`. The search text and the
filter tree do not reach the function, and a relation facet or `__unset__` is refused with an
`invalid_request` error rather than counted wrongly.

## Alternatives considered

- Put `order` and relation filters into the core without a plugin: the check code alone added about 1.3
  KB to the `list` entry, against 1.3 KB for everything else.
- Date buckets through a filter tree that compiles to SQL: it needs the whole tree in SQL, which ADR 0099
  and `filter-tree-sql.ts` do only for rules.
- A generic function that takes a table name: it would run dynamic SQL on any table the caller may read.

## Consequences

`./list` grew from 24,116 to 25,427 bytes (gzip, +1,311, 5.4 percent): the relation facet branches and
the free sort hooks. That is just past the 5 percent slack, so the baseline moved by this amount and no
more. The new entries are `./list/order` (1,329) and `./list/buckets` (7,627, mostly the shared error
and result classes). The `buckets` tag adds one rendered function per tagged table and no module SQL.
