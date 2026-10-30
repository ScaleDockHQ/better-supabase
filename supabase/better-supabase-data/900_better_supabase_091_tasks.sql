-- better-supabase module: tasks
-- @bsb-block-data tasks
-- @bsb-hash sha256:8d4e5c2d7f62493606e4dc7e73c59e36f8c82df8022a86d4e477c0a0556b86d1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tasks', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
