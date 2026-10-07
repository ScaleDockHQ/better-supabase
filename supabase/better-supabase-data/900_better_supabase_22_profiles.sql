-- better-supabase module: profiles (0.5.1)
-- @bs-module-data profiles
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

-- Warns about another trigger that also creates profiles (handle_new_user).
select better_supabase.replace_equivalent_triggers('auth.users', 'bs_profile_sync', '(handle_new_user|create_profile|new_user_profile)', false);

insert into better_supabase.modules (name, version, mode)
values ('profiles', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
