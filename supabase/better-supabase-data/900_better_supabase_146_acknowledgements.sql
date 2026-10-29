-- better-supabase module: acknowledgements
-- @bsb-block-data acknowledgements
-- @bsb-hash sha256:f804dc1bd56a250af2771946adc718a33fc2dbcbbb8cd45180ca0480d6b11329
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('acknowledgements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
