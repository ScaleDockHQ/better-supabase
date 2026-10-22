-- Work-item checklists, repeat rules and watchers on the fixture's access
-- contract. Ann (…a1) owns Acme (…0001); Carl (…a3) owns Globex (…0002) and
-- is not an Acme member (supabase/seed.sql).
begin;
select plan(13);

select has_table('better_supabase', 'work_item_checklist_items', 'the checklist table exists');
select has_column('better_supabase', 'work_items', 'recurs_from', 'a repeated item points at the item it repeats');
select ok(
  not has_function_privilege('authenticated', 'api.repeat_work_item(uuid, timestamptz)', 'execute'),
  'only the service creates the next item of a repeat rule'
);

-- Acme owner.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config(
  'test.item',
  api.create_work_item('00000000-0000-4000-8000-000000000001', '{"title":"Monthly report","dueAt":"2026-11-02T09:00:00Z"}', null) ->> 'id',
  true
);

select is(
  api.save_work_item_checklist_item(current_setting('test.item')::uuid, null, '{"title":"Draft"}') ->> 'title',
  'Draft',
  'the owner adds a checklist item'
);
select is(
  api.save_work_item_checklist_item(current_setting('test.item')::uuid, null, '{"title":"Send","done":true}') ->> 'done',
  'true',
  'and a checked one, after the first'
);
select is(
  api.get_work_item(current_setting('test.item')::uuid) -> 'checklist',
  '{"total": 2, "done": 1}'::jsonb,
  'the item counts its checklist'
);
select is(
  (select jsonb_agg(entry ->> 'title') from jsonb_array_elements(api.list_work_item_checklist(current_setting('test.item')::uuid)) as entry),
  '["Draft", "Send"]'::jsonb,
  'the checklist lists in rank order'
);
select is(
  api.set_work_item_recurrence(current_setting('test.item')::uuid, 'RRULE:FREQ=MONTHLY;BYMONTHDAY=2', 'Europe/Amsterdam') ->> 'rrule',
  'FREQ=MONTHLY;BYMONTHDAY=2',
  'the owner sets a repeat rule'
);
select throws_ok(
  format($$select api.set_work_item_recurrence(%L, 'every monday', 'UTC')$$, current_setting('test.item')),
  '22023',
  'rrule must be an RRULE such as FREQ=WEEKLY;BYDAY=MO',
  'a rule that is not an RRULE is rejected'
);
select ok(
  api.watch_work_item(current_setting('test.item')::uuid, 'all'),
  'the owner watches the item'
);
select is(
  api.list_work_item_watchers(current_setting('test.item')::uuid),
  '[{"userId": "00000000-0000-4000-8000-0000000000a1", "level": "all"}]'::jsonb,
  'and is its only watcher'
);

-- Globex owner, outside Acme.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*) from better_supabase.work_item_checklist_items where work_item_id = current_setting('test.item')::uuid),
  0::bigint,
  'an outsider reads none of the checklist'
);
select throws_ok(
  format($$select api.save_work_item_checklist_item(%L, null, '{"title":"Sneak"}')$$, current_setting('test.item')),
  'P0002',
  'no such work item you can edit',
  'nor adds to it'
);

select * from finish();
rollback;
