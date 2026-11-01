-- better-supabase module: signatures
-- @bsb-block-data signatures
-- @bsb-hash sha256:60d4f60f0497e6f4c25a101c6509c7c3f2624d76a1b38ef0dd34918d9d221802
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('signatures', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
