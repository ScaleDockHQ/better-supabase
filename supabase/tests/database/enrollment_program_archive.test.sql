-- Archiving an enrollment program (ADR 1085): an archived program leaves
-- enrollment_programs, refuses new enrollments and edits, keeps its
-- enrollments, restores, and purge removes it with its enrollments only once it
-- is archived. Run with `supabase test db`.
begin;
select plan(12);

create function pg_temp.n(t text) returns integer language sql security definer as $$
  select count(*)::integer from better_supabase.outbox_events where type = t
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.base',
  jsonb_array_length(better_supabase.enrollment_programs('00000000-0000-4000-8000-000000000001'))::text, true);
select set_config('test.program', better_supabase.upsert_enrollment_program(
  '00000000-0000-4000-8000-000000000001',
  '{"key":"archive-plan","name":"Archive plan","subjectTypes":["customer"],"steps":[{"id":"one"}]}'
) ->> 'id', true);
select better_supabase.enroll('00000000-0000-4000-8000-000000000001', 'archive-plan',
  'customer', '00000000-0000-4000-8000-00000000a0a1');

select isnt(
  better_supabase.archive_enrollment_program(current_setting('test.program')::uuid) ->> 'archivedAt', null,
  'archiving sets archivedAt'
);
select is(pg_temp.n('enrollment_program.archived'), 1, 'archiving records enrollment_program.archived');
select is(
  jsonb_array_length(better_supabase.enrollment_programs('00000000-0000-4000-8000-000000000001')),
  current_setting('test.base')::integer,
  'the archived program leaves the list'
);
select is(
  jsonb_array_length(better_supabase.enrollment_programs('00000000-0000-4000-8000-000000000001', true)),
  current_setting('test.base')::integer + 1,
  'include_archived lists it again'
);
select throws_ok(
  $$select better_supabase.enroll('00000000-0000-4000-8000-000000000001', 'archive-plan', 'customer', '00000000-0000-4000-8000-00000000a0a2')$$,
  '55000', null, 'an archived program refuses a new enrollment'
);
select throws_ok(
  format($$select better_supabase.upsert_enrollment_program('00000000-0000-4000-8000-000000000001', jsonb_build_object('id', %L, 'name', 'Renamed'))$$,
    current_setting('test.program')),
  '55000', null, 'an archived program refuses an edit'
);
select better_supabase.archive_enrollment_program(current_setting('test.program')::uuid);
select is(pg_temp.n('enrollment_program.archived'), 1, 'archiving twice records one event');

select is(
  better_supabase.restore_enrollment_program(current_setting('test.program')::uuid) ->> 'archivedAt', null,
  'restoring clears archivedAt'
);
select throws_ok(
  format($$select better_supabase.purge_enrollment_program(%L)$$, current_setting('test.program')),
  '55000', null, 'purge refuses an active program'
);
select better_supabase.archive_enrollment_program(current_setting('test.program')::uuid);
select is(
  better_supabase.purge_enrollment_program(current_setting('test.program')::uuid), true,
  'purge removes an archived program'
);
select is(pg_temp.n('enrollment_program.purged'), 1, 'purging records enrollment_program.purged');
select is(
  (select count(*)::integer from better_supabase.enrollments where program = 'archive-plan'), 0,
  'purge takes the enrollments with it'
);

select * from finish();
rollback;
