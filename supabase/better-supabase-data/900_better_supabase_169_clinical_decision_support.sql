-- better-supabase module: clinical-decision-support
-- @bsb-block-data clinical-decision-support
-- @bsb-hash sha256:1489add5de9fc5ff5ff278865e0ec1ea4f9f80995d36f7d7a76c308f1be5e23b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('clinical-decision-support', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
