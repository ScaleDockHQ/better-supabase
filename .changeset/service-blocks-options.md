---
"better-supabase": minor
---

`blockSet.serviceBlocks(admin, options)` takes `options.blocks`, a typed map of options per block (a tenant for the comments copy, the Stripe and account resolvers for billing, a TTL for flags, the audit recorder). Each entry is what `block.with(options)` takes and applies for that call only, so a worker can build a different set per tenant or job. `ServiceBlocksOptions` is exported.
