---
"better-supabase": patch
---

`bucket.sweep({ olderThan })` recognizes a `Temporal.Instant` from any copy of Temporal by its tag, so an instant from a second polyfill copy is no longer read as a duration. `createJobs(source, queues, { now })` takes a clock for `runAt` delays and schedule runs, and block events on `betterSupabase.events` take their `time` from the definition's `now` option. The Temporal docs now lead with `defineSupabase(schema, { temporal })` and keep `temporal-polyfill/global` as the alternative.
