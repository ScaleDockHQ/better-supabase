---
"better-supabase": minor
---

Client sessions can omit JWT claims (`toSession(auth, { claims: false })`). `PermissionsProvider`, `can` and `useCan` read the compact bootstrap payload, and the roles and catalog models gain `better_supabase.bootstrap_permissions()`. Membership claims accept `claimFormat: "summary"`.

The verified-token memo is shared on `globalThis` and keyed by the raw token. A stale JWKS is served while it refreshes. Role-default and platform-role changes bump authorization versions in one statement, and `hook_plan` returns `full` when the active tenant changed. The browser client refreshes on `visibilitychange` inside the leeway.

Cursor pages count `estimated` unless `count` says otherwise. `defineInfiniteListHook` pages with `page()` and its cursor. Block list methods take an optional `limit` and return only that many rows. Facet counts can use a capped sample, and `countFacets` with `facetCacheKey` keeps that sample out of later pages. `OfflineBoundary` and `nativePermissions` cover React Native. A PowerSync reconnect refreshes server-backed reads only.
