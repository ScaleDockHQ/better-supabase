-- comment.posted on the messaging core: sent only when the record has a
-- follower besides the author, and labeled with the record's title. The
-- check constraint stands in for an adopted notifications table that
-- requires a label. Acme (…0001) has the admin …a1 and the member …a2.
begin;
select plan(5);

alter table better_supabase.notification_events
  add constraint comment_notifications_label_required
  check (type <> 'comment.posted' or subject_label is not null);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select lives_ok(
  $$select better_supabase.create_comment('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a002', 'Nobody follows this yet')$$,
  'a comment on a record nobody else follows sends no comment.posted'
);

reset role;
select is(
  (select count(*)::int from better_supabase.notification_events
   where type = 'comment.posted' and subject_id = '00000000-0000-4000-8000-00000000a002'),
  0,
  'no comment.posted event is written without a follower'
);

insert into better_supabase.notification_subscriptions (organization_id, user_id, subject_type, subject_id, level)
values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'customer', '00000000-0000-4000-8000-00000000a001', 'all');

set local role authenticated;
select lives_ok(
  $$select better_supabase.create_comment('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'The admin follows this one')$$,
  'a comment on a followed record passes a table that requires a label'
);

reset role;
select is(
  (select subject_label from better_supabase.notification_events
   where type = 'comment.posted' and subject_id = '00000000-0000-4000-8000-00000000a001'),
  'Road Runner Inc',
  'comment.posted carries the record''s title as its label'
);
select is(
  (select count(*)::int from better_supabase.notification_recipients r
   join better_supabase.notification_events e on e.id = r.event_id
   where e.type = 'comment.posted' and r.user_id = '00000000-0000-4000-8000-0000000000a1'),
  1,
  'the follower receives comment.posted'
);

select * from finish();
rollback;
