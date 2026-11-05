-- better-supabase module: deadlines
-- @bsb-block-data deadlines
-- @bsb-hash sha256:6cd29c48bb1c8de25f48f75496836046ab3978529a3dcb36ec3a491bf63763ed
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('deadlines', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
