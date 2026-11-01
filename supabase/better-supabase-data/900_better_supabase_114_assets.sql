-- better-supabase module: assets
-- @bsb-block-data assets
-- @bsb-hash sha256:4b95cfa6067a3d116a52cc1c6dcfd2e264743b243404cf61a1ac255a641b3937
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "postgis" with schema "extensions";

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.assets', target_type => 'asset', event_prefix => 'asset', deferred => true);
select better_supabase.audit('better_supabase.asset_locations', target_type => 'asset_location', event_prefix => 'asset_location', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('assets', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
