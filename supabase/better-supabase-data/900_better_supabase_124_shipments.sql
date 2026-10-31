-- better-supabase module: shipments
-- @bsb-block-data shipments
-- @bsb-hash sha256:11114c45bc76d3e4028398e28ee2c2a1d6e35189ca63081e232f2d14217adcd7
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('shipments', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
