---
"better-supabase": minor
---

`entitlements.claim` controls the size and shape of the features claim `feature_claims` writes: `false` writes `{}` (check entitlements in SQL only), `maxTenants` keeps at most that many tenants, and `keys` writes short codes instead of the feature keys. `hasEntitlement` takes `{ claim, keys }` as its last argument to read the short codes, and `EntitlementClaimOptions` is exported.
