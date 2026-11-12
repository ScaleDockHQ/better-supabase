-- better-supabase module: outbox
-- @bsb-block-data outbox
-- @bsb-hash sha256:5c9cec3a63705d9fd7a833e2cb6b5d01cd1dfe88a40bdc7731ee87f9b90121cc
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('outbox', 6, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
