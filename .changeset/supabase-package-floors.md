---
"better-supabase": minor
---

The Supabase peers now start at their newest releases. `@supabase/supabase-js`, `@supabase/auth-js` and `@supabase/realtime-js` need `^2.119.0` (was `^2.118.0`), `@supabase/server` needs `^1.9.2`, and `@supabase/config` needs `^1.6.1` (was `>=0.9.0 <2`). `@supabase/postgrest-typegen` and `@supabase/mcp-server-supabase` have a floor and no upper bound: `>=0.8.1` (was `>=0.6.0 <0.7`) and `>=0.16.1` (was `>=0.13.0 <0.15`). The CLI is tested against postgrest-typegen 0.8.1, so install that release (`pnpm add -D @supabase/postgrest-typegen@0.8.1`) to keep `database.types.ts` equal to `supabase gen types`.
