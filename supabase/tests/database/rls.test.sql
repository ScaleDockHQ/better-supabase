-- RLS for the fixture schema, against the rows in supabase/seed.sql: Acme
-- (…0001) has two customers, Globex (…0002) has one. Run with `supabase test db`.
begin;
select plan(14);

select is(
  (select count(*) from pg_catalog.pg_tables where schemaname in ('public', 'rbac') and not rowsecurity),
  0::bigint,
  'every table in public and rbac has RLS enabled'
);

set local role anon;

select throws_ok('select * from public.customers', '42501', null, 'anon cannot read customers');
select throws_ok('select * from public.organizations', '42501', null, 'anon cannot read organizations');

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select results_eq(
  'select id from public.organizations',
  $$values ('00000000-0000-4000-8000-000000000001'::uuid)$$,
  'a member sees only their own organization'
);
select is((select count(*) from public.customers), 2::bigint, 'a member sees only their tenant''s customers');
select is_empty(
  $$select id from public.customers where organization_id = '00000000-0000-4000-8000-000000000002'$$,
  'a member sees no customers of another tenant'
);
select throws_ok(
  $$insert into public.customers (organization_id, name) values ('00000000-0000-4000-8000-000000000002', 'Intruder')$$,
  '42501',
  null,
  'a member cannot insert into another tenant'
);
select is_empty(
  $$update public.customers set name = 'Renamed' where id = '00000000-0000-4000-8000-00000000a003' returning id$$,
  'a member cannot update another tenant''s customer'
);
select throws_ok('select * from rbac.user_roles', '42501', null, 'authenticated cannot read user roles');

-- The member carries no user_role claim, so authorize() finds no permission.
select ok(not rbac.authorize('customers.read'), 'authorize() denies a token without a user_role claim');

-- The seed sends both Acme users a welcome notification; this adds one more.
select isnt(
  better_supabase.notify('{"type":"test.sent","tenant":"00000000-0000-4000-8000-000000000001","recipients":["00000000-0000-4000-8000-0000000000a2"],"include_actor":true,"data":{"title":"For the member"}}'),
  null,
  'a member sends themselves a notification'
);
select is(
  (select count(*) from better_supabase.notification_recipients),
  2::bigint,
  'a member sees their own notifications'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","user_role":"admin","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is_empty(
  $$select id from better_supabase.notification_recipients where user_id = '00000000-0000-4000-8000-0000000000a2'$$,
  'another user in the same tenant does not see them'
);
select ok(rbac.authorize('users.manage'), 'authorize() grants an admin permission from the user_role claim');

select * from finish();
rollback;
