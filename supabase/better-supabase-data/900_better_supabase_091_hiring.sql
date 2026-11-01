-- better-supabase module: hiring
-- @bsb-block-data hiring
-- @bsb-hash sha256:91d93ed4b11073d769fc6fcd6dd7763b8368dd0efcdd4615dcc32f9841216d07
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into "better_supabase"."automation_defaults" ("key", "block", "subject_type", "trigger", "name", "description", "actions", "enabled")
values ('hiring.application_to_employee', 'hiring', 'application', 'application.hired', 'Preboard each hired candidate', 'Creates an employee in preboarding from the hired application''s candidate and job, linked created_from the application.', '[{"kind":"employees.from_application","config":{"targetType":"employee"}}]'::jsonb, true)
on conflict ("key") do update set "subject_type" = excluded."subject_type", "trigger" = excluded."trigger", "name" = excluded."name", "description" = excluded."description", "actions" = excluded."actions", "enabled" = excluded."enabled", "block" = excluded."block", "updated_at" = now();

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.job_openings', target_type => 'job_opening', event_prefix => 'job_opening', deferred => true);
select better_supabase.audit('better_supabase.applications', target_type => 'application', event_prefix => 'application', deferred => true);
select better_supabase.audit('better_supabase.interviews', target_type => 'interview', event_prefix => 'interview', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('hiring', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
