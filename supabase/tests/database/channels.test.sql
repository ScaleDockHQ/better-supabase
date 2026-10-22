-- Channels on the messaging core. Acme (…0001) has the owner …a1 and the
-- member …a2; Globex (…0002) has the owner …a3 (supabase/seed.sql).
begin;
select plan(14);

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
select 'general', (api.create_channel(
  '00000000-0000-4000-8000-000000000001',
  ' General ',
  '{"topic":"Everything"}'
) ->> 'id')::uuid;
insert into ids
select 'secret', (api.create_channel(
  '00000000-0000-4000-8000-000000000001',
  'secret',
  '{"visibility":"private"}'
) ->> 'id')::uuid;

select is(
  api.get_channel((select id from ids where name = 'general')) ->> 'name',
  'general',
  'a member creates a channel; its name is trimmed and lowercased'
);
select is(
  (api.get_channel((select id from ids where name = 'secret')) ->> 'role'),
  'owner',
  'the creator owns the private channel they made'
);
select is(
  (select array_agg(x ->> 'name') from jsonb_array_elements(api.channels_for_record(
    'customer', (api.create_channel(
      '00000000-0000-4000-8000-000000000001',
      'deal-room',
      '{"subjectType":"customer","subjectId":"00000000-0000-4000-8000-00000000a001"}'
    ) ->> 'subject_id')
  )) x),
  array['deal-room'],
  'a channel linked to a record is listed for that record'
);
select throws_ok(
  $$select api.create_channel('00000000-0000-4000-8000-000000000001', 'general')$$,
  '23505',
  null,
  'a channel name is unique in the organization'
);
select throws_ok(
  $$select api.create_channel('00000000-0000-4000-8000-000000000001', 'Not a name!')$$,
  '22023',
  null,
  'a channel name is lowercase letters, digits, - and _'
);

-- Acme owner, not in either channel yet.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (select array_agg(x ->> 'name') from jsonb_array_elements(
    api.list_channels('00000000-0000-4000-8000-000000000001', true)
  ) x),
  array['deal-room', 'general'],
  'browsing lists the public channels and hides private ones from non-members'
);
select is(
  api.find_channel('00000000-0000-4000-8000-000000000001', 'secret'),
  null,
  'a non-member cannot find a private channel by name'
);
select ok(
  api.join_channel((select id from ids where name = 'general')),
  'a member of the organization joins a public channel'
);
select is(
  jsonb_array_length(api.list_channels('00000000-0000-4000-8000-000000000001')),
  1,
  'the joined channel is in the caller''s own list'
);
select throws_ok(
  format($$select api.join_channel(%L)$$, (select id from ids where name = 'secret')),
  'P0002',
  null,
  'a non-member cannot join a private channel, and learns nothing of it'
);
select is(
  api.update_channel(
    (select id from ids where name = 'general'),
    '{"topic":null,"purpose":"Company news"}'
  ) ->> 'purpose',
  'Company news',
  'whoever holds channels.manage changes the purpose'
);

-- Globex owner, an outsider to Acme.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  api.get_channel((select id from ids where name = 'general')),
  null,
  'an outsider cannot read an Acme channel'
);
select throws_ok(
  format($$select api.join_channel(%L)$$, (select id from ids where name = 'general')),
  'P0002',
  null,
  'an outsider cannot join an Acme channel'
);

-- Anonymous.
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

select throws_ok(
  $$select api.create_channel('00000000-0000-4000-8000-000000000001', 'anon')$$,
  '42501',
  null,
  'anonymous callers create no channels'
);

select * from finish();
rollback;
