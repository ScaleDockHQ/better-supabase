-- The observations module against the seed: the Acme owner (…a1) records
-- vital signs on the Road Runner customer with the seeded vitals
-- definitions, an Acme member (…a2) records and reads them but can't manage
-- definitions, and the Globex owner (…a3) sees none of it. Run with
-- `supabase test db`.
begin;
select plan(15);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('observation_definitions', 'observations')
     and rowsecurity),
  2::bigint,
  'the observations tables have RLS enabled'
);
select table_privs_are('better_supabase', 'observations', 'anon', '{}'::text[],
  'anon has no privileges on observations');
select table_privs_are('better_supabase', 'observation_definitions', 'anon', '{}'::text[],
  'anon has no privileges on observation definitions');
select is(
  (select count(*) from better_supabase.observation_definitions where tenant_id is null),
  9::bigint,
  'the vitals defaults seed nine system definitions'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('pulse', (better_supabase.record_observation(
  '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001',
  'heart_rate', '128') ->> 'id')::uuid);

select is(
  (select flag from better_supabase.observations where id = (select id from ids where name = 'pulse')),
  'high',
  'a heart rate above the reference range is flagged high'
);
select throws_ok(
  $$select better_supabase.record_observation('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'heart_rate', '900')$$,
  '22023',
  null,
  'a value outside the valid range is refused'
);
select throws_ok(
  $$select better_supabase.record_observation('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a003', 'heart_rate', '70')$$,
  '42501',
  null,
  'a record of another organization is refused'
);
select is(
  (better_supabase.save_observation_definition('00000000-0000-4000-8000-000000000001', 'mews',
    '{"title":"MEWS","valueType":"integer","validLow":0,"validHigh":14,"criticalHigh":7}') ->> 'system')::boolean,
  false,
  'the owner saves an organization definition'
);
select is(
  better_supabase.amend_observation((select id from ids where name = 'pulse'), '{"value": 80}', 'wrong monitor') ->> 'flag',
  'normal',
  'an amendment records the corrected value with its own flag'
);
select is(
  (select status from better_supabase.observations where id = (select id from ids where name = 'pulse')),
  'amended',
  'the amended observation is no longer final'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(better_supabase.list_observations('customer', '00000000-0000-4000-8000-00000000a001')),
  1,
  'a member reads the final observations'
);
select lives_ok(
  $$select better_supabase.record_observation('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'body_temperature', '37.2')$$,
  'a member records an observation'
);
select throws_ok(
  $$select better_supabase.save_observation_definition('00000000-0000-4000-8000-000000000001', 'pews', '{"title":"PEWS","valueType":"integer"}')$$,
  '42501',
  null,
  'a member cannot manage definitions'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*) from better_supabase.observations),
  0::bigint,
  'the Globex owner sees no Acme observations'
);
select is(
  (select count(*) from better_supabase.observation_definitions
   where tenant_id = '00000000-0000-4000-8000-000000000001'),
  0::bigint,
  'the Globex owner sees no Acme definitions'
);
select * from finish();
rollback;
