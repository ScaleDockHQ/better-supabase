-- book_with_reminder (ADR 1235): scheduling.bookWithReminder as one function.
-- The admin (…a1) of Acme (…0001) books a confirmed slot and sets a reminder
-- 60 minutes before it in one call. A slot that is taken fails and saves no
-- reminder.
begin;
select plan(5);

insert into better_supabase.booking_resources (id, tenant_id, name, capacity, tz) values
  ('00000000-0000-4000-8000-00000000d001', '00000000-0000-4000-8000-000000000001', 'Desk', 1, 'UTC');
insert into better_supabase.booking_availability (tenant_id, resource_id, weekday, starts_at, ends_at)
select '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000d001', d, time '06:00', time '22:00'
from generate_series(1, 7) d;
insert into better_supabase.booking_services (id, tenant_id, name, duration) values
  ('00000000-0000-4000-8000-00000000d101', '00000000-0000-4000-8000-000000000001', 'Welcome', interval '1 hour');

select set_config('test.day', (date_trunc('day', now()) + interval '2 days')::text, true);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.result', better_supabase.book_with_reminder(
  '00000000-0000-4000-8000-00000000d101',
  '00000000-0000-4000-8000-00000000d001',
  current_setting('test.day')::timestamptz + interval '10 hours',
  '{"name":"Bo","email":"bo@example.test"}',
  60)::text, true);

select is(
  current_setting('test.result')::jsonb -> 'booking' ->> 'status',
  'confirmed',
  'the booking is confirmed'
);
select ok(
  current_setting('test.result')::jsonb -> 'reminder' ->> 'id' is not null,
  'a reminder id comes back'
);
select is(
  (select count(*) from jsonb_array_elements(better_supabase.list_my_reminders(
     '00000000-0000-4000-8000-000000000001', 'booking',
     current_setting('test.result')::jsonb -> 'booking' ->> 'id')) r
   where (r ->> 'offsetMinutes')::int = 60),
  1::bigint,
  'the reminder is on the booking, 60 minutes before'
);
select throws_ok(
  $$select better_supabase.book_with_reminder(
    '00000000-0000-4000-8000-00000000d101', '00000000-0000-4000-8000-00000000d001',
    current_setting('test.day')::timestamptz + interval '10 hours', '{"name":"Al"}', 30)$$,
  '23P01',
  null,
  'a taken slot is refused'
);
select is(
  (select count(*) from jsonb_array_elements(better_supabase.list_my_reminders(
     '00000000-0000-4000-8000-000000000001')) r
   where (r ->> 'offsetMinutes')::int = 30),
  0::bigint,
  'a refused booking saves no reminder'
);

select * from finish();
rollback;
