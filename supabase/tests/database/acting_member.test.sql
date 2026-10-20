-- acting_member() reads the x-bs-actor header for a service caller only, so a
-- signed-in user cannot name another user as the actor of an audited write.
begin;
select plan(4);

select set_config(
  'request.headers',
  '{"x-bs-actor":"00000000-0000-4000-8000-0000000000b1"}',
  true
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}',
  true
);
set local role authenticated;
select is(
  better_supabase.acting_member(),
  null::uuid,
  'an authenticated caller gets no acting member'
);
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

select * from finish();
rollback;
