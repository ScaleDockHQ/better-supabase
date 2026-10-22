-- The moderation module on the fixture's access contract: the member (…00a2)
-- of Acme (…0001) reports the admin's (…00a1) comment, the admin hides it
-- from the queue and bans the member, and Globex (…0002) sees nothing.
begin;
select plan(14);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.comment', better_supabase.create_comment(
  '00000000-0000-4000-8000-000000000001', 'customer',
  '00000000-0000-4000-8000-00000000a001', 'Buy cheap watches'
) ->> 'id', true);

select throws_ok(
  $$select better_supabase.report_content('00000000-0000-4000-8000-000000000001', 'message', current_setting('test.comment'), 'spam')$$,
  '22023',
  null,
  'nobody reports their own comment'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select is(
  (better_supabase.report_content(
    '00000000-0000-4000-8000-000000000001', 'message', current_setting('test.comment'), 'spam', 'A watch shop'
  ) ->> 'status'),
  'open',
  'a member reports a comment'
);
select is(
  (select count(*)::integer from better_supabase.moderation_reports),
  1,
  'reporting the same comment again keeps one open report'
) from (select better_supabase.report_content(
  '00000000-0000-4000-8000-000000000001', 'message', current_setting('test.comment'), 'spam'
)) again;
select throws_ok(
  $$select better_supabase.report_content('00000000-0000-4000-8000-000000000001', 'message', current_setting('test.comment'), 'boring')$$,
  '22023',
  null,
  'a report names one of the configured reasons'
);
select throws_ok(
  $$select better_supabase.moderation_queue('00000000-0000-4000-8000-000000000001')$$,
  '42501',
  null,
  'a member can''t read the moderation queue'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select set_config('test.item', (better_supabase.moderation_queue('00000000-0000-4000-8000-000000000001') -> 0 ->> 'id'), true);
select is(
  (better_supabase.moderation_item(
    '00000000-0000-4000-8000-000000000001', 'message', current_setting('test.comment')
  ) ->> 'openReports')::integer,
  1,
  'the reported comment waits in the queue with its open report'
);
select is(
  (better_supabase.moderate(current_setting('test.item')::uuid, 'hide', 'Spam') ->> 'status'),
  'hidden',
  'an admin hides the comment'
);
select is(
  (select status from better_supabase.moderation_reports),
  'resolved',
  'the decision resolves the open report'
);
select is(
  (select count(*)::integer from better_supabase.messages where id = current_setting('test.comment')::uuid),
  1,
  'the author still reads a hidden comment'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  (select count(*)::integer from better_supabase.messages where id = current_setting('test.comment')::uuid),
  0,
  'other members no longer read a hidden comment'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  (better_supabase.ban_user(
    '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'Repeated spam'
  ) ->> 'userId'),
  '00000000-0000-4000-8000-0000000000a2',
  'an admin bans a member'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  $$select better_supabase.create_comment('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'Still here')$$,
  '42501',
  null,
  'a banned member can''t comment'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select is(
  (select count(*)::integer from better_supabase.moderation_items),
  0,
  'another organization reads no moderation items'
);
select throws_ok(
  $$select better_supabase.moderate(current_setting('test.item')::uuid, 'restore')$$,
  '42501',
  null,
  'another organization can''t moderate'
);

select * from finish();
rollback;
