-- better-supabase module: data-lifecycle
-- @bsb-block-data data-lifecycle
-- @bsb-hash sha256:454bffec4b7e024f75d25fd323bc740cda249507fe6ed6669359a9e5e508588c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public)
values ('data-exports', 'data-exports', false)
on conflict (id) do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('data-lifecycle', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
