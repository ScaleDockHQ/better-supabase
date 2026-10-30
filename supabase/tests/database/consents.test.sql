-- The consents module against the seed: the Acme owner (…a1) manages purposes
-- and records consent for Acme's customer Road Runner (…a001), the Acme member
-- (…a2) has no consent permission, and Globex's owner (…a3) sees nothing of
-- Acme's. Run with `supabase test db`.
begin;
select plan(17);

select is(
  (select rowsecurity from pg_catalog.pg_tables
   where schemaname = 'better_supabase' and tablename = 'consents'),
  true,
  'consents has RLS enabled'
);
select table_privs_are('better_supabase', 'consents', 'anon', '{}'::text[],
  'anon has no privileges on consents');
select table_privs_are('better_supabase', 'consents', 'authenticated', array['SELECT'],
  'authenticated only reads consents directly');
select is(
  (select count(*)::integer
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('api', 'better_supabase')
     and has_function_privilege('anon', p.oid, 'execute')
     and p.proname ~ 'consent'),
  0,
  'anon can execute no consent function'
);
select ok(
  not has_function_privilege('authenticated', 'better_supabase.expire_consents()', 'execute'),
  'only the service role expires consents'
);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

-- Acme owner.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

insert into ids
select 'purpose', (better_supabase.save_consent_purpose('00000000-0000-4000-8000-000000000001',
  'marketing.email', 'Marketing email', valid_months => 12) ->> 'id')::uuid;

select throws_ok(
  $$select better_supabase.save_consent_purpose('00000000-0000-4000-8000-000000000001', 'Not A Key', 'Bad')$$,
  '22023',
  null,
  'a purpose key is lowercase'
);
select throws_ok(
  $$select better_supabase.save_consent_purpose(null, 'terms', 'Terms')$$,
  '42501',
  null,
  'only the service role saves a system purpose'
);

insert into ids
select 'first', (better_supabase.record_consent('customer', '00000000-0000-4000-8000-00000000a001',
  'marketing.email', 'granted') ->> 'id')::uuid;

select ok(
  better_supabase.consent_active('customer', '00000000-0000-4000-8000-00000000a001', 'marketing.email'),
  'a grant is active'
);
select ok(
  (select valid_until between now() + interval '11 months' and now() + interval '13 months'
   from better_supabase.consents where id = (select id from ids where name = 'first')),
  'a grant lasts the purpose''s valid_months'
);

insert into ids
select 'second', (better_supabase.record_consent('customer', '00000000-0000-4000-8000-00000000a001',
  'marketing.email', 'refused') ->> 'id')::uuid;

select is(
  (select status from better_supabase.consents where id = (select id from ids where name = 'first')),
  'withdrawn',
  'a new decision ends the grant it replaces'
);
select ok(
  not better_supabase.consent_active('customer', '00000000-0000-4000-8000-00000000a001', 'marketing.email'),
  'a refusal is not active'
);
select is(
  jsonb_array_length(better_supabase.list_consents('customer', '00000000-0000-4000-8000-00000000a001', true)),
  2,
  'the history keeps both decisions'
);
select throws_ok(
  $$select better_supabase.withdraw_consent((select id from ids where name = 'second'))$$,
  '22023',
  null,
  'only a grant can be withdrawn'
);
select throws_ok(
  $$select better_supabase.record_consent('customer', '00000000-0000-4000-8000-00000000a001', 'unknown', 'granted')$$,
  'P0002',
  null,
  'an unknown purpose is not found'
);

-- Acme member: no consent permission.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select throws_ok(
  $$select better_supabase.record_consent('customer', '00000000-0000-4000-8000-00000000a001', 'marketing.email', 'granted')$$,
  '42501',
  null,
  'a member without consents.record can''t record'
);

-- Globex owner.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select is(
  (select count(*)::integer from better_supabase.consents),
  0,
  'another organization reads none of the consents'
);
select ok(
  not better_supabase.consent_active('customer', '00000000-0000-4000-8000-00000000a001', 'marketing.email'),
  'another organization can''t probe a consent'
);

select * from finish();
rollback;
