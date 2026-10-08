-- better-supabase module: inbox (0.5.1)
-- @bs-module-data inbox
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public, file_size_limit)
values ('inbox-files', 'inbox-files', false, 26214400)
on conflict (id) do nothing;

insert into better_supabase.modules (name, version, mode)
values ('inbox', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
