-- The api-keys, settings and comments modules over the fixture's access
-- contract (supabase/schemas/045_access_contract.sql): the admin
-- (…00a1) and the member (…00a2) of Acme (…0001), never Globex (…0002).
begin;
select plan(25);

insert into better_supabase.comments (id, organization_id, subject_type, subject_id, author_id, body) values
  ('00000000-0000-4000-8000-0000000cc001', '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', '00000000-0000-4000-8000-0000000000a1', 'Admin note'),
  ('00000000-0000-4000-8000-0000000cc002', '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', '00000000-0000-4000-8000-0000000000a2', 'Member note'),
  ('00000000-0000-4000-8000-0000000cc003', '00000000-0000-4000-8000-000000000002', 'customer', '00000000-0000-4000-8000-00000000a003', null, 'Globex note');
insert into better_supabase.activity_entries (organization_id, event_id, type) values
  ('00000000-0000-4000-8000-000000000002', 'globex-event', 'customer.created');
insert into better_supabase.organization_settings (organization_id, key, value) values
  ('00000000-0000-4000-8000-000000000002', 'theme', '"light"');

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
  $$select better_supabase.create_comment('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'Call back on Monday')$$,
  'the member comments on an Acme customer'
);
select throws_ok(
  $$select better_supabase.create_comment('00000000-0000-4000-8000-000000000002', 'customer', '00000000-0000-4000-8000-00000000a003', 'Intruder')$$,
  '42501',
  null,
  'the member cannot comment in Globex'
);
select is(
  (select count(*)::int from better_supabase.comments where organization_id = '00000000-0000-4000-8000-000000000002'),
  0,
  'the member reads no Globex comments'
);
select is(
  (select count(*)::int from better_supabase.activity_entries where organization_id = '00000000-0000-4000-8000-000000000002'),
  0,
  'the member reads no Globex activity'
);
select is(
  (select count(*)::int from better_supabase.organization_settings where organization_id = '00000000-0000-4000-8000-000000000002'),
  0,
  'the member reads no Globex settings'
);
select is(
  better_supabase.edit_comment('00000000-0000-4000-8000-0000000cc001', 'Rewritten'),
  null,
  'the member cannot edit the admin''s comment'
);
select ok(
  not better_supabase.delete_comment('00000000-0000-4000-8000-0000000cc001'),
  'the member cannot delete the admin''s comment'
);
select throws_ok(
  $$select better_supabase.list_audit_events()$$,
  '42501',
  null,
  'the member cannot list audit events'
);
select throws_ok(
  $$select better_supabase.purge_rate_limits()$$,
  '42501',
  null,
  'the member cannot purge rate limits'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select better_supabase.edit_comment('00000000-0000-4000-8000-0000000cc002', 'Rewritten')$$,
  '42501',
  null,
  'the admin cannot rewrite a member''s comment'
);
select ok(
  better_supabase.delete_comment('00000000-0000-4000-8000-0000000cc002'),
  'the admin moderates a member''s comment by deleting it'
);

reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

select throws_ok(
  $$select count(*) from better_supabase.comments$$,
  '42501',
  null,
  'anon cannot read comments'
);
select throws_ok(
  $$select count(*) from better_supabase.activity_entries$$,
  '42501',
  null,
  'anon cannot read activity'
);
select throws_ok(
  $$select count(*) from better_supabase.organization_settings$$,
  '42501',
  null,
  'anon cannot read organization settings'
);
select throws_ok(
  $$select better_supabase.list_comments('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001')$$,
  '42501',
  null,
  'anon cannot list comments'
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select is(
  better_supabase.verify_api_key('00000000000000b2', repeat('c', 64)) ->> 'status',
  'ok',
  'a personal key verifies while its owner is a member'
);
select lives_ok(
  $$select better_supabase.purge_rate_limits()$$,
  'the service role purges rate limits'
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
