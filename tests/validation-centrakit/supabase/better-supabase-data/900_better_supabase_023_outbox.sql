-- better-supabase module: outbox
-- @bsb-block-data outbox
-- @bsb-hash sha256:2b0f8a1684a74c737ad8d391f145e3c8f00a9f3a334a12823cc6bc018ca50b62
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('outbox', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
