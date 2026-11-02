-- E-prescribing on the fixture. The Acme owner (…a1) drafts a prescription for an
-- active order, signs it as the prescriber, records a failed and then a
-- successful delivery and the dispensing. A second draft names the Acme member
-- (…a2) as prescriber: the owner may not sign it, the service role never signs,
-- and the owner may cancel it as a manager. The member holds no e_prescribing
-- keys. Run with `supabase test db`.
begin;
select plan(17);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase' and tablename = 'prescriptions' and rowsecurity),
  1::bigint,
  'the prescriptions table has RLS enabled'
);
select table_privs_are('better_supabase', 'prescriptions', 'anon', '{}'::text[], 'anon has no privileges on prescriptions');
select table_privs_are('better_supabase', 'prescriptions', 'authenticated', array['SELECT'], 'members can only read prescriptions');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('med', (better_supabase.save_medication(
  '00000000-0000-4000-8000-000000000001', 'Amoxicillin', 'mg') ->> 'id')::uuid);
insert into ids values ('order', (better_supabase.prescribe_medication(
  '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001',
  (select id from ids where name = 'med'),
  jsonb_build_object('dose', 500, 'schedule', jsonb_build_object('times', jsonb_build_array('08:00', '20:00')),
    'startsOn', current_date)) ->> 'id')::uuid);
insert into ids values ('order2', (better_supabase.prescribe_medication(
  '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001',
  (select id from ids where name = 'med'),
  jsonb_build_object('dose', 250, 'schedule', jsonb_build_object('times', jsonb_build_array('09:00')),
    'startsOn', current_date)) ->> 'id')::uuid);

insert into ids values ('rx', (better_supabase.create_prescription(
  '00000000-0000-4000-8000-000000000001', (select id from ids where name = 'order')) ->> 'id')::uuid);
select is(
  (select status from better_supabase.prescriptions where id = (select id from ids where name = 'rx')),
  'draft',
  'an owner drafts a prescription for an active order'
);
select throws_ok(
  $$select better_supabase.create_prescription('00000000-0000-4000-8000-000000000001', (select id from ids where name = 'order'))$$,
  '55000',
  null,
  'an order has one prescription that is not cancelled'
);
select throws_ok(
  $$select better_supabase.record_prescription_delivery((select id from ids where name = 'rx'), 'gw', 'ref-1')$$,
  '55000',
  null,
  'a draft cannot be sent'
);
select lives_ok(
  $$select better_supabase.sign_prescription((select id from ids where name = 'rx'))$$,
  'the prescriber signs the draft'
);
select is(
  (select snapshot ->> 'medicationName' from better_supabase.prescriptions where id = (select id from ids where name = 'rx')),
  'Amoxicillin',
  'the signature freezes the order'
);
select throws_ok(
  $$select better_supabase.sign_prescription((select id from ids where name = 'rx'))$$,
  '55000',
  null,
  'a signed prescription cannot be signed again'
);
select is(
  better_supabase.record_prescription_delivery((select id from ids where name = 'rx'), 'gw', null, 'timeout') ->> 'status',
  'signed',
  'a failed delivery leaves the prescription signed'
);
select is(
  better_supabase.record_prescription_delivery((select id from ids where name = 'rx'), 'gw', 'ref-1') ->> 'status',
  'sent',
  'a delivery with a receipt marks it sent'
);
select is(
  better_supabase.record_prescription_dispense((select id from ids where name = 'rx')) ->> 'status',
  'dispensed',
  'the pharmacy dispenses a sent prescription'
);
select throws_ok(
  $$select better_supabase.cancel_prescription((select id from ids where name = 'rx'), 'late')$$,
  '55000',
  null,
  'a dispensed prescription cannot be cancelled'
);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
insert into ids values ('rx2', (better_supabase.create_prescription(
  '00000000-0000-4000-8000-000000000001', (select id from ids where name = 'order2'),
  jsonb_build_object('prescriberId', '00000000-0000-4000-8000-0000000000a2')) ->> 'id')::uuid);
select throws_ok(
  $$select better_supabase.sign_prescription((select id from ids where name = 'rx2'))$$,
  '42501',
  null,
  'the service role never signs'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  $$select better_supabase.sign_prescription((select id from ids where name = 'rx2'))$$,
  '42501',
  null,
  'only the named prescriber signs'
);
select lives_ok(
  $$select better_supabase.cancel_prescription((select id from ids where name = 'rx2'))$$,
  'a manager cancels a draft without a reason'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  $$select better_supabase.list_prescriptions('00000000-0000-4000-8000-000000000001')$$,
  '42501',
  null,
  'a member without the key may not read prescriptions'
);

select * from finish();
rollback;
