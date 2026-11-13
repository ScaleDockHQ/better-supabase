# 0841: Search pages by an opaque cursor over a capped pool

- Status: accepted
- Date: 2026-11-13

## Context

`search(q)` returns the best `max_results` hits and cannot continue. A list view
needs to browse a tenant's documents without a query, filter them by a few
record columns such as a customer or a status, and page through results.

## Decision

`search_documents` gets a `facets` jsonb column, filled from a record type's
`search.facets` columns with null values left out, and a GIN `jsonb_path_ops`
index. It also gets a `sort_key` column, the first 200 characters of the
normalized title, and a btree index on `(tenant, subject_type, sort_key,
subject_id)` that replaces the `(tenant, subject_type)` index.

`search_page(q, types, tenant, filter, after, page_size)` runs as the caller
and returns `{ items, nextCursor }`. Without `q` it keysets on `(sort_key,
subject_id, subject_type)`. With `q` it scores like `search`, keeps the best 500
candidates, rounds each score to six decimals and pages on `(score,
subject_type, subject_id)`. The cursor is base64url JSON that carries the mode
and, for a query, an md5 of the normalized text, so a cursor from another query
is rejected with `SEARCH_CURSOR_INVALID`. `can_subject` filters after the
cursor, so the page fills from further rows. `search` is unchanged.

## Alternatives considered

- `offset` paging: it rescans earlier rows and shifts when rows change.
- An uncapped ranked query: ranking every match for each page is too slow on a
  large tenant, so a query only pages through its 500 best candidates.
- A column per facet: the set differs per record type, and one GIN index covers
  every combination.

## Consequences

Existing installs reindex to fill the two columns (the module's data file does
it). A record whose facet column is null cannot be found with a filter on it.
