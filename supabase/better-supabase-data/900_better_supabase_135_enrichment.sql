-- better-supabase module: enrichment
-- @bsb-block-data enrichment
-- @bsb-hash sha256:dcb04aea5c6dba2694f8efab01af3f4faf3ae190eaf85c4f2685d756fb3f5cb1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('enrichment', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
