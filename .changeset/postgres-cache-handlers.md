---
"better-supabase": minor
---

`better-supabase/cache-postgres` keeps Next.js `cacheHandlers` entries and Astro route cache responses in Supabase Postgres, so every instance shares them and a tag you expire takes effect on all. It exports `postgresCacheHandler`, `astroPostgresCache` (and `better-supabase/cache-postgres/astro` as the Astro provider entrypoint), `postgresCacheStore` and `postgresCacheSql`, which returns the SQL for two tables that only the service role can read.
