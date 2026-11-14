-- Restoring an archived item records its `restored` event once (ADR 1024).
-- The Acme owner (…00a1) archives and restores a work item and a
-- conversation; restoring an item that is not archived records nothing.
begin;
select plan(6);

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
  'test.item',
  api.create_work_item('00000000-0000-4000-8000-000000000001', '{"title":"Restore me"}', null) ->> 'id',
  true
);

select api.archive_work_item(current_setting('test.item')::uuid, false);
select is(
  pg_temp.n('work_item.restored'),
  0,
  'restoring an item that is not archived records nothing'
);

select api.archive_work_item(current_setting('test.item')::uuid, true);
select api.archive_work_item(current_setting('test.item')::uuid, false);
select is(
  pg_temp.n('work_item.restored'),
  1,
  'restoring an archived item records work_item.restored'
);

select is(
  (api.archive_work_items(array[current_setting('test.item')::uuid], true) -> 'ids') -> 0,
  to_jsonb(current_setting('test.item')),
  'the set form archives the item'
);
select api.archive_work_items(array[current_setting('test.item')::uuid], false);
select is(
  pg_temp.n('work_item.restored'),
  2,
  'the set form records work_item.restored for an archived item'
);

select set_config(
  'test.conversation',
  api.open_conversation('00000000-0000-4000-8000-000000000001', 'channel', '{"title":"Restore channel"}') ->> 'id',
  true
);
select api.archive_conversation(current_setting('test.conversation')::uuid, true);
select api.archive_conversation(current_setting('test.conversation')::uuid, false);
select is(
  pg_temp.n('conversation.restored'),
  1,
  'restoring an archived conversation records conversation.restored'
);
select is(
  pg_temp.n('conversation.archived'),
  1,
  'and archiving it recorded conversation.archived'
);

select * from finish();
rollback;
