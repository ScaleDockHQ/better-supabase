-- calendar_bootstrap on the fixture's access contract: one call returns the
-- calendars, the events of two ranges and the caller's reminders on events.
-- Ann (…a1) owns Acme (…0001); Carl (…a3) owns Globex (…0002) and is not an
-- Acme member (supabase/seed.sql).
begin;
select plan(8);

select has_function('api', 'calendar_bootstrap', 'the bootstrap function is exposed');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config(
  'test.calendar',
  api.create_calendar('00000000-0000-4000-8000-000000000001', 'Bootstrap', 'Europe/Amsterdam', 'user', '00000000-0000-4000-8000-0000000000a1') ->> 'id',
  true
);
select set_config(
  'test.event',
  api.save_calendar_event(
    current_setting('test.calendar')::uuid,
    '{"title":"Planning","startsAt":"2030-03-06T09:00:00Z","endsAt":"2030-03-06T10:00:00Z"}'
  ) ->> 'id',
  true
);
select set_config(
  'test.later',
  api.save_calendar_event(
    current_setting('test.calendar')::uuid,
    '{"title":"Later","startsAt":"2030-05-06T09:00:00Z","endsAt":"2030-05-06T10:00:00Z"}'
  ) ->> 'id',
  true
);
select api.save_reminder('00000000-0000-4000-8000-000000000001', 'calendar_event', current_setting('test.event'), 15);

select api.calendar_bootstrap(
  '00000000-0000-4000-8000-000000000001',
  '2030-03-01T00:00:00Z', '2030-04-01T00:00:00Z',
  '2030-05-01T00:00:00Z', '2030-06-01T00:00:00Z'
) as boot \gset

select is(
  (select jsonb_agg(c ->> 'name') from jsonb_array_elements(:'boot'::jsonb -> 'calendarList') c where c ->> 'name' = 'Bootstrap'),
  '["Bootstrap"]'::jsonb,
  'the calendars of the organization come back'
);
select is(
  (select jsonb_agg(e ->> 'title') from jsonb_array_elements(:'boot'::jsonb -> 'monthEvents') e),
  '["Planning"]'::jsonb,
  'the events of the first range come back'
);
select is(
  (select jsonb_agg(e ->> 'title') from jsonb_array_elements(:'boot'::jsonb -> 'upcomingEvents') e),
  '["Later"]'::jsonb,
  'the events of the second range come back'
);
select is(
  (select jsonb_agg(r ->> 'offsetMinutes') from jsonb_array_elements(:'boot'::jsonb -> 'myReminders') r where r ->> 'subjectId' = current_setting('test.event')),
  '["15"]'::jsonb,
  'the reminders of the caller on events come back'
);
select is(
  api.calendar_bootstrap('00000000-0000-4000-8000-000000000001', '2030-03-01T00:00:00Z', '2030-04-01T00:00:00Z') -> 'upcomingEvents',
  '[]'::jsonb,
  'without a second range the upcoming events are empty'
);

-- Globex owner, outside Acme.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select is(
  (select count(*) from jsonb_array_elements(api.calendar_bootstrap('00000000-0000-4000-8000-000000000001', '2030-03-01T00:00:00Z', '2030-04-01T00:00:00Z') -> 'calendarList') c where c ->> 'name' = 'Bootstrap'),
  0::bigint,
  'a caller outside the organization sees none of its calendars'
);
select is(
  api.calendar_bootstrap('00000000-0000-4000-8000-000000000001', '2030-03-01T00:00:00Z', '2030-04-01T00:00:00Z') -> 'myReminders',
  '[]'::jsonb,
  'and none of its reminders'
);

select * from finish();
rollback;
