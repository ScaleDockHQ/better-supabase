-- better-supabase module: approvals
-- @bsb-block-data approvals
-- @bsb-hash sha256:808fa3d8e5e1a963abc95ce2789ce9a6074e03d82b1fdae1566c8a6d03e1230e
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('approvals', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
