-- The risks module against the seed: the Acme owner (…a1) registers and
-- assesses a risk on the default matrix, an Acme member (…a2) reads it but
-- can't change it, and the Globex owner (…a3) sees none of it. Run with
-- `supabase test db`.
begin;
select plan(16);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('risk_matrices', 'risks', 'risk_assessments')
     and rowsecurity),
  3::bigint,
  'the risks tables have RLS enabled'
);
select table_privs_are('better_supabase', 'risks', 'anon', '{}'::text[],
  'anon has no privileges on risks');
select table_privs_are('better_supabase', 'risk_assessments', 'anon', '{}'::text[],
  'anon has no privileges on risk assessments');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('spill', (better_supabase.create_risk(
  '00000000-0000-4000-8000-000000000001',
  '{"title":"Solvent spill","category":"environment","reviewIntervalMonths":6}') ->> 'id')::uuid);

select is(
  jsonb_array_length(better_supabase.list_risk_matrices('00000000-0000-4000-8000-000000000001') -> 0 -> 'bands'),
  4,
  'the organization gets the default matrix with four bands'
);
select throws_ok(
  $$select better_supabase.create_risk('00000000-0000-4000-8000-000000000001', '{"title":"Odd","category":"astrology"}')$$,
  '22023',
  null,
  'a category outside the list is refused'
);
select throws_ok(
  $$select better_supabase.create_risk('00000000-0000-4000-8000-000000000002', '{"title":"Elsewhere","category":"quality"}')$$,
  '42501',
  null,
  'the owner cannot register a risk in an organization they only belong to as a member'
);
select throws_ok(
  $$select better_supabase.assess_risk((select id from ids where name = 'spill'), 6, 1, 1, 1)$$,
  '22023',
  null,
  'a likelihood outside the matrix is refused'
);
select is(
  (select (r -> 'inherent' ->> 'band') || '/' || (r -> 'inherent' ->> 'score') || '/'
     || (r -> 'residual' ->> 'band') || '/' || (r -> 'residual' ->> 'score')
   from (select better_supabase.assess_risk((select id from ids where name = 'spill'),
     4, 5, 2, 3, 'Bunded storage') as r) x),
  'critical/20/medium/6',
  'an assessment scores the risk before and after controls'
);
select is(
  (select status from better_supabase.risks where id = (select id from ids where name = 'spill')),
  'assessed',
  'the first assessment moves the risk to assessed'
);
select is(
  (select count(*) from better_supabase.risk_assessments
   where risk_id = (select id from ids where name = 'spill') and version_id is not null),
  1::bigint,
  'the assessment is frozen as a version'
);
select is(
  (select c ->> 'count' from jsonb_array_elements(
     better_supabase.risk_heatmap('00000000-0000-4000-8000-000000000001') -> 'cells') c
   where (c ->> 'likelihood')::int = 2 and (c ->> 'impact')::int = 3),
  '1',
  'the heatmap counts the risk in its residual cell'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(better_supabase.list_risks('00000000-0000-4000-8000-000000000001')),
  1,
  'a member reads the register'
);
select throws_ok(
  $$select better_supabase.set_risk_treatment((select id from ids where name = 'spill'), 'accept')$$,
  '42501',
  null,
  'a member cannot accept a risk'
);
select throws_ok(
  $$select better_supabase.close_risk((select id from ids where name = 'spill'), 'Gone')$$,
  '42501',
  null,
  'a member cannot close a risk'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*) from better_supabase.risks) + (select count(*) from better_supabase.risk_assessments),
  0::bigint,
  'the Globex owner sees no Acme risks or assessments'
);
select throws_ok(
  $$select better_supabase.get_risk((select id from ids where name = 'spill'))$$,
  'P0002',
  null,
  'the Globex owner cannot read an Acme risk'
);
select * from finish();
rollback;
