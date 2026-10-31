-- The maintenance module against the seed: the Acme owner (…a1) adds a meter
-- and two plans, one by time and one by meter, records readings, generates
-- dispatch work orders and closes one. The member …a2 reads but can't manage,
-- and the Globex owner (…a3) sees none of it. Run with `supabase test db`.
begin;
select plan(18);

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
