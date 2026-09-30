---
'better-supabase': patch
---

Entitlements are no longer treated as a PermDock conflict, because `features` is not a PermDock claim.

- Doctor BS407 reports a custom access token hook next to PermDock only when it calls `better_supabase.membership_claims` or writes `roles`, `user_role`, `memberships` or the configured tenant claim itself. It no longer reports `feature_claims`, and it leaves PermDock's generated hook alone.
- `sql add entitlements` works next to a `permdock.config.ts` without `--force`. It writes `tenant` as a dependency and prints a note. Only `sql add tenant` still needs `--force`.
- The PermDock and entitlements docs say what works today. `has_entitlement(tenant, key)` and `tenant_entitlements(tenant)` work in SQL and RLS without a claim. `hasEntitlement(session, ...)` needs the `features` claim, which PermDock's hook doesn't write yet, so read entitlements from the database on the server until PermDock adds a hook slot for it.
