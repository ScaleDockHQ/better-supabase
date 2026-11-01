-- better-supabase module: versions
-- @bsb-block-data versions
-- @bsb-hash sha256:2f421fedc5066967515c63e92fba372b1c7e39c78074a974dc621ef6bd6c4510
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.versions', target_type => 'version', event_prefix => 'version', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('versions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
