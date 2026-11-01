-- better-supabase module: ai-schedules
-- @bsb-block-data ai-schedules
-- @bsb-hash sha256:43de88ba0dbb65c1156d816eb749533bf1807cd81b507d4dcf3059b78c44d38f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-schedules', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
