-- Restoring a company or a lims method records its `restored` event once
-- (ADR 1025). Restoring one that is not archived records nothing.
begin;
select plan(5);

create function pg_temp.n(t text) returns integer language sql security definer as $$
  select count(*)::integer from better_supabase.outbox_events where type = t
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config(
  't.company',
  better_supabase.save_company('00000000-0000-4000-8000-000000000001', null, '{"name": "Restore Co"}') ->> 'id',
  true
);

select better_supabase.archive_company(current_setting('t.company')::uuid, false);
select is(pg_temp.n('company.restored'), 0, 'restoring an active company records nothing');

select better_supabase.archive_company(current_setting('t.company')::uuid, true);
select better_supabase.archive_company(current_setting('t.company')::uuid, false);
select is(pg_temp.n('company.restored'), 1, 'restoring an archived company records company.restored');

select better_supabase.archive_company(current_setting('t.company')::uuid, false);
select is(pg_temp.n('company.restored'), 1, 'a second restore records nothing');

select set_config(
  't.method',
  better_supabase.save_lims_method('00000000-0000-4000-8000-000000000001', '{"key":"restore_me","name":"Restore me"}', null) ->> 'id',
  true
);
select better_supabase.archive_lims_method(current_setting('t.method')::uuid);
select better_supabase.restore_lims_method(current_setting('t.method')::uuid);
select is(pg_temp.n('lims_method.restored'), 1, 'restoring an archived method records lims_method.restored');
select better_supabase.restore_lims_method(current_setting('t.method')::uuid);
select is(pg_temp.n('lims_method.restored'), 1, 'restoring an active method records nothing');

select * from finish();
rollback;
