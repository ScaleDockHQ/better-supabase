-- better-supabase module: ai-cache
-- @bsb-block-data ai-cache
-- @bsb-hash sha256:24b9c0173f55096a24f3173dc48fc3c2dcbdb9d5e6b1816f0223ef9834dcab18
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-cache', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
