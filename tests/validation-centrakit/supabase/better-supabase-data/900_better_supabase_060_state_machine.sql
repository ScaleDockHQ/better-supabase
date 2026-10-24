-- better-supabase module: state-machine
-- @bsb-block-data state-machine
-- @bsb-hash sha256:5d7403d9a64f8fbaf3bf7657ec34ce81a8b879a5ad9827b08d0441016bd9de7e
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('state-machine', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
