-- better-supabase module: notifications
-- @bsb-block-data notifications
-- @bsb-hash sha256:88e2e0b8de370edbca884a9a755a5c5054ff743897904d9402b94a1d0c11dcd9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('notifications', 8, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
