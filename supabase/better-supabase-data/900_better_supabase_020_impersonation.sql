-- better-supabase module: impersonation
-- @bsb-block-data impersonation
-- @bsb-hash sha256:5b75ec6020bd1354c5949a5872776c45a105f49ad9d7557d8968fcebf0428695
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('impersonation', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
