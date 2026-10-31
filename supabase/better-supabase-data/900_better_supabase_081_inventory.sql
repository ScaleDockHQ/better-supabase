-- better-supabase module: inventory
-- @bsb-block-data inventory
-- @bsb-hash sha256:ea44e3b8b1525a301ac30a33b17c5ce2127de622ef0df73b59a9a10aa7fb8a72
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('inventory', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
