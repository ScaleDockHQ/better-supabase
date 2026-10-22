-- The messaging core on the fixture's access contract. Acme (…0001) has the
-- owner …a1 and the member …a2; Globex (…0002) has the owner …a3, and …a1 is
-- a member there too (supabase/seed.sql).
begin;
select plan(8);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon;

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
  '{"title":"launch"}',
  array['00000000-0000-4000-8000-0000000000a1']::uuid[]
) ->> 'id')::uuid;

select isnt(
  (select id from ids where name = 'channel'),
  null,
  'a member with messages.send opens a channel in their organization'
);

insert into ids
select 'message', (api.send_message((select id from ids where name = 'channel'), 'Ship it') ->> 'id')::uuid;

select isnt(
  (select id from ids where name = 'message'),
  null,
  'a member of the conversation sends a message'
);
select ok(
  api.list_messages((select id from ids where name = 'channel'))::text like '%Ship it%',
  'the sender lists the message'
);
select ok(
  api.can_conversation((select id from ids where name = 'channel'), 'send'),
  'a member may send in a conversation they belong to'
);
select throws_ok(
  $$select api.open_conversation('00000000-0000-4000-8000-000000000002', 'channel', '{"title":"x"}')$$,
  '42501',
  null,
  'a member of Acme opens nothing in Globex'
);

-- Globex owner, an outsider to Acme.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select ok(
  not api.can_conversation((select id from ids where name = 'channel'), 'read'),
  'an outsider cannot read an Acme conversation'
);
select throws_ok(
  format($$select api.send_message(%L, 'hello')$$, (select id from ids where name = 'channel')),
  'P0002',
  null,
  'an outsider cannot send into an Acme conversation, and learns nothing of it'
);

-- Anonymous.
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

select throws_ok(
  format($$select api.list_messages(%L)$$, (select id from ids where name = 'channel')),
  '42501',
  null,
  'an anonymous caller cannot call the messaging API'
);

select * from finish();
rollback;
