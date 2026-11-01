-- better-supabase module: appraisals
-- @bsb-block-data appraisals
-- @bsb-hash sha256:ff62b2a70053408f2fb6ab6aaeb54ae4ef08766cb052dce51c932a77fa5a9054
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('appraisals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
