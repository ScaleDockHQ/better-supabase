-- list_inbox_conversations joins contacts, inbox and read times in one pass
-- (ADR 0652). Acme (…0001) has the Help inbox with one conversation from Road
-- Runner and the member …a2; Globex (…0002) has the owner …a3.
begin;
select plan(9);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

insert into ids
select 'conversation', id from better_supabase.inbox_conversations limit 1;
insert into ids
select 'person', contact_id from better_supabase.inbox_conversations where id = (select id from ids where name = 'conversation');
-- The Globex owner stands in for Road Runner's signed-in account.
update better_supabase.people
set user_id = '00000000-0000-4000-8000-0000000000a3'
where id = (select id from ids where name = 'person');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (api.list_inbox_conversations('00000000-0000-4000-8000-000000000001') -> 0 -> 'contact' ->> 'id')::uuid,
  (select id from ids where name = 'person'),
  'staff read the contact of each conversation');
select is(
  api.list_inbox_conversations('00000000-0000-4000-8000-000000000001') -> 0 -> 'inbox' ->> 'name',
  (select name from better_supabase.inboxes limit 1),
  'each conversation carries its inbox');
select ok(
  (api.list_inbox_conversations('00000000-0000-4000-8000-000000000001') -> 0) ? 'last_read_at'
    and (api.list_inbox_conversations('00000000-0000-4000-8000-000000000001') -> 0) ? 'contact_read_at'
    and (api.list_inbox_conversations('00000000-0000-4000-8000-000000000001') -> 0) ? 'unread',
  'each conversation carries both read times and the unread flag');

select is(
  jsonb_array_length(api.list_inbox_conversations(
    '00000000-0000-4000-8000-000000000001',
    jsonb_build_object('search', (select name from better_supabase.people where id = (select id from ids where name = 'person'))))),
  1,
  'a search matches the contact name');
select is(
  jsonb_array_length(api.list_inbox_conversations(
    '00000000-0000-4000-8000-000000000001', '{"search":"no such contact anywhere"}')),
  0,
  'a search that matches nothing returns an empty page');

select is(
  api.list_inbox_conversations('00000000-0000-4000-8000-000000000001') -> 0 ->> 'id',
  (select id::text from ids where name = 'conversation'),
  'the page has the conversation');

-- The contact's own account.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select is(
  api.list_inbox_conversations('00000000-0000-4000-8000-000000000001') -> 0 -> 'contact' ->> 'id',
  (select id::text from ids where name = 'person'),
  'a contact reads their own person');
select is(
  api.list_inbox_conversations('00000000-0000-4000-8000-000000000001') -> 0 -> 'contact_read_at',
  'null'::jsonb,
  'a contact gets no staff read receipt');

-- An organization member of another tenant that is no contact.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select is(
  jsonb_array_length(api.list_inbox_conversations('00000000-0000-4000-8000-000000000002')),
  0,
  'another tenant lists nothing from this one');

select * from finish();
rollback;
