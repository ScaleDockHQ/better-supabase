-- Recurring bookings and class credits on the fixture's access contract: the
-- admin (…00a1) of Acme (…0001) books a daily series on a one-seat room, moves
-- an occurrence, and books a class for a holder (…00e1) with a pack of
-- credits that is refunded on an early cancellation. The member (…00a2)
-- outside the bookings permissions can't move a booking.
begin;
select plan(16);

insert into auth.users (id, email, email_confirmed_at, aud, role, instance_id) values
  ('00000000-0000-4000-8000-0000000000e1', 'holder@example.test', now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000');

insert into better_supabase.booking_resources (id, tenant_id, name, capacity, tz) values
  ('00000000-0000-4000-8000-00000000c001', '00000000-0000-4000-8000-000000000001', 'Studio', 1, 'UTC');
insert into better_supabase.booking_availability (tenant_id, resource_id, weekday, starts_at, ends_at)
select '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000c001', d, time '06:00', time '22:00'
from generate_series(1, 7) d;
insert into better_supabase.booking_services (id, tenant_id, name, duration) values
  ('00000000-0000-4000-8000-00000000c101', '00000000-0000-4000-8000-000000000001', 'Class', interval '1 hour');

select set_config('test.day', (date_trunc('day', now()) + interval '2 days')::text, true);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.series', better_supabase.book_series(
  '00000000-0000-4000-8000-00000000c101',
  '00000000-0000-4000-8000-00000000c001',
  current_setting('test.day')::timestamptz + interval '10 hours',
  '{"freq":"daily","count":3}',
  '{"name":"Bo","email":"bo@example.test"}'
)::text, true);

select is(
  jsonb_array_length(current_setting('test.series')::jsonb -> 'bookings'),
  3,
  'a daily rule with a count of 3 books 3 occurrences'
);
select is(
  (select count(*) from better_supabase.bookings
   where series_id = (current_setting('test.series')::jsonb -> 'series' ->> 'id')::uuid and status = 'confirmed'),
  3::bigint,
  'every occurrence is a confirmed booking in the series'
);
select throws_ok(
  $$select better_supabase.book_series(
    '00000000-0000-4000-8000-00000000c101', '00000000-0000-4000-8000-00000000c001',
    current_setting('test.day')::timestamptz + interval '1 day 10 hours', '{"freq":"daily","count":2}', '{"name":"Al"}')$$,
  '23P01',
  'an occurrence is not an open slot',
  'a series that overlaps a taken occurrence fails'
);
select is(
  jsonb_array_length(better_supabase.book_series(
    '00000000-0000-4000-8000-00000000c101', '00000000-0000-4000-8000-00000000c001',
    current_setting('test.day')::timestamptz + interval '1 day 10 hours', '{"freq":"daily","count":4}', '{"name":"Al"}', true
  ) -> 'skipped'),
  2,
  'with skip_conflicts the taken occurrences are skipped'
);
select throws_ok(
  $$select better_supabase.booking_series_starts('{"freq":"monthly","count":2}', now(), 'UTC')$$,
  '22023',
  null,
  'a monthly rule is refused'
);

select set_config(
  'test.first',
  current_setting('test.series')::jsonb -> 'bookings' -> 0 ->> 'id',
  true
);
select is(
  (better_supabase.reschedule_booking(
    current_setting('test.first')::uuid,
    current_setting('test.day')::timestamptz + interval '8 hours'
  ) -> 0 ->> 'startsAt')::timestamptz,
  current_setting('test.day')::timestamptz + interval '8 hours',
  'reschedule moves one occurrence'
);
select throws_ok(
  $$select better_supabase.reschedule_booking(
    current_setting('test.first')::uuid,
    current_setting('test.day')::timestamptz + interval '1 day 10 hours'
  )$$,
  '23P01',
  null,
  'a move onto a taken seat is refused by the exclusion constraint'
);
select is(
  (select lower(during) from better_supabase.bookings where id = current_setting('test.first')::uuid),
  current_setting('test.day')::timestamptz + interval '8 hours',
  'a refused move leaves the booking where it was'
);
select throws_ok(
  $$select better_supabase.move_booking(current_setting('test.first')::uuid, now())$$,
  '42501',
  null,
  'move_booking is not granted to members'
);
select is(
  better_supabase.cancel_booking_series(current_setting('test.first')::uuid),
  3,
  'cancelling from the first occurrence cancels the series'
);
reset role;
select is(
  (select status from better_supabase.booking_series where id = (current_setting('test.series')::jsonb -> 'series' ->> 'id')::uuid),
  'cancelled',
  'the series is cancelled'
);

-- Class credits.
set local role authenticated;
select set_config('test.pack', better_supabase.issue_pass(
  '00000000-0000-4000-8000-000000000001', 'visitor',
  holder_user => '00000000-0000-4000-8000-0000000000e1', holder_name => 'Holder',
  resource_id => '00000000-0000-4000-8000-00000000c001', uses_allowed => 2
)::text, true);
select set_config('test.class', better_supabase.book_with_credit(
  (current_setting('test.pack')::jsonb ->> 'id')::uuid,
  '00000000-0000-4000-8000-00000000c101',
  '00000000-0000-4000-8000-00000000c001',
  current_setting('test.day')::timestamptz + interval '15 hours'
)::text, true);

select is(
  (current_setting('test.class')::jsonb ->> 'creditsLeft')::int,
  1,
  'a class takes one credit from the pack'
);
select is(
  current_setting('test.class')::jsonb ->> 'customerUserId',
  '00000000-0000-4000-8000-0000000000e1',
  'the class is booked for the holder'
);
select better_supabase.cancel_booking((current_setting('test.class')::jsonb ->> 'id')::uuid, 'ill');
select is(
  (select sum((e ->> 'delta')::int)::int from jsonb_array_elements(
    better_supabase.list_pass_credits((current_setting('test.pack')::jsonb ->> 'id')::uuid)
  ) e),
  0,
  'an early cancellation refunds the credit'
);
reset role;
select throws_ok(
  $$insert into better_supabase.pass_credit_entries (tenant_id, pass_id, booking_id, delta, reason)
    values ('00000000-0000-4000-8000-000000000001', (current_setting('test.pack')::jsonb ->> 'id')::uuid,
      (current_setting('test.class')::jsonb ->> 'id')::uuid, 1, 'refund')$$,
  '23505',
  null,
  'a booking is refunded once'
);

-- Acme member without bookings.manage.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select throws_ok(
  $$select better_supabase.list_pass_credits((current_setting('test.pack')::jsonb ->> 'id')::uuid)$$,
  'P0002',
  null,
  'someone who neither holds nor reads passes cannot read the credits'
);

select * from finish();
rollback;
