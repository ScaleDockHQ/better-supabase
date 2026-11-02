-- better-supabase module: moderation
-- @bsb-block-data moderation
-- @bsb-hash sha256:97d80d244d5ecfdb00b7662ae72c988dec37f9a47d1839281040f4050ac1d3b5
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('moderation', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
