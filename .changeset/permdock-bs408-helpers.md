---
"better-supabase": patch
---

Doctor BS408 checks exactly the PermDock helpers the `entitlements` module calls for the chosen scope, and no longer claims PermDock writes `member_<scope>_ids_for` for every scope. It warns when the manifest lacks `member_<scope>_ids` or doesn't let `authenticated` execute it, when it lacks `member_<scope>_ids_for` (add a membership source for the scope in `permdock.config.ts`), and when `supabase_auth_admin` may not execute `member_<scope>_ids_for` (add `supabase.hook.claims: { features: 'better_supabase.feature_claims' }`).
