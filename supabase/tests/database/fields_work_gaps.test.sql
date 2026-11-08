-- The fields and work gaps of the declarative base layer plan (ADR 0269): time
-- is tracked only on the record types options.on names (the fixture lists
-- company and project). The admin (…00a1) of Acme (…0001) logs time.
begin;
select plan(4);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.company', better_supabase.save_company('00000000-0000-4000-8000-000000000001', null, '{"name": "Time Co"}') ->> 'id', true);
select set_config('t.person', better_supabase.save_person('00000000-0000-4000-8000-000000000001', null, '{"name": "Time Pat"}') ->> 'id', true);

select is(
  (better_supabase.log_time('00000000-0000-4000-8000-000000000001', '2026-11-02 09:00+00', '2026-11-02 10:00+00', 'company', current_setting('t.company')) ->> 'subjectType'),
  'company',
  'time is tracked on a type options.on lists'
);
select throws_ok(
  format($$select better_supabase.log_time('00000000-0000-4000-8000-000000000001', '2026-11-02 11:00+00', '2026-11-02 12:00+00', 'person', %L)$$, current_setting('t.person')),
  '22023',
  'time is tracked on company, project records',
  'a type options.on leaves out is refused'
);
select lives_ok(
  $$select better_supabase.log_time('00000000-0000-4000-8000-000000000001', '2026-11-02 13:00+00', '2026-11-02 14:00+00')$$,
  'time without a record is not restricted'
);
select throws_ok(
  format($$select better_supabase.start_timer('00000000-0000-4000-8000-000000000001', 'person', %L)$$, current_setting('t.person')),
  '22023',
  'time is tracked on company, project records',
  'a timer follows the same record types'
);

select * from finish();
rollback;
