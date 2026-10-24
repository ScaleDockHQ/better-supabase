-- better-supabase module: profiles
-- @bsb-block-data profiles
-- @bsb-hash sha256:6adf551cd907a3c673e2daa1bb0b7d2a3af0d1ed7457255a464bc937d6c2733b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('profiles', 2, 'adopt')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
