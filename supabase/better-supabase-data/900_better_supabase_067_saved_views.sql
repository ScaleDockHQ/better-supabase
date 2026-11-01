-- better-supabase module: saved-views
-- @bsb-block-data saved-views
-- @bsb-hash sha256:7ed0d893bd38be86750cfebdd6ab7b24e9b593922fed0dce6635058caf6505c0
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.shared_views', target_type => 'saved_view', event_prefix => 'saved_view', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('saved-views', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
