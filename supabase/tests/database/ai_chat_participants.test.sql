-- Chat participants: the owner adds viewers and editors to a private chat.
-- Viewers read it, editors also write to it, and the tenant scope still keeps
-- out a participant from another tenant. Acme (…0001) has the owner …a1 and
-- the member …a2; …a3 belongs to Globex only (supabase/seed.sql).
begin;
select plan(13);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

-- Acme owner.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

insert into ids
select 'chat', (api.create_ai_chat(
  '00000000-0000-4000-8000-000000000001',
  '{"title":"Plans","visibility":"private"}'
) ->> 'id')::uuid;

select is(
  api.add_ai_chat_participant(
    (select id from ids where name = 'chat'),
    '00000000-0000-4000-8000-0000000000a2'
  ) ->> 'role',
  'viewer',
  'the owner adds a viewer'
);

select throws_ok(
  format(
    $$select api.add_ai_chat_participant(%L, '00000000-0000-4000-8000-0000000000a1')$$,
    (select id from ids where name = 'chat')
  ),
  '22023',
  null,
  'the owner is no participant'
);

select throws_ok(
  format(
    $$select api.add_ai_chat_participant(%L, '00000000-0000-4000-8000-0000000000a2', 'admin')$$,
    (select id from ids where name = 'chat')
  ),
  '22023',
  null,
  'a participant is a viewer or an editor'
);

select throws_ok(
  format(
    $$select api.add_ai_chat_participant(%L, '00000000-0000-4000-8000-0000000000a3')$$,
    (select id from ids where name = 'chat')
  ),
  '22023',
  null,
  'a participant must read chats in the chat''s organization'
);

-- A participant row left over after someone left the tenant.
reset role;
insert into better_supabase.ai_chat_participants (chat_id, user_id, role)
values ((select id from ids where name = 'chat'), '00000000-0000-4000-8000-0000000000a3', 'editor');
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

-- Acme member, a viewer.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  api.get_ai_chat((select id from ids where name = 'chat')) ->> 'title',
  'Plans',
  'a viewer reads the private chat'
);

select is(
  jsonb_array_length(api.list_ai_chat_participants((select id from ids where name = 'chat'))),
  2,
  'a viewer lists the participants'
);

select throws_ok(
  format(
    $$select api.append_ai_user_message(%L, '{"id":"m1","role":"user","parts":[{"type":"text","text":"hi"}]}')$$,
    (select id from ids where name = 'chat')
  ),
  'P0002',
  null,
  'a viewer cannot write'
);

select throws_ok(
  format(
    $$select api.add_ai_chat_participant(%L, '00000000-0000-4000-8000-0000000000a2', 'editor')$$,
    (select id from ids where name = 'chat')
  ),
  'P0002',
  null,
  'a participant cannot change roles'
);

-- Back to the owner, who makes …a2 an editor.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select api.add_ai_chat_participant(
  (select id from ids where name = 'chat'),
  '00000000-0000-4000-8000-0000000000a2',
  'editor'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (api.append_ai_user_message(
    (select id from ids where name = 'chat'),
    '{"id":"m1","role":"user","parts":[{"type":"text","text":"hi"}]}'
  ) ->> 'created')::boolean,
  true,
  'an editor writes to the chat'
);

select is(
  api.remove_ai_chat_participant(
    (select id from ids where name = 'chat'),
    '00000000-0000-4000-8000-0000000000a2'
  ),
  true,
  'a participant leaves the chat'
);

-- Globex owner, a participant of an Acme chat.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select throws_ok(
  format(
    $$select api.get_ai_chat(%L)$$,
    (select id from ids where name = 'chat')
  ),
  'P0002',
  null,
  'a participant outside the tenant cannot read the chat'
);

select throws_ok(
  format(
    $$select api.append_ai_user_message(%L, '{"id":"m2","role":"user","parts":[{"type":"text","text":"hi"}]}')$$,
    (select id from ids where name = 'chat')
  ),
  'P0002',
  null,
  'nor write to it'
);

select is(
  (api.list_ai_chats() -> 'items') @> jsonb_build_array(jsonb_build_object('id', (select id from ids where name = 'chat'))),
  false,
  'nor list it'
);

select * from finish();
rollback;
