-- The acknowledgements module against the seed: the Acme owner (…a1) publishes
-- a policy and asks the member role to acknowledge it, an Acme member (…a2)
-- acknowledges the current version and is asked again after a new one, and
-- the Globex owner (…a3) sees none of it. Run with `supabase test db`.
begin;
select plan(19);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('acknowledgement_assignments', 'acknowledgements', 'acknowledgement_notices')
     and rowsecurity),
  3::bigint,
  'the acknowledgements tables have RLS enabled'
);
select table_privs_are('better_supabase', 'acknowledgements', 'anon', '{}'::text[],
  'anon has no privileges on acknowledgements');
select table_privs_are('better_supabase', 'acknowledgement_notices', 'authenticated', '{}'::text[],
  'signed-in users cannot read the reminder log');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('aup', (better_supabase.save_compliance_policy(
  '00000000-0000-4000-8000-000000000001', 'acceptable-use', 'Acceptable use') ->> 'id')::uuid);
insert into ids values ('v1', (better_supabase.publish_compliance_policy(
  (select id from ids where name = 'aup'), '{"body":"Be kind"}'::jsonb, 'v1') ->> 'versionId')::uuid);
insert into ids values ('ask', (better_supabase.assign_acknowledgement(
  '00000000-0000-4000-8000-000000000001', 'compliance_policy', (select id::text from ids where name = 'aup'),
  'role', 'member', due_in_days => 14) ->> 'id')::uuid);

select is(
  (select count(*) from ids where id is not null),
  3::bigint,
  'the owner publishes a policy and asks the member role to acknowledge it'
);
select throws_ok(
  $$select better_supabase.assign_acknowledgement('00000000-0000-4000-8000-000000000001', 'compliance_policy',
    (select id::text from ids where name = 'aup'), 'role', 'member', due_in_days => 0)$$,
  '22023',
  'due_in_days must be between 1 and 365',
  'a due date outside one to 365 days is refused'
);
select throws_ok(
  $$select better_supabase.assign_acknowledgement('00000000-0000-4000-8000-000000000001', 'compliance_policy',
    (select id::text from ids where name = 'aup'), 'user', '00000000-0000-4000-8000-0000000000a3')$$,
  '22023',
  'the user isn''t a member of this organization',
  'a user from another organization cannot be asked'
);
select is(
  (better_supabase.acknowledgement_status('compliance_policy', (select id::text from ids where name = 'aup')) ->> 'versionId')::uuid,
  (select id from ids where name = 'v1'),
  'the status counts acknowledgements of the published version'
);
select is(
  jsonb_array_length(better_supabase.list_acknowledgement_assignments('compliance_policy', (select id::text from ids where name = 'aup'))),
  1,
  'the owner lists the assignment'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (better_supabase.list_my_acknowledgements('00000000-0000-4000-8000-000000000001') -> 0 ->> 'dueOn')::date,
  current_date + 14,
  'the member sees the policy, due 14 days after the version was published'
);
select throws_ok(
  $$select better_supabase.assign_acknowledgement('00000000-0000-4000-8000-000000000001', 'compliance_policy',
    (select id::text from ids where name = 'aup'), 'role', 'admin')$$,
  '42501',
  null,
  'a member cannot assign acknowledgements'
);
select throws_ok(
  $$select better_supabase.acknowledge('compliance_policy', (select id::text from ids where name = 'aup'),
    version_id => '00000000-0000-4000-8000-00000000dead')$$,
  '55000',
  'the record has a newer version; acknowledge that one',
  'acknowledging a version that isn''t current is refused'
);
insert into ids values ('ack', (better_supabase.acknowledge(
  'compliance_policy', (select id::text from ids where name = 'aup'), version_id => (select id from ids where name = 'v1')) ->> 'id')::uuid);
select is(
  (select method from better_supabase.acknowledgements where id = (select id from ids where name = 'ack')),
  'click',
  'the member acknowledges the current version'
);
select is(
  (better_supabase.acknowledge('compliance_policy', (select id::text from ids where name = 'aup')) ->> 'id')::uuid,
  (select id from ids where name = 'ack'),
  'acknowledging twice keeps one acknowledgement'
);
select is(
  jsonb_array_length(better_supabase.list_my_acknowledgements('00000000-0000-4000-8000-000000000001')),
  0,
  'an acknowledged policy is no longer pending'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

insert into ids values ('v2', (better_supabase.publish_compliance_policy(
  (select id from ids where name = 'aup'), '{"body":"Be kinder"}'::jsonb, 'v2') ->> 'versionId')::uuid);
select is(
  jsonb_array_length(better_supabase.acknowledgements_of('compliance_policy', (select id::text from ids where name = 'aup'),
    version_id => (select id from ids where name = 'v1'))),
  1,
  'the acknowledgement of the first version stays on record'
);
select is(
  jsonb_array_length(better_supabase.acknowledgements_of('compliance_policy', (select id::text from ids where name = 'aup'))),
  0,
  'a new version has no acknowledgements yet'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (better_supabase.list_my_acknowledgements('00000000-0000-4000-8000-000000000001') -> 0 ->> 'versionId')::uuid,
  (select id from ids where name = 'v2'),
  'a new version asks the member again'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*) from better_supabase.acknowledgement_assignments) + (select count(*) from better_supabase.acknowledgements),
  0::bigint,
  'the Globex owner sees no Acme assignments or acknowledgements'
);
select throws_ok(
  $$select better_supabase.acknowledgements_of('compliance_policy', (select id::text from ids where name = 'aup'))$$,
  '42501',
  null,
  'the Globex owner cannot read who acknowledged an Acme policy'
);
select * from finish();
rollback;
