---
"better-supabase": patch
---

`gen`, `doctor`, `seed` and `snapshot` now find a local stack that runs on the Supabase CLI's stack engine (`[experimental] stack = true`), which picks its ports per checkout. When no database URL is configured and `supabase/config.toml` sets no `[db] port`, they read `DB_URL` from `supabase status` before falling back to port 54322.
