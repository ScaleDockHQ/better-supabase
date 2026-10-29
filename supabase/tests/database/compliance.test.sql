-- The compliance module against the seed: the Acme owner (…a1) sets up a
-- framework, controls, an evidence task and a policy, an Acme member (…a2)
-- collects evidence and acknowledges the policy, and the Globex owner (…a3)
-- sees none of it. Run with `supabase test db`.
begin;
select plan(20);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('control_frameworks', 'controls', 'control_evidence', 'evidence_tasks', 'policies', 'policy_acknowledgements')
     and rowsecurity),
  6::bigint,
  'the controls tables have RLS enabled'
);
select table_privs_are('better_supabase', 'controls', 'anon', '{}'::text[],
  'anon has no privileges on controls');
select table_privs_are('better_supabase', 'policies', 'anon', '{}'::text[],
  'anon has no privileges on policies');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('soc2', (better_supabase.save_control_framework(
  '00000000-0000-4000-8000-000000000001', 'soc2', 'SOC 2', '2017') ->> 'id')::uuid);
insert into ids values ('cc61', (better_supabase.save_control(
  (select id from ids where name = 'soc2'), 'CC6.1', 'Logical access',
  owner_id => '00000000-0000-4000-8000-0000000000a2') ->> 'id')::uuid);
insert into ids values ('cc72', (better_supabase.save_control(
  (select id from ids where name = 'soc2'), 'CC7.2', 'Monitoring') ->> 'id')::uuid);
insert into ids values ('a11', (better_supabase.save_control(
  (select id from ids where name = 'soc2'), 'A1.1', 'Capacity', applicable => false) ->> 'id')::uuid);
insert into ids values ('review', (better_supabase.save_evidence_task(
  (select id from ids where name = 'cc72'), 'Review alerts', 30, current_date - 1,
  '00000000-0000-4000-8000-0000000000a2') ->> 'id')::uuid);
insert into ids values ('aup', (better_supabase.save_policy(
  '00000000-0000-4000-8000-000000000001', 'acceptable-use', 'Acceptable use') ->> 'id')::uuid);

select is(
  (select count(*) from ids),
  6::bigint,
  'the owner sets up a framework, three controls, an evidence task and a policy'
);
select throws_ok(
  $$select better_supabase.save_control_framework('00000000-0000-4000-8000-000000000002', 'iso', 'ISO 27001')$$,
  '42501',
  null,
  'the owner cannot add a framework to an organization they only belong to as a member'
);
select is(
  (better_supabase.publish_policy((select id from ids where name = 'aup'), '{"body":"Be kind"}'::jsonb, 'v1') ->> 'versionId') is not null,
  true,
  'publishing a policy stores a version'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select better_supabase.save_control((select id from ids where name = 'soc2'), 'CC9.9', 'Sneaky')$$,
  '42501',
  null,
  'a member cannot add controls'
);
select is(
  (better_supabase.list_evidence_tasks('00000000-0000-4000-8000-000000000001', overdue_only => true) -> 0 ->> 'overdue'),
  'true',
  'an evidence task past its due date is overdue'
);
select is(
  (better_supabase.add_control_evidence((select id from ids where name = 'cc61'), note => 'Access review done') ->> 'controlId')::uuid,
  (select id from ids where name = 'cc61'),
  'a member collects evidence for a control'
);
select ok(
  (better_supabase.add_control_evidence((select id from ids where name = 'cc72'), note => 'Alerts reviewed',
    task_id => (select id from ids where name = 'review')) ->> 'id') is not null,
  'a member collects evidence for an evidence task'
);
select is(
  (select due_on from better_supabase.evidence_tasks where id = (select id from ids where name = 'review')),
  current_date + 30,
  'collecting evidence moves the task to its next due date'
);
select is(
  (select string_agg(p ->> 'passing' || '/' || (p ->> 'failing') || '/' || (p ->> 'notApplicable') || '/' || (p ->> 'total'), ',')
   from jsonb_array_elements(better_supabase.control_posture('00000000-0000-4000-8000-000000000001')) p),
  '2/0/1/3',
  'the posture rolls up passing, failing and not applicable controls'
);
select is(
  jsonb_array_length(better_supabase.list_policies('00000000-0000-4000-8000-000000000001', pending_only => true)),
  1,
  'the published policy waits for the member to acknowledge it'
);
select lives_ok(
  $$select better_supabase.acknowledge_policy((select id from ids where name = 'aup'))$$,
  'a member acknowledges the policy'
);
select is(
  jsonb_array_length(better_supabase.list_policies('00000000-0000-4000-8000-000000000001', pending_only => true)),
  0,
  'an acknowledged policy is no longer pending'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*) from better_supabase.controls) + (select count(*) from better_supabase.policies),
  0::bigint,
  'the Globex owner sees no Acme controls or policies'
);
select throws_ok(
  $$select better_supabase.add_control_evidence((select id from ids where name = 'cc61'), note => 'Forged')$$,
  null,
  null,
  'the Globex owner cannot add evidence to an Acme control'
);

-- A legal register: a framework of kind legal whose controls are obligations.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (select better_supabase.save_control(
    (better_supabase.save_control_framework(
      '00000000-0000-4000-8000-000000000001', 'gdpr', 'GDPR register', kind => 'legal') ->> 'id')::uuid,
    'ART30', 'Records of processing',
    source => 'GDPR article 30', jurisdiction => 'EU') - 'id' - 'organizationId' - 'frameworkId' - 'createdAt' - 'updatedAt' - 'fields' - 'status' - 'description' - 'ownerId' - 'applicable' - 'code' - 'title'),
  '{"source":"GDPR article 30","jurisdiction":"EU"}'::jsonb,
  'a control keeps where its obligation comes from and where it applies'
);
select is(
  (select f ->> 'kind' from jsonb_array_elements(better_supabase.list_control_frameworks('00000000-0000-4000-8000-000000000001')) f
   where f ->> 'key' = 'gdpr'),
  'legal',
  'a legal register is a framework of kind legal'
);
select throws_ok(
  $$select better_supabase.save_control_framework('00000000-0000-4000-8000-000000000001', 'odd', 'Odd', kind => 'treaty')$$,
  '22023',
  'kind must be one of standard, legal, internal, contract',
  'a framework kind outside the list is refused'
);
select * from finish();
rollback;
