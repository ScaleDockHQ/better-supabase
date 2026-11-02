-- Block tables carry a deferred row trigger: a write a block function already
-- recorded is audited once, and a direct write leaves a row entry.
begin;
select plan(3);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select lives_ok(
  $$select better_supabase.create_api_key('ci-rows', '00000000000000c1', repeat('c', 64), '00000000-0000-4000-8000-000000000001')$$,
  'the admin creates an API key through the block function'
);

reset role;
set constraints all immediate;

select is(
  (select count(*)::int from better_supabase.audit_events
    where target_type = 'api_key'
      and organization_id = '00000000-0000-4000-8000-000000000001'
      and event_type = 'api_key.created'),
  1,
  'the function and the row trigger record the key once'
);

create temp table before_deletes as
select count(*)::int as n from better_supabase.audit_events where op = 'delete';

delete from better_supabase.role_permissions
where ctid = (select ctid from better_supabase.role_permissions limit 1);
set constraints all immediate;

select is(
  (select count(*)::int from better_supabase.audit_events
    where op = 'delete') - (select n from before_deletes),
  1,
  'a direct delete that no function recorded leaves a row entry'
);

select * from finish();
rollback;
