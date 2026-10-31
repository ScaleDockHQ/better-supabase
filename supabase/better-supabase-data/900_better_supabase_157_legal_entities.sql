-- better-supabase module: legal-entities
-- @bsb-block-data legal-entities
-- @bsb-hash sha256:2f562e0fc37b73534d82eec86c0b9b2fbd8131c55be9ab68dee46882609313a6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('legal-entities', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
