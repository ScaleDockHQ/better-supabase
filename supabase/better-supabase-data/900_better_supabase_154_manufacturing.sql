-- better-supabase module: manufacturing
-- @bsb-block-data manufacturing
-- @bsb-hash sha256:18e97e8f7006d8439ff170eb5ff50bad4ae04bd0bce4957faa697bb6da3b3dd2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('manufacturing', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
