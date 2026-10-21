---
"better-supabase": patch
---

Two SQL fixes. See [From 0.11 to 0.12](https://bettersupabase.com/docs/migration/0.11-to-0.12) for what to check.

- `better_supabase.acting_member()` is granted to `service_role` only; `anon` and `authenticated` get `permission denied` instead of an RPC that returned null. `better_supabase.set_actor()` is `security definer`, so the trigger still records the actor for every writer. Run `sql sync` to get the new grant in a migration. If your own SQL calls `acting_member()`, run it as `service_role` or from a `security definer` function.
- Module file headers no longer carry the package version, so a release doesn't rewrite every module file. The `@bs-module` marker keeps the module version, and a header written by an older release still counts as current. `ModuleLayout.version` is deprecated.
