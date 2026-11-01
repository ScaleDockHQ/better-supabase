-- better-supabase module: billable-time
-- @bsb-block-data billable-time
-- @bsb-hash sha256:e03d1cc092ec5ad01389ac485d7354915fad1cc6732344906a9f3d41034c5eb8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('billable-time', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
