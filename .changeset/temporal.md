---
"better-supabase": minor
"@better-supabase/cli": minor
---

Breaking: time values in the public API are now `Temporal` values instead of `Date` objects and epoch numbers.

- The `codecs.timestamptz` option takes `'instant'` instead of `'date'`. `timestamptz` columns decode to `Temporal.Instant`, `timestamp` columns to `Temporal.PlainDateTime`, and both keep microseconds. Rename the option and run `better-supabase gen`.
- The `now` options of `defineSupabase`, plugin hooks, `toCloudEvents`, `forwardMutations`, `verifyWebhook` and `bucket.sweep` return a `Temporal.Instant`.
- `Job.enqueuedAt`, `Job.visibleUntil`, `InboxMessage.receivedAt`, `EnqueueOptions.runAt`, the verified webhook `timestamp` and the `signWebhook` `timestamp` are `Temporal.Instant`.
- `bucket.sweep({ olderThan })` takes a `Temporal.Duration` or a `Temporal.Instant` instead of milliseconds.
- TypeScript 5.9 is no longer supported, because it has no Temporal lib. Use TypeScript 6 or 7.

On Node 24, Safari and other runtimes without a native `Temporal`, install `temporal-polyfill` and import `temporal-polyfill/global` once at startup. Without it, the calls that need `Temporal` return a `DbError` that names the import. Auth keeps its `now` option in epoch milliseconds.
