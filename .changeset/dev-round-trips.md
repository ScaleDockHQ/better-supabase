---
"better-supabase": minor
---

Development shows how many sequential database round trips a page waits on. `createNext` takes `devRoundTripBudget` (default 4, `false` turns it off) and warns when a render goes over it, naming read sets as the fix. The OpenTelemetry plugin sets `db.round_trips` on each database span, and `better-supabase doctor` reports BS609 for three or more database reads in one `Promise.all`.
