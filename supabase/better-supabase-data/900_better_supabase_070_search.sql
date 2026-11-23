-- better-supabase module: search
-- @bsb-block-data search
-- @bsb-hash sha256:6f62d4518d3b53db3e3cb27d801b0ebfed3ab401d890357d9d6b7453850e97c8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pg_trgm" with schema "extensions";
create extension if not exists "unaccent" with schema "extensions";

-- Indexes the rows that existed before the triggers.
select "better_supabase"."search_reindex"();

insert into better_supabase.blocks (name, version, mode)
values ('search', 6, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
