-- Cases and inspections against the other blocks: a tenant policy asks for an
-- approval before a case closes, closing writes a version, a scheduled
-- inspection shows in the "Audits" calendar, joining the team and a missed
-- planned end notify. Run with `supabase test db`.
begin;
select plan(11);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;

-- Cases: the floor asks for nothing, so an observation closes freely.
insert into ids values ('free', (better_supabase.open_case(
  '00000000-0000-4000-8000-000000000001', 'observation', 'Loose cable in aisle 3') ->> 'id')::uuid);
select is(
  better_supabase.case_close_blockers((select id from ids where name = 'free')),
  array[]::text[],
  'without a tenant policy an observation has no blocker'
);

select api.save_approval_policy('00000000-0000-4000-8000-000000000001',
  '{"subjectType":"case","action":"close","name":"Close needs sign-off",
    "steps":[{"approvers":{"users":["00000000-0000-4000-8000-0000000000a2"]},"required":1}]}');
select is(
  better_supabase.case_close_blockers((select id from ids where name = 'free')),
  array['CASE_APPROVAL_REQUIRED'],
  'a tenant policy for closing asks for an approval first'
);
select throws_ok(
  $$select better_supabase.close_case((select id from ids where name = 'free'))$$,
  null, null,
  'the case does not close without the approval'
);

select set_config('test.request', api.request_approval('00000000-0000-4000-8000-000000000001', 'case',
  (select id::text from ids where name = 'free'), 'close') ->> 'id', true);
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;
select is(
  api.decide_approval(current_setting('test.request')::uuid, 'approved') ->> 'status',
  'approved',
  'a second member signs off on closing the case'
);
select is(
  (select c.closed_at is not null from better_supabase.cases c where c.id = (select id from ids where name = 'free')),
  true,
  'approving the request closes the case'
);
select is(
  (select count(*)::int from better_supabase.versions v
   where v.subject_type = 'case' and v.subject_id = (select id::text from ids where name = 'free')),
  1,
  'closing a case writes one version of it'
);

-- Inspections: the "Audits" calendar mirrors planned inspections.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;
select api.create_calendar('00000000-0000-4000-8000-000000000001', 'Audits', 'Europe/Amsterdam', 'user',
  '00000000-0000-4000-8000-0000000000a1');
insert into ids values ('walk', (better_supabase.schedule_inspection(
  '00000000-0000-4000-8000-000000000001',
  jsonb_build_object(
    'kind', 'inspection',
    'title', 'Dock walk-through',
    'plannedStart', '2020-01-01',
    'plannedEnd', '2020-01-02',
    'members', jsonb_build_array(jsonb_build_object(
      'userId', '00000000-0000-4000-8000-0000000000a2', 'role', 'auditee'))
  )) ->> 'id')::uuid);

reset role;
select is(
  (select count(*)::int from better_supabase.calendar_events e
   where e.uid = 'inspection-' || (select id from ids where name = 'walk')),
  1,
  'a scheduled inspection with a start date shows in the Audits calendar'
);
select is(
  (select count(*)::int from better_supabase.notification_events
   where type = 'inspection.assigned' and idempotency_key like '%' || (select id from ids where name = 'walk') || '%'),
  1,
  'adding a team member sends one inspection.assigned'
);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select is(better_supabase.notify_overdue_inspections(), 1, 'an inspection past its planned end is reported');
select is(better_supabase.notify_overdue_inspections(), 0, 'a second run reports nothing new');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;
select better_supabase.cancel_inspection((select id from ids where name = 'walk'));
reset role;
select is(
  (select count(*)::int from better_supabase.calendar_events e
   where e.uid = 'inspection-' || (select id from ids where name = 'walk')),
  0,
  'canceling the inspection removes its calendar event'
);

select * from finish();
rollback;
