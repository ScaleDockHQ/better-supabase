-- better-supabase module: invoices
-- @bsb-block-data invoices
-- @bsb-hash sha256:d19b11c884bd81b40f1d9c8429a45b7091ac097304bbdaeaa86bfcf562ccd146
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('invoices', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
