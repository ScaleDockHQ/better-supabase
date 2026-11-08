---
"better-supabase": minor
---

`init` no longer enables pg-delta in a `supabase/config.toml` that lists `[db.migrations] schema_paths`. `upgrade` under the `migra` workflow keeps seeing the app's tables once its module files exist in `supabase/schemas`, so a second run no longer writes `create table` for them. The `profiles` block adds `active_organization_id` and `active_team_id` only next to `memberships` and `teams`, so an app with no organizations gets no tenant column. The generated `generated.ts` no longer imports `EnrichDatabase` when no table needs it, which failed `noUnusedLocals`.
