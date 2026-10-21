---
"better-supabase": minor
---

Seed each tenant with the same demo rows. `defineTenantSeed(betterSupabase, (tenant) => fixtures)` in `better-supabase/testing` builds typed fixtures from a tenant id, and `better-supabase seed --tenant <slug>` (or `--tenant '*'`) inserts them for organizations from the organizations block, all in one transaction. The file comes from the new `seed.perTenant` config key (`supabase/seed.tenant.ts` by default). `seedTenantOnCreate(betterSupabase, seed, { sql })` applies the seed to each organization created in development; it runs after the create call and never changes its result.
