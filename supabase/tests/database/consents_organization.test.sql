-- Consent on the organization itself: the fixture registers the tenant table as
-- record type `organization` with `tenant: "id"`, so a record's tenant is its
-- own id. The Acme owner (…a1) accepts a system purpose for Acme (…0001), the
-- Acme member (…a2) has no consents.record, and Globex's owner (…a3) can't
-- record or read one for Acme (supabase/seed.sql).
begin;
select plan(8);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select ok(
  better_supabase.save_consent_purpose(null, 'agency.agreement', 'Agency agreement') ->> 'key' = 'agency.agreement',
  'the service role saves a system purpose'
);

-- Acme owner.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  better_supabase.record_consent('organization', '00000000-0000-4000-8000-000000000001',
    'agency.agreement', 'granted') ->> 'status',
  'granted',
  'an owner records a consent on their own organization'
);
select ok(
  better_supabase.consent_active('organization', '00000000-0000-4000-8000-000000000001', 'agency.agreement'),
  'the organization''s consent is active'
);
select is(
  (select tenant_id::text from better_supabase.consents where subject_type = 'organization'),
  '00000000-0000-4000-8000-000000000001',
  'the consent belongs to the organization it is about'
);
select is(
  jsonb_array_length(better_supabase.list_consents('organization', '00000000-0000-4000-8000-000000000001')),
  1,
  'list_consents returns it'
);

-- Acme member: no consents.record.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select throws_ok(
  $$select better_supabase.record_consent('organization', '00000000-0000-4000-8000-000000000001', 'agency.agreement', 'refused')$$,
  '42501',
  null,
  'a member without consents.record can''t record one for the organization'
);

-- Globex owner.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select throws_ok(
  $$select better_supabase.record_consent('organization', '00000000-0000-4000-8000-000000000001', 'agency.agreement', 'granted')$$,
  '42501',
  null,
  'another organization''s owner can''t record one for Acme'
);
select ok(
  not better_supabase.consent_active('organization', '00000000-0000-4000-8000-000000000001', 'agency.agreement'),
  'and can''t read Acme''s'
);

select * from finish();
rollback;
