-- better-supabase module: profiles
-- @bsb-block-data profiles
-- @bsb-hash sha256:e62b50956e32d7e493f9540e7bdf11245e0be5852c4bf930ecebdb916657bbad
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('profiles', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
