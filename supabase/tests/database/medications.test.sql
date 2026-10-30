-- The medications module against the seed: the Acme owner (…a1) adds a
-- high-risk medication, prescribes it for a customer and plans its doses, the
-- double check refuses a missing, self or unqualified checker, the Acme member
-- (…a2) holds no medications keys, and the Globex owner (…a3) sees none of it.
-- Run with `supabase test db`.
begin;
select plan(18);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('medications', 'medication_orders', 'medication_administrations')
     and rowsecurity),
  3::bigint,
  'the medications tables have RLS enabled'
);
select table_privs_are('better_supabase', 'medication_orders', 'anon', '{}'::text[],
  'anon has no privileges on medication orders');
select table_privs_are('better_supabase', 'medication_administrations', 'authenticated', array['SELECT'],
  'authenticated only reads doses; writes go through the functions');
select ok(
  not has_function_privilege('authenticated',
    'better_supabase.mark_missed_medication_administrations()', 'execute'),
  'only the service role marks doses missed'
);
select ok(
  not has_function_privilege('authenticated',
    'better_supabase.import_medication_orders(uuid, jsonb)', 'execute'),
  'only the service role imports orders'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('warfarin', (better_supabase.save_medication(
  '00000000-0000-4000-8000-000000000001', 'Warfarin', 'mg', 'atc', 'B01AA03',
  high_risk => true) ->> 'id')::uuid);

select throws_ok(
  $$select better_supabase.save_medication('00000000-0000-4000-8000-000000000001', 'Again', 'mg', 'atc', 'B01AA03')$$,
  '22023',
  null,
  'a code is unique per code system in an organization'
);

insert into ids values ('order', (better_supabase.prescribe_medication(
  '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001',
  (select id from ids where name = 'warfarin'),
  jsonb_build_object('dose', 2, 'schedule', jsonb_build_object('times', jsonb_build_array('08:00', '20:00')),
    'startsOn', current_date + 1)) ->> 'id')::uuid);

select is(
  (select dose_unit from better_supabase.medication_orders where id = (select id from ids where name = 'order')),
  'mg',
  'an order takes the medication''s unit'
);
select throws_ok(
  $$select better_supabase.prescribe_medication('00000000-0000-4000-8000-000000000001', 'customer',
    '00000000-0000-4000-8000-00000000a001', (select id from ids where name = 'warfarin'), '{"dose":2}')$$,
  '22023',
  null,
  'an order without a schedule must be given as needed'
);

select ok(
  better_supabase.plan_medication_administrations('00000000-0000-4000-8000-000000000001', now() + interval '3 days') >= 4,
  'planning adds the doses of the next days'
);
select is(
  better_supabase.plan_medication_administrations('00000000-0000-4000-8000-000000000001', now() + interval '3 days'),
  0,
  'planning again adds nothing'
);

insert into ids values ('dose', (select id from better_supabase.medication_administrations
  where order_id = (select id from ids where name = 'order') order by scheduled_at limit 1));

select throws_ok(
  $$select better_supabase.record_medication_administration((select id from ids where name = 'dose'), 'given')$$,
  '22023',
  'this dose needs a second member to check it',
  'a high-risk dose needs a second member'
);
select throws_ok(
  $$select better_supabase.record_medication_administration((select id from ids where name = 'dose'), 'given',
    null, null, '00000000-0000-4000-8000-0000000000a1')$$,
  '22023',
  'the second check is by another member',
  'the member who gives the dose cannot check it'
);
select throws_ok(
  $$select better_supabase.record_medication_administration((select id from ids where name = 'dose'), 'given',
    null, null, '00000000-0000-4000-8000-0000000000a2')$$,
  '22023',
  'the member who checks may administer medication in this organization',
  'a checker without medications.administer is refused'
);
select throws_ok(
  $$select better_supabase.record_medication_administration((select id from ids where name = 'dose'), 'refused')$$,
  '22023',
  'a refused or skipped dose needs a reason',
  'a refused dose needs a reason'
);

reset role;
update better_supabase.medication_administrations
  set scheduled_at = now() - interval '2 hours'
  where id = (select id from ids where name = 'dose');
select is(
  better_supabase.mark_missed_medication_administrations(),
  1,
  'a dose past missedAfterMinutes becomes missed'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select better_supabase.prescribe_medication('00000000-0000-4000-8000-000000000001', 'customer',
    '00000000-0000-4000-8000-00000000a001', (select id from ids where name = 'warfarin'), '{"dose":1,"asNeeded":true}')$$,
  '42501',
  null,
  'a member without medications.prescribe cannot prescribe'
);
select is(
  (select count(*) from better_supabase.medication_orders),
  0::bigint,
  'a member without medications.read sees no orders'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*) from better_supabase.medication_administrations),
  0::bigint,
  'another organization sees none of the doses'
);

select * from finish();
rollback;
