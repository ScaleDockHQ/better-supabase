---
"better-supabase": patch
---

The PermDock docs and the plugins skill reference match current PermDock. With `supabase.hook.claims: { features: 'better_supabase.feature_claims' }` in `permdock.config.ts`, PermDock's hook writes the `features` claim, so `hasEntitlement(session, ...)` works next to PermDock. The MCP recipe answers `visible` with PermDock's `mayUse`, and the Storage and Realtime pages point to the catalog's `rowConditions` and `permdock doctor` PD037 for permissions the helpers don't fully check.
