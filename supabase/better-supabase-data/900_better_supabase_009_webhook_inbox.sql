-- better-supabase module: webhook-inbox
-- @bsb-block-data webhook-inbox
-- @bsb-hash sha256:51db52578fb675651d33b940a0fc413c20526dc847e6c962a775bdfb99c200b4
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('webhook-inbox', 11, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
