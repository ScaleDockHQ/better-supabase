-- The api-keys, settings and comments modules over the fixture's access
-- contract (supabase/schemas/045_access_contract.sql): the admin
-- (…00a1) and the member (…00a2) of Acme (…0001), never Globex (…0002).
begin;
select plan(11);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select ok(
  better_supabase.can('tenant', '00000000-0000-4000-8000-000000000001', 'settings.update'),
  'the admin updates Acme''s settings'
);
select is(
  better_supabase.set_organization_setting('00000000-0000-4000-8000-000000000001', 'theme', '{"value":"dark"}'),
  '"dark"'::jsonb,
  'the admin sets an organization setting'
);
select lives_ok(
  $$select better_supabase.create_api_key('ci', '00000000000000a1', repeat('a', 64), '00000000-0000-4000-8000-000000000001')$$,
  'the admin creates a tenant API key'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select ok(
  not better_supabase.can('tenant', '00000000-0000-4000-8000-000000000001', 'settings.update'),
  'the member cannot update Acme''s settings'
);
select is(
  better_supabase.get_organization_settings('00000000-0000-4000-8000-000000000001') -> 'theme',
  '"dark"'::jsonb,
  'the member reads Acme''s settings'
);
select throws_ok(
  $$select better_supabase.create_api_key('ci', '00000000000000b1', repeat('b', 64), '00000000-0000-4000-8000-000000000001')$$,
  '42501',
  null,
  'the member cannot create a tenant API key'
);
select lives_ok(
  $$select better_supabase.create_api_key('mine', '00000000000000b2', repeat('c', 64), '00000000-0000-4000-8000-000000000001', personal => true)$$,
  'the member creates a personal API key in Acme'
);
select lives_ok(
  $$select better_supabase.create_comment('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000c001', 'Call back on Monday')$$,
  'the member comments on an Acme customer'
);
select throws_ok(
  $$select better_supabase.create_comment('00000000-0000-4000-8000-000000000002', 'customer', '00000000-0000-4000-8000-00000000c003', 'Intruder')$$,
  '42501',
  null,
  'the member cannot comment in Globex'
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select is(
  better_supabase.verify_api_key('00000000000000b2', repeat('c', 64)) ->> 'status',
  'ok',
  'a personal key verifies while its owner is a member'
);
reset role;
update auth.users
set raw_app_meta_data = raw_app_meta_data || '{"tenant_id":"00000000-0000-4000-8000-000000000002"}'
where id = '00000000-0000-4000-8000-0000000000a2';
set local role service_role;
select is(
  better_supabase.verify_api_key('00000000000000b2', repeat('c', 64)) ->> 'status',
  'invalid',
  'a personal key stops working once its owner leaves the tenant'
);

select * from finish();
rollback;
