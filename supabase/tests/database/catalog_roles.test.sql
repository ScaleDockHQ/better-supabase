-- list_roles and set_permission_override on the fixture's catalog. In Acme
-- (…0001) a1 is the owner and a2 a member; in Globex (…0002) a1 is a member
-- (supabase/seed.sql).
begin;
select plan(10);

-- Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select ok(
  (select array_agg(r ->> 'key' order by r ->> 'key') from jsonb_array_elements(api.list_roles('00000000-0000-4000-8000-000000000001')) r)
    @> array['admin', 'member', 'owner'],
  'a member with members.read lists the tenant roles'
);
select is(
  (select (r ->> 'members')::int from jsonb_array_elements(api.list_roles('00000000-0000-4000-8000-000000000001')) r where r ->> 'key' = 'owner'),
  1,
  'each role counts the members holding it in the tenant'
);
select throws_ok(
  $$select api.set_permission_override('00000000-0000-4000-8000-000000000001', 'member', 'customers.write', true)$$,
  '42501',
  'Not allowed to change role permissions',
  'a member without roles.manage cannot change a role'
);

-- Acme owner.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select ok(
  api.set_permission_override('00000000-0000-4000-8000-000000000001', 'member', 'customers.write', true)
    -> 'permissions' ? 'customers.write',
  'an owner grants a key to a role in the tenant'
);
select throws_ok(
  $$select api.set_permission_override('00000000-0000-4000-8000-000000000001', 'owner', 'roles.manage', false)$$,
  '42501',
  'You cannot take this key from your own role',
  'nobody denies roles.manage to the role they hold'
);
select throws_ok(
  $$select api.set_permission_override('00000000-0000-4000-8000-000000000001', 'member', 'nope.nope', true)$$,
  'P0002',
  'Unknown permission',
  'an unknown key is refused'
);
select throws_ok(
  $$select api.set_permission_override('00000000-0000-4000-8000-000000000002', 'member', 'customers.write', true)$$,
  '42501',
  'Not allowed to change role permissions',
  'the override is per tenant: a1 is only a member of Globex'
);

reset role;
select ok(
  better_supabase.member_can('00000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-000000000001', 'customers.write'),
  'the Acme member holds the granted key'
);
select ok(
  not better_supabase.member_can('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-000000000002', 'customers.write'),
  'members of Globex do not'
);

set local role authenticated;
select ok(
  not (api.set_permission_override('00000000-0000-4000-8000-000000000001', 'member', 'customers.write', null)
    -> 'permissions' ? 'customers.write'),
  'null clears the override, back to the role default'
);

select * from finish();
rollback;
