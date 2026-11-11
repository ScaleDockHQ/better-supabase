-- better-supabase module: idempotency
-- @bsb-block-data idempotency
-- @bsb-hash sha256:7aebd6173b219eef0e7b719c6ed48638fbbc2f920de216f47cbb794ae1a42d8f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('idempotency', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
