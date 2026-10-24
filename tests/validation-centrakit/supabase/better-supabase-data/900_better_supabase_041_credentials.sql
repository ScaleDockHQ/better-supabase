-- better-supabase module: credentials
-- @bsb-block-data credentials
-- @bsb-hash sha256:3d1dc5f51081386b5208cc7fc619b0d93bf725b4d1b8f33978d7c8eaf0c602c6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('credentials', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
