-- Record mentions (@[Name](subject:<type>/<id>)) index on send and list as the
-- record's backlinks for its readers only. Acme (…0001) has the member …a2 and
-- the customer …a001; Globex (…0002) has the owner …a3 and the customer
-- …a003 (supabase/seed.sql).
begin;
select plan(9);

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
  '{"title":"accounts"}'
) ->> 'id')::uuid;

insert into ids
select 'message', (api.send_message(
  (select id from ids where name = 'channel'),
  'Renewal for @[Road Runner](subject:customer/00000000-0000-4000-8000-00000000a001), not @[x](subject:nope/1) or @[Initech](subject:customer/00000000-0000-4000-8000-00000000a003)'
) ->> 'id')::uuid;

select is(
  jsonb_array_length(api.list_record_mentions('customer', '00000000-0000-4000-8000-00000000a001')),
  1,
  'a reader of the record lists the message that mentions it'
);
select is(
  api.list_record_mentions('customer', '00000000-0000-4000-8000-00000000a001') -> 0 -> 'conversation' ->> 'id',
  (select id::text from ids where name = 'channel'),
  'a backlink names the conversation the message is in'
);
select is(
  api.list_record_mentions('customer', '00000000-0000-4000-8000-00000000a001') -> 0 -> 'message' ->> 'id',
  (select id::text from ids where name = 'message'),
  'a backlink carries the message'
);
select is(
  api.list_record_mentions('nope', '1'),
  '[]'::jsonb,
  'a mention of an unregistered subject type is not indexed'
);
select is(
  api.list_record_mentions('customer', '00000000-0000-4000-8000-00000000a003'),
  '[]'::jsonb,
  'a member lists no backlinks of a record in another organization'
);

select api.edit_message((select id from ids where name = 'message'), 'Renewal handled');

select is(
  api.list_record_mentions('customer', '00000000-0000-4000-8000-00000000a001'),
  '[]'::jsonb,
  'an edit that drops the mention drops the backlink'
);

select api.edit_message(
  (select id from ids where name = 'message'),
  'Back to @[Road Runner](subject:customer/00000000-0000-4000-8000-00000000a001)'
);

select is(
  jsonb_array_length(api.list_record_mentions('customer', '00000000-0000-4000-8000-00000000a001')),
  1,
  'an edit that adds the mention back restores the backlink'
);

-- Globex owner, an outsider to Acme and its customer.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  api.list_record_mentions('customer', '00000000-0000-4000-8000-00000000a001'),
  '[]'::jsonb,
  'an outsider lists no backlinks of a record they cannot read'
);

-- Anonymous.
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

select throws_ok(
  $$select api.list_record_mentions('customer', '00000000-0000-4000-8000-00000000a001')$$,
  '42501',
  null,
  'an anonymous caller cannot list backlinks'
);

select * from finish();
rollback;
