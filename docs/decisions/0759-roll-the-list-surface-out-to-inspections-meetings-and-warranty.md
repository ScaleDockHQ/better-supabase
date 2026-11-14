# 0759: Roll the list surface out to inspections, meetings and warranty

- Status: accepted
- Date: 2026-11-13

## Context

ADR 0749 shipped the shared `page`, `facets` and `count` for nine blocks and left
the recipe for lanes G2 to G5. In the work and collaboration categories, only
`inspections`, `meetings` and `warranty` already render their SQL list function
through the keyset list template (ADR 0637) and return `{ items, hasMore,
nextCursor }`, so they take the contract without a change to their paging. The
other blocks of the two categories (`cases`, `incidents`, `assets`, `approvals`,
`deadlines`, `dispatch`, `tasks`, `posts`, `guests`, `comments` and others) page
by `before` timestamps, `after` ids, `maxRows` or a `cursor` string of their
own, or have no page at all. Moving them means changing each block's cursor
shape and its callers, which is a separate decision per block.

## Decision

`inspections`, `meetings` and `warranty` follow the recipe in the blocks
reference. Each gets a `lists.ts` surface that its manifest spreads into the
entity, an `entityList` in its client for `page`, `facets` and `count`, and
`sorts`, `facets` and list filters in the SQL list function. Date filters
(`from`, `to`) and `attendeeId` stay single values read with `filterFirst`.
Inspections and meetings declare `search`, because their SQL reads the `search`
filter; warranty claims have no search column, so `q` returns `invalid_input`.
`warranty` also gets `get_warranty_claim` and `get(id)`, which EX-1215 asks for
and which the entity lacked. The `list` methods keep their scalar options.

The remaining work and collaboration blocks stay on their own paging, listed in
the audit report's Lane G2 progress, and move in follow-up PRs of this lane.

## Alternatives considered

- Convert every list-capable block of the two categories in one PR. Rejected:
  the cursor shape of about thirty lists changes at once, with one migration and
  one golden diff too large to review.
- Wrap the `before`-cursor lists in `entityList` without changing the SQL.
  Rejected: the SQL would not accept `sort`, list filters or `facet`, so the
  three reads could drift from the page.

## Consequences

Three more entities take the same options and answer the same questions as the
nine of ADR 0749. The cursor-based blocks are the larger remaining part of
EX-1200 to EX-1205 and EX-1215 in these categories, so the findings stay partly
fixed until they move.
