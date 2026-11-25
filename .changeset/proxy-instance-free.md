---
"better-supabase": minor
---

`createProxy({ auth, env, jwks, debug })` runs without the app definition, so `proxy.ts` no longer imports the schema or the blocks. `gen` writes `proxy-permissions.generated.ts` (permission key to bit index) when `gen.permissionCatalog` is on, so `permissionsOf` reads the token bitset without the catalog. A new doctor rule, BS650, reads the proxy's file trace from the last `next build` and reports above 400 KB. The old `createProxy(betterSupabase, options)` form keeps working.
