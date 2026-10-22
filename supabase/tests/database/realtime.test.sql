-- The realtime-tables receive policy: signed-in users read change signals,
-- anonymous users (signInAnonymously()) read none, and a tenant or user topic
-- reaches only its own tenant or user.
begin;
select plan(7);

insert into realtime.messages (topic, extension, payload, event, private)
values
  ('bsb:t:public.customers', 'broadcast', '{}', 'change', true),
  ('bsb:t:public.customers:00000000-0000-4000-8000-000000000001', 'broadcast', '{}', 'change', true),
  ('bsb:t:public.notes:u:00000000-0000-4000-8000-0000000000a1', 'broadcast', '{}', 'change', true);

set local role authenticated;
set local realtime.topic = 'bsb:t:public.customers';

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-000000000001", "role": "authenticated", "is_anonymous": false}';
select is(
  (select count(*)::int from realtime.messages where topic = 'bsb:t:public.customers'),
  1,
  'a signed-in user receives an unscoped topic'
);

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-000000000002", "role": "authenticated", "is_anonymous": true}';
select is(
  (select count(*)::int from realtime.messages where topic = 'bsb:t:public.customers'),
  0,
  'an anonymous user receives nothing'
);

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select is(
  (select count(*)::int from realtime.messages where topic = 'bsb:t:public.customers'),
  1,
  'a token without is_anonymous counts as a signed-in user'
);

-- Acme (…0001) topic: an Acme member receives it, a Globex (…0002) member does not.
set local realtime.topic = 'bsb:t:public.customers:00000000-0000-4000-8000-000000000001';

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-0000000000a2", "role": "authenticated", "app_metadata": {"tenant_id": "00000000-0000-4000-8000-000000000001"}}';
select is(
  (select count(*)::int from realtime.messages where topic = 'bsb:t:public.customers:00000000-0000-4000-8000-000000000001'),
  1,
  'a member receives their tenant''s topic'
);

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-0000000000b1", "role": "authenticated", "app_metadata": {"tenant_id": "00000000-0000-4000-8000-000000000002"}}';
select is(
  (select count(*)::int from realtime.messages where topic = 'bsb:t:public.customers:00000000-0000-4000-8000-000000000001'),
  0,
  'a member of another tenant does not receive it'
);

-- User topic of …a1: only that user receives it.
set local realtime.topic = 'bsb:t:public.notes:u:00000000-0000-4000-8000-0000000000a1';

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-0000000000a1", "role": "authenticated"}';
select is(
  (select count(*)::int from realtime.messages where topic = 'bsb:t:public.notes:u:00000000-0000-4000-8000-0000000000a1'),
  1,
  'a user receives their own user topic'
);

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-0000000000a2", "role": "authenticated"}';
select is(
  (select count(*)::int from realtime.messages where topic = 'bsb:t:public.notes:u:00000000-0000-4000-8000-0000000000a1'),
  0,
  'another user does not receive it'
);

select * from finish();
rollback;
