-- better-supabase SQL kit: realtime-tables (0.4.0)
-- @bs-kit-data realtime-tables
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `kits` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.kit_modules (name, version, mode)
values ('realtime-tables', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
