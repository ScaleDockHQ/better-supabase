---
"better-supabase": patch
---

Doctor BS408 respects `entitlements.claim: false`. With the features claim off, `feature_claims` writes `{}` and `hasEntitlement()` reads the database, so doctor no longer asks to register the claim in PermDock's hook; it still checks the helpers `has_entitlement` needs. The message for a missing claim now names `claim: false` as the alternative.
