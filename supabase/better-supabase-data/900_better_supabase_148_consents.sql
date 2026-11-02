-- better-supabase module: consents
-- @bsb-block-data consents
-- @bsb-hash sha256:5f7ff09af34614229fbd9dd1e5b96f6262cf6ed2038bed5391a20b2ebb876d5b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('consents', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
