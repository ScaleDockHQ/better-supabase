-- better-supabase module: webhook-inbox
-- @bsb-block-data webhook-inbox
-- @bsb-hash sha256:c5f43d72270e2ddde5384257e157069600d003d04adf4997aa6096e958705f53
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('webhook-inbox', 10, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
