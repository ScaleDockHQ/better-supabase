---
"better-supabase": minor
---

Every block creator takes a `temporal` option (`BlockTemporalOptions`), so apps on runtimes without a global `Temporal` pass the polyfill's namespace instead of importing `temporal-polyfill/global`. It covers the `create*` functions (`createJobs` and `createRateLimit` take it as a new last argument), `exportAuditLog`, `purgeAuditLog`, `scimHandler` and the settings and onboarding `connect` options, and sets the process-wide namespace like `defineSupabase(schema, { temporal })`. The api-keys and audit blocks no longer read the global `Temporal` directly.
