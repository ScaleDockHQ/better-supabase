-- acting_member() reads the x-bsb-actor header for a service caller only, so a
-- signed-in user cannot name another user as the actor of an audited write.
-- Only service_role may execute it; the audit functions call it as their owner.
begin;
select plan(7);

select ok(
  not has_function_privilege('anon', 'better_supabase.acting_member()', 'execute'),
  'anon cannot execute acting_member()'
);
select ok(
  not has_function_privilege('authenticated', 'better_supabase.acting_member()', 'execute'),
  'authenticated cannot execute acting_member()'
);
select ok(
  has_function_privilege('service_role', 'better_supabase.acting_member()', 'execute'),
  'service_role can execute acting_member()'
);

select set_config(
  'request.headers',
  '{"x-bsb-actor":"00000000-0000-4000-8000-0000000000b1"}',
  true
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}',
  true
);
set local role authenticated;
select better_supabase.audit_event('test.spoof');

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select is(
  better_supabase.acting_member()::text,
  '00000000-0000-4000-8000-0000000000b1',
  'the service role acts for the named member'
);
select better_supabase.audit_event('test.service');

reset role;
select results_eq(
  $$select actor_id::text from better_supabase.audit_events where event_type = 'test.spoof'$$,
  $$values ('00000000-0000-4000-8000-0000000000a1')$$,
  'a user keeps their own id as the actor'
);
select results_eq(
  $$select actor_id::text from better_supabase.audit_events where event_type = 'test.service'$$,
  $$values ('00000000-0000-4000-8000-0000000000b1')$$,
  'a service write records the acting member'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}',
  true
);
set local role authenticated;
select lives_ok(
  $$select better_supabase.audit_event('test.user-after-revoke')$$,
  'a signed-in user still writes audit events after the revoke'
);
reset role;

select * from finish();
rollback;
