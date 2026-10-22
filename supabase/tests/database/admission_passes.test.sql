-- The passes module on the fixture's access contract: the admin (…00a1) of
-- Acme (…0001) issues a ticket for a confirmed booking and drop-in passes for
-- a one-seat room, scans them at the door, and the holder (…00e1) sees their
-- own pass. The member (…00a2) can't issue passes.
begin;
select plan(20);

insert into auth.users (id, email, email_confirmed_at, aud, role, instance_id) values
  ('00000000-0000-4000-8000-0000000000e1', 'holder@example.test', now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
  ('00000000-0000-4000-8000-0000000000e2', 'someone@example.test', now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000');

insert into better_supabase.booking_resources (id, tenant_id, name, capacity) values
  ('00000000-0000-4000-8000-00000000b001', '00000000-0000-4000-8000-000000000001', 'Studio', 5),
  ('00000000-0000-4000-8000-00000000b002', '00000000-0000-4000-8000-000000000001', 'Quiet room', 1);
insert into better_supabase.booking_services (id, tenant_id, name, duration) values
  ('00000000-0000-4000-8000-00000000b101', '00000000-0000-4000-8000-000000000001', 'Class', interval '1 hour');
insert into better_supabase.bookings (id, tenant_id, resource_id, service_id, seat, during, blocked, status, hold_expires_at) values
  ('00000000-0000-4000-8000-00000000b201', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000b001', '00000000-0000-4000-8000-00000000b101', 1,
    tstzrange(now() - interval '10 minutes', now() + interval '50 minutes'), tstzrange(now() - interval '10 minutes', now() + interval '50 minutes'), 'confirmed', null),
  ('00000000-0000-4000-8000-00000000b202', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000b001', '00000000-0000-4000-8000-00000000b101', 2,
    tstzrange(now() - interval '10 minutes', now() + interval '50 minutes'), tstzrange(now() - interval '10 minutes', now() + interval '50 minutes'), 'hold', now() + interval '5 minutes');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.ticket', better_supabase.issue_pass(
  '00000000-0000-4000-8000-000000000001', 'ticket',
  holder_user => '00000000-0000-4000-8000-0000000000e1', holder_name => 'Holder',
  booking_id => '00000000-0000-4000-8000-00000000b201'
)::text, true);

select is(
  (current_setting('test.ticket')::jsonb ->> 'usesAllowed')::int,
  1,
  'a ticket for a booking admits once'
);
select is(
  current_setting('test.ticket')::jsonb ->> 'resourceId',
  '00000000-0000-4000-8000-00000000b001',
  'a ticket takes the booking''s resource'
);
select ok(
  (current_setting('test.ticket')::jsonb ->> 'validUntil')::timestamptz > now(),
  'a ticket is valid until the booking ends'
);
select throws_ok(
  $$select better_supabase.issue_pass('00000000-0000-4000-8000-000000000001', 'ticket', booking_id => '00000000-0000-4000-8000-00000000b201', resource_id => '00000000-0000-4000-8000-00000000b002')$$,
  '22023',
  'the booking is for another resource',
  'a ticket cannot name another resource than its booking'
);

select is(
  better_supabase.check_in_pass((current_setting('test.ticket')::jsonb ->> 'id')::uuid, 'not-the-nonce') ->> 'reason',
  'invalid',
  'a scan with the wrong nonce is turned away'
);
select is(
  (better_supabase.check_in_pass(
    (current_setting('test.ticket')::jsonb ->> 'id')::uuid,
    current_setting('test.ticket')::jsonb ->> 'nonce',
    gate => 'north'
  ) -> 'pass' ->> 'uses')::int,
  1,
  'a scan with the nonce admits and uses the ticket'
);
select is(
  better_supabase.check_in_pass(
    (current_setting('test.ticket')::jsonb ->> 'id')::uuid,
    current_setting('test.ticket')::jsonb ->> 'nonce'
  ) ->> 'reason',
  'used_up',
  'a used ticket is turned away'
);
select is(
  jsonb_array_length(better_supabase.list_pass_check_ins((current_setting('test.ticket')::jsonb ->> 'id')::uuid)),
  3,
  'every scan is logged'
);

select set_config('test.held', better_supabase.issue_pass(
  '00000000-0000-4000-8000-000000000001', 'ticket', booking_id => '00000000-0000-4000-8000-00000000b202'
)::text, true);
select is(
  better_supabase.check_in_pass((current_setting('test.held')::jsonb ->> 'id')::uuid, method => 'manual') ->> 'reason',
  'booking_unconfirmed',
  'a ticket for a booking still on hold is turned away'
);

-- Drop-ins at the one-seat room.
select set_config('test.first', better_supabase.issue_pass(
  '00000000-0000-4000-8000-000000000001', 'visitor', resource_id => '00000000-0000-4000-8000-00000000b002'
)::text, true);
select set_config('test.second', better_supabase.issue_pass(
  '00000000-0000-4000-8000-000000000001', 'visitor', resource_id => '00000000-0000-4000-8000-00000000b002'
)::text, true);

select is(
  (better_supabase.check_in_pass(
    (current_setting('test.first')::jsonb ->> 'id')::uuid,
    current_setting('test.first')::jsonb ->> 'nonce',
    'nfc'
  ) ->> 'admitted')::boolean,
  true,
  'a drop-in takes the free seat'
);
select is(
  better_supabase.check_in_pass(
    (current_setting('test.second')::jsonb ->> 'id')::uuid,
    current_setting('test.second')::jsonb ->> 'nonce'
  ) ->> 'reason',
  'full',
  'a drop-in is turned away when the room is full'
);
select is(
  better_supabase.pass_occupancy('00000000-0000-4000-8000-00000000b002'),
  '{"resourceId": "00000000-0000-4000-8000-00000000b002", "capacity": 1, "booked": 0, "dropIns": 1, "free": 0}'::jsonb,
  'occupancy counts the drop-in'
);
select is(
  better_supabase.check_in_pass(
    (current_setting('test.second')::jsonb ->> 'id')::uuid,
    current_setting('test.second')::jsonb ->> 'nonce',
    resource_id => '00000000-0000-4000-8000-00000000b001'
  ) ->> 'reason',
  'wrong_resource',
  'a pass for one room is turned away at another'
);

select better_supabase.revoke_pass((current_setting('test.second')::jsonb ->> 'id')::uuid);
select is(
  better_supabase.check_in_pass((current_setting('test.second')::jsonb ->> 'id')::uuid, method => 'manual') ->> 'reason',
  'revoked',
  'a revoked pass is turned away'
);
reset role;
select is(
  (select count(*) from better_supabase.outbox_events where type in ('pass.admitted', 'pass.rejected')),
  8::bigint,
  'every scan records an event'
);
set local role authenticated;
select throws_ok(
  $$select count(*) from better_supabase.passes$$,
  '42501',
  null,
  'the passes table is read through the functions only'
);

-- The holder.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;

select is(
  better_supabase.get_pass((current_setting('test.ticket')::jsonb ->> 'id')::uuid) ->> 'nonce',
  current_setting('test.ticket')::jsonb ->> 'nonce',
  'the holder reads their pass with its nonce'
);
select is(
  jsonb_array_length(better_supabase.my_passes()),
  1,
  'the holder lists their live passes'
);

-- Someone else.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e2","role":"authenticated"}', true);
set local role authenticated;

select is(
  better_supabase.get_pass((current_setting('test.ticket')::jsonb ->> 'id')::uuid),
  null,
  'nobody else reads the pass'
);

-- Acme member without passes.manage.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select better_supabase.issue_pass('00000000-0000-4000-8000-000000000001', 'visitor')$$,
  '42501',
  'not allowed to issue passes',
  'a member without passes.manage cannot issue passes'
);

select * from finish();
rollback;
