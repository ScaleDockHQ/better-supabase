-- better-supabase module: webhook-inbox
-- @bsb-block-data webhook-inbox
-- @bsb-hash sha256:f1b5389c5480df1f232a153ec54c86baa5a08c9f236eb6930f1a161a18d994b8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('webhook-inbox', 8, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
