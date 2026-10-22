-- The subjects module's presence policies: presence:<type>:<id> reaches the
-- readers of that record and nobody else. Acme (…0001) has the member …a2 and
-- the customer …a001; Globex (…0002) has the customer …a003.
begin;
select plan(7);

insert into realtime.messages (topic, extension, payload, event, private)
values
  ('presence:customer:00000000-0000-4000-8000-00000000a001', 'presence', '{}', 'presence', true),
  ('presence:customer:00000000-0000-4000-8000-00000000a003', 'presence', '{}', 'presence', true);

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-0000000000a2", "role": "authenticated", "app_metadata": {"tenant_id": "00000000-0000-4000-8000-000000000001"}}';

set local realtime.topic = 'presence:customer:00000000-0000-4000-8000-00000000a001';
select is(
  (select count(*)::int from realtime.messages where topic = 'presence:customer:00000000-0000-4000-8000-00000000a001'),
  1,
  'a reader of the record receives its presence'
);
select lives_ok(
  $$insert into realtime.messages (topic, extension, payload, event, private)
    values ('presence:customer:00000000-0000-4000-8000-00000000a001', 'presence', '{}', 'presence', true)$$,
  'a reader of the record tracks presence on it'
);

set local realtime.topic = 'presence:customer:00000000-0000-4000-8000-00000000a003';
select is(
  (select count(*)::int from realtime.messages where topic = 'presence:customer:00000000-0000-4000-8000-00000000a003'),
  0,
  'a member receives no presence of a record in another organization'
);
select throws_ok(
  $$insert into realtime.messages (topic, extension, payload, event, private)
    values ('presence:customer:00000000-0000-4000-8000-00000000a003', 'presence', '{}', 'presence', true)$$,
  '42501',
  null,
  'a member tracks no presence on a record in another organization'
);

select ok(
  not better_supabase.subject_presence_allowed('presence:customer:not-a-uuid'),
  'an id the subject cannot cast is refused, not an error'
);
select ok(
  not better_supabase.subject_presence_allowed('presence:Customer:00000000-0000-4000-8000-00000000a001'),
  'a topic outside presence:<type>:<id> is refused'
);
select ok(
  not better_supabase.subject_presence_allowed('presence:nope:1'),
  'an unregistered subject type is refused'
);

select * from finish();
rollback;
