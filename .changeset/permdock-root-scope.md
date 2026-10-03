---
"better-supabase": patch
---

The `entitlements` kit module takes its PermDock scope from the manifest. Without `entitlements.permdock.scope`, it now uses the manifest's root scope (the `rls.scopes` entry without `within`) instead of `organization`, so a PermDock project whose root scope is `tenant` works without config. A manifest with no root scope or several stops `sql add entitlements` and doctor BS408 asks for `entitlements.permdock: { scope }`. An explicit `scope` still overrides, `false` still opts out, and a scope the manifest doesn't list is still reported by BS408. `permdockKeyStatus` and the `PermdockCatalog` and `PermdockKeyStatus` types are exported from `better-supabase/sql`.
