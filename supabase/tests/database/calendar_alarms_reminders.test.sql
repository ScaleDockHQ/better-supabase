-- Calendar alarms and one-time reminders on the fixture's access contract.
-- Ann (…a1) owns Acme (…0001); Carl (…a3) owns Globex (…0002) and is not an
-- Acme member (supabase/seed.sql).
begin;
select plan(12);

select has_table('better_supabase', 'calendar_event_alarms', 'the alarms table exists');
select has_column('better_supabase', 'reminders', 'remind_at', 'reminders can fire at a fixed time');
select ok(
  not has_function_privilege('authenticated', 'api.list_reminder_schedule()', 'execute'),
  'only the service reads the reminder schedule'
);

-- Acme owner.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config(
  'test.calendar',
  api.create_calendar('00000000-0000-4000-8000-000000000001', 'Ann', 'Europe/Amsterdam', 'user', '00000000-0000-4000-8000-0000000000a1') ->> 'id',
  true
);
select set_config(
  'test.event',
  api.save_calendar_event(
    current_setting('test.calendar')::uuid,
    '{"title":"Review","startsAt":"2030-03-06T09:00:00Z","endsAt":"2030-03-06T10:00:00Z","alarms":[{"offsetMinutes":15},{"method":"email","at":"2030-03-05T18:00:00Z","summary":"Prepare","description":"Read the notes","repeat":2,"repeatMinutes":5}]}'
  ) ->> 'id',
  true
);

select is(
  (
    select jsonb_agg(a -> 'method' order by a ->> 'method')
    from jsonb_array_elements(api.list_calendar_events(array[current_setting('test.calendar')::uuid], '2030-03-01T00:00:00Z', '2030-04-01T00:00:00Z') -> 0 -> 'alarms') a
  ),
  '["display", "email"]'::jsonb,
  'an event keeps its display and email alarms'
);
select is(
  (
    select (a ->> 'repeat')::integer
    from jsonb_array_elements(api.list_calendar_events(array[current_setting('test.calendar')::uuid], '2030-03-01T00:00:00Z', '2030-04-01T00:00:00Z') -> 0 -> 'alarms') a
    where a ->> 'method' = 'email'
  ),
  2,
  'an alarm keeps its repeat count'
);
select throws_like(
  format(
    $$ select api.save_calendar_event(%L::uuid, %L::jsonb) $$,
    current_setting('test.calendar'),
    jsonb_build_object('id', current_setting('test.event'), 'alarms', '[{"offsetMinutes":15,"at":"2030-03-05T18:00:00Z"}]'::jsonb)
  ),
  '%offsetMinutes or at%',
  'an alarm with both a relative and an absolute trigger is refused'
);
select is(
  (
    select jsonb_array_length(api.list_calendar_events(array[current_setting('test.calendar')::uuid], '2030-03-01T00:00:00Z', '2030-04-01T00:00:00Z') -> 0 -> 'alarms')
  ),
  2,
  'a refused save leaves the alarms alone'
);

select ok(
  api.save_reminder('00000000-0000-4000-8000-000000000001', 'calendar_event', current_setting('test.event'), 0, '2030-03-06T07:30:00Z') ->> 'id' is not null,
  'a member sets a one-time reminder on an event'
);
select throws_like(
  $$ select api.save_reminder('00000000-0000-4000-8000-000000000001', 'calendar_event', '00000000-0000-4000-8000-00000000dead', 15) $$,
  '%not found in this organization%',
  'a reminder on a missing record is refused'
);

-- Globex owner, outside Acme.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select is(
  (select count(*)::integer from better_supabase.calendar_event_alarms where event_id = current_setting('test.event')::uuid),
  0,
  'an outsider cannot read Acme alarms'
);

-- The scheduler.
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select is(
  (
    select s.dtstart
    from api.list_reminder_schedule() s
    where s.subject_id = current_setting('test.event') and s.rrule = 'FREQ=DAILY;COUNT=1' and s.offset_minutes = 0
  ),
  '2030-03-06T07:30:00Z'::timestamptz,
  'the schedule lists a one-time reminder at its time'
);
select is(
  (
    select s.user_id
    from api.list_reminder_schedule() s
    where s.subject_id = current_setting('test.event') and s.offset_minutes = 0
  ),
  '00000000-0000-4000-8000-0000000000a1'::uuid,
  'and names the user to remind'
);

select * from finish();
rollback;
