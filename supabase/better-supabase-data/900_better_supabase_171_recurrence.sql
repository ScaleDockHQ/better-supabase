-- better-supabase module: recurrence
-- @bsb-block-data recurrence
-- @bsb-hash sha256:17a00515ab36dc8e8ed14219001282f39566955b8b570a34f4cede67b19ca745
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('recurrence', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
