-- better-supabase module: expenses
-- @bsb-block-data expenses
-- @bsb-hash sha256:ae6a125f9a785b00eb4c30cad610f60e21a9e43c0cb59a8fda9e695849b3e7fd
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('expenses', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
