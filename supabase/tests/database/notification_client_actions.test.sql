-- Notification actions are buttons a recipient presses to run an operation,
-- so only the service role (the app's server) sends them. A member who may
-- send notifications sends plain ones. The member (…a2) of Acme (…0001) holds
-- notifications.send.
begin;
select plan(2);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated"}', true);

select throws_ok(
  $$select better_supabase.send_notification(jsonb_build_object(
    'type', 'approval.requested', 'tenant', '00000000-0000-4000-8000-000000000001',
    'recipients', jsonb_build_array('00000000-0000-4000-8000-0000000000a1'), 'summary', 'Approve this',
    'actions', jsonb_build_array(jsonb_build_object('key', 'approve', 'label', 'Approve', 'operation', 'approve_payment'))))$$,
  '42501', null, 'a member can''t send a notification with actions'
);
select lives_ok(
  $$select better_supabase.send_notification(jsonb_build_object(
    'type', 'comment.added', 'tenant', '00000000-0000-4000-8000-000000000001',
    'recipients', jsonb_build_array('00000000-0000-4000-8000-0000000000a1'), 'summary', 'Hello'))$$,
  'a member still sends a plain notification'
);

select * from finish();
rollback;
