-- better-supabase module: maintenance
-- @bsb-block-data maintenance
-- @bsb-hash sha256:aa67977ca8bdd7c9dee7e72445d71fb451fd1793d30bf571fe1ddd58a7d20225
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('maintenance', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
