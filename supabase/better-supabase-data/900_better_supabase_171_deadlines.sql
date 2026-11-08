-- better-supabase module: deadlines
-- @bsb-block-data deadlines
-- @bsb-hash sha256:7ea2732774b4ed46501ce1403ec32652ba8d39b914a294487d9f53853ccc2c11
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('deadlines', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
