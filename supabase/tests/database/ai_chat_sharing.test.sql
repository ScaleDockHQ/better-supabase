-- Chat sharing: a chat shared with a team is read by the team's members and by
-- nobody else in the organization, the live link follows its salt and the
-- share summary names the owner first. Acme (…0001) has the admin …a1 and the
-- member …a2; Sales (…e1) has both, Support (…e2) only the admin
-- (supabase/seed.sql).
begin;
select plan(14);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;
create temporary table tokens (name text primary key, token text) on commit drop;
grant all on tokens to authenticated, anon, service_role;

-- Acme admin, the owner.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

insert into ids
select 'chat', (api.create_ai_chat(
  '00000000-0000-4000-8000-000000000001',
  '{"title":"Escalations","visibility":"private"}'
) ->> 'id')::uuid;

select is(
  api.add_ai_chat_party(
    (select id from ids where name = 'chat'),
    'team',
    '00000000-0000-4000-8000-0000000000e2'
  ) ->> 'kind',
  'team',
  'the owner shares the chat with a team'
);

select is(
  api.get_ai_chat((select id from ids where name = 'chat')) ->> 'visibility',
  'shared',
  'adding a party makes a private chat shared'
);

select throws_ok(
  format(
    $$select api.add_ai_chat_party(%L, 'external', 'not an email')$$,
    (select id from ids where name = 'chat')
  ),
  '22023',
  null,
  'an external party needs an email address'
);

-- Acme member, not in Support.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
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
  'an organization member outside the team cannot read the shared chat'
);

select is(
  (api.list_ai_chats() -> 'items') @> jsonb_build_array(jsonb_build_object('id', (select id from ids where name = 'chat'))),
  false,
  'nor list it'
);

-- Back to the owner: Sales has the member.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select api.add_ai_chat_party(
  (select id from ids where name = 'chat'),
  'team',
  '00000000-0000-4000-8000-0000000000e1'
);

select is(
  (api.ai_chat_share_summaries(array[(select id from ids where name = 'chat')]) -> 0 -> 'users' -> 0 ->> 'role'),
  'owner',
  'the share summary lists the owner first'
);

select is(
  (api.ai_chat_share_summaries(array[(select id from ids where name = 'chat')]) -> 0 ->> 'team_count')::int,
  2,
  'and counts the teams'
);

select is(
  api.list_ai_chat_participants((select id from ids where name = 'chat')) -> 0 ->> 'role',
  'owner',
  'the participant list starts with the owner'
);

insert into tokens
select 'first', api.create_ai_chat_link((select id from ids where name = 'chat')) ->> 'token';

select is(
  (api.ai_chat_share_summaries(array[(select id from ids where name = 'chat')]) -> 0 ->> 'has_link')::boolean,
  true,
  'the summary shows the live link'
);

-- Acme member, in Sales.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  api.get_ai_chat((select id from ids where name = 'chat')) ->> 'title',
  'Escalations',
  'a member of a participating team reads the chat'
);

-- Anyone with the link.
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

select is(
  api.get_ai_chat_by_link((select token from tokens where name = 'first')) -> 'chat' ->> 'title',
  'Escalations',
  'the live link opens the chat'
);

-- The owner rotates the link.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

insert into tokens
select 'second', api.rotate_ai_chat_link((select id from ids where name = 'chat')) ->> 'token';

reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

select is(
  api.get_ai_chat_by_link((select token from tokens where name = 'first')),
  null::jsonb,
  'rotating the salt invalidates the old link'
);

select is(
  api.get_ai_chat_by_link((select token from tokens where name = 'second')) -> 'chat' ->> 'title',
  'Escalations',
  'and the new link opens the chat'
);

-- The owner revokes it.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select api.revoke_ai_chat_link((select id from ids where name = 'chat'));

reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

select is(
  api.get_ai_chat_by_link((select token from tokens where name = 'second')),
  null::jsonb,
  'a revoked link opens nothing'
);

select * from finish();
rollback;
