---
"better-supabase": minor
---

The `entitlements` SQL kit module reads memberships from PermDock when `permdock.manifest.json` is present: `has_entitlement` checks `<rls.schema>.member_<scope>_ids()`, `feature_claims` reads `member_<scope>_ids_for(user_id)` from PermDock's hook, and `entitlement_members` reads the manifest's membership tables. `sql add entitlements` then no longer adds the `tenant` module or prints the hook note. The scope defaults to `organization`; set `entitlements.permdock: { scope }` for another of the manifest's scopes, or `entitlements.permdock: false` to keep `better_supabase.memberships`. The new doctor check BS408 warns when the manifest or the database lacks one of the two helpers. PermDock's `next-better-supabase` example can now drop its `public.feature_claims` stand-in for the kit's `better_supabase.feature_claims`.
