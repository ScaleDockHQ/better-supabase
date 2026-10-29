-- The qualifications module against the seed: the Acme owner (…a1) defines a
-- forklift licence every member must hold and grants it, the Acme member
-- (…a2) reads their own gaps but can't grant, and the Globex owner (…a3)
-- sees none of it. Run with `supabase test db`.
begin;
select plan(17);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('qualification_types', 'qualification_requirements', 'qualifications')
     and rowsecurity),
  3::bigint,
  'the qualifications tables have RLS enabled'
);
select table_privs_are('better_supabase', 'qualifications', 'anon', '{}'::text[],
  'anon has no privileges on qualifications');
select table_privs_are('better_supabase', 'qualifications', 'authenticated', array['SELECT'],
  'authenticated only reads qualifications; writes go through the functions');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('forklift', (better_supabase.save_qualification_type(
  '00000000-0000-4000-8000-000000000001', 'forklift', 'Forklift licence', array['member'],
  valid_for_months => 12) ->> 'id')::uuid);
insert into ids values ('rule', (better_supabase.add_qualification_requirement(
  (select id from ids where name = 'forklift'), 'role', 'member') ->> 'id')::uuid);

select is(
  (better_supabase.qualification_gaps('00000000-0000-4000-8000-000000000001', 'member',
    '{"holderId": "00000000-0000-4000-8000-0000000000a2"}') -> 0 ->> 'status'),
  'missing',
  'a member the role requirement names lacks the licence'
);
select throws_ok(
  $$select better_supabase.save_qualification_type('00000000-0000-4000-8000-000000000001', 'bad', 'Bad', array['member'], valid_for_months => 300)$$,
  '22023',
  'valid_for_months is between 1 and 240',
  'a validity past 240 months is refused'
);
select throws_ok(
  $$select better_supabase.add_qualification_requirement((select id from ids where name = 'forklift'), 'asset_kind', 'truck')$$,
  '22023',
  null,
  'an asset kind requirement on a member-only type is refused'
);
select throws_ok(
  $$select better_supabase.grant_qualification('00000000-0000-4000-8000-000000000001', 'forklift', 'member', '00000000-0000-4000-8000-0000000000a3')$$,
  '22023',
  'the holder isn''t in this organization',
  'a holder outside the organization is refused'
);

insert into ids values ('held', (better_supabase.grant_qualification(
  '00000000-0000-4000-8000-000000000001', 'forklift', 'member', '00000000-0000-4000-8000-0000000000a2',
  granted_on => current_date - 350) ->> 'id')::uuid);

select is(
  (select expires_on from better_supabase.qualifications where id = (select id from ids where name = 'held')),
  (current_date - 350 + interval '12 months')::date,
  'a holding expires the type''s validity after it was granted'
);
select is(
  (better_supabase.qualification_gaps('00000000-0000-4000-8000-000000000001', 'member',
    '{"holderId": "00000000-0000-4000-8000-0000000000a2"}') -> 0 ->> 'status'),
  'expiring',
  'a holding inside the renewal window is expiring'
);
select is(
  better_supabase.qualified_holders('00000000-0000-4000-8000-000000000001', 'forklift'),
  '["00000000-0000-4000-8000-0000000000a2"]'::jsonb,
  'the member is qualified today'
);
select is(
  better_supabase.qualified_holders('00000000-0000-4000-8000-000000000001', 'forklift',
    on_date => current_date + 60),
  '[]'::jsonb,
  'nobody is qualified after the holding expires'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(better_supabase.qualifications_of('member', '00000000-0000-4000-8000-0000000000a2')),
  1,
  'a member reads their own holdings'
);
select is(
  jsonb_array_length(better_supabase.qualification_gaps('00000000-0000-4000-8000-000000000001', 'member',
    '{"holderId": "00000000-0000-4000-8000-0000000000a2"}')),
  1,
  'a member reads their own gaps'
);
select throws_ok(
  $$select better_supabase.qualification_gaps('00000000-0000-4000-8000-000000000001')$$,
  '42501',
  null,
  'a member cannot read everyone''s gaps'
);
select throws_ok(
  $$select better_supabase.grant_qualification('00000000-0000-4000-8000-000000000001', 'forklift', 'member', '00000000-0000-4000-8000-0000000000a2')$$,
  '42501',
  null,
  'a member cannot grant qualifications'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*) from better_supabase.qualification_types) + (select count(*) from better_supabase.qualifications),
  0::bigint,
  'the Globex owner sees no Acme types or holdings'
);
select throws_ok(
  $$select better_supabase.revoke_qualification((select id from ids where name = 'held'))$$,
  null,
  null,
  'the Globex owner cannot revoke an Acme holding'
);

select * from finish();
rollback;
