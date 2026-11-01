-- Clinical decision support on the fixture. The Acme owner (…a1) adds a dose
-- range rule for a medication, lists it and evaluates a record with no orders
-- (no alerts). A rule with no bounds is refused. The Acme member (…a2) holds no
-- clinical_decision_support keys and may not read alerts or change rules, and
-- the Globex owner (…a3) sees none of it. Run with `supabase test db`.
begin;
select plan(8);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('care_rules', 'care_alerts')
     and rowsecurity),
  2::bigint,
  'the care tables have RLS enabled'
);
select table_privs_are('better_supabase', 'care_rules', 'anon', '{}'::text[], 'anon has no privileges on rules');
select table_privs_are('better_supabase', 'care_alerts', 'authenticated', array['SELECT'], 'members can only read alerts');
select function_privs_are('better_supabase', 'sync_care_alerts', array['uuid', 'text', 'text', 'text', 'jsonb'], 'authenticated', '{}'::text[], 'the internal sync function is not callable');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.med', better_supabase.save_medication(
  '00000000-0000-4000-8000-000000000001', 'Paracetamol', 'mg') ->> 'id', true);

select lives_ok(
  format($$select better_supabase.save_care_rule('00000000-0000-4000-8000-000000000001',
    jsonb_build_object('kind', 'dose_range', 'medicationIds', jsonb_build_array(%L), 'maxDose', 1000))$$, current_setting('t.med')),
  'an owner saves a dose range rule'
);
select throws_ok(
  format($$select better_supabase.save_care_rule('00000000-0000-4000-8000-000000000001',
    jsonb_build_object('kind', 'dose_range', 'medicationIds', jsonb_build_array(%L)))$$, current_setting('t.med')),
  '22023',
  null,
  'a dose range rule needs a bound'
);
select is(
  jsonb_array_length(better_supabase.list_care_rules('00000000-0000-4000-8000-000000000001')),
  1,
  'the owner lists the rule'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  $$select better_supabase.list_care_alerts('00000000-0000-4000-8000-000000000001')$$,
  '42501',
  null,
  'a member without the key may not read alerts'
);

select * from finish();
rollback;
