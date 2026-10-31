-- better-supabase module: catalog
-- @bsb-block-data catalog
-- @bsb-hash sha256:f1b2b4ddf75f743b52b4e2090b59663b897cde55903fcfa589ff6dc45f0bb9b9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('catalog', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
