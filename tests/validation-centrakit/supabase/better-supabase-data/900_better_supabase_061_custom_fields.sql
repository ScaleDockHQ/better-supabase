-- better-supabase module: custom-fields
-- @bsb-block-data custom-fields
-- @bsb-hash sha256:bf98d83435a0af9b755b2461111a0962ca26ead36da48b2f14a93ede844e6d0b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('custom-fields', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
