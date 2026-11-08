-- better-supabase module: time-entries
-- @bsb-block-data time-entries
-- @bsb-hash sha256:9f119fc99f2ff9bc951756a5b19544390bd76af8e195481c89a8c5a8633f80ca
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('time-entries', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
