-- Inbound events with a lease and a retry delay, deliveries that never move
-- backwards, and conversations that keep last_inbound_at. Needs the inbox
-- module at version 9 or later, so run it after the fixture is regenerated.
-- It uses the first inbox in the fixture (the Help inbox in supabase/seed.sql).
begin;
select plan(17);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to service_role;

insert into ids select 'inbox', id from better_supabase.inboxes order by created_at limit 1;
insert into ids select 'event', (better_supabase.store_inbound_event('whatsapp', '{}', 'evt-pgtap') ->> 'id')::uuid;

set local role service_role;

select is(
  jsonb_array_length(better_supabase.pending_inbound_events()),
  1,
  'a received event is pending'
);

select ok(
  better_supabase.set_inbound_event_status((select id from ids where name = 'event'), 'processing', null, null, interval '5 minutes'),
  'an event moves to processing with a lease'
);
select is(
  (select attempts from better_supabase.inbox_inbound_events where id = (select id from ids where name = 'event')),
  1,
  'processing counts one attempt'
);
select is(
  jsonb_array_length(better_supabase.pending_inbound_events()),
  0,
  'a leased event is not offered again'
);

reset role;
update better_supabase.inbox_inbound_events set lock_expires_at = now() - interval '1 second';
set local role service_role;

select is(
  jsonb_array_length(better_supabase.pending_inbound_events()),
  1,
  'an event whose lease ran out is offered again'
);

select ok(
  better_supabase.set_inbound_event_status((select id from ids where name = 'event'), 'failed', 'boom', interval '1 hour', null),
  'a failure takes a retry delay'
);
select is(
  jsonb_array_length(better_supabase.pending_inbound_events()),
  0,
  'a failed event waits for available_at'
);
select is(
  (select lock_expires_at from better_supabase.inbox_inbound_events where id = (select id from ids where name = 'event')),
  null,
  'a failure clears the lease'
);

reset role;
update better_supabase.inbox_inbound_events set available_at = now() - interval '1 second';
set local role service_role;

select is(
  jsonb_array_length(better_supabase.pending_inbound_events()),
  1,
  'a failed event returns once its delay passed'
);
select is(
  jsonb_array_length(better_supabase.pending_inbound_events(100, 1)),
  0,
  'max_attempts hides an event that used its attempts'
);

select ok(
  better_supabase.set_inbound_event_status((select id from ids where name = 'event'), 'processed', null, null, null),
  'an event is marked processed'
);
select isnt(
  (select processed_at from better_supabase.inbox_inbound_events where id = (select id from ids where name = 'event')),
  null,
  'processing sets processed_at'
);

-- last_inbound_at and deliveries. record_inbound calls resolve_person, which
-- service_role can execute (contacts version 3), so this block runs as it.
select ok(
  has_function_privilege('service_role', 'better_supabase.resolve_person(uuid, jsonb)', 'execute'),
  'service_role can execute resolve_person'
);
select ok(
  not has_function_privilege('authenticated', 'better_supabase.resolve_person(uuid, jsonb)', 'execute'),
  'authenticated cannot execute resolve_person'
);

insert into ids
select 'message', (better_supabase.record_inbound(jsonb_build_object(
  'inbox_id', (select id from ids where name = 'inbox'),
  'thread_id', 'whatsapp:+3100:+3197',
  'contact', jsonb_build_object('external_id', '+3197', 'name', 'Cy'),
  'message', jsonb_build_object('body', 'Hi', 'external_id', 'wamid.pgtap')
)) ->> 'message_id')::uuid;

select isnt(
  (select last_inbound_at from better_supabase.inbox_conversations where thread_id = 'whatsapp:+3100:+3197'),
  null,
  'an inbound message sets last_inbound_at on its conversation'
);

select better_supabase.record_delivery((select id from ids where name = 'message'), 'whatsapp', 'wamid.out-pgtap', 'sent', null);
select is(better_supabase.set_delivery_status('whatsapp', 'wamid.out-pgtap', 'read'), 1, 'a read callback moves the delivery');
select is(better_supabase.set_delivery_status('whatsapp', 'wamid.out-pgtap', 'delivered'), 0, 'a later delivered callback leaves a read delivery read');

select * from finish();
rollback;
