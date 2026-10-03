---
"better-supabase": minor
---

Fixes four bugs the performance audit found, one of which changes behavior.

- `findMany` without `orderBy` now orders by the primary key's database names. On a camel-cased table whose key isn't `id` (`customerTags` with `customerId` and `tagId`) it sent `order=customerId.asc`, which PostgREST rejects.
- `topic.send()` no longer closes a subscription on the same topic. realtime-js reuses the open channel for a topic, and `send()` removed it after sending.
- `liveQuery` keeps the shared channel when a listener re-joins in the same tick (React StrictMode remounts), instead of subscribing the new listener to a closing channel.
- A session refresh now times out after `refreshTimeoutMs` (5000 by default, an option of `resolveAuth` and every adapter's `auth`) and counts as a network failure. Before, a hung Auth request blocked every later request carrying the same refresh token. A rejected refresh is reused for ten seconds, like a successful one.

Breaking: where refreshing is off (Server Components, route handlers, prefetches, MCP), a token in its last 60 seconds is now valid until its `exp`. It used to resolve as `{ kind: 'anon', reason: 'expired' }`, so pages rendered signed out in the last minute of every token. `leeway` now only decides when the proxy refreshes.
