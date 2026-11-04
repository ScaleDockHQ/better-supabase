---
"better-supabase": minor
---

Count token verifications and service-role calls per request. `db.$stats()`, the `x-bsb-db-calls` header, the `auth` event and the OpenTelemetry spans now report `verifications` and `adminCalls` next to calls and waves, `expectDbBudget` takes `maxVerifications` and `maxAdminCalls`, and the stats collector falls back to the trace id, `x-vercel-id` or `x-request-id` when a request has no `x-bsb-request-id`. Pass `{ request }` to `bsb.admin()` to attach an admin call to its render.
