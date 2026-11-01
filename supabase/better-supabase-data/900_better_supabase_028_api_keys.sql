-- better-supabase module: api-keys
-- @bsb-block-data api-keys
-- @bsb-hash sha256:4e455e11e2f396b5918263f01f7e35717fcfccaf9f98103152327d0652a07b8d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.api_keys', target_type => 'api_key', event_prefix => 'api_key', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('api-keys', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
