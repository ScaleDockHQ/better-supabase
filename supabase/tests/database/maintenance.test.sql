-- The maintenance module against the seed: the Acme owner (…a1) adds a meter
-- and two plans, one by time and one by meter, records readings, generates
-- dispatch work orders and closes one. It also covers RRULE plans and the
-- qualifications a technician and a calibration need. The member …a2 reads but can't manage,
-- and the Globex owner (…a3) sees none of it. Run with `supabase test db`.
begin;
select plan(31);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('maintenance_plans', 'maintenance_plan_parts', 'maintenance_meters', 'maintenance_meter_readings', 'maintenance_calibrations')
     and rowsecurity),
  5::bigint,
  'the maintenance tables have RLS enabled'
);
select table_privs_are('better_supabase', 'maintenance_plans', 'anon', '{}'::text[],
  'anon has no privileges on plans');
select table_privs_are('better_supabase', 'maintenance_calibrations', 'anon', '{}'::text[],
  'anon has no privileges on calibrations');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('meter', (better_supabase.create_maintenance_meter(
  '00000000-0000-4000-8000-000000000001', 'Press hours', 'h') ->> 'id')::uuid);

select is(
  better_supabase.record_meter_reading((select id from ids where name = 'meter'), 100) ->> 'reading',
  '100',
  'a reading sets the meter'
);
select throws_ok(
  format($$select better_supabase.record_meter_reading(%L, 50)$$, (select id from ids where name = 'meter')),
  '22023',
  null,
  'a reading never goes below the previous one'
);

insert into ids values ('meterPlan', (better_supabase.create_maintenance_plan(
  '00000000-0000-4000-8000-000000000001',
  jsonb_build_object(
    'title', 'Grease the press',
    'kind', 'meter',
    'meterId', (select id from ids where name = 'meter'),
    'everyValue', '500',
    'priority', 'high',
    'parts', jsonb_build_array(jsonb_build_object('name', 'Grease', 'quantity', '2'))
  )) ->> 'id')::uuid);
insert into ids values ('timePlan', (better_supabase.create_maintenance_plan(
  '00000000-0000-4000-8000-000000000001',
  jsonb_build_object('title', 'Fire extinguisher check', 'kind', 'time', 'everyDays', 30)) ->> 'id')::uuid);

select throws_ok(
  $$select better_supabase.create_maintenance_plan('00000000-0000-4000-8000-000000000001', '{"title": "Odd", "kind": "time"}'::jsonb)$$,
  '22023',
  null,
  'a time plan needs everyDays'
);
select throws_ok(
  $$select better_supabase.create_maintenance_plan('00000000-0000-4000-8000-000000000001', '{"title": "Odd", "kind": "yearly", "everyDays": 5}'::jsonb)$$,
  '22023',
  null,
  'the kind is time or meter'
);
select is(
  (select count(*) from better_supabase.maintenance_plan_parts
   where plan_id = (select id from ids where name = 'meterPlan')),
  1::bigint,
  'the plan keeps its spare parts'
);
select is(
  jsonb_array_length(better_supabase.generate_maintenance_work_orders('00000000-0000-4000-8000-000000000001')),
  0,
  'nothing is due yet'
);

select better_supabase.record_meter_reading((select id from ids where name = 'meter'), 650);
select is(
  (select (p ->> 'due')::boolean
   from jsonb_array_elements(better_supabase.list_maintenance_plans('00000000-0000-4000-8000-000000000001')) p
   where p ->> 'title' = 'Grease the press'),
  true,
  '500 units later the meter plan is due'
);

create temporary table made (made jsonb) on commit drop;
insert into made select better_supabase.generate_maintenance_work_orders('00000000-0000-4000-8000-000000000001');
select is(
  jsonb_array_length((select made from made)),
  1,
  'one work order opens for the plan that is due'
);
select is(
  (select count(*) from better_supabase.work_order_parts
   where work_order_id = (((select made from made) -> 0 ->> 'workOrderId'))::uuid),
  1::bigint,
  'the plan''s spare part is on the work order'
);
select is(
  jsonb_array_length(better_supabase.generate_maintenance_work_orders('00000000-0000-4000-8000-000000000001')),
  0,
  'a plan with an open work order opens no second one'
);

select better_supabase.schedule_work_order(
  (((select made from made) -> 0 ->> 'workOrderId'))::uuid,
  '00000000-0000-4000-8000-0000000000a2',
  '2031-01-07 11:00:00+00', '2031-01-07 13:00:00+00'
);
select better_supabase.set_work_order_status((((select made from made) -> 0 ->> 'workOrderId'))::uuid, 'en_route');
select better_supabase.set_work_order_status((((select made from made) -> 0 ->> 'workOrderId'))::uuid, 'on_site');
select better_supabase.set_work_order_status((((select made from made) -> 0 ->> 'workOrderId'))::uuid, 'done');
select is(
  (select (p ->> 'due')::boolean
   from jsonb_array_elements(better_supabase.list_maintenance_plans('00000000-0000-4000-8000-000000000001')) p
   where p ->> 'title' = 'Grease the press'),
  false,
  'a done work order resets the meter plan'
);

select is(
  better_supabase.record_calibration('00000000-0000-4000-8000-000000000001',
    '{"instrument": "Scale", "performedAt": "2026-10-01T09:00:00Z", "dueAt": "2027-10-01T09:00:00Z", "result": "pass"}'::jsonb) ->> 'result',
  'pass',
  'a calibration is recorded'
);
select throws_ok(
  $$select better_supabase.record_calibration('00000000-0000-4000-8000-000000000001', '{"instrument": "Scale", "performedAt": "2026-10-01T09:00:00Z", "dueAt": "2026-09-01T09:00:00Z", "result": "pass"}'::jsonb)$$,
  '22023',
  null,
  'a calibration is due on or after it was performed'
);

insert into ids values ('rrulePlan', (better_supabase.create_maintenance_plan(
  '00000000-0000-4000-8000-000000000001',
  jsonb_build_object('title', 'First Monday inspection', 'kind', 'rrule',
    'rrule', 'FREQ=MONTHLY;BYDAY=1MO', 'dtstart', '2031-01-06T09:00:00Z', 'tz', 'UTC')) ->> 'id')::uuid);
select is(
  (select next_due_at from better_supabase.maintenance_plans where id = (select id from ids where name = 'rrulePlan')),
  '2031-01-06 09:00:00+00'::timestamptz,
  'an rrule plan falls due on the first occurrence after now'
);
select throws_ok(
  $$select better_supabase.create_maintenance_plan('00000000-0000-4000-8000-000000000001', '{"title": "Odd", "kind": "rrule", "rrule": "FREQ=HOURLY", "dtstart": "2031-01-06T09:00:00Z"}'::jsonb)$$,
  '22023',
  null,
  'an rrule needs FREQ of DAILY to YEARLY'
);
select throws_ok(
  $$select better_supabase.create_maintenance_plan('00000000-0000-4000-8000-000000000001', '{"title": "Odd", "kind": "rrule", "rrule": "FREQ=DAILY"}'::jsonb)$$,
  '22023',
  null,
  'an rrule plan needs a dtstart'
);
select throws_ok(
  $$select better_supabase.create_maintenance_plan('00000000-0000-4000-8000-000000000001', '{"title": "Odd", "kind": "time", "everyDays": 5, "rrule": "FREQ=DAILY"}'::jsonb)$$,
  '22023',
  null,
  'a time plan takes no rrule'
);
select throws_ok(
  $$select better_supabase.create_maintenance_plan('00000000-0000-4000-8000-000000000001', '{"title": "Odd", "kind": "rrule", "rrule": "FREQ=DAILY", "dtstart": "2031-01-06T09:00:00Z", "tz": "Mars/Base"}'::jsonb)$$,
  '22023',
  null,
  'the time zone must be an IANA name'
);

select better_supabase.save_qualification_type('00000000-0000-4000-8000-000000000001',
  'welding', 'Welding', array['member']);
select throws_ok(
  $$select better_supabase.create_maintenance_plan('00000000-0000-4000-8000-000000000001', '{"title": "Odd", "kind": "time", "everyDays": 5, "requiredQualifications": ["unknown"]}'::jsonb)$$,
  '22023',
  null,
  'a required qualification must be a qualification type'
);
select throws_ok(
  $$select better_supabase.record_calibration('00000000-0000-4000-8000-000000000001', '{"instrument": "Scale", "performedAt": "2026-10-01T09:00:00Z", "dueAt": "2027-10-01T09:00:00Z", "result": "pass", "qualifications": ["unknown"]}'::jsonb)$$,
  '22023',
  null,
  'a calibration names qualification types that exist'
);
select throws_ok(
  $$select better_supabase.record_calibration('00000000-0000-4000-8000-000000000001', '{"instrument": "Scale", "performedAt": "2026-10-01T09:00:00Z", "dueAt": "2027-10-01T09:00:00Z", "result": "pass", "qualifications": ["welding"]}'::jsonb)$$,
  '42501',
  null,
  'a calibration by someone without the qualification is refused'
);

insert into ids values ('weldPlan', (better_supabase.create_maintenance_plan(
  '00000000-0000-4000-8000-000000000001',
  jsonb_build_object('title', 'Weld inspection', 'kind', 'rrule', 'rrule', 'FREQ=WEEKLY',
    'dtstart', '2026-01-05T09:00:00Z', 'requiredQualifications', jsonb_build_array('welding'))) ->> 'id')::uuid);
reset role;
update better_supabase.maintenance_plans set next_due_at = now() - interval '1 hour'
  where id = (select id from ids where name = 'weldPlan');
set local role authenticated;
create temporary table weld (made jsonb) on commit drop;
insert into weld select better_supabase.generate_maintenance_work_orders('00000000-0000-4000-8000-000000000001');
select is(
  jsonb_array_length((select made from weld)),
  1,
  'an rrule plan that fell due opens a work order'
);
select throws_ok(
  format($$select better_supabase.schedule_work_order(%L, '00000000-0000-4000-8000-0000000000a2', '2031-02-07 11:00:00+00', '2031-02-07 13:00:00+00')$$,
    (select made -> 0 ->> 'workOrderId' from weld)),
  '42501',
  null,
  'a technician without the required qualification can''t be assigned'
);

select better_supabase.grant_qualification('00000000-0000-4000-8000-000000000001', 'welding', 'member', '00000000-0000-4000-8000-0000000000a2');
select better_supabase.grant_qualification('00000000-0000-4000-8000-000000000001', 'welding', 'member', '00000000-0000-4000-8000-0000000000a1');
select is(
  (better_supabase.schedule_work_order(
    ((select made -> 0 ->> 'workOrderId' from weld))::uuid,
    '00000000-0000-4000-8000-0000000000a2', '2031-02-07 11:00:00+00', '2031-02-07 13:00:00+00') ->> 'technicianId'),
  '00000000-0000-4000-8000-0000000000a2',
  'a qualified technician is assigned'
);
select is(
  better_supabase.record_calibration('00000000-0000-4000-8000-000000000001',
    jsonb_build_object('instrument', 'Scale', 'performedAt', now(), 'dueAt', now() + interval '1 year', 'result', 'pass', 'qualifications', jsonb_build_array('welding'))) -> 'qualifications',
  '["welding"]'::jsonb,
  'a qualified calibration keeps the qualifications it needed'
);

select better_supabase.set_work_order_status(((select made -> 0 ->> 'workOrderId' from weld))::uuid, 'en_route');
select better_supabase.set_work_order_status(((select made -> 0 ->> 'workOrderId' from weld))::uuid, 'on_site');
select better_supabase.set_work_order_status(((select made -> 0 ->> 'workOrderId' from weld))::uuid, 'done');
select is(
  (select next_due_at > now() and last_done_at is not null and work_order_id is null
   from better_supabase.maintenance_plans where id = (select id from ids where name = 'weldPlan')),
  true,
  'a done work order moves an rrule plan to its next occurrence'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  $$select better_supabase.create_maintenance_plan('00000000-0000-4000-8000-000000000001', '{"title": "Nope", "kind": "time", "everyDays": 5}'::jsonb)$$,
  '42501',
  null,
  'a member can''t manage plans'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select is(
  (select count(*) from better_supabase.maintenance_plans),
  0::bigint,
  'another organization sees no plans'
);

select * from finish();
rollback;
