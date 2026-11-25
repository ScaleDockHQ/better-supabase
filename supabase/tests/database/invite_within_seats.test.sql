-- invite_within_seats (ADR 1235): saas.inviteWithinSeats as one function. It
-- counts the members, reads the `seats` entitlement and invites in one
-- transaction. The admin owns Acme (…0001) with two members; the member holds
-- no invite permission (supabase/seed.sql).
begin;
select plan(7);

select set_config('t.member_email', (select email from auth.users where id = '00000000-0000-4000-8000-0000000000a2'), true);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select better_supabase.invite_within_seats('00000000-0000-4000-8000-000000000001', 'seat1@acme.test', 'member')$$,
  '42501',
  'Not allowed to invite members',
  'a member without the invite permission is refused'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select lives_ok(
  $$select better_supabase.invite_within_seats('00000000-0000-4000-8000-000000000001', 'seat1@acme.test', 'member')$$,
  'an owner invites while the plan has seats left'
);

select is(
  (select count(*)::int from better_supabase.list_organization_invitations('00000000-0000-4000-8000-000000000001') i
   where i.email = 'seat1@acme.test'),
  1,
  'the invitation is open'
);

select throws_ok(
  $$select better_supabase.invite_within_seats('00000000-0000-4000-8000-000000000001', current_setting('t.member_email'), 'member')$$,
  '23505',
  null,
  'an existing member is still refused by invite_member'
);

reset role;
update public.plan_features set value = '2'::jsonb where feature_key = 'seats';
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select better_supabase.invite_within_seats('00000000-0000-4000-8000-000000000001', 'seat2@acme.test', 'member')$$,
  '22023',
  'The plan has no seat left',
  'two members on a two-seat plan leave no seat'
);

select is(
  (select count(*)::int from better_supabase.list_organization_invitations('00000000-0000-4000-8000-000000000001') i
   where i.email = 'seat2@acme.test'),
  0,
  'a refused invite writes nothing'
);

reset role;
update public.plan_features set value = null where feature_key = 'seats';
set local role authenticated;

select lives_ok(
  $$select better_supabase.invite_within_seats('00000000-0000-4000-8000-000000000001', 'seat3@acme.test', 'member')$$,
  'a plan without a numeric seats value has no cap'
);

select * from finish();
rollback;
