-- better-supabase module: comments
-- @bs-module-data comments
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('comments', 8, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
