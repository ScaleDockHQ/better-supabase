-- Calendar working hours, free/busy and focus time on the fixture's access
-- contract. Ann (…a1) owns Acme (…0001) and Ben (…a2) is a member; Carl
-- (…a3) owns Globex (…0002) and is not an Acme member (supabase/seed.sql).
begin;
select plan(11);

select has_table('better_supabase', 'calendar_working_hours', 'the working hours table exists');
select has_column('better_supabase', 'calendar_events', 'kind', 'events have a kind');
select ok(
  not has_function_privilege('authenticated', 'better_supabase.calendar_busy_blocks(uuid, uuid[], timestamptz, timestamptz)', 'execute'),
  'only the service reads raw busy blocks'
);
select is(
  (select count(*)::integer from api.calendar_rule_starts('2030-03-04T08:00:00Z', 'Europe/Amsterdam', 'FREQ=WEEKLY;BYDAY=MO,WE;COUNT=3', '2030-03-01T00:00:00Z', '2030-04-01T00:00:00Z')),
  3,
  'the SQL expander honours COUNT'
);

-- Acme owner.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  api.set_calendar_working_hours('00000000-0000-4000-8000-000000000001', null, 'Europe/Amsterdam', '[{"weekday":3,"start":"09:00","end":"17:00"}]'),
  1,
  'a member sets their own working hours'
);
select throws_like(
  $$ select api.set_calendar_working_hours('00000000-0000-4000-8000-000000000001', null, 'Europe/Amsterdam', '[{"weekday":3,"start":"17:00","end":"09:00"}]') $$,
  '%end after start%',
  'hours that end before they start are refused'
);

select set_config(
  'test.calendar',
  api.create_calendar('00000000-0000-4000-8000-000000000001', 'Ann', 'Europe/Amsterdam', 'user', '00000000-0000-4000-8000-0000000000a1') ->> 'id',
  true
);
select ok(
  api.save_calendar_event(
    current_setting('test.calendar')::uuid,
    '{"title":"Deep work","kind":"focus_time","startsAt":"2030-03-06T09:00:00Z","endsAt":"2030-03-06T11:00:00Z","tz":"Europe/Amsterdam"}'
  ) ->> 'id' is not null,
  'the owner blocks focus time'
);

select is(
  api.calendar_free_busy('00000000-0000-4000-8000-000000000001', array['00000000-0000-4000-8000-0000000000a1']::uuid[], '2030-03-06T00:00:00Z', '2030-03-07T00:00:00Z') -> 0 -> 'focusTime' -> 0 ->> 'startsAt',
  '2030-03-06T09:00:00+00:00',
  'free/busy reports the focus time'
);
select is(
  jsonb_array_length(api.calendar_free_busy('00000000-0000-4000-8000-000000000001', array['00000000-0000-4000-8000-0000000000a1']::uuid[], '2030-03-06T00:00:00Z', '2030-03-07T00:00:00Z') -> 0 -> 'workingHours'),
  1,
  'and the working hours of that Wednesday'
);

-- Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select throws_like(
  $$ select api.set_calendar_working_hours('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'UTC', '[]') $$,
  '%not allowed%',
  'a member cannot set someone else''s working hours'
);

-- Globex owner, outside Acme.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select throws_like(
  $$ select api.calendar_free_busy('00000000-0000-4000-8000-000000000001', array['00000000-0000-4000-8000-0000000000a1']::uuid[], '2030-03-06T00:00:00Z', '2030-03-07T00:00:00Z') $$,
  '%not allowed%',
  'an outsider cannot read Acme free/busy'
);

select * from finish();
rollback;
