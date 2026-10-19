---
"better-supabase": minor
---

`loadEnv`, `parseEnv` and `envSchema` read `dbUrl` from `POSTGRES_URL` and then `POSTGRES_URL_NON_POOLING` when `SUPABASE_DB_URL` and `DATABASE_URL` are unset, the names the Vercel Supabase integration and Vercel Postgres set. `createPostgres()` falls back to the same names in the same order.
