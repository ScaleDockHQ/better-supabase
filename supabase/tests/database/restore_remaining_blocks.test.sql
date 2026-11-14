-- Restoring an archived content entry or pipeline stage records its
-- `restored` event once (ADR 1026).
begin;
select plan(2);

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
  't.pipeline',
  (better_supabase.save_pipeline('00000000-0000-4000-8000-000000000001', null, 'deal', 'restore_me', 'Restore me', null, false) ->> 'id'),
  true
);
select better_supabase.archive_pipeline(current_setting('t.pipeline')::uuid);
select better_supabase.restore_pipeline(current_setting('t.pipeline')::uuid);
select is(pg_temp.n('pipeline.restored'), 1, 'restoring an archived pipeline records pipeline.restored');
select better_supabase.restore_pipeline(current_setting('t.pipeline')::uuid);
select is(pg_temp.n('pipeline.restored'), 1, 'restoring an active pipeline records nothing');

select * from finish();
rollback;
