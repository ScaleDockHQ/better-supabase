-- Rotating a key hands the caller a working secret that acts as the key's
-- user, so a key manager may revoke a colleague's personal key but only its
-- own user rotates it. The admin (…a1) owns Acme and Wile (…a2) is a member.
begin;
select plan(4);

insert into better_supabase.api_keys (id, tenant_id, user_id, name, prefix, public_id, secret_hash, scopes)
values
  ('00000000-0000-4000-8000-0000000a4e01', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'member key', 'bsk', '00000000000000a1', repeat('1', 64), '{}'),
  ('00000000-0000-4000-8000-0000000a4e02', '00000000-0000-4000-8000-000000000001', null, 'tenant key', 'bsk', '00000000000000a2', repeat('2', 64), '{}');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);

select throws_ok(
  $$select better_supabase.rotate_api_key('00000000-0000-4000-8000-0000000a4e01', '00000000000000a3', repeat('3', 64))$$,
  '42501', null, 'a key manager cannot rotate another member''s personal key'
);
select lives_ok(
  $$select better_supabase.rotate_api_key('00000000-0000-4000-8000-0000000a4e02', '00000000000000a4', repeat('4', 64))$$,
  'a key manager rotates a tenant key without a user'
);
select ok(
  better_supabase.revoke_api_key('00000000-0000-4000-8000-0000000a4e01'),
  'a key manager still revokes another member''s key'
);

reset role;
select is(
  (select count(*)::int from better_supabase.api_keys where public_id = '00000000000000a3'),
  0, 'no successor key was created for the manager'
);

select * from finish();
rollback;
