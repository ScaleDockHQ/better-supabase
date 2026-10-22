-- A record's conversation (comments) and a channel linked to a record stay
-- in the record's tenant. The admin …a1 owns Acme (…0001) and is a member of
-- Globex (…0002), so they read customers in both; Initech (…a003) is Globex's.
begin;
select plan(8);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select better_supabase.create_comment('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a003', 'Wrong organization')$$,
  'P0002',
  'no such record in this organization',
  'a comment in Acme on a Globex customer is refused'
);
select throws_ok(
  $$select better_supabase.open_conversation('00000000-0000-4000-8000-000000000001', 'subject', '{"subjectType":"customer","subjectId":"00000000-0000-4000-8000-00000000a003"}')$$,
  'P0002',
  'no such record in this organization',
  'an Acme conversation on a Globex customer is refused'
);
select throws_ok(
  $$select better_supabase.create_channel('00000000-0000-4000-8000-000000000001', 'initech', '{"subjectType":"customer","subjectId":"00000000-0000-4000-8000-00000000a003"}')$$,
  'P0002',
  'no such record in this organization',
  'an Acme channel linked to a Globex customer is refused'
);
select lives_ok(
  $$select better_supabase.create_comment('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'Same organization')$$,
  'a comment in Acme on an Acme customer works'
);
select lives_ok(
  $$select better_supabase.create_comment('00000000-0000-4000-8000-000000000002', 'customer', '00000000-0000-4000-8000-00000000a003', 'In Globex')$$,
  'a comment in Globex on a Globex customer works'
);

reset role;
select is(
  (select count(*)::int from better_supabase.conversations
   where kind = 'subject' and subject_id = '00000000-0000-4000-8000-00000000a003'
     and tenant_id = '00000000-0000-4000-8000-000000000001'),
  0,
  'no Acme conversation exists for the Globex customer'
);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select throws_ok(
  $$select better_supabase.open_conversation('00000000-0000-4000-8000-000000000001', 'subject', '{"subjectType":"customer","subjectId":"00000000-0000-4000-8000-00000000a003"}')$$,
  'P0002',
  'no such record in this organization',
  'the service role opens no cross-tenant record conversation either'
);
select lives_ok(
  $$select better_supabase.open_conversation('00000000-0000-4000-8000-000000000002', 'subject', '{"subjectType":"customer","subjectId":"00000000-0000-4000-8000-00000000a003"}')$$,
  'the service role opens the record conversation in its own tenant'
);

select * from finish();
rollback;
