---
"better-supabase": minor
---

`createServer(betterSupabase, { db: { timeout, retry, urlLengthLimit } })` tunes the requests the server makes: the per-request PostgREST client and the shared service and anon clients get the same `retry` and `urlLengthLimit`, and repositories use an executor with the `timeout`. `maxUrlLength` on the definition keeps working. The server reads its environment through `getEnv` from `@supabase/middleware`, so on Workers the bindings a bridge seeds are found before `process.env`.
