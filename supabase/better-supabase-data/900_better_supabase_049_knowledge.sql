-- better-supabase module: knowledge
-- @bsb-block-data knowledge
-- @bsb-hash sha256:31229537e7fd8ac633d9c419d45cd77587d9d01d8e8ecb4cc956111f5a29f98c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('knowledge', 7, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
