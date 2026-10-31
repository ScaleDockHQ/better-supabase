-- better-supabase module: inventory
-- @bsb-block-data inventory
-- @bsb-hash sha256:cceceeec0ea99073af6312f71cdbe0989c2416c29906644d4e37dc5359e4cb3a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('inventory', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
