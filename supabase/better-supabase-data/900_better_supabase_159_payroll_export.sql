-- better-supabase module: payroll-export
-- @bsb-block-data payroll-export
-- @bsb-hash sha256:87e29a2610aa11f95cfd1ee674f2c7ad1a9b3fd957079d4d7faa69011f00cd1c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('payroll-export', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
