-- better-supabase module: bulk-actions
-- @bsb-block-data bulk-actions
-- @bsb-hash sha256:f6f12b0c55c4dcc82ff19c67a5ffd411e97dfdea8218965c0ef89b4d8af3dc52
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('bulk-actions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
