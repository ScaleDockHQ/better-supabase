-- Inbox snooze wake-ups and scheduled replies. Acme (…0001) has the Help
-- inbox with one conversation and the member …a2; Globex (…0002) has the
-- owner …a3 (supabase/seed.sql).
begin;
select plan(25);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

insert into ids
select 'conversation', id from better_supabase.conversations where kind = 'inbox';

-- Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  format($$select api.schedule_inbox_message(%L, '{"body":"Too late"}', now() - interval '1 minute')$$, (select id from ids where name = 'conversation')),
  '22023',
  null,
  'a reply cannot be scheduled in the past'
);
select throws_ok(
  format($$select api.schedule_inbox_message(%L, '{"kind":"note","body":"Later"}', now() + interval '1 hour')$$, (select id from ids where name = 'conversation')),
  '22023',
  null,
  'a note cannot be scheduled'
);
select throws_ok(
  format($$select api.schedule_inbox_message(%L, '{"body":"  "}', now() + interval '1 hour')$$, (select id from ids where name = 'conversation')),
  '22023',
  null,
  'a scheduled reply needs a body or an attachment'
);

insert into ids
select 'scheduled', (api.schedule_inbox_message(
  (select id from ids where name = 'conversation'),
  '{"body":"Scheduled hello","external_id":"x-1","author_type":"system"}',
  now() + interval '1 hour'
) ->> 'id')::uuid;
insert into ids
select 'cancelled', (api.schedule_inbox_message(
  (select id from ids where name = 'conversation'),
  '{"body":"Never mind"}',
  now() + interval '2 hours'
) ->> 'id')::uuid;

select is(
  (select author_id from better_supabase.scheduled_inbox_messages where id = (select id from ids where name = 'scheduled')),
  '00000000-0000-4000-8000-0000000000a2'::uuid,
  'the scheduled reply belongs to its author'
);
select is(
  (select input from better_supabase.scheduled_inbox_messages where id = (select id from ids where name = 'scheduled')),
  '{"body":"Scheduled hello"}'::jsonb,
  'the service''s fields are dropped from a scheduled reply'
);
select is(
  jsonb_array_length(api.list_scheduled_inbox_messages()),
  2,
  'the author lists their scheduled replies'
);
select is(
  api.list_scheduled_inbox_messages((select id from ids where name = 'conversation')) -> 0 ->> 'id',
  (select id from ids where name = 'scheduled')::text,
  'the soonest reply comes first'
);
select throws_ok(
  format($$select api.reschedule_inbox_message(%L, now() - interval '1 minute')$$, (select id from ids where name = 'scheduled')),
  '22023',
  null,
  'a reply cannot be moved into the past'
);
select is(
  (api.reschedule_inbox_message((select id from ids where name = 'scheduled'), now() + interval '3 hours') ->> 'scheduled_for')::timestamptz,
  now() + interval '3 hours',
  'the author moves a scheduled reply'
);
select ok(
  api.cancel_inbox_message((select id from ids where name = 'cancelled')),
  'the author cancels a scheduled reply'
);
select throws_ok(
  format($$select api.set_conversation_status(%L, 'snoozed', now() - interval '1 minute')$$, (select id from ids where name = 'conversation')),
  '22023',
  null,
  'a conversation cannot be snoozed until a past time'
);
select is(
  api.set_conversation_status((select id from ids where name = 'conversation'), 'snoozed', now() + interval '1 day') ->> 'status',
  'snoozed',
  'a member snoozes the conversation until tomorrow'
);

-- The Globex owner: another tenant.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(api.list_scheduled_inbox_messages()),
  0,
  'nobody else sees the scheduled reply'
);
select throws_ok(
  format($$select api.cancel_inbox_message(%L)$$, (select id from ids where name = 'scheduled')),
  'P0002',
  null,
  'nobody else cancels the scheduled reply'
);
select throws_ok(
  format($$select api.schedule_inbox_message(%L, '{"body":"x"}', now() + interval '1 hour')$$, (select id from ids where name = 'conversation')),
  '42501',
  null,
  'an outsider cannot schedule a reply'
);

reset role;
select set_config('request.jwt.claims', null, true);

select is(
  (select count(*)::int from pgmq.q_inbox_schedule
   where message ->> 'dedupe_key' like 'inbox-publish:' || (select id from ids where name = 'scheduled')::text || ':%'),
  2,
  'scheduling and rescheduling each queue a delayed publish job'
);
select is(
  (select count(*)::int from pgmq.q_inbox_schedule
   where message ->> 'dedupe_key' like 'inbox-wake:' || (select id from ids where name = 'conversation')::text || ':%'),
  1,
  'snoozing queues a delayed wake job'
);

update better_supabase.scheduled_inbox_messages set scheduled_for = now() - interval '1 minute';
update better_supabase.inbox_conversations set snoozed_until = now() - interval '1 minute'
where id = (select id from ids where name = 'conversation');

-- The job handler.
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select is(api.publish_due_inbox_messages(10), 1, 'the service publishes the due reply');
select is(
  (select direction from better_supabase.inbox_message_details d
   join better_supabase.messages m on m.id = d.message_id
   where m.body = 'Scheduled hello' and m.author_id = '00000000-0000-4000-8000-0000000000a2'),
  'outbound',
  'the reply is sent as its author, outbound'
);
select is(
  (select count(*)::int from better_supabase.scheduled_inbox_messages),
  0,
  'a published reply leaves the schedule'
);
select is(api.wake_snoozed_conversations(), 1, 'the service wakes the snoozed conversation');
select is(
  (select status from better_supabase.inbox_conversations where id = (select id from ids where name = 'conversation')),
  'open',
  'a woken conversation is open'
);
select is(
  (select count(*)::int from better_supabase.conversation_events
   where conversation_id = (select id from ids where name = 'conversation') and type = 'unsnoozed'),
  1,
  'waking logs unsnoozed in the activity'
);
select is(
  (select count(*)::int from better_supabase.outbox_events
   where type = 'inbox_conversation.unsnoozed' and payload ->> 'conversationId' = (select id from ids where name = 'conversation')::text),
  1,
  'waking emits inbox_conversation.unsnoozed'
);

-- Anonymous.
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

select throws_ok(
  format($$select api.schedule_inbox_message(%L, '{"body":"x"}', now() + interval '1 hour')$$, (select id from ids where name = 'conversation')),
  '42501',
  null,
  'anonymous callers schedule nothing'
);

select * from finish();
rollback;
