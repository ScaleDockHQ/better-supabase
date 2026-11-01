-- better-supabase module: enrichment
-- @bsb-block-data enrichment
-- @bsb-hash sha256:f576c7f34149a7dc8fc0b89e38b14b8a7f7f0f165eabf7b901696dc419879773
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.enrichments', target_type => 'enrichment', event_prefix => 'enrichment', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('enrichment', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
