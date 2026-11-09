-- The shared fixture keeps one catalog role per membership (roles.many off).
-- A member who holds several roles is covered by
-- packages/better-supabase/tests/sql/modules/membership-roles-db.test.ts,
-- which renders the memberships module with the option on. Turning it on
-- here would rewrite that module. Run with `supabase test db`.
begin;
select plan(3);

select hasnt_table(
  'better_supabase',
  'membership_roles',
  'the fixture does not install the role set'
);

select is(
  (
    select count(*)::int
    from public.memberships m
    where m.organization_id = '00000000-0000-4000-8000-000000000001'
      and m.user_id = '00000000-0000-4000-8000-0000000000a2'
  ),
  1,
  'a membership holds one role'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  better_supabase.has_organization_role(
    '00000000-0000-4000-8000-000000000001',
    array['member']
  ),
  true,
  'has_organization_role answers the membership''s one role'
);

select * from finish();
rollback;
