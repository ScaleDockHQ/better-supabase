---
"better-supabase": patch
---

Doctor runs Supabase's splinter lints with `pgrst.db_schemas` set to the `[api] schemas` in `supabase/config.toml`, so the lints that check exposed schemas report the same findings as the dashboard instead of assuming `public`.
