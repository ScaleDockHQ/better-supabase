-- An API key holds only the permissions its scopes map to: no scopes, no
-- permission; * every permission that is not interactive-only. The owner's
-- own session is not narrowed. The admin owns Acme (…0001) (supabase/seed.sql).
begin;
select plan(9);

create function pg_temp.as_claims(claims jsonb) returns void
language sql as $$
  select set_config('request.jwt.claims', claims::text, true)
$$;

set local role authenticated;

select pg_temp.as_claims('{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}');
select ok(
  better_supabase.can('organization', '00000000-0000-4000-8000-000000000001', 'members.update_role'),
  'the owner''s own session holds members.update_role'
);

select pg_temp.as_claims('{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","api_key":{"id":"k1","scopes":[]}}');
select ok(
  not better_supabase.cap_allows('members.read'),
  'a key without scopes holds no permission'
);
select ok(
  not coalesce(better_supabase.can('organization', '00000000-0000-4000-8000-000000000001', 'members.read'), false),
  'a key without scopes cannot read members, although its user can'
);
select is(
  coalesce(cardinality(better_supabase.my_permissions('00000000-0000-4000-8000-000000000001', array['members.read', 'members.update_role'])), 0),
  0,
  'my_permissions lists nothing for a key without scopes'
);

select pg_temp.as_claims('{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","api_key":{"id":"k2"}}');
select ok(
  not better_supabase.cap_allows('members.read'),
  'a key claim without a scopes array holds no permission'
);

select pg_temp.as_claims('{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","api_key":{"id":"k3","scopes":["members.read"]}}');
select ok(
  better_supabase.can('organization', '00000000-0000-4000-8000-000000000001', 'members.read'),
  'a key holds the permission its scope names'
);
select ok(
  not coalesce(better_supabase.can('organization', '00000000-0000-4000-8000-000000000001', 'members.update_role'), false),
  'a key does not hold its user''s other permissions'
);

select pg_temp.as_claims('{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","api_key":{"id":"k4","scopes":["*"]}}');
select ok(
  better_supabase.can('organization', '00000000-0000-4000-8000-000000000001', 'members.update_role'),
  'a key with * holds its user''s permissions'
);
select ok(
  not better_supabase.cap_allows('organization.delete'),
  'a key with * still never holds an interactive-only permission'
);

reset role;

select * from finish();
rollback;
