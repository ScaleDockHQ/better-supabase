---
"better-supabase": minor
---

`createPostgres({ attachDatabasePool })` takes `attachDatabasePool` from `@vercel/functions` and calls it with the pool it opens, so a function instance stays alive until its idle connections close. `createServer({ auth: { jwksStore } })` and `verifyPassport({ store })` share the fetched JWKS between instances through a `JwksStore`; `vercelRuntimeCache(getCache)` builds one on the Vercel Runtime Cache. A stored key set keeps the time of its original fetch, so a Supabase key set is still never served more than 600 seconds after it was fetched, and a store that fails or takes over 500 ms is skipped. `accessTokenResolver` takes it as `cache: { store }`.
