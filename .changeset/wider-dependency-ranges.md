---
"better-supabase": patch
---

The optional `oxfmt` peer accepts any version from 0.66.0 below 1.0, so `pnpm add -D oxfmt` installs the latest. The runtime dependencies are ranges instead of exact versions: `@supabase/postgrest-js ^2.116.0` (the floor of the `@supabase/supabase-js` peer), `@supabase/ssr ^0.12.7`, `@supabase/server ^1.9.0`, `@supabase/middleware ^1.0.0` and `@standard-schema/spec ^1.1.0`, so an app shares one copy of each with its own Supabase packages. `@supabase/postgrest-typegen` stays at exactly 0.3.1, because 0.4.0 writes a `ComputedFields` key that `supabase gen types` from Supabase CLI 2.119 doesn't write.

The `canAssign` JSDoc no longer says it defaults to true. The `custom` access model requires it. Without it, the `permdock` model lets only owners assign the owner role when the `tenant` module is installed, and lets only the service role assign roles when it isn't. The access kit docs now say the same, and their `custom` example sets `canAssign`, which that model requires.
