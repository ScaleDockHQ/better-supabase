-- better-supabase module: meetings
-- @bsb-block-data meetings
-- @bsb-hash sha256:d31cbf2e018d65bfd29e91b50d5c2732ada972c444c0320c57445f6ebe6a41f6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('meetings', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
