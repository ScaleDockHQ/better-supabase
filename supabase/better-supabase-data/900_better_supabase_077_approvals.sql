-- better-supabase module: approvals
-- @bsb-block-data approvals
-- @bsb-hash sha256:48a7bff7d4738df2c103e1d10c48270ec8d32ddfc98730b6453f8a436e7bbf2f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('approvals', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
