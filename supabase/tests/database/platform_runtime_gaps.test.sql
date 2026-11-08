-- The platform and runtime gaps of the declarative base layer plan (ADR 0270):
-- notifications reach a member at the address options.resolveAddress returns,
-- and the Realtime triggers of the module tables are static statements in the
-- schema files. Acme (…0001) has the admin …a1.
begin;
select plan(7);

-- options.resolveAddress: a claimed delivery carries the app's address, the
-- sign-in email when the function returns null.
insert into better_supabase.notification_events (id, tenant_id, type, summary)
values ('00000000-0000-4000-8000-0000000e0001', '00000000-0000-4000-8000-000000000001', 'test.address', 'Address test');
select set_config('t.event', '00000000-0000-4000-8000-0000000e0001', true);
insert into better_supabase.notification_recipients (event_id, tenant_id, user_id)
values (current_setting('t.event')::uuid, '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1');
insert into better_supabase.notification_deliveries (recipient_id, tenant_id, channel)
select r.id, r.tenant_id, 'email' from better_supabase.notification_recipients r where r.event_id = current_setting('t.event')::uuid;
insert into better_supabase.notification_deliveries (recipient_id, tenant_id, channel)
select r.id, r.tenant_id, 'sms' from better_supabase.notification_recipients r where r.event_id = current_setting('t.event')::uuid;

select set_config('t.email', (select email from auth.users where id = '00000000-0000-4000-8000-0000000000a1'), true);
set local role service_role;
select set_config('t.claimed', better_supabase.claim_notification_deliveries('email')::text, true);
select is(
  current_setting('t.claimed')::jsonb -> 0 ->> 'email',
  'work.' || current_setting('t.email'),
  'a delivery goes to the address the app function returns'
);
select set_config('t.sms', better_supabase.claim_notification_deliveries('sms')::text, true);
select is(
  current_setting('t.sms')::jsonb -> 0 ->> 'email',
  current_setting('t.email'),
  'a channel the function has no address for falls back to the sign-in email'
);
reset role;
select is(
  better_supabase.member_address('00000000-0000-4000-8000-0000000000a1', 'sms'),
  null,
  'the app function returns null for a channel it does not know'
);

-- Static Realtime triggers on a module table.
select has_trigger('better_supabase', 'work_items', 'bsb_realtime_insert', 'work_items broadcasts inserts');
select has_trigger('better_supabase', 'work_items', 'bsb_realtime_update', 'work_items broadcasts updates');
select has_trigger('better_supabase', 'work_items', 'bsb_realtime_delete', 'work_items broadcasts deletes');
select is(
  (select count(*)::int from pg_trigger t
   where t.tgrelid = 'better_supabase.work_items'::regclass and t.tgname like 'bsb_realtime%' and not t.tgisinternal),
  3,
  'each event has one trigger'
);

select * from finish();
rollback;
