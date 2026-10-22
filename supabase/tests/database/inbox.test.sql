-- The inbox on the messaging core. Acme (…0001) has the Help inbox with one
-- conversation from Road Runner and the member …a2; Globex (…0002) has the
-- owner …a3 (supabase/seed.sql).
begin;
select plan(16);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

insert into ids
select 'conversation', id from better_supabase.conversations where kind = 'inbox';
-- The Globex owner stands in for Road Runner's signed-in account.
update better_supabase.contacts
set user_id = '00000000-0000-4000-8000-0000000000a3'
where id = (select contact_id from better_supabase.inbox_conversations where id = (select id from ids where name = 'conversation'));

-- Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(api.list_inbox_conversations('00000000-0000-4000-8000-000000000001')),
  1,
  'a member lists the inbox conversations of the organization'
);
select is(
  (select kind from better_supabase.conversations where id = (select id from ids where name = 'conversation')),
  'inbox',
  'an inbox conversation is a core conversation of kind inbox'
);

insert into ids
select 'note', (api.send_inbox_message(
  (select id from ids where name = 'conversation'),
  '{"kind":"note","body":"Check the billing profile first"}'
) ->> 'id')::uuid;
insert into ids
select 'reply', (api.send_inbox_message(
  (select id from ids where name = 'conversation'),
  '{"body":"We are on it"}'
) ->> 'id')::uuid;

select is(
  api.get_inbox_message((select id from ids where name = 'note')) ->> 'kind',
  'note',
  'a member writes an internal note as a message of kind note'
);
select is(
  api.get_inbox_message((select id from ids where name = 'reply')) ->> 'direction',
  'outbound',
  'a member''s reply is outbound'
);
select is(
  jsonb_array_length(api.list_inbox_messages((select id from ids where name = 'conversation'))),
  3,
  'a member reads the messages and the note'
);
select isnt(
  api.mark_conversation_read((select id from ids where name = 'conversation')),
  null,
  'a member marks the conversation read'
);
select isnt(
  (select last_read_at from better_supabase.conversation_members
   where conversation_id = (select id from ids where name = 'conversation')
     and user_id = '00000000-0000-4000-8000-0000000000a2'),
  null,
  'the read time lives on conversation_members.last_read_at'
);
select ok(
  api.set_typing((select id from ids where name = 'conversation'), true),
  'typing in an inbox conversation goes through the core'
);
select is(
  (api.react_to_inbox_message((select id from ids where name = 'reply'), '👍') -> 0 ->> 'count')::int,
  1,
  'a member reacts to a message and gets the reaction list back'
);
select is(
  api.create_inbox_attachment((select id from ids where name = 'conversation'), 'invoice.pdf', 'application/pdf', 1024) ->> 'status',
  'pending',
  'an upload starts as a pending attachment row'
);

-- Road Runner, the conversation's contact.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select array_agg(x ->> 'kind') from jsonb_array_elements(
    api.list_inbox_messages((select id from ids where name = 'conversation'))
  ) x),
  array['message', 'message'],
  'the contact reads the messages but not the note'
);
select is(
  api.get_inbox_message((select id from ids where name = 'note')),
  null,
  'the contact cannot fetch the note by id'
);
select throws_ok(
  format($$select api.send_inbox_message(%L, '{"kind":"note","body":"x"}')$$, (select id from ids where name = 'conversation')),
  '42501',
  null,
  'the contact cannot write a note'
);
select throws_ok(
  format($$select api.react_to_inbox_message(%L, '👍')$$, (select id from ids where name = 'note')),
  '42501',
  null,
  'the contact cannot react to a note'
);

-- The inbound handler.
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select api.send_inbox_message(
  (select id from ids where name = 'conversation'),
  '{"author_type":"contact","body":"Here is the invoice","files":[{"url":"https://files.test/invoice.pdf","name":"invoice.pdf","content_type":"application/pdf"}]}'
);
select is(
  (select x -> 'source' ->> 'url' from jsonb_array_elements(api.pending_inbox_files(10)) x limit 1),
  'https://files.test/invoice.pdf',
  'a channel file waits as a pending attachment with its source'
);

-- Anonymous.
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

select throws_ok(
  format($$select api.send_inbox_message(%L, '{"body":"x"}')$$, (select id from ids where name = 'conversation')),
  '42501',
  null,
  'anonymous callers write nothing'
);

select * from finish();
rollback;
