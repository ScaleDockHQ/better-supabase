---
"better-supabase": minor
---

`bs.admin()` returns an `AdminDb` with `$authAdmin`, the typed Auth admin API (`auth.admin`) of the secret-key client, so cron jobs and webhook handlers can create, invite, ban and delete users without a second client. Request repositories don't have it. The `AdminDb` type is exported from `better-supabase/server`.
