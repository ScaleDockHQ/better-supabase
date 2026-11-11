-- better-supabase module: webhook-inbox
-- @bsb-block-data webhook-inbox
-- @bsb-hash sha256:83d1487ca9e4c747ce9eca48531f316f83c8a940c2d779b242894f520d8aa855
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('webhook-inbox', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
