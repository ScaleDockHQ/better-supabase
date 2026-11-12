-- better-supabase module: billing
-- @bsb-block-data billing
-- @bsb-hash sha256:9192c5a247a10a63b3db4a9a5d145a27c1a3ad52659ca7ef8e067daddb2d51c2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('billing', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
