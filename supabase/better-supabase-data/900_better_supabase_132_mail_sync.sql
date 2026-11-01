-- better-supabase module: mail-sync
-- @bsb-block-data mail-sync
-- @bsb-hash sha256:a455c51c4d5ee70107696c80dad74fd5dee24dfb085ce0167490dd90eb1ef9c4
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('mail-sync', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
