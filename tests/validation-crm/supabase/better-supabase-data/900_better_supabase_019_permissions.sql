-- better-supabase module: permissions
-- @bsb-block-data permissions
-- @bsb-hash sha256:c055520d670c266f5c3e20973b51f9a03c119a78e82ac24fc3a21c0cdf390698
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('permissions', 1, 'adopt')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
