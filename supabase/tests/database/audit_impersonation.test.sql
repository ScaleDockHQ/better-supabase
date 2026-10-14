-- audit_event fills the impersonation columns from its arguments: always for
-- the service role, and for other callers only when they name themselves as
-- impersonated_by from a token without an act claim. A read-only session
-- may not write at all (ADR 0019), so the act case runs with read_only false.
begin;
select plan(4);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}',
  true
);
set local role authenticated;

select better_supabase.audit_event(
  'test.self',
  support_session => '00000000-0000-4000-8000-0000000005e1',
  impersonated_by => '00000000-0000-4000-8000-0000000000a1',
  impersonation_reason => 'ticket 9'
);
select better_supabase.audit_event(
  'test.other',
  support_session => '00000000-0000-4000-8000-0000000005e1',
  impersonated_by => '00000000-0000-4000-8000-0000000000a2',
  impersonation_reason => 'ticket 9'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","act":{"kind":"support","sub":"00000000-0000-4000-8000-0000000000a1","reason":"from the token","session_id":"00000000-0000-4000-8000-0000000005e2","read_only":false}}',
  true
);
select better_supabase.audit_event(
  'test.act',
  support_session => '00000000-0000-4000-8000-0000000005e1',
  impersonated_by => '00000000-0000-4000-8000-0000000000a2',
  impersonation_reason => 'from the argument'
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select better_supabase.audit_event(
  'test.service',
  support_session => '00000000-0000-4000-8000-0000000005e3',
  impersonated_by => '00000000-0000-4000-8000-0000000000a1',
  impersonation_reason => 'expired'
);

reset role;

select results_eq(
  $$select support_session_id::text, impersonated_by::text, impersonation_reason
    from better_supabase.audit_events where event_type = 'test.self'$$,
  $$values ('00000000-0000-4000-8000-0000000005e1', '00000000-0000-4000-8000-0000000000a1', 'ticket 9')$$,
  'a caller names itself as the impersonator'
);
select results_eq(
  $$select support_session_id::text, impersonated_by::text, impersonation_reason
    from better_supabase.audit_events where event_type = 'test.other'$$,
  $$values (null::text, null::text, null::text)$$,
  'a caller cannot name someone else as the impersonator'
);
select results_eq(
  $$select support_session_id::text, impersonated_by::text, impersonation_reason
    from better_supabase.audit_events where event_type = 'test.act'$$,
  $$values ('00000000-0000-4000-8000-0000000005e2', '00000000-0000-4000-8000-0000000000a1', 'from the token')$$,
  'the act claim wins over the arguments'
);
select results_eq(
  $$select support_session_id::text, impersonated_by::text, impersonation_reason
    from better_supabase.audit_events where event_type = 'test.service'$$,
  $$values ('00000000-0000-4000-8000-0000000005e3', '00000000-0000-4000-8000-0000000000a1', 'expired')$$,
  'the service role sets every impersonation column'
);

select * from finish();
rollback;
