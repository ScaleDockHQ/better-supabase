-- The shifts module against the seed: the Acme owner (…a1) plans shifts from
-- a template and assigns the Acme member (…a2), the checks refuse overlap,
-- short rest and a missing qualification, the member reads only the published
-- roster and asks for a swap, and the Globex owner (…a3) sees none of it.
-- Run with `supabase test db`.
begin;
select plan(20);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('shift_templates', 'shifts', 'shift_assignments', 'shift_swaps', 'shift_availability')
     and rowsecurity),
  5::bigint,
  'the shifts tables have RLS enabled'
);
select table_privs_are('better_supabase', 'shifts', 'anon', '{}'::text[],
  'anon has no privileges on shifts');
select table_privs_are('better_supabase', 'shift_assignments', 'authenticated', array['SELECT'],
  'authenticated only reads assignments; writes go through the functions');
select ok(
  not has_function_privilege('authenticated',
    'better_supabase.shifts_to_time_entries(uuid, timestamptz)', 'execute'),
  'only the service role turns shifts into time entries'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('template', (better_supabase.save_shift_template(
  '00000000-0000-4000-8000-000000000001', 'Early', '06:00', '14:00',
  weekdays => array[1, 2, 3, 4, 5, 6, 7]) ->> 'id')::uuid);

select is(
  jsonb_array_length(better_supabase.generate_shifts('00000000-0000-4000-8000-000000000001',
    (select id from ids where name = 'template'), current_date + 10, current_date + 12)),
  3,
  'a template generates one shift a day'
);
select is(
  jsonb_array_length(better_supabase.generate_shifts('00000000-0000-4000-8000-000000000001',
    (select id from ids where name = 'template'), current_date + 10, current_date + 12)),
  0,
  'generating again skips the days that have the shift'
);

insert into ids values ('early', (select id from better_supabase.shifts
  where template_id = (select id from ids where name = 'template')
  order by starts_at limit 1));
insert into ids values ('late', (better_supabase.save_shift('00000000-0000-4000-8000-000000000001',
  ((current_date + 10) + time '15:00') at time zone 'UTC',
  ((current_date + 10) + time '22:00') at time zone 'UTC') ->> 'id')::uuid);
insert into ids values ('overlap', (better_supabase.save_shift('00000000-0000-4000-8000-000000000001',
  ((current_date + 10) + time '12:00') at time zone 'UTC',
  ((current_date + 10) + time '18:00') at time zone 'UTC') ->> 'id')::uuid);

insert into ids values ('assigned', (better_supabase.assign_shift(
  (select id from ids where name = 'early'), '00000000-0000-4000-8000-0000000000a2') ->> 'id')::uuid);

select is(
  (select status from better_supabase.shift_assignments where id = (select id from ids where name = 'assigned')),
  'assigned',
  'the owner assigns the member to a shift'
);
select throws_ok(
  $$select better_supabase.assign_shift((select id from ids where name = 'overlap'), '00000000-0000-4000-8000-0000000000a2')$$,
  '23P01',
  null,
  'an overlapping shift is refused'
);
select throws_ok(
  $$select better_supabase.assign_shift((select id from ids where name = 'late'), '00000000-0000-4000-8000-0000000000a2')$$,
  '23514',
  null,
  'a shift one hour after the last one is refused for rest time'
);
select throws_ok(
  $$select better_supabase.assign_shift((select id from ids where name = 'late'), '00000000-0000-4000-8000-0000000000a3')$$,
  '22023',
  null,
  'a user outside the organization is refused'
);

select better_supabase.save_qualification_type('00000000-0000-4000-8000-000000000001',
  'first_aid', 'First aid', array['member']);
insert into ids values ('qualified', (better_supabase.save_shift('00000000-0000-4000-8000-000000000001',
  ((current_date + 20) + time '08:00') at time zone 'UTC',
  ((current_date + 20) + time '16:00') at time zone 'UTC',
  required_qualifications => array['first_aid']) ->> 'id')::uuid);
select throws_ok(
  $$select better_supabase.assign_shift((select id from ids where name = 'qualified'), '00000000-0000-4000-8000-0000000000a2')$$,
  '23514',
  null,
  'a member without the required qualification is refused'
);
select throws_ok(
  $$select better_supabase.save_shift('00000000-0000-4000-8000-000000000001', now(), now() + interval '25 hours')$$,
  '22023',
  null,
  'a shift longer than 24 hours is refused'
);

select is(
  better_supabase.publish_shifts('00000000-0000-4000-8000-000000000001', current_date + 10, current_date + 10),
  3,
  'publishing a day publishes its drafts'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(better_supabase.roster('00000000-0000-4000-8000-000000000001', current_date + 10, current_date + 20)),
  3,
  'a member sees the published shifts, not the drafts'
);
select is(
  jsonb_array_length(better_supabase.my_shifts()),
  1,
  'a member reads their own shifts'
);
select throws_ok(
  $$select better_supabase.save_shift('00000000-0000-4000-8000-000000000001', now() + interval '1 day', now() + interval '1 day 8 hours')$$,
  '42501',
  null,
  'a member cannot plan shifts'
);
select is(
  better_supabase.request_shift_swap((select id from ids where name = 'assigned'),
    '00000000-0000-4000-8000-0000000000a1') ->> 'status',
  'pending',
  'a member offers their shift to a colleague'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  better_supabase.decide_shift_swap((select id from better_supabase.shift_swaps
    where assignment_id = (select id from ids where name = 'assigned')), true) ->> 'status',
  'approved',
  'the owner approves the swap'
);
select is(
  (select user_id from better_supabase.shift_assignments
   where shift_id = (select id from ids where name = 'early') and status = 'assigned'),
  '00000000-0000-4000-8000-0000000000a1'::uuid,
  'the colleague takes the shift'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*) from better_supabase.shifts),
  0::bigint,
  'another organization sees none of the shifts'
);

select * from finish();
rollback;
