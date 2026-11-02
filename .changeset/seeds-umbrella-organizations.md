---
"better-supabase": minor
---

The `organizations` block now installs a `seeds` module with `seed_tenant_defaults(tenant, variants, locale)`, which calls the `seed_<block>_defaults` function of every installed block that declares rows, in install order. `create_organization` calls it for the new organization unless `database.seed.defaults` is `false` or its `onCreate` is `false`, and the configured `locale` and `variants` become the function's defaults. The `developer-api` preset now also installs `housekeeping`, which runs notification digests.
