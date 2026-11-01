-- better-supabase module: inspections
-- @bsb-block-data inspections
-- @bsb-hash sha256:2c4ab9279a8aac170a8a54241e6d7a8324187aaaeb53650843666defd2157344
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.inspections', target_type => 'inspection', event_prefix => 'inspection', deferred => true);
select better_supabase.audit('better_supabase.inspection_programs', target_type => 'inspection_program', event_prefix => 'inspection_program', deferred => true);
select better_supabase.audit('better_supabase.inspection_findings', target_type => 'inspection_finding', event_prefix => 'inspection_finding', deferred => true);
select better_supabase.audit('better_supabase.inspection_members', target_type => 'inspection_member', event_prefix => 'inspection_member', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('inspections', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
