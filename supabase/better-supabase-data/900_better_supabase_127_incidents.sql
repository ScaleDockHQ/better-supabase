-- better-supabase module: incidents
-- @bsb-block-data incidents
-- @bsb-hash sha256:ac92b9d8b52fe4487192e0f407db610b8cfc32433b5fc3a3ce42a7ebc358f561
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.incidents', target_type => 'incident', event_prefix => 'incident', deferred => true);
select better_supabase.audit('better_supabase.incident_status_components', target_type => 'status_component', event_prefix => 'status_component', deferred => true);
select better_supabase.audit('better_supabase.incident_postmortems', target_type => 'incident_postmortem', event_prefix => 'incident_postmortem', deferred => true);
select better_supabase.audit('better_supabase.incident_status_pages', target_type => 'status_page', event_prefix => 'status_page', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('incidents', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
