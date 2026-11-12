-- better-supabase module: mfa
-- @bsb-block-data mfa
-- @bsb-hash sha256:9d4b5127d519e3599828ad8e00823159b8b2ab5ac1a9e736125a63a738f7c611
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('mfa', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
