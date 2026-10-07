---
"better-supabase": minor
---

`deleteAccount(betterSupabase, service, userId, options)` is exported from `better-supabase/server`, so apps on the `@supabase/server` pipeline (or `withBlock`) delete accounts without `createServer`. `service` is the service-role client itself or a function that returns it.
