-- better-supabase module: webhook-inbox
-- @bsb-block-data webhook-inbox
-- @bsb-hash sha256:dd842247ebf41b0e533386ef03398c47c4daeae00ee9aa89f79c6d3928b3c20d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('webhook-inbox', 8, 'adopt')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
