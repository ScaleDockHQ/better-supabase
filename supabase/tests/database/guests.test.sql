-- The guests module on the fixture's access contract: the admin (…00a1) of
-- Acme (…0001) invites a client acting for the customer …a001, the client
-- accepts with their confirmed email, and a grant lets them read and comment
-- on that one customer. The member (…00a2) can't manage guests and Globex
-- (…0002) sees none of them.
begin;
select plan(17);

insert into auth.users (id, email, email_confirmed_at, aud, role, instance_id) values
  ('00000000-0000-4000-8000-0000000000e1', 'client@example.test', now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
  ('00000000-0000-4000-8000-0000000000e2', 'someone@example.test', now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.invite', better_supabase.invite_guest(
  '00000000-0000-4000-8000-000000000001', 'Client@Example.test', 'Client',
  party_type => 'customer', party_id => '00000000-0000-4000-8000-00000000a001'
)::text, true);
select set_config('test.guest', current_setting('test.invite')::jsonb ->> 'id', true);

select is(
  current_setting('test.invite')::jsonb ->> 'email',
  'client@example.test',
  'an invite stores the email in lower case'
);
select isnt(
  current_setting('test.invite')::jsonb ->> 'token',
  null,
  'an invite returns a one-time token'
);
select throws_ok(
  $$select better_supabase.invite_guest('00000000-0000-4000-8000-000000000001', 'other@example.test', party_type => 'customer', party_id => '00000000-0000-4000-8000-00000000a003')$$,
  'P0002',
  'the party does not exist in this organization',
  'a guest cannot act for a party in another organization'
);

-- Someone else signed in with the forwarded link.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e2","role":"authenticated"}', true);
set local role authenticated;

select throws_ok(
  format($$select better_supabase.accept_guest_invite('%s')$$, current_setting('test.invite')::jsonb ->> 'token'),
  '42501',
  'this invite was sent to another email',
  'an invite only accepts for the invited email'
);

-- The invited client.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;

select is(
  better_supabase.accept_guest_invite(current_setting('test.invite')::jsonb ->> 'token') ->> 'status',
  'active',
  'the invited email accepts the invite'
);
select throws_ok(
  format($$select better_supabase.accept_guest_invite('%s')$$, current_setting('test.invite')::jsonb ->> 'token'),
  'P0002',
  'this invite is not valid or has expired',
  'a token accepts once'
);
select is(
  better_supabase.guest_can('customer', '00000000-0000-4000-8000-00000000a001'),
  false,
  'a guest reaches nothing before a grant'
);
select results_eq(
  $$select party_type, party_id from better_supabase.portal_parties()$$,
  $$values ('customer'::text, '00000000-0000-4000-8000-00000000a001'::text)$$,
  'the guest acts for the customer they were invited for'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  better_supabase.grant_guest_access(
    current_setting('test.guest')::uuid, 'customer', '00000000-0000-4000-8000-00000000a001', array['comment']
  ) -> 'actions',
  '["read", "comment"]'::jsonb,
  'a grant always includes read'
);
select throws_ok(
  format($$select better_supabase.grant_guest_access('%s', 'customer', '00000000-0000-4000-8000-00000000a003')$$, current_setting('test.guest')),
  'P0002',
  'the record does not exist in this organization',
  'a grant cannot point at another organization''s record'
);

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;

select is(
  better_supabase.guest_can('customer', '00000000-0000-4000-8000-00000000a001', 'comment'),
  true,
  'the grant lets the guest comment on the customer'
);
select lives_ok(
  $$insert into better_supabase.comments (organization_id, subject_type, subject_id, body)
    values ('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'Thanks for the update')$$,
  'the guest comments through the comments policy'
);
select throws_ok(
  $$insert into better_supabase.comments (organization_id, subject_type, subject_id, body)
    values ('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a002', 'Not mine')$$,
  '42501',
  null,
  'the guest cannot comment on a customer they were not granted'
);
select throws_ok(
  $$select better_supabase.list_guests('00000000-0000-4000-8000-000000000001')$$,
  '42501',
  'not allowed to read guests',
  'a guest cannot list the organization''s guests'
);

-- Acme member without guests.manage.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select better_supabase.invite_guest('00000000-0000-4000-8000-000000000001', 'friend@example.test')$$,
  '42501',
  'not allowed to manage guests',
  'a member without guests.manage cannot invite'
);

-- Globex owner.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*) from better_supabase.guests where tenant_id = '00000000-0000-4000-8000-000000000001'),
  0::bigint,
  'Globex reads no Acme guests'
);

-- Revoking the guest ends their access.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select better_supabase.revoke_guest(current_setting('test.guest')::uuid);

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;

select is(
  better_supabase.guest_can('customer', '00000000-0000-4000-8000-00000000a001'),
  false,
  'a revoked guest reaches nothing'
);

select * from finish();
rollback;
