-- better-supabase module: referrals
-- @bsb-block-data referrals
-- @bsb-hash sha256:ceb9afb90afb8e28f7810b7fb091d8845f340739a53570a530fd9a63c84d22f8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('referrals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
