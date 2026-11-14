-- better_supabase.update_member_roles: the role change for many members in
-- one call, with the checks of update_member_role per member (ADR 0853). The
-- owner is …00a1, the member …00a2, both in Acme (…0001); supabase/seed.sql.
begin;
select plan(8);

-- Acme member: every member is refused, none is changed, the call returns.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (select jsonb_array_length(better_supabase.update_member_roles('00000000-0000-4000-8000-000000000001', array['00000000-0000-4000-8000-0000000000a2']::uuid[], 'admin') -> 'succeeded')),
  0,
  'a member changes no roles'
);
select is(
  (select better_supabase.update_member_roles('00000000-0000-4000-8000-000000000001', array['00000000-0000-4000-8000-0000000000a2']::uuid[], 'admin') -> 'failed' -> 0 ->> 'code'),
  'ORGANIZATION_FORBIDDEN',
  'the refusal names its code per member'
);

-- Acme owner.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temp table result as
select better_supabase.update_member_roles(
  '00000000-0000-4000-8000-000000000001',
  array[
    '00000000-0000-4000-8000-0000000000a2',
    '00000000-0000-4000-8000-0000000000a1',
    '00000000-0000-4000-8000-0000000000a2',
    '00000000-0000-4000-8000-0000000000ff'
  ]::uuid[],
  'admin'
) as r;
grant select on result to authenticated;

select is(
  (select r -> 'succeeded' from result),
  '["00000000-0000-4000-8000-0000000000a2"]'::jsonb,
  'the owner changes the member once, though the id is listed twice'
);
select is(
  (select jsonb_array_length(r -> 'failed') from result),
  2,
  'the owner and the stranger fail, nothing else'
);
select is(
  (select r -> 'failed' @> '[{"id": "00000000-0000-4000-8000-0000000000a1", "code": "ORGANIZATION_SELF_ROLE"}]'::jsonb from result),
  true,
  'a change to your own role is refused with its code'
);
select is(
  (select r -> 'failed' @> '[{"id": "00000000-0000-4000-8000-0000000000ff", "code": "ORGANIZATION_NOT_MEMBER"}]'::jsonb from result),
  true,
  'a user outside the organization is reported, not raised'
);
reset role;
select is(
  (select r.key from public.memberships m join better_supabase.roles r on r.id = m.role where m.user_id = '00000000-0000-4000-8000-0000000000a2' and m.organization_id = '00000000-0000-4000-8000-000000000001'),
  'admin',
  'the member now holds the role'
);
set local role authenticated;
select throws_ok(
  format($$select better_supabase.update_member_roles('00000000-0000-4000-8000-000000000001', (select array_agg(gen_random_uuid()) from generate_series(1, 501)), 'admin')$$),
  '22023',
  'A bulk call takes at most 500 members',
  'more than 500 members is refused before any change'
);

select * from finish();
rollback;
