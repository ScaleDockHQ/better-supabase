-- better-supabase module: field-encryption
-- @bsb-block-data field-encryption
-- @bsb-hash sha256:24e0bcbdcd12ed728d7919648db8a89bd1920454f56ac96aeb81e0e3b7248c21
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('field-encryption', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
