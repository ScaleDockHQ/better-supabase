-- better-supabase module: enrollments
-- @bsb-block-data enrollments
-- @bsb-hash sha256:f3c43f8528dd0330050009a7308139919a3338a8ac84e4a97985d138aea823c5
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.enrollment_programs', target_type => 'enrollment_program', event_prefix => 'enrollment_program', deferred => true);
select better_supabase.audit('better_supabase.enrollments', target_type => 'enrollment', event_prefix => 'enrollment', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('enrollments', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
