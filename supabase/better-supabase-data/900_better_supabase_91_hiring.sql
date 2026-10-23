-- better-supabase module: hiring
-- @bsb-block-data hiring
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into "better_supabase"."rule_defaults" ("key", "block", "subject_type", "trigger", "name", "description", "actions", "enabled")
values ('hiring.application_to_employee', 'hiring', 'application', 'application.hired', 'Preboard each hired candidate', 'Creates an employee in preboarding from the hired application''s candidate and job, linked created_from the application.', '[{"kind":"employees.from_application","config":{"targetType":"employee"}}]'::jsonb, true)
on conflict ("key") do update set "subject_type" = excluded."subject_type", "trigger" = excluded."trigger", "name" = excluded."name", "description" = excluded."description", "actions" = excluded."actions", "enabled" = excluded."enabled", "block" = excluded."block", "updated_at" = now();

insert into better_supabase.blocks (name, version, mode)
values ('hiring', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
