-- better-supabase module: share-links
-- @bsb-block-data share-links
-- @bsb-hash sha256:e5d5a130255d7429c5bf014f074b47b3ad2af24425edf1e8a3fc49b8be36d542
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('share-links', 1, 'adopt')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
