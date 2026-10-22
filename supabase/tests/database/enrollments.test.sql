-- The enrollments module on the fixture's access contract: the admin (…00a1)
-- of Acme (…0001) defines a program and enrolls a customer, the member
-- (…00a2) reads it but can't manage it, and Globex (…0002) sees nothing.
begin;
select plan(13);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (better_supabase.save_enrollment_program(
    '00000000-0000-4000-8000-000000000001',
    '{"key":"customer-setup","name":"Customer setup","subjectTypes":["customer"],"steps":[{"id":"kickoff"},{"id":"import"}]}'
  ) ->> 'version')::integer,
  1,
  'an admin saves a program'
);
select throws_ok(
  $$select better_supabase.save_enrollment_program('00000000-0000-4000-8000-000000000001', '{"key":"Bad Key","name":"x","steps":[]}')$$,
  '22023',
  null,
  'a program key is a lowercase slug'
);
select throws_ok(
  $$select better_supabase.enroll('00000000-0000-4000-8000-000000000001', 'customer-setup', 'deal', 'd1')$$,
  '22023',
  null,
  'a program enrolls only its subject types'
);

select set_config('test.enrollment', better_supabase.enroll(
  '00000000-0000-4000-8000-000000000001', 'customer-setup',
  'customer', '00000000-0000-4000-8000-00000000a001'
) ->> 'id', true);

select is(
  (better_supabase.enroll(
    '00000000-0000-4000-8000-000000000001', 'customer-setup',
    'customer', '00000000-0000-4000-8000-00000000a001'
  ) ->> 'id'),
  current_setting('test.enrollment'),
  'enrolling again returns the same enrollment'
);
select is(
  (better_supabase.complete_enrollment_step(current_setting('test.enrollment')::uuid, 'kickoff') ->> 'completedSteps')::integer,
  1,
  'completing a step counts it'
);
select throws_ok(
  $$select better_supabase.complete_enrollment_step(current_setting('test.enrollment')::uuid, 'launch')$$,
  '22023',
  null,
  'a step belongs to the program'
);
select is(
  (better_supabase.complete_enrollment_step(current_setting('test.enrollment')::uuid, 'import') ->> 'status'),
  'completed',
  'completing the last step completes the enrollment'
);
select is(
  (better_supabase.reset_enrollment_step(current_setting('test.enrollment')::uuid, 'import') ->> 'status'),
  'active',
  'resetting a step reopens it'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select is(
  jsonb_array_length(better_supabase.list_enrollments('00000000-0000-4000-8000-000000000001', 'customer-setup')),
  1,
  'a member reads the organization''s enrollments'
);
select throws_ok(
  $$select better_supabase.cancel_enrollment(current_setting('test.enrollment')::uuid)$$,
  '42501',
  null,
  'a member can''t cancel an enrollment'
);
select throws_ok(
  $$select better_supabase.save_enrollment_program('00000000-0000-4000-8000-000000000001', '{"key":"other","name":"Other","steps":[]}')$$,
  '42501',
  null,
  'a member can''t save a program'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select is(
  (select count(*)::integer from better_supabase.enrollments
    where tenant_id = '00000000-0000-4000-8000-000000000001'),
  0,
  'another organization sees none of its enrollments'
);
select is(
  better_supabase.list_enrollments('00000000-0000-4000-8000-000000000001'),
  '[]'::jsonb,
  'listing them returns only the caller''s own enrollments, which are none'
);

select * from finish();
rollback;
