-- The lims module against the seed, with options.instrumentQualification =
-- 'calibration': the Acme owner (…a1) saves a method with limits, registers a
-- sample and records results with a calibrated instrument. An out of
-- specification result opens a nonconformity case and blocks the release. The
-- Globex owner (…a3) sees none of it. Run with `supabase test db`.
begin;
select plan(16);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('lims_methods', 'lims_samples', 'lims_results')
     and rowsecurity),
  3::bigint,
  'the lims tables have RLS enabled'
);
select table_privs_are('better_supabase', 'lims_samples', 'anon', '{}'::text[],
  'anon has no privileges on samples');
select table_privs_are('better_supabase', 'lims_results', 'anon', '{}'::text[],
  'anon has no privileges on results');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.asset', better_supabase.create_asset(
  '00000000-0000-4000-8000-000000000001', 'laptop', 'Balance', tag => 'LAB-1') ->> 'id', true);
select set_config('test.cold', better_supabase.create_asset(
  '00000000-0000-4000-8000-000000000001', 'laptop', 'Uncalibrated balance', tag => 'LAB-2') ->> 'id', true);
select better_supabase.save_qualification_type(
  '00000000-0000-4000-8000-000000000001', 'calibration', 'Calibration', array['asset'], valid_for_months => 12);
select better_supabase.grant_qualification(
  '00000000-0000-4000-8000-000000000001', 'calibration', 'asset', current_setting('test.asset'),
  granted_on => current_date - 30);

select set_config(
  'test.method',
  better_supabase.save_lims_method(
    '00000000-0000-4000-8000-000000000001',
    '{"key": "ph", "name": "pH", "lowerLimit": 6.5, "upperLimit": 7.5}'::jsonb) ->> 'id',
  true
);
select throws_ok(
  $$select better_supabase.save_lims_method('00000000-0000-4000-8000-000000000001', '{"key": "bad", "name": "Bad", "lowerLimit": 9, "upperLimit": 1}'::jsonb)$$,
  '22023',
  null,
  'the lower limit is at most the upper limit'
);

select set_config(
  'test.sample',
  better_supabase.register_sample(
    '00000000-0000-4000-8000-000000000001', '{"title": "Batch 12", "lot": "L-12"}'::jsonb) ->> 'id',
  true
);
select is(
  (better_supabase.get_sample(current_setting('test.sample')::uuid) ->> 'status'),
  'registered',
  'a sample starts registered'
);
select is(
  (better_supabase.get_sample(current_setting('test.sample')::uuid) ->> 'number'),
  'SMP-1',
  'a sample gets a number'
);

select throws_ok(
  format($$select better_supabase.record_lims_result(%L, %L, '{"value": 7}'::jsonb)$$,
    current_setting('test.sample'), current_setting('test.method')),
  '22023',
  null,
  'a result needs the instrument that produced it'
);
select throws_ok(
  format($$select better_supabase.record_lims_result(%L, %L, jsonb_build_object('value', 7, 'instrumentId', %L))$$,
    current_setting('test.sample'), current_setting('test.method'), current_setting('test.cold')),
  '22023',
  null,
  'an instrument without a valid qualification is refused'
);
select is(
  (better_supabase.record_lims_result(
    current_setting('test.sample')::uuid, current_setting('test.method')::uuid,
    jsonb_build_object('value', 7.1, 'instrumentId', current_setting('test.asset'), 'testedAt', (now() - interval '1 hour')::text)) ->> 'outcome'),
  'in_spec',
  'a result inside the limits is in specification'
);
select is(
  (better_supabase.get_sample(current_setting('test.sample')::uuid) ->> 'status'),
  'in_testing',
  'the first result moves the sample into testing'
);

select is(
  (better_supabase.record_lims_result(
    current_setting('test.sample')::uuid, current_setting('test.method')::uuid,
    jsonb_build_object('value', 8.2, 'instrumentId', current_setting('test.asset'))) ->> 'outcome'),
  'out_of_spec',
  'a result outside the limits is out of specification'
);
select isnt(
  (select (r ->> 'caseId') from jsonb_array_elements(better_supabase.get_sample(current_setting('test.sample')::uuid) -> 'results') r
   where r ->> 'outcome' = 'out_of_spec' limit 1),
  null,
  'an out of specification result opens a nonconformity case'
);

select better_supabase.complete_sample(current_setting('test.sample')::uuid);
select throws_ok(
  format($$select better_supabase.release_sample(%L)$$, current_setting('test.sample')),
  '22023',
  null,
  'a sample with an out of specification result is not released'
);

select set_config(
  'test.clean',
  better_supabase.register_sample(
    '00000000-0000-4000-8000-000000000001', '{"title": "Batch 13"}'::jsonb) ->> 'id',
  true
);
select is(
  (better_supabase.record_lims_result(
    current_setting('test.clean')::uuid, current_setting('test.method')::uuid,
    jsonb_build_object('value', 7.0, 'instrumentId', current_setting('test.asset'))) ->> 'outcome'),
  'in_spec',
  'another sample tests inside the limits'
);
select better_supabase.complete_sample(current_setting('test.clean')::uuid);
select is(
  (better_supabase.release_sample(current_setting('test.clean')::uuid) ->> 'status'),
  'released',
  'a sample inside the limits is released'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select is(
  jsonb_array_length(better_supabase.list_samples('00000000-0000-4000-8000-000000000002')),
  0,
  'another organization sees no samples'
);

select * from finish();
rollback;
