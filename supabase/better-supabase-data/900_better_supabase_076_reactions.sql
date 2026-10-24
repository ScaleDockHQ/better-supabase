-- better-supabase module: reactions
-- @bsb-block-data reactions
-- @bsb-hash sha256:5deb9a6c5e8fa6ac34d3276a3a2aad0f2b697ad0b07b884da22c9ed016f895f8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('reactions', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
