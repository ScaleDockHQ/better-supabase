-- better-supabase module: contacts
-- @bsb-block-data contacts
-- @bsb-hash sha256:de08c7697682e28b5a387f3550c0e726eaf1f369eac0d849c9c9d8bc751d7dcf
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('contacts', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
