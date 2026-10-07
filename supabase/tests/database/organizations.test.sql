-- The organizations and invitations modules on the fixture's memberships and
-- access contract (supabase/schemas/041_memberships.sql and
-- 045_access_contract.sql). The admin owns Acme (…0001) and is a member of
-- Globex (…0002); the member belongs to Acme only (supabase/seed.sql).
begin;
select plan(19);

-- The invitations module rechecks the inviter with the access scope
-- (`organization` by default), so the contract answers for both names.
select ok(
  better_supabase.can_user('00000000-0000-4000-8000-0000000000a1', 'organization', '00000000-0000-4000-8000-000000000001', 'members.invite'),
  'the owner may invite in the organization scope'
);
select ok(
  not better_supabase.can_user('00000000-0000-4000-8000-0000000000a2', 'organization', '00000000-0000-4000-8000-000000000001', 'members.invite'),
  'a member may not invite'
);

-- Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (select count(*)::int from better_supabase.member_organization_ids()),
  1,
  'a member of one organization sees one membership'
);
select throws_ok(
  $$select better_supabase.switch_organization('00000000-0000-4000-8000-000000000002')$$,
  'P0002',
  'Not a member',
  'a user cannot switch to an organization they do not belong to'
);
select throws_ok(
  $$select better_supabase.invite_member('00000000-0000-4000-8000-000000000001', 'someone@acme.test', 'member')$$,
  '42501',
  'Not allowed to invite members',
  'a member cannot invite'
);
select throws_ok(
  $$select better_supabase.update_member_role('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'admin')$$,
  '42501',
  null,
  'a member cannot promote themselves'
);
select is(
  (select better_supabase.invitation_preview('seed-invitation-acme') ->> 'tenant'),
  '00000000-0000-4000-8000-000000000001',
  'the seeded invitation token previews Acme'
);
select is(
  (select count(*)::int from public.organization_members('00000000-0000-4000-8000-000000000001')),
  2,
  'a member lists the members of their organization'
);
select throws_ok(
  $$select * from public.organization_members('00000000-0000-4000-8000-000000000002')$$,
  '42501',
  null,
  'nobody lists the members of an organization they are not in'
);
select throws_ok(
  $$select * from public.organization_invitations('00000000-0000-4000-8000-000000000001')$$,
  '42501',
  null,
  'a member cannot list invitations'
);

reset role;

-- Acme owner, also a Globex member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (select count(*)::int from better_supabase.member_organization_ids()),
  2,
  'a user in two organizations sees both memberships'
);
select lives_ok(
  $$select better_supabase.invite_member('00000000-0000-4000-8000-000000000001', 'teammate@acme.test', 'admin')$$,
  'an owner invites an admin'
);
select is(
  (select count(*)::int from public.organization_invitations('00000000-0000-4000-8000-000000000001')),
  2,
  'an owner lists the open invitations'
);
select is(
  (select array_agg(role order by name) from public.my_organizations()),
  array['owner', 'member'],
  'my_organizations lists each membership with its role'
);
select throws_ok(
  $$select better_supabase.invite_member('00000000-0000-4000-8000-000000000002', 'someone@globex.test', 'member')$$,
  '42501',
  'Not allowed to invite members',
  'a plain member of Globex cannot invite into it'
);
select throws_ok(
  $$select better_supabase.invite_member('00000000-0000-4000-8000-000000000001', 'someone@acme.test', 'viewer')$$,
  '23514',
  null,
  'an invitation only takes the fixture''s roles'
);
select lives_ok(
  $$select better_supabase.switch_organization('00000000-0000-4000-8000-000000000002')$$,
  'a user switches to another organization they belong to'
);

reset role;

select is(
  (select raw_app_meta_data ->> 'tenant_id' from auth.users where id = '00000000-0000-4000-8000-0000000000a1'),
  '00000000-0000-4000-8000-000000000002',
  'switching writes the active organization to app_metadata'
);

delete from public.memberships
where organization_id = '00000000-0000-4000-8000-000000000002'
  and user_id = '00000000-0000-4000-8000-0000000000a1';
select is(
  (select raw_app_meta_data ->> 'tenant_id' from auth.users where id = '00000000-0000-4000-8000-0000000000a1'),
  null,
  'leaving the active organization clears the tenant claim'
);

select * from finish();
rollback;
