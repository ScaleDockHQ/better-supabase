-- The realtime-tables receive policy: signed-in users read change signals,
-- anonymous users (signInAnonymously()) read none.
begin;
select plan(3);

insert into realtime.messages (topic, extension, payload, event, private)
values ('bs:t:public.customers', 'broadcast', '{}', 'change', true);

set local role authenticated;
set local realtime.topic = 'bs:t:public.customers';

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-000000000001", "role": "authenticated", "is_anonymous": false}';
select is(
  (select count(*)::int from realtime.messages where topic = 'bs:t:public.customers'),
  1,
  'a signed-in user receives an unscoped topic'
);

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-000000000002", "role": "authenticated", "is_anonymous": true}';
select is(
  (select count(*)::int from realtime.messages where topic = 'bs:t:public.customers'),
  0,
  'an anonymous user receives nothing'
);

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select is(
  (select count(*)::int from realtime.messages where topic = 'bs:t:public.customers'),
  1,
  'a token without is_anonymous counts as a signed-in user'
);

select * from finish();
rollback;
