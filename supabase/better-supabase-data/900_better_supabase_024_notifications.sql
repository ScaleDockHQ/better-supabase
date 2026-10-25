-- better-supabase module: notifications
-- @bsb-block-data notifications
-- @bsb-hash sha256:bfc5247523bcdb57cdb4645ed107de16d8675d27c58c33c43c97c28326b8dde3
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('notifications', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
