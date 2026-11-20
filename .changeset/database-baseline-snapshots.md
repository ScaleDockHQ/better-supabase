---
"better-supabase": minor
---

Add `better-supabase baseline build`, `apply` and `verify`. `build` replays the migrations once and saves the schema, the migration history rows and, with `--with-seed`, the seeded rows and a storage tarball, keyed by a hash of the migrations and the tool versions. `apply` loads that snapshot into an empty local stack and runs only the newer migrations, and falls back to a full replay when the snapshot does not fit. `verify` checks a restored database against a full replay. The migration history in `supabase/migrations` is not touched.
