-- better-supabase module: courses
-- @bsb-block-data courses
-- @bsb-hash sha256:54038f81ebd10cd26de9047b1aec811fd6ad5c04f81571016303c693ec9d990b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.courses', target_type => 'course', event_prefix => 'course', deferred => true);
select better_supabase.audit('better_supabase.course_modules', target_type => 'course_module', event_prefix => 'course_module', deferred => true);
select better_supabase.audit('better_supabase.course_lessons', target_type => 'course_lesson', event_prefix => 'course_lesson', deferred => true);
select better_supabase.audit('better_supabase.course_certificates', target_type => 'course_certificate', event_prefix => 'course_certificate', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('courses', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
