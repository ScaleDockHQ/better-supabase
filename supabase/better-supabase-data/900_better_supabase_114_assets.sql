-- better-supabase module: assets
-- @bsb-block-data assets
-- @bsb-hash sha256:a1bd4e939134879335c7da47b14fe6a1e8cd091e99c52bf6b106fb40741a1f99
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "postgis" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('assets', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
