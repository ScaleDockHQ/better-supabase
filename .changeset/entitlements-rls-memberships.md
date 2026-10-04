---
"better-supabase": patch
---

The entitlements module in PermDock mode reads `entitlement_members()` from the manifest's `rls.memberships` entries for its scope, the tables PermDock's `member_<scope>_ids_for` reads, and falls back to the hook's membership sources only for a manifest without `rls.memberships`. Doctor (BS408) warns when `rls.memberships` maps no table to the scope, and notes the fallback.
