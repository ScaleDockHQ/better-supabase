-- The inspections module against the seed: the Acme owner (…a1) plans an
-- audit programme, schedules an inspection with the member …a2 as auditee,
-- records a major finding and can't close the inspection until the finding
-- has a case. The member reads only the inspection they are on and can't add
-- findings, and the Globex owner (…a3) sees none of it. Run with
-- `supabase test db`.
begin;
select plan(20);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('inspection_programs', 'inspections', 'inspection_members', 'inspection_findings')
     and rowsecurity),
  4::bigint,
  'the inspections tables have RLS enabled'
);
select table_privs_are('better_supabase', 'inspections', 'anon', '{}'::text[],
  'anon has no privileges on inspections');
select table_privs_are('better_supabase', 'inspection_findings', 'anon', '{}'::text[],
  'anon has no privileges on findings');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('programme', (better_supabase.save_inspection_program(
  '00000000-0000-4000-8000-000000000001', 'Audit programme 2027', '2027-01-01', '2027-12-31') ->> 'id')::uuid);
insert into ids values ('warehouse', (better_supabase.schedule_inspection(
  '00000000-0000-4000-8000-000000000001',
  jsonb_build_object(
    'programId', (select id from ids where name = 'programme'),
    'kind', 'internal_audit',
    'title', 'Warehouse audit',
    'plannedStart', '2027-02-01',
    'members', jsonb_build_array(jsonb_build_object(
      'userId', '00000000-0000-4000-8000-0000000000a2', 'role', 'auditee'))
  )) ->> 'id')::uuid);
insert into ids values ('office', (better_supabase.schedule_inspection(
  '00000000-0000-4000-8000-000000000001',
  '{"kind": "inspection", "title": "Office walk-through"}'::jsonb) ->> 'id')::uuid);

select is(
  better_supabase.approve_inspection_program((select id from ids where name = 'programme')) ->> 'status',
  'approved',
  'the owner approves the programme'
);
select is(
  (select status from better_supabase.inspections where id = (select id from ids where name = 'warehouse')),
  'planned',
  'a scheduled inspection starts planned'
);
select is(
  (select role from better_supabase.inspection_members
   where inspection_id = (select id from ids where name = 'warehouse')
     and user_id = '00000000-0000-4000-8000-0000000000a2'),
  'auditee',
  'the member joins the inspection team as auditee'
);
select throws_ok(
  $$select better_supabase.schedule_inspection('00000000-0000-4000-8000-000000000001', '{"kind": "astrology", "title": "Odd"}'::jsonb)$$,
  '22023',
  null,
  'a kind outside options.kinds is refused'
);
select throws_ok(
  $$select better_supabase.add_inspection_finding((select id from ids where name = 'warehouse'), 'major_nonconformity', 'Too early')$$,
  '55000',
  null,
  'a planned inspection takes no findings'
);

select is(
  better_supabase.start_inspection((select id from ids where name = 'warehouse')) ->> 'status',
  'in_progress',
  'the lead starts the inspection'
);
insert into ids values ('labels', (better_supabase.add_inspection_finding(
  (select id from ids where name = 'warehouse'), 'major_nonconformity', 'Unlabelled stock',
  clause => 'ISO 9001 8.5.2') ->> 'id')::uuid);
select is(
  (select number from better_supabase.inspection_findings where id = (select id from ids where name = 'labels')),
  1,
  'the first finding is numbered 1'
);
select throws_ok(
  $$select better_supabase.add_inspection_finding((select id from ids where name = 'warehouse'), 'gossip', 'Odd')$$,
  '22023',
  null,
  'a finding type outside options.findingTypes is refused'
);
select is(
  better_supabase.complete_inspection((select id from ids where name = 'warehouse'), 'One major finding') ->> 'status',
  'reporting',
  'the lead completes the inspection'
);
select throws_ok(
  $$select better_supabase.close_inspection((select id from ids where name = 'warehouse'))$$,
  '55000',
  null,
  'an inspection with a major finding and no case does not close'
);
select isnt(
  better_supabase.raise_inspection_finding_case((select id from ids where name = 'labels')) ->> 'caseId',
  null,
  'the finding raises a case of the finding kind'
);
select is(
  (select count(*) from better_supabase.relations
   where kind = 'created_from'
     and target_type = 'inspection_finding'
     and target_id = (select id from ids where name = 'labels')::text),
  1::bigint,
  'the case links back to the finding'
);
select is(
  better_supabase.close_inspection((select id from ids where name = 'warehouse')) ->> 'status',
  'closed',
  'the inspection closes once the finding has a case'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(better_supabase.list_inspections('00000000-0000-4000-8000-000000000001')),
  1,
  'a member lists only the inspection they are on'
);
select throws_ok(
  $$select better_supabase.get_inspection((select id from ids where name = 'office'))$$,
  'P0002',
  null,
  'a member cannot read an inspection they are not on'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*) from better_supabase.inspections) + (select count(*) from better_supabase.inspection_findings),
  0::bigint,
  'the Globex owner sees no Acme inspections or findings'
);
select throws_ok(
  $$select better_supabase.start_inspection((select id from ids where name = 'office'))$$,
  '42501',
  null,
  'the Globex owner cannot start an Acme inspection'
);
select * from finish();
rollback;
