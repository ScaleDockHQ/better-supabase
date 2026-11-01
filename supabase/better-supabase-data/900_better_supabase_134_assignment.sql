-- better-supabase module: assignment
-- @bsb-block-data assignment
-- @bsb-hash sha256:336c65d0cac5c9c18ec22385c79dea4ed6a56ebaee602d9ffd157ca812e472aa
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('assignment', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
