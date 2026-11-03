---
"better-supabase": minor
---

The `rate-limit` SQL module is at version 2: `rate_limit_rules` gets `organization_id`, so a scope has one global rule and one rule per organization. `RateLimit.setRule({ scope, organizationId, max, period })` writes it (`set_organization_rate_limit` in SQL), and `check` and `checkAll` take `organizationId` to apply it. `hit_rate_limit` and `check_rate_limit` take a fifth `organization_id` argument. Run `better-supabase upgrade` to add the column and drop the primary key on `scope`.
