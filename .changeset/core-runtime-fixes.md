---
"better-supabase": minor
---

Fix several query runtime bugs.

- `deleteMany` and `updateMany` refuse a `where` that filters nothing (missing, empty, or only `undefined` conditions) with `invalid_request`. Pass `allowAll: true` to `updateMany` to update every row.
- `update` and `updateMany` whose `data` sets no columns return `invalid_request` instead of `not_found`, unless a plugin fills a column in.
- `limit` and `offset` must be non-negative integers.
- Filters send a `Date` as ISO 8601 text, a `null` in an `in` or `notIn` list matches or excludes null rows, and a `*` in `like` and `ilike` patterns is a literal character, as in Postgres.
- A primary key with a `null` or `undefined` part returns `invalid_request` instead of reading or writing with `is null`.
- The validation plugin keeps columns its schema doesn't list, such as `organization_id` from `tenant()`.
- `findOnly` no longer trips the rules plugin's cursor-order rule, and `noDeleteManyWithoutWhere` catches a `where` whose conditions are all `undefined`.
- Reads split for a long `in` list can order by columns they don't select, including the default primary-key order. Writes whose URL is over `urlLengthLimit` return `invalid_request` instead of a 414.
- Read sets abort a batch only once every reader's signal has aborted; a reader whose own signal aborts gets `aborted` right away.
- List facet counts run one aggregate per facet, capped at `facetLimit` values (100 by default), and the page lists cut facets in `facetCountsTruncated`.
- Realtime topic subscriptions share one channel per topic and client, and both topics and live queries drop a channel whose first join failed, so the next subscription joins again.
- Job workers retry transient claim errors with backoff, and a fatal claim error stops every lane before `work` or `drain` rejects.
