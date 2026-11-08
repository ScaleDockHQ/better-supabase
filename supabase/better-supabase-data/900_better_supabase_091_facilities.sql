-- better-supabase module: facilities
-- @bsb-block-data facilities
-- @bsb-hash sha256:26548264d87718b9cf9763eb29e54bfa361d9fa9573a831242e17451a14d4091
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, block, version, mode)
values ('facilities', 'tasks', 5, 'managed')
on conflict (name) do update
  set block = excluded.block, version = excluded.version, mode = excluded.mode, updated_at = now();
