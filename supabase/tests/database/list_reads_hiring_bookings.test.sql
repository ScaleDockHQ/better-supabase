-- The list reads of hiring and bookings as the admin (…00a1) of Acme (…0001):
-- jobs by status, applications by state, and the booking resources and services
-- without the inactive ones. Another organization's rows never show.
begin;
select plan(9);

insert into better_supabase.job_openings (id, tenant_id, title, status) values
  ('00000000-0000-4000-8000-00000000d001', '00000000-0000-4000-8000-000000000001', 'Engineer', 'open'),
  ('00000000-0000-4000-8000-00000000d002', '00000000-0000-4000-8000-000000000001', 'Designer', 'closed'),
  ('00000000-0000-4000-8000-00000000d003', '00000000-0000-4000-8000-0000000000ff', 'Elsewhere', 'open');
insert into better_supabase.applications (id, tenant_id, job_id, candidate_type, candidate_id, state) values
  ('00000000-0000-4000-8000-00000000d101', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000d001', 'person', 'p1', 'active'),
  ('00000000-0000-4000-8000-00000000d102', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000d001', 'person', 'p2', 'rejected');
insert into better_supabase.booking_resources (id, tenant_id, name, capacity, tz, active) values
  ('00000000-0000-4000-8000-00000000d201', '00000000-0000-4000-8000-000000000001', 'Studio', 1, 'UTC', true),
  ('00000000-0000-4000-8000-00000000d202', '00000000-0000-4000-8000-000000000001', 'Old room', 1, 'UTC', false);
insert into better_supabase.booking_services (id, tenant_id, name, duration, active) values
  ('00000000-0000-4000-8000-00000000d301', '00000000-0000-4000-8000-000000000001', 'Class', interval '1 hour', true),
  ('00000000-0000-4000-8000-00000000d302', '00000000-0000-4000-8000-000000000001', 'Retired', interval '30 minutes', false);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(better_supabase.list_jobs('00000000-0000-4000-8000-000000000001')),
  2,
  'list_jobs returns the organization''s jobs only'
);
select is(
  better_supabase.list_jobs('00000000-0000-4000-8000-000000000001', 'open') -> 0 ->> 'title',
  'Engineer',
  'list_jobs keeps one status'
);
select is(
  jsonb_array_length(better_supabase.list_jobs('00000000-0000-4000-8000-0000000000ff')),
  0,
  'list_jobs hides another organization''s jobs'
);
select is(
  jsonb_array_length(better_supabase.list_applications('00000000-0000-4000-8000-00000000d001')),
  2,
  'list_applications returns a job''s applications'
);
select is(
  jsonb_array_length(better_supabase.list_applications('00000000-0000-4000-8000-00000000d001', 'hired')),
  0,
  'list_applications keeps one state'
);
select is(
  jsonb_array_length(better_supabase.list_booking_resources('00000000-0000-4000-8000-000000000001')),
  1,
  'list_booking_resources leaves out inactive resources'
);
select is(
  jsonb_array_length(better_supabase.list_booking_resources('00000000-0000-4000-8000-000000000001', true)),
  2,
  'include_inactive adds them back'
);
select is(
  better_supabase.list_booking_services('00000000-0000-4000-8000-000000000001') -> 0 ->> 'name',
  'Class',
  'list_booking_services leaves out inactive services'
);
select is(
  better_supabase.list_booking_services('00000000-0000-4000-8000-000000000001') -> 0 ->> 'duration',
  '01:00:00',
  'a duration is interval text'
);

select * from finish();
rollback;
