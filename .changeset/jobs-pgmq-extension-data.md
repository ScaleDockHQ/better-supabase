---
"better-supabase": minor
---

The `jobs` module's data file creates `pgmq` (`create extension if not exists "pgmq"`) on the pgmq backend, so `better-supabase sql data` puts the extension in a migration even when a pg-delta diff leaves it out, and no migration needs a hand edit. Modules declare such extensions with a new `extensions` field. Doctor BS321 warns under pg-delta about a `create extension` in `supabase/schemas`, SQL module files included, that no migration repeats.
