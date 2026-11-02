-- better-supabase module: usage
-- @bsb-block-data usage
-- @bsb-hash sha256:1211581c793a98340e3ba0553f33e9468c9e9dcc0dc4d8613f97394e3d6677fb
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('usage', 7, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
