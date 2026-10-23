---
"better-supabase": minor
---

`better-supabase scaffold api`, the `scaffold` config key (`tooling.scaffold`) and the `scaffold` step of `gen` are removed. `defineApi` from `better-supabase/spec` now includes every app table and block instance by default, and `createOrpc(betterSupabase).router(api)` from `better-supabase/orpc` serves it, so there is no API module to generate. Running `scaffold api` prints that replacement, and a config that still sets `scaffold` fails to load with a message that tells you to delete the key. Delete `lib/api.generated.ts` and the routes `scaffold api` wrote, and serve the router instead: https://bettersupabase.com/docs/frameworks/orpc#serve-the-api
