-- better-supabase module: contacts
-- @bsb-block-data contacts
-- @bsb-hash sha256:c5f2eb5e5df84c0f9c5ec31500d003e5348e8859fca006ee0be39d557d583f3f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.companies', target_type => 'company', event_prefix => 'company', deferred => true);
select better_supabase.audit('better_supabase.people', target_type => 'person', event_prefix => 'person', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('contacts', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
