-- Thread summaries are written by the service role and read by the readers of
-- their conversation, with `stale` set once a message lands, changes or goes
-- away after the summary. Acme (…0001) has the member …a2; Globex (…0002) has
-- the owner …a3 (supabase/seed.sql).
begin;
select plan(14);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

-- Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

insert into ids
select 'channel', (api.open_conversation(
  '00000000-0000-4000-8000-000000000001',
  'channel',
  '{"title":"launch"}'
) ->> 'id')::uuid;

insert into ids
select 'root', (api.send_message((select id from ids where name = 'channel'), 'Ship on Friday?') ->> 'id')::uuid;

insert into ids
select 'reply', (api.send_message(
  (select id from ids where name = 'channel'),
  'Friday works',
  jsonb_build_object('parentId', (select id from ids where name = 'root'))
) ->> 'id')::uuid;

select is(
  api.thread_summary((select id from ids where name = 'channel')),
  null,
  'a conversation has no summary until one is saved'
);

select throws_ok(
  format(
    $$select api.save_thread_summary(%L, null, 'Spoofed', '{"messageCount":1,"throughAt":"2026-01-01T00:00:00Z"}')$$,
    (select id from ids where name = 'channel')
  ),
  '42501',
  null,
  'a member cannot save a summary'
);

-- Service role.
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select is(
  api.save_thread_summary(
    (select id from ids where name = 'channel'),
    null,
    '  The team plans to ship on Friday.  ',
    jsonb_build_object('model', 'test/model', 'messageCount', 1, 'throughAt', now() - interval '1 minute')
  ) ->> 'summary',
  'The team plans to ship on Friday.',
  'the service role saves a trimmed conversation summary'
);

select is(
  (api.thread_summary((select id from ids where name = 'channel')) ->> 'stale')::boolean,
  true,
  'a message sent after throughAt makes the summary stale'
);

select is(
  (api.save_thread_summary(
    (select id from ids where name = 'channel'),
    null,
    'Shipping on Friday.',
    jsonb_build_object('messageCount', 1, 'throughAt', now())
  ) ->> 'stale')::boolean,
  false,
  'saving again through the newest message replaces the summary and clears stale'
);

select is(
  (api.save_thread_summary(
    null,
    (select id from ids where name = 'root'),
    'Friday is agreed.',
    jsonb_build_object('messageCount', 2, 'throughAt', now())
  ) ->> 'conversation_id')::uuid,
  (select id from ids where name = 'channel'),
  'a thread summary resolves its conversation from the root message'
);

select throws_ok(
  format(
    $$select api.save_thread_summary(%L, null, '   ', '{"messageCount":1,"throughAt":"2026-01-01T00:00:00Z"}')$$,
    (select id from ids where name = 'channel')
  ),
  '22023',
  null,
  'an empty summary is rejected'
);

select throws_ok(
  format(
    $$select api.save_thread_summary(%L, null, 'No count', '{"messageCount":"many","throughAt":"2026-01-01T00:00:00Z"}')$$,
    (select id from ids where name = 'channel')
  ),
  '22023',
  null,
  'a message count that is not a number is rejected'
);

select throws_ok(
  format(
    $$select api.save_thread_summary(null, %L, 'Not a root', '{"messageCount":1,"throughAt":"2026-01-01T00:00:00Z"}')$$,
    (select id from ids where name = 'reply')
  ),
  'P0002',
  null,
  'a reply is not a thread root'
);

-- Age the summaries so an edit or a delete in this transaction lands after them.
reset role;
update better_supabase.thread_summaries set updated_at = now() - interval '1 minute';

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  api.thread_summary(null, (select id from ids where name = 'root')) ->> 'summary',
  'Friday is agreed.',
  'a reader of the conversation reads the thread summary'
);

select api.edit_message((select id from ids where name = 'reply'), 'Friday works, after lunch');

select is(
  (api.thread_summary(null, (select id from ids where name = 'root')) ->> 'stale')::boolean,
  true,
  'an edited reply makes the thread summary stale'
);

select api.delete_message((select id from ids where name = 'root'));

select is(
  (api.thread_summary((select id from ids where name = 'channel')) ->> 'stale')::boolean,
  true,
  'a deleted message makes the conversation summary stale'
);

-- Globex owner, an outsider to the Acme channel.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  api.thread_summary((select id from ids where name = 'channel')),
  null,
  'an outsider reads no summary'
);

-- Anonymous.
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

select throws_ok(
  format($$select api.thread_summary(%L)$$, (select id from ids where name = 'channel')),
  '42501',
  null,
  'an anonymous caller cannot read summaries'
);

select * from finish();
rollback;
