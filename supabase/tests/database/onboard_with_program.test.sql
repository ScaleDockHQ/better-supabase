-- onboard_with_program (ADR 1235): people.onboard as one function. The owner
-- (…a1) of Acme (…0001) creates an employee and enrolls them in a program in
-- one call, with dates. An unknown program rolls the employee back.
begin;
select plan(6);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select better_supabase.save_enrollment_program(
  '00000000-0000-4000-8000-000000000001',
  '{"key":"welcome-pack","name":"Welcome pack","subjectTypes":["employee"],"steps":[{"id":"laptop"}]}');

select set_config('test.result', better_supabase.onboard_with_program(
  '00000000-0000-4000-8000-000000000001',
  '{"name": "Nova Newhire"}'::jsonb,
  'welcome-pack',
  '{"startsAt": "2027-02-01T00:00:00Z"}'::jsonb)::text, true);

select is(
  current_setting('test.result')::jsonb -> 'employee' ->> 'name',
  'Nova Newhire',
  'the employee is created'
);
select is(
  current_setting('test.result')::jsonb -> 'enrollment' ->> 'program',
  'welcome-pack',
  'the employee is enrolled in the program'
);
select is(
  current_setting('test.result')::jsonb -> 'enrollment' ->> 'subjectId',
  current_setting('test.result')::jsonb -> 'employee' ->> 'id',
  'the enrollment is for the new employee'
);
select is(
  (select count(*) from better_supabase.enrollments
   where subject_id = current_setting('test.result')::jsonb -> 'employee' ->> 'id'
     and starts_at = '2027-02-01T00:00:00Z'::timestamptz),
  1::bigint,
  'the enrollment dates are set'
);
select throws_ok(
  $$select better_supabase.onboard_with_program('00000000-0000-4000-8000-000000000001', '{"name": "Ghost Hire"}'::jsonb, 'no-such-program')$$,
  null,
  null,
  'an unknown program is refused'
);
select is(
  (select count(*) from better_supabase.employees where name = 'Ghost Hire'),
  0::bigint,
  'a failed enrollment leaves no employee behind'
);

select * from finish();
rollback;
