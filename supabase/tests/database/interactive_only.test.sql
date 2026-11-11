-- Interactive-only permissions: only the user's own session transfers
-- ownership, deletes an organization or grants and takes away the owner role.
-- An API key, an OAuth client and an agent are refused whatever their scopes
-- say, and no API key may carry such a key as a scope. The admin owns Acme
-- (…0001) and the member belongs to Acme (supabase/seed.sql).
begin;
select plan(23);

create function pg_temp.as_claims(claims jsonb) returns void
language sql as $$
  select set_config('request.jwt.claims', claims::text, true)
$$;

set local role authenticated;

-- A personal API key of the owner whose scopes name the permission.
select pg_temp.as_claims('{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","api_key":{"id":"k1","scopes":["organization.transfer_ownership","organization.delete","members.read","members.update_role"]}}');
select throws_ok(
  $$select better_supabase.transfer_ownership('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2')$$,
  '42501',
  'Not allowed to transfer ownership',
  'a personal API key cannot transfer ownership, even with the scope'
);
select ok(
  not better_supabase.cap_allows('organization.delete'),
  'an API key never holds organization.delete'
);
select ok(
  better_supabase.can('organization', '00000000-0000-4000-8000-000000000001', 'members.read'),
  'an API key keeps the permissions that are not interactive-only'
);
select is(
  better_supabase.my_permissions('00000000-0000-4000-8000-000000000001', array['organization.transfer_ownership', 'members.read']),
  array['members.read'],
  'my_permissions leaves interactive-only keys out for an API key'
);
select throws_ok(
  $$select better_supabase.update_member_role('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'owner')$$,
  '42501',
  'That role is above your own',
  'an API key cannot make a member an owner'
);

-- An organization API key that acts as a user inside the tenant.
select pg_temp.as_claims('{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","api_key":{"id":"k2","organization_id":"00000000-0000-4000-8000-000000000001","scopes":["*"]}}');
select throws_ok(
  $$select better_supabase.transfer_ownership('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2')$$,
  '42501',
  'Not allowed to transfer ownership',
  'a tenant API key with * cannot transfer ownership'
);

-- An OAuth client token whose scope maps to the key.
select pg_temp.as_claims('{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","client_id":"app_1","scope":"organization.transfer_ownership members.read"}');
select throws_ok(
  $$select better_supabase.transfer_ownership('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2')$$,
  '42501',
  'Not allowed to transfer ownership',
  'an OAuth client cannot transfer ownership, even with the scope'
);
select ok(
  better_supabase.cap_allows('members.read'),
  'an OAuth client keeps a scope that is not interactive-only'
);

-- An agent acting for the owner.
select pg_temp.as_claims('{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","scope":"organization.transfer_ownership","act":{"sub":"agent-1","kind":"agent"}}');
select throws_ok(
  $$select better_supabase.transfer_ownership('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2')$$,
  '42501',
  'Not allowed to transfer ownership',
  'an agent cannot transfer ownership, even with the scope'
);
select ok(
  not better_supabase.cap_allows('organization.delete'),
  'an agent never holds organization.delete'
);

-- An OAuth client allowed to create personal keys mints one no broader
-- than its own scopes.
select pg_temp.as_claims('{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","client_id":"app_1","scope":"api_keys.own members.read"}');
select throws_ok(
  $$select better_supabase.create_api_key('k', '0123456789abcde1', repeat('b', 64), '00000000-0000-4000-8000-000000000001', true, array['customers.write'])$$,
  '42501',
  'A token may only give a key the scopes it holds itself',
  'an OAuth client cannot mint a key broader than its scopes'
);
select lives_ok(
  $$select better_supabase.create_api_key('k', '0123456789abcde2', repeat('b', 64), '00000000-0000-4000-8000-000000000001', true, array['members.read'])$$,
  'an OAuth client mints a key within its scopes'
);

-- An agent with the same scopes.
select pg_temp.as_claims('{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","scope":"api_keys.own","act":{"sub":"agent-1","kind":"agent"}}');
select throws_ok(
  $$select better_supabase.create_api_key('k', '0123456789abcde3', repeat('b', 64), '00000000-0000-4000-8000-000000000001', true, array['*'])$$,
  '42501',
  'A token may only give a key the scopes it holds itself',
  'an agent cannot mint a key with *'
);

-- An API key mints and rotates only within its own scopes.
select pg_temp.as_claims('{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","api_key":{"id":"k3","scopes":["members.read","api_keys.own"]}}');
select throws_ok(
  $$select better_supabase.create_api_key('k', '0123456789abcde4', repeat('b', 64), '00000000-0000-4000-8000-000000000001', true, array['members.read', 'customers.write'])$$,
  '42501',
  'A token may only give a key the scopes it holds itself',
  'an API key cannot mint a broader key'
);

-- The owner's own session.
select pg_temp.as_claims('{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}');
select ok(
  better_supabase.interactive_session(),
  'a signed-in user is an interactive session'
);
select ok(
  better_supabase.cap_allows('organization.transfer_ownership'),
  'the owner''s own session may use an interactive-only key'
);
select throws_ok(
  $$select better_supabase.create_api_key('k', '0123456789abcdef', repeat('a', 64), '00000000-0000-4000-8000-000000000001', true, array['organization.transfer_ownership'])$$,
  '42501',
  'Only a signed-in user may use this permission, so an API key cannot carry it',
  'no API key may carry an interactive-only scope'
);
select lives_ok(
  $$select better_supabase.create_api_key('k', '0123456789abcdef', repeat('a', 64), '00000000-0000-4000-8000-000000000001', true, array['members.read'])$$,
  'an API key may still carry other scopes'
);
select ok(
  set_config('test.broad_key', better_supabase.create_api_key('broad', '0123456789abcde5', repeat('c', 64), '00000000-0000-4000-8000-000000000001', true, array['customers.write']) ->> 'id', true) is not null,
  'the owner''s own session creates a key with any scope'
);
select pg_temp.as_claims('{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","client_id":"app_1","scope":"api_keys.own"}');
select throws_ok(
  $$select better_supabase.rotate_api_key(current_setting('test.broad_key')::uuid, '0123456789abcde6', repeat('d', 64))$$,
  '42501',
  'A token may only give a key the scopes it holds itself',
  'an OAuth client cannot rotate a key broader than its scopes'
);
select pg_temp.as_claims('{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}');
select lives_ok(
  $$select better_supabase.transfer_ownership('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2')$$,
  'the owner transfers ownership from their own session'
);

reset role;

select ok(
  exists (
    select 1 from public.memberships m
    join better_supabase.roles r on r.id = m.role
    where m.organization_id = '00000000-0000-4000-8000-000000000001'
      and m.user_id = '00000000-0000-4000-8000-0000000000a2'
      and r.key = 'owner'
  ),
  'the member is now an owner'
);
select ok(
  not better_supabase.interactive_only('members.read'),
  'members.read is not interactive-only'
);

select * from finish();
rollback;
