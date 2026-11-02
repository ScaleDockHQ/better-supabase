-- better-supabase module: e-prescribing
-- @bsb-block-data e-prescribing
-- @bsb-hash sha256:ee8e0a6f8aee44c28fe5af663969a83d12a0783824592651edb998fa04f281fe
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('e-prescribing', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
