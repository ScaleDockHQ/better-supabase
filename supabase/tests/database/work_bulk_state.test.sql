-- The work.setState bulk action: `authenticated` can only read work_items, so
-- the bulk bar writes through public.work_bulk_state after a tasks.write check.
-- Ann (…a1) owns Acme (…0001); Carl (…a3) owns Globex and is not an Acme member
-- (supabase/seed.sql).
begin;
select plan(8);

select ok(
  not has_table_privilege('authenticated', 'better_supabase.work_items', 'update'),
  'authenticated still has no update grant on work_items'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.a', api.create_work_item('00000000-0000-4000-8000-000000000001', '{"title":"Bulk A"}', null) ->> 'id', true);
select set_config('test.b', api.create_work_item('00000000-0000-4000-8000-000000000001', '{"title":"Bulk B"}', null) ->> 'id', true);

select is(
  (better_supabase.bulk_apply(
    '00000000-0000-4000-8000-000000000001', 'work_item',
    array[current_setting('test.a'), current_setting('test.b')],
    'work.setState', '{"to":"started"}', false
  ) ->> 'succeeded')::integer,
  2,
  'the owner moves both rows to started in one bulk run'
);

select is(
  (select count(*)::integer from better_supabase.work_items
   where id in (current_setting('test.a')::uuid, current_setting('test.b')::uuid) and state = 'started'),
  2,
  'both rows hold the new state'
);

select is(
  (better_supabase.bulk_apply(
    '00000000-0000-4000-8000-000000000001', 'work_item',
    array[current_setting('test.a'), '00000000-0000-4000-8000-00000000ffff'],
    'work.setState', '{"to":"completed"}', false
  ) -> 'results' -> 1 -> 'error' ->> 'code'),
  'TASK_NOT_FOUND',
  'a missing row fails on its own with TASK_NOT_FOUND'
);

select ok(
  api.archive_work_item(current_setting('test.a')::uuid, true),
  'the owner archives the first row'
);

select is(
  (better_supabase.bulk_apply(
    '00000000-0000-4000-8000-000000000001', 'work_item',
    array[current_setting('test.a')],
    'work.setState', '{"to":"started"}', false
  ) -> 'results' -> 0 -> 'error' ->> 'code'),
  'TASK_NOT_FOUND',
  'an archived row is not changed'
);

select is(
  (better_supabase.bulk_apply(
    '00000000-0000-4000-8000-000000000001', 'work_item',
    array[current_setting('test.b')],
    'trash.trash', '{}', false
  ) ->> 'succeeded')::integer,
  1,
  'the same bar can trash a row'
);

-- Carl is not an Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select throws_ok(
  format(
    $q$select better_supabase.bulk_apply('00000000-0000-4000-8000-000000000001', 'work_item', array[%L], 'work.setState', '{"to":"completed"}', false)$q$,
    current_setting('test.a')
  ),
  '42501',
  'not allowed to run bulk actions',
  'a user outside the organization is refused'
);

select * from finish();
rollback;
