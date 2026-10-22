-- Bookings to engagements: a confirmed booking keeps one meeting engagement,
-- linked to the booker's person and company, and cancelling it completes the
-- meeting. Acme (…0001) has the owner …a1 (supabase/seed.sql).
begin;
select plan(14);

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values
  ('resource', gen_random_uuid()),
  ('service', gen_random_uuid()),
  ('company', gen_random_uuid()),
  ('person', gen_random_uuid()),
  ('booking', gen_random_uuid()),
  ('stranger', gen_random_uuid());

insert into better_supabase.booking_resources (id, tenant_id, name) values
  ((select id from ids where name = 'resource'), '00000000-0000-4000-8000-000000000001', 'Ada');
insert into better_supabase.booking_services (id, tenant_id, name, duration) values
  ((select id from ids where name = 'service'), '00000000-0000-4000-8000-000000000001', 'Intro call', interval '30 minutes');
insert into better_supabase.companies (id, tenant_id, name, lifecycle) values
  ((select id from ids where name = 'company'), '00000000-0000-4000-8000-000000000001', 'Initech', 'customer');
insert into better_supabase.people (id, tenant_id, name, email, lifecycle, owner_user_id) values
  ((select id from ids where name = 'person'), '00000000-0000-4000-8000-000000000001', 'Peter', 'peter@initech.test', 'customer', '00000000-0000-4000-8000-0000000000a1');
insert into better_supabase.company_people (tenant_id, company_id, person_id, is_primary) values
  ('00000000-0000-4000-8000-000000000001', (select id from ids where name = 'company'), (select id from ids where name = 'person'), true);

-- A hold logs nothing.
insert into better_supabase.bookings (id, tenant_id, resource_id, service_id, during, blocked, status, hold_expires_at, customer_name, customer_email, notes) values
  ((select id from ids where name = 'booking'), '00000000-0000-4000-8000-000000000001', (select id from ids where name = 'resource'), (select id from ids where name = 'service'),
   tstzrange('2026-11-02 10:00+00', '2026-11-02 10:30+00'), tstzrange('2026-11-02 10:00+00', '2026-11-02 10:30+00'), 'hold', now() + interval '10 minutes', 'Peter', 'Peter@Initech.test', 'Bring the TPS reports');

select is(
  (select count(*)::int from better_supabase.engagements where external_ref = 'booking:' || (select id from ids where name = 'booking')),
  0,
  'a held booking logs no engagement'
);

update better_supabase.bookings set status = 'confirmed', hold_expires_at = null where id = (select id from ids where name = 'booking');

select results_eq(
  $$select type, title, body, owner_user_id, due_at, duration_seconds, done_at is null
    from better_supabase.engagements where external_ref = 'booking:' || (select id from ids where name = 'booking')$$,
  $$values ('meeting'::text, 'Intro call with Peter'::text, 'Bring the TPS reports'::text, '00000000-0000-4000-8000-0000000000a1'::uuid, '2026-11-02 10:00+00'::timestamptz, 1800, true)$$,
  'confirming logs an open meeting owned by the person''s owner'
);
select results_eq(
  $$select s.subject_type, s.subject_id, s.position from better_supabase.engagement_subjects s
    join better_supabase.engagements e on e.id = s.engagement_id
    where e.external_ref = 'booking:' || (select id from ids where name = 'booking') order by s.position$$,
  $$values ('person'::text, (select id::text from ids where name = 'person'), 1), ('company'::text, (select id::text from ids where name = 'company'), 2)$$,
  'the meeting links the booker (matched by email, any case) and their company'
);
select is(
  (select count(*)::int from better_supabase.outbox_events where type = 'engagement.logged' and payload ->> 'subjectType' = 'person'),
  1,
  'confirming records engagement.logged on the person'
);

-- Moving a confirmed booking moves the meeting; a no-op update changes nothing.
update better_supabase.bookings set notes = 'changed' where id = (select id from ids where name = 'booking');
select is(
  (select count(*)::int from better_supabase.outbox_events where type = 'engagement.updated'),
  0,
  'an update that keeps status and time records nothing'
);
update better_supabase.bookings
set during = tstzrange('2026-11-03 09:00+00', '2026-11-03 10:00+00'), blocked = tstzrange('2026-11-03 09:00+00', '2026-11-03 10:00+00')
where id = (select id from ids where name = 'booking');
select results_eq(
  $$select due_at, duration_seconds from better_supabase.engagements where external_ref = 'booking:' || (select id from ids where name = 'booking')$$,
  $$values ('2026-11-03 09:00+00'::timestamptz, 3600)$$,
  'rescheduling moves the meeting'
);
select is(
  (select count(*)::int from better_supabase.engagements where external_ref = 'booking:' || (select id from ids where name = 'booking')),
  1,
  'rescheduling keeps one engagement'
);
select is(
  (select count(*)::int from better_supabase.outbox_events where type = 'engagement.updated'),
  1,
  'rescheduling records engagement.updated'
);
select is(
  (select count(*)::int from better_supabase.engagement_subjects s join better_supabase.engagements e on e.id = s.engagement_id
   where e.external_ref = 'booking:' || (select id from ids where name = 'booking')),
  2,
  'rescheduling does not duplicate the links'
);

-- Cancelling completes the meeting with the reason.
update better_supabase.bookings
set status = 'cancelled', cancelled_at = '2026-11-01 08:00+00', cancel_reason = '  Out sick '
where id = (select id from ids where name = 'booking');
select results_eq(
  $$select done_at, outcome from better_supabase.engagements where external_ref = 'booking:' || (select id from ids where name = 'booking')$$,
  $$values ('2026-11-01 08:00+00'::timestamptz, 'cancelled: Out sick'::text)$$,
  'cancelling completes the meeting with the reason'
);
select is(
  (select count(*)::int from better_supabase.outbox_events where type = 'engagement.completed'),
  1,
  'cancelling records engagement.completed'
);

-- A booking without a matching person is a meeting on no subject, titled by the service.
insert into better_supabase.bookings (id, tenant_id, resource_id, service_id, during, blocked, status, customer_email, created_by) values
  ((select id from ids where name = 'stranger'), '00000000-0000-4000-8000-000000000001', (select id from ids where name = 'resource'), (select id from ids where name = 'service'),
   tstzrange('2026-11-04 10:00+00', '2026-11-04 10:30+00'), tstzrange('2026-11-04 10:00+00', '2026-11-04 10:30+00'), 'confirmed', 'nobody@elsewhere.test', '00000000-0000-4000-8000-0000000000a1');
select results_eq(
  $$select title, body, owner_user_id from better_supabase.engagements where external_ref = 'booking:' || (select id from ids where name = 'stranger')$$,
  $$values ('Intro call'::text, null::text, '00000000-0000-4000-8000-0000000000a1'::uuid)$$,
  'an unknown booker gets a meeting owned by the booking''s author'
);
select is(
  (select count(*)::int from better_supabase.engagement_subjects s join better_supabase.engagements e on e.id = s.engagement_id
   where e.external_ref = 'booking:' || (select id from ids where name = 'stranger')),
  0,
  'an unknown booker links no subject'
);

select ok(
  not has_function_privilege('authenticated', 'better_supabase.bs_booking_engagement()', 'execute'),
  'the trigger function is not callable by users'
);

select * from finish();
rollback;
