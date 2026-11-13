-- list_bookings_for_customer (ADR 0822): a customer's bookings, newest first,
-- as the caller. The admin of Acme reads them; the customer reads their own;
-- another customer sees none. Run with `supabase test db`.
begin;
select plan(4);

insert into auth.users (id, email, email_confirmed_at, aud, role, instance_id) values
  ('00000000-0000-4000-8000-0000000000e1', 'holder@example.test', now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
  ('00000000-0000-4000-8000-0000000000e2', 'other@example.test', now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000');
insert into better_supabase.booking_resources (id, tenant_id, name, capacity, tz) values
  ('00000000-0000-4000-8000-00000000c001', '00000000-0000-4000-8000-000000000001', 'Studio', 1, 'UTC');
insert into better_supabase.booking_services (id, tenant_id, name, duration) values
  ('00000000-0000-4000-8000-00000000c101', '00000000-0000-4000-8000-000000000001', 'Class', interval '1 hour');
insert into better_supabase.bookings (tenant_id, resource_id, service_id, seat, during, blocked, status, customer_name, customer_id)
values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000c001', '00000000-0000-4000-8000-00000000c101', 1,
   tstzrange(now() + interval '1 day', now() + interval '1 day 1 hour'), tstzrange(now() + interval '1 day', now() + interval '1 day 1 hour'), 'confirmed', 'Holder', '00000000-0000-4000-8000-0000000000e1');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select is(
  jsonb_array_length(better_supabase.list_bookings_for_customer(
    '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000e1')),
  1,
  'the admin reads the customer''s bookings'
);
select is(
  better_supabase.list_bookings_for_customer(
    '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000e2'),
  '[]'::jsonb,
  'another customer has none'
);

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;
select is(
  jsonb_array_length(better_supabase.list_bookings_for_customer(
    '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000e1')),
  1,
  'the customer reads their own booking'
);

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e2","role":"authenticated"}', true);
set local role authenticated;
select is(
  better_supabase.list_bookings_for_customer(
    '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000e1'),
  '[]'::jsonb,
  'another customer cannot read it'
);

select * from finish();
rollback;
