-- better-supabase module: knowledge
-- @bsb-block-data knowledge
-- @bsb-hash sha256:3f13f31c5c7b941b26fb88f737ed1d1413bf1a46b5f012b865b9d0bda15adaf7
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('knowledge', 6, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
