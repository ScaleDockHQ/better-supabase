-- Module actions write one audit entry each, under the shared categories,
-- as the admin (…00a1) of Acme (…0001).
begin;
select plan(6);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select lives_ok(
  $$select better_supabase.set_organization_setting('00000000-0000-4000-8000-000000000001', 'theme', '{"value":"dark"}')$$,
  'the admin sets an organization setting'
);
select lives_ok(
  $$select better_supabase.create_api_key('ci', '00000000000000b1', repeat('b', 64), '00000000-0000-4000-8000-000000000001')$$,
  'the admin creates an API key'
);

reset role;

select is(
  (select count(*)::int from better_supabase.audit_events
    where event_type = 'organization_setting.updated'
      and organization_id = '00000000-0000-4000-8000-000000000001'),
  1,
  'the setting change writes one audit entry'
);
select is(
  (select category from better_supabase.audit_events
    where event_type = 'organization_setting.updated'
      and organization_id = '00000000-0000-4000-8000-000000000001'),
  'configuration',
  'a setting change is a configuration event'
);
select is(
  (select count(*)::int from better_supabase.audit_events
    where event_type = 'api_key.created'
      and organization_id = '00000000-0000-4000-8000-000000000001'),
  1,
  'the new API key writes one audit entry'
);
select is(
  (select category from better_supabase.audit_events
    where event_type = 'api_key.created'
      and organization_id = '00000000-0000-4000-8000-000000000001'),
  'security',
  'an API key is a security event'
);

select * from finish();
rollback;
