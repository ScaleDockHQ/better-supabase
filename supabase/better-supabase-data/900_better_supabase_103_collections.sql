-- better-supabase module: collections
-- @bsb-block-data collections
-- @bsb-hash sha256:5cfc756ef45516c641430f0bc9a3e1bbf70862c367e4ff02a7bddb4e6079f24f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('collections', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
