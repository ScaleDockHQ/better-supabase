-- better-supabase module: goals
-- @bsb-block-data goals
-- @bsb-hash sha256:6ccbb19a784390c80a73f1c3058be7d0e9d5e8f5641194f8c64fcbae29905639
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('goals', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
