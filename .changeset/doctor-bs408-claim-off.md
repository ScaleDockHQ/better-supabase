---
"better-supabase": patch
---

Doctor BS408 respects `entitlements.claim: false`. With the features claim off, `feature_claims` writes `{}` and `hasEntitlement()` reads the database, so doctor no longer asks to register the claim in the authorization provider's hook; it still checks the functions `has_entitlement` needs. The message for a missing claim now names `claim: false` as the alternative.
