-- The enrollments module on the fixture's access contract: the admin (…00a1)
-- of Acme (…0001) defines a program and enrolls a customer, the member
-- (…00a2) reads it but can't manage it, and Globex (…0002) sees nothing. A
-- second program assigns a step to the member and renders its due dates.
begin;
select plan(27);

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

select is(
  (better_supabase.save_enrollment_program(
    '00000000-0000-4000-8000-000000000001',
    '{"key":"go-live","name":"Go live","steps":[{"id":"kickoff","assignee":{"userId":"00000000-0000-4000-8000-0000000000a2"},"due":{"days":2,"from":"start"}},{"id":"import"},{"id":"review","assignee":{"role":"admin"},"due":{"days":-1,"from":"end"}}]}'
  ) -> 'steps' -> 0 -> 'due' ->> 'days')::integer,
  2,
  'a program step keeps its assignee and due date'
);
select throws_ok(
  $$select better_supabase.save_enrollment_program('00000000-0000-4000-8000-000000000001', '{"key":"late","name":"Late","steps":[{"id":"a","due":{"days":1,"from":"later"}}]}')$$,
  '22023',
  null,
  'a due date counts from the start or the end'
);

select set_config('test.dated', better_supabase.enroll(
  '00000000-0000-4000-8000-000000000001', 'go-live',
  'customer', '00000000-0000-4000-8000-00000000a002'
) ->> 'id', true);

select is(
  (select count(*)::integer from better_supabase.enrollment_steps
    where enrollment_id = current_setting('test.dated')::uuid and completed_at is null),
  2,
  'enrolling opens a row for each scheduled step'
);
select is(
  (better_supabase.set_enrollment_dates(
    current_setting('test.dated')::uuid,
    '{"startsAt":"2026-11-01T00:00:00Z","endsAt":"2026-11-30T00:00:00Z"}'
  ) -> 'schedule' -> 1 ->> 'dueAt')::timestamptz,
  '2026-11-29T00:00:00Z'::timestamptz,
  'setting the dates renders a due date from the end'
);
select is(
  (select due_at from better_supabase.enrollment_steps
    where enrollment_id = current_setting('test.dated')::uuid and step = 'kickoff'),
  '2026-11-03T00:00:00Z'::timestamptz,
  'a due date from the start counts from startsAt'
);
select throws_ok(
  $$select better_supabase.set_enrollment_dates(current_setting('test.dated')::uuid, '{"endsAt":"2026-10-01T00:00:00Z"}')$$,
  '22023',
  null,
  'an enrollment can''t end before it starts'
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
select is(
  jsonb_array_length(better_supabase.open_enrollment_steps(
    '00000000-0000-4000-8000-000000000001',
    assignee_user => '00000000-0000-4000-8000-0000000000a2'
  )),
  1,
  'a member lists the steps assigned to them'
);
select is(
  (better_supabase.complete_enrollment_step(current_setting('test.dated')::uuid, 'kickoff') ->> 'completedSteps')::integer,
  1,
  'an assigned member completes their step'
);
select is(
  (select due_at from better_supabase.enrollment_steps
    where enrollment_id = current_setting('test.dated')::uuid and step = 'kickoff' and completed_at is not null),
  '2026-11-03T00:00:00Z'::timestamptz,
  'a completed step keeps its due date'
);
select throws_ok(
  $$select better_supabase.set_enrollment_dates(current_setting('test.dated')::uuid, '{"startsAt":null}')$$,
  '42501',
  null,
  'a member can''t change an enrollment''s dates'
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
select is(
  better_supabase.open_enrollment_steps('00000000-0000-4000-8000-000000000001'),
  '[]'::jsonb,
  'another organization lists none of its open steps'
);

-- A resync that drops the steps left completes the enrollment and says so.
reset role;
select set_config('test.ensured', better_supabase.enrollment_ensure(
  '00000000-0000-4000-8000-000000000001', 'resync-program', 1, array['a', 'b'],
  'customer', '00000000-0000-4000-8000-00000000a009', null
)::text, true);
select better_supabase.enrollment_mark(current_setting('test.ensured')::uuid, 'a', true, null);
select is(
  (select count(*)::integer from better_supabase.outbox_events
    where type = 'enrollment.completed' and payload ->> 'program' = 'resync-program'),
  0,
  'an enrollment with a step left has not completed'
);
select better_supabase.enrollment_ensure(
  '00000000-0000-4000-8000-000000000001', 'resync-program', 1, array['a'],
  'customer', '00000000-0000-4000-8000-00000000a009', null
);
select is(
  (select status::text from better_supabase.enrollments where id = current_setting('test.ensured')::uuid),
  'completed',
  'dropping the step that was left completes the enrollment'
);
select is(
  (select count(*)::integer from better_supabase.outbox_events
    where type = 'enrollment.completed' and payload ->> 'program' = 'resync-program'),
  1,
  'the resync emits enrollment.completed once'
);

select * from finish();
rollback;
