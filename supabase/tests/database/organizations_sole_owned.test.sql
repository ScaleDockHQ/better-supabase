-- sole_owned_organizations lists the organizations whose last owner a member
-- is, by the rule ensure_organization_owner checks at commit. The admin (…a1)
-- owns Acme (…0001) alone and is a member of Globex (…0002); the member
-- (…a2) owns nothing (supabase/seed.sql).
begin;
select plan(6);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  better_supabase.sole_owned_organizations(),
  array['00000000-0000-4000-8000-000000000001']::uuid[],
  'the only owner of Acme sees Acme, not the organization they are a member of'
);
select is(
  better_supabase.sole_owned_organizations('00000000-0000-4000-8000-0000000000a1'),
  array['00000000-0000-4000-8000-000000000001']::uuid[],
  'a member passes their own id'
);
select throws_ok(
  $$select better_supabase.sole_owned_organizations('00000000-0000-4000-8000-0000000000a3')$$,
  '42501',
  null,
  'a member can''t read another user''s organizations'
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select is(
  better_supabase.sole_owned_organizations('00000000-0000-4000-8000-0000000000a2'),
  '{}'::uuid[],
  'a member who owns nothing has no organizations'
);

reset role;
update public.memberships set role = (select r.id from better_supabase.roles r where r.key = 'owner')
where organization_id = '00000000-0000-4000-8000-000000000001' and user_id = '00000000-0000-4000-8000-0000000000a2';
set local role service_role;

select is(
  better_supabase.sole_owned_organizations('00000000-0000-4000-8000-0000000000a1'),
  '{}'::uuid[],
  'a second owner takes Acme off the list'
);
select is(
  better_supabase.sole_owned_organizations('00000000-0000-4000-8000-0000000000a3'),
  array['00000000-0000-4000-8000-000000000002']::uuid[],
  'the service role reads any member'
);

select * from finish();
rollback;
